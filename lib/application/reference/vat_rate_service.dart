/// KDV oranı yönetimi — **docs/08 §3, §4 · BR-VAT-001/004/005**
///
/// ## Seed YOKTUR
///
/// BR-VAT-001 · REQ-VAT-002 · docs/08 §3: **hiçbir KDV oranı önceden seed
/// edilmez** ve hiçbir oran koda gömülmez. Güncel oranlar mevzuata bağlıdır;
/// kullanıcı kendi oranlarını tanımlar. Bu servis yalnızca kullanıcının
/// açıkça istediği kaydı oluşturur; açılışta veya ilk çağrıda kendiliğinden
/// oran **üretmez**. `data/db/seed.dart` de KDV'ye dokunmaz.
///
/// ## Silme metodu YOKTUR — kasıtlıdır
///
/// docs/08 §4: "Oran kaydı **silinemez** (geçmiş ürün ilişkileri korunur)."
/// docs/04 §5 tablosu da VatRate için kalıcı silmeyi ❌ işaretler. Bu yüzden
/// `VatRatesDao` `deleteById` sunmaz ve bu serviste silme metodu yoktur.
///
/// Geçmiş satışlar zaten `sale_items.vat_rate_snapshot_bp` taşır (BR-VAT-002)
/// ve oran değişikliğinden etkilenmez (BR-VAT-004) — ama ürün ilişkileri
/// (`products.vat_rate_id`) korunmalıdır.
///
/// ## Varsayılan oran invariant'ı
///
/// docs/04 §3.4: `isDefault` **yalnızca bir kayıtta** `true` olabilir.
/// [setDefault] eski varsayılanı ve yenisini **tek transaction** içinde yazar;
/// [create] `isDefault: true` ile çağrıldığında da aynı yol işletilir.
library;

import 'dart:convert';

import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../data/dao/daos.dart';
import '../../data/dao/vat_rate_mapper.dart';
import '../../data/db/canteen_database.dart' show CanteenDatabase;
import '../../domain/models/vat_rate.dart';
import '../../domain/services/vat_rate_parser.dart';
import 'vat_rate_failures.dart';

class VatRateService {
  /// docs/18 §2 — `entity_type`.
  static const String auditEntityType = 'vat_rate';

  // docs/18 §3.
  static const String actionCreated = 'vatRateCreated';
  static const String actionChanged = 'vatRateChanged';
  static const String actionDeactivated = 'vatRateDeactivated';

  final CanteenDatabase _db;
  final VatRatesDao _vatRates;
  final AuditLogsDao _auditLogs;
  final AppLogger? _logger;
  final DateTime Function() _clock;

  VatRateService({
    required CanteenDatabase db,
    required VatRatesDao vatRates,
    required AuditLogsDao auditLogs,
    AppLogger? logger,
    DateTime Function()? clock,
  }) : _db = db,
       _vatRates = vatRates,
       _auditLogs = auditLogs,
       _logger = logger,
       _clock = clock ?? db.clock;

  // --- Okuma ---------------------------------------------------------------

  /// Oran listesi. Varsayılan olarak **pasifler de** listelenir: oran
  /// silinmediği için yönetim ekranı onları görebilmelidir.
  Future<List<VatRate>> list({bool onlyActive = false}) async {
    final rows = onlyActive
        ? await _vatRates.listActive()
        : await _vatRates.listAll();
    return [for (final row in rows) row.toDomain()];
  }

  Future<VatRate?> findById(int id) async =>
      (await _vatRates.findById(id))?.toDomain();

  /// Ürüne oran atanmamışsa kullanılan oran (docs/08 §4).
  ///
  /// **BR-VAT-005:** varsayılan oran yoksa `null` döner ve sistem KDV'siz
  /// çalışır (`vat = 0`, `net = total`). Bu durumda burada oran **üretilmez.**
  Future<VatRate?> defaultRate() async =>
      (await _vatRates.findDefault())?.toDomain();

