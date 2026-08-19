/// Tedarikçi yönetimi — **docs/10 §2 · BR-SUP-001/002**
///
/// ## Silme metodu YOKTUR — kasıtlıdır
///
/// BR-SUP-002 · REQ-SUP-002: **tedarikçi silinemez, pasifleştirilir.**
///
/// Bu kural burada bir runtime kontrolü olarak değil, **var olmayan bir metot**
/// olarak uygulanır: `delete`/`remove`/`purge` adında bir üye yoktur ve
/// `SuppliersDao` de `deleteById` sunmaz. Reddedilecek bir çağrı yoktur çünkü
/// çağrı derlenmez. `test/application/reference/supplier_service_test.dart`
/// bunu yapısal olarak doğrular.
///
/// ## Transaction sınırı
///
/// rules/01 §5: transaction yalnızca bu katmanda açılır. Yazma + audit tek
/// transaction'dır (rules/03 §9/1).
library;

import 'dart:convert';

import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../data/dao/daos.dart';
import '../../data/dao/supplier_mapper.dart';
import '../../data/db/canteen_database.dart' show CanteenDatabase;
import '../../domain/models/supplier.dart';
import 'supplier_failures.dart';

class SupplierService {
  /// docs/18 §2 — `entity_type`.
  static const String auditEntityType = 'supplier';

  // docs/18 §3.
  static const String actionCreated = 'supplierCreated';
  static const String actionUpdated = 'supplierUpdated';
  static const String actionDeactivated = 'supplierDeactivated';

  /// OD-020 — pasifleştirme tek yönlü değildir.
  static const String actionActivated = 'supplierActivated';

  final CanteenDatabase _db;
  final SuppliersDao _suppliers;
  final AuditLogsDao _auditLogs;
  final AppLogger? _logger;
  final DateTime Function() _clock;

  SupplierService({
    required CanteenDatabase db,
    required SuppliersDao suppliers,
    required AuditLogsDao auditLogs,
    AppLogger? logger,
    DateTime Function()? clock,
  }) : _db = db,
       _suppliers = suppliers,
       _auditLogs = auditLogs,
       _logger = logger,
       _clock = clock ?? db.clock;

  // --- Okuma ---------------------------------------------------------------

  /// Tedarikçi listesi. Varsayılan olarak **pasifler de** listelenir:
  /// tedarikçi silinmediği için yönetim ekranı onları görebilmelidir.
  Future<List<Supplier>> list({bool onlyActive = false}) async {
    final rows = onlyActive
        ? await _suppliers.listActive()
        : await _suppliers.listAll();
    return [for (final row in rows) row.toDomain()];
  }

  Future<Supplier?> findById(int id) async =>
      (await _suppliers.findById(id))?.toDomain();

  /// Bu tedarikçiye bağlı ürün sayısı — pasifleştirme onayı için
  /// (EC-SUP-001: "İzin verilir; ürünler etkilenmez").
  Future<int> productCount(int id) => _suppliers.countProducts(id);

  // --- Yazma ---------------------------------------------------------------