  /// Sistemde hiç KDV oranı tanımlı değilse `true` — BR-VAT-005.
  ///
  /// Ürün formu ve raporlar KDV alanlarını buna göre gizler. Sistemin oran
  /// **üretmesi** için bir tetikleyici değildir (docs/08 §3 — seed yok).
  Future<bool> isVatDisabled() async => (await _vatRates.countAll()) == 0;

  /// Bu orana **doğrudan** bağlı ürün sayısı (`products.vat_rate_id`).
  ///
  /// docs/08 §4: oran değiştirilmeden önce kullanıcıya "bu oran `N` üründe
  /// kullanılıyor" bilgisi gösterilir.
  Future<int> productCount(int id) => _vatRates.countProducts(id);

  // --- Yazma ---------------------------------------------------------------

  /// Kullanıcının yazdığı oranı basis point'e çevirir (BR-FIN-002).
  ///
  /// Tek implementasyon `domain/services/vat_rate_parser.dart` içindedir
  /// (rules/01 §2); bu metot yalnızca hatayı `Failure`'a çevirir.
  ///
  /// `%20` → `2000` · `0,5` → `50` · `18` → `1800`
  static Result<int> parseRate(String input) {
    final bp = VatRateParser.tryParseBasisPoints(input);
    if (bp == null) return const Err(VatRateFailures.invalidRate);
    return Ok(bp);
  }

  /// Yeni KDV oranı oluşturur ve id'sini döndürür (REQ-VAT-001).
  ///
  /// [rateBasisPoints] **basis point tam sayıdır** (`%20 → 2000`). Metin
  /// girdisi için önce [parseRate] kullanılır.
  ///
  /// [isDefault] `true` ise varsayılan aynı transaction içinde devredilir —
  /// docs/04 §3.4 invariant'ı korunur.
  Future<Result<int>> create({
    required String name,
    required int rateBasisPoints,
    bool isDefault = false,
    int? userId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const Err(VatRateFailures.nameRequired);
    // docs/05 §2.4 — CHECK(rate_basis_points >= 0). Kısıt ihlalini SQLite
    // hatasına bırakmak yerine burada beklenen iş hatası olarak döneriz.
    if (rateBasisPoints < 0) return const Err(VatRateFailures.invalidRate);

    final now = _clock().toUtc();

    return _db.transaction(() async {
      final id = await _vatRates.insertVatRate(
        name: trimmed,
        rateBasisPoints: rateBasisPoints,
        now: now,
        isDefault: isDefault,
      );
      if (isDefault) {
        // Yalnızca **bir** kayıt varsayılan olabilir (docs/04 §3.4).
        await _vatRates.clearDefault(exceptId: id);
      }
      await _writeAudit(
        action: actionCreated,
        now: now,
        userId: userId,
        entityId: id,
        newValue: {
          'name': trimmed,
          'rate_basis_points': rateBasisPoints,
          'is_default': isDefault,
        },
      );
      return Ok(id);
    });
  }

  /// Oranın adını ve/veya oran değerini günceller (REQ-VAT-001).
  ///
  /// **BR-VAT-004 · REQ-VAT-004:** değişiklik yalnızca bundan sonraki satışları
  /// etkiler. Geçmiş satışların KDV tutarı değişmez çünkü her satış satırı
  /// kendi `vat_rate_snapshot_bp` değerini taşır (BR-VAT-002); bu servis
  /// `sale_items` tablosuna **dokunmaz**.
  ///
  /// Audit: docs/18 §3 `vatRateChanged` — eski/yeni oran ve **etkilenen ürün
  /// sayısı** metadata'ya yazılır.
  Future<Result<void>> update(
    int id, {
    String? name,
    int? rateBasisPoints,
    int? userId,
  }) async {
    final trimmed = name?.trim();
    if (trimmed != null && trimmed.isEmpty) {
      return const Err(VatRateFailures.nameRequired);
    }
    if (rateBasisPoints != null && rateBasisPoints < 0) {
      return const Err(VatRateFailures.invalidRate);
    }

    final now = _clock().toUtc();

    return _db.transaction(() async {
      final current = await _vatRates.findById(id);
      if (current == null) return const Err<void>(VatRateFailures.notFound);

      final nextName = trimmed ?? current.name;
      final nextRate = rateBasisPoints ?? current.rateBasisPoints;
      final nameChanged = nextName != current.name;
      final rateChanged = nextRate != current.rateBasisPoints;
      if (!nameChanged && !rateChanged) return const Ok<void>(null);

      await _vatRates.updateVatRate(
        id,
        name: nameChanged ? nextName : null,
        rateBasisPoints: rateChanged ? nextRate : null,
      );

      // docs/18 §2 — yalnızca değişen alanlar.
      await _writeAudit(
        action: actionChanged,
        now: now,
        userId: userId,
        entityId: id,
        oldValue: {
          if (nameChanged) 'name': current.name,
          if (rateChanged) 'rate_basis_points': current.rateBasisPoints,
        },
        newValue: {
          if (nameChanged) 'name': nextName,
          if (rateChanged) 'rate_basis_points': nextRate,
        },
        metadata: {'affected_product_count': await _vatRates.countProducts(id)},
      );
      return const Ok<void>(null);
    });
  }

  /// Varsayılan oranı belirler — docs/04 §3.4 · docs/08 §4.
  ///
  /// **Invariant:** aynı anda yalnızca **bir** kayıt `is_default = true`
  /// olabilir. Eski varsayılanın temizlenmesi ile yenisinin yazılması **tek
  /// transaction** içindedir; yarıda kalırsa hiçbiri uygulanmaz.
  ///
  /// Pasif bir oran varsayılan yapılamaz: `findDefault` pasif kaydı varsayılan
  /// saymaz (docs/08 §4 — "Varsayılan oran yok → %0 kabul edilir"), dolayısıyla
  /// böyle bir atama KDV'yi sessizce sıfırlardı. Hata görünür olmalıdır.
  Future<Result<void>> setDefault(int id, {int? userId}) async {
    final now = _clock().toUtc();

    return _db.transaction(() async {
      final current = await _vatRates.findById(id);
      if (current == null) return const Err<void>(VatRateFailures.notFound);
      if (!current.isActive) {
        return const Err<void>(VatRateFailures.inactiveCannotBeDefault);
      }
      if (current.isDefault) {
        // Yine de temizlik yapılır: veri daha önce bozulmuşsa (iki varsayılan)
        // bu çağrı invariant'ı geri getirir.
        await _vatRates.clearDefault(exceptId: id);
        return const Ok<void>(null);
      }

      await _vatRates.clearDefault(exceptId: id);
      await _vatRates.setDefault(id, true);

      await _writeAudit(
        action: actionChanged,
        now: now,
        userId: userId,
        entityId: id,
        oldValue: {'is_default': false},
        newValue: {'is_default': true},
      );
      return const Ok<void>(null);
    });
  }

  /// Oranı pasifleştirir (docs/08 §4 — silme yerine pasifleştirme).
  ///
  /// Bu orana bağlı ürünler **etkilenmez**: docs/08 §4 tablosu "Ürünün oranı
  /// pasifleştirilmiş → ürün geçerliliğini korur; satışta o oran kullanılmaya
  /// devam eder" der. Bu servis `products` tablosuna dokunmaz.
  ///
  /// Varsayılan oran pasifleştirilirse sistem "varsayılan oran yok" durumuna
  /// döner ve oransız ürünler için KDV `%0` kabul edilir (docs/08 §4).
  ///
  /// Zaten pasif kayıt için işlem yinelenmez (docs/18 §4).
  Future<Result<void>> deactivate(int id, {int? userId}) async {
    final now = _clock().toUtc();

    return _db.transaction(() async {
      final current = await _vatRates.findById(id);
      if (current == null) return const Err<void>(VatRateFailures.notFound);
      if (!current.isActive) return const Ok<void>(null);

      await _vatRates.setActive(id, false);
      await _writeAudit(
        action: actionDeactivated,
        now: now,
        userId: userId,
        entityId: id,
        oldValue: {'is_active': true},
        newValue: {'is_active': false},
        metadata: {
          'rate_basis_points': current.rateBasisPoints,
          'affected_product_count': await _vatRates.countProducts(id),
        },
      );
      return const Ok<void>(null);
    });
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
}