  /// Yeni tedarikçi oluşturur ve id'sini döndürür.
  ///
  /// REQ-SUP-001: **yalnızca [name] zorunludur**; diğer alanların tümü
  /// opsiyoneldir ve boş bırakılabilir.
  ///
  /// Ad benzersizliği **aranmaz**: `docs/05 §2.3` şemasında `suppliers.name`
  /// üzerinde UNIQUE kısıtı yoktur ve hiçbir BR/REQ benzersizlik istemez.
  /// Kısıt eklemek bir şema kararı olurdu (rules/00 §5.2/2).
  Future<Result<int>> create({
    required String name,
    String? contactName,
    String? phone,
    String? email,
    String? address,
    String? note,
    int? userId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const Err(SupplierFailures.nameRequired);

    final now = _clock().toUtc();

    return _db.transaction(() async {
      final id = await _suppliers.insertSupplier(
        name: trimmed,
        now: now,
        contactName: _clean(contactName),
        phone: _clean(phone),
        email: _clean(email),
        address: _clean(address),
        note: _clean(note),
      );
      await _writeAudit(
        action: actionCreated,
        now: now,
        userId: userId,
        entityId: id,
        newValue: {'name': trimmed},
      );
      return Ok(id);
    });
  }

  /// Tüm alanları günceller (docs/10 §2.1 — "Düzenle | Tüm alanlar").
  ///
  /// Opsiyonel alanlar `null` verilerek **temizlenir**; bu yüzden metot kısmi
  /// güncelleme değil, tam kayıt güncellemesi yapar.
  ///
  /// Audit'e docs/18 §2 gereği **yalnızca değişen alanlar** yazılır.
  Future<Result<void>> update(
    int id, {
    required String name,
    String? contactName,
    String? phone,
    String? email,
    String? address,
    String? note,
    int? userId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const Err(SupplierFailures.nameRequired);

    final now = _clock().toUtc();

    return _db.transaction(() async {
      final current = await _suppliers.findById(id);
      if (current == null) return const Err<void>(SupplierFailures.notFound);

      final next = <String, Object?>{
        'name': trimmed,
        'contact_name': _clean(contactName),
        'phone': _clean(phone),
        'email': _clean(email),
        'address': _clean(address),
        'note': _clean(note),
      };
      final previous = <String, Object?>{
        'name': current.name,
        'contact_name': current.contactName,
        'phone': current.phone,
        'email': current.email,
        'address': current.address,
        'note': current.note,
      };

      final changed = [
        for (final key in next.keys)
          if (previous[key] != next[key]) key,
      ];
      if (changed.isEmpty) return const Ok<void>(null);

      await _suppliers.updateSupplier(
        id,
        name: trimmed,
        contactName: next['contact_name'] as String?,
        phone: next['phone'] as String?,
        email: next['email'] as String?,
        address: next['address'] as String?,
        note: next['note'] as String?,
      );

      await _writeAudit(
        action: actionUpdated,
        now: now,
        userId: userId,
        entityId: id,
        oldValue: {for (final key in changed) key: previous[key]},
        newValue: {for (final key in changed) key: next[key]},
      );
      return const Ok<void>(null);
    });
  }

  /// Tedarikçiyi pasifleştirir (BR-SUP-002).
  ///
  /// **EC-SUP-001 — bağlı ürünlere DOKUNULMAZ.** Ürünlerin `supplier_id` bağı
  /// kopmaz, geçmiş stok girişleri ve raporlar korunur (docs/10 §2.3).
  ///
  /// Zaten pasif kayıt için işlem yinelenmez; veri değişmediği için audit kaydı
  /// da üretilmez (docs/18 §4).
  Future<Result<void>> deactivate(int id, {int? userId}) async {
    final now = _clock().toUtc();

    return _db.transaction(() async {
      final current = await _suppliers.findById(id);
      if (current == null) return const Err<void>(SupplierFailures.notFound);
      if (!current.isActive) return const Ok<void>(null);

      await _suppliers.setActive(id, false);
      await _writeAudit(
        action: actionDeactivated,
        now: now,
        userId: userId,
        entityId: id,
        oldValue: {'is_active': true},
        newValue: {'is_active': false},
      );
      return const Ok<void>(null);
    });
  }

  /// Boş metni `null`'a indirger: "girilmedi" ile "boş string" aynı şeydir
  /// (REQ-SUP-001 — alanlar opsiyoneldir).
  static String? _clean(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed;
  }

  /// REQ-AUDIT-007 — audit yazımındaki hata ana işlemi başarısız kılmaz.
  Future<void> _writeAudit({
    required String action,
    required DateTime now,
    required int entityId,
    int? userId,
    Map<String, Object?>? oldValue,
    Map<String, Object?>? newValue,
    Map<String, Object?>? metadata,
  }) async {
    try {
      await _auditLogs.record(
        createdAt: now,
        action: action,
        entityType: auditEntityType,
        userId: userId,
        entityId: entityId,
        oldValue: oldValue == null ? null : jsonEncode(oldValue),
        newValue: newValue == null ? null : jsonEncode(newValue),
        metadata: metadata == null ? null : jsonEncode(metadata),
      );
    } on Object catch (error, stackTrace) {
      _logger?.error(
        'Denetim kaydı yazılamadı ($action).',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// Pasifleştirilmiş tedarikçiyi yeniden aktifleştirir — **REQ-SUP-006 ·
  /// EC-SUP-003 (OD-020).**
  ///
  /// Zaten aktif kayıt için işlem yinelenmez (docs/18 §4).
  Future<Result<void>> activate(int id, {int? userId}) async {
    final now = _clock().toUtc();

    return _db.transaction(() async {
      final current = await _suppliers.findById(id);
      if (current == null) return const Err<void>(SupplierFailures.notFound);
      if (current.isActive) return const Ok<void>(null);

      await _suppliers.setActive(id, true);
      await _writeAudit(
        action: actionActivated,
        now: now,
        userId: userId,
        entityId: id,
        oldValue: {'is_active': false},
        newValue: {'is_active': true},
      );
      return const Ok<void>(null);
    });
  }
}
