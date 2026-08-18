/// Kategori yönetimi — **docs/10 §1 · BR-CAT-001…005**
///
/// ## Kapsam sınırı
///
/// Bu servis kategori kaydının yaşam döngüsünü yönetir: oluşturma, yeniden
/// adlandırma, sıralama, pasifleştirme ve **koşullu** kalıcı silme.
///
/// | Kapsamda **değil** | Neden |
/// |---|---|
/// | Kategori birleştirme / "ürünleri başka kategoriye taşı" (REQ-CAT-004) | docs/10 §1.4 audit action'ını `categoryMerge`, docs/18 §3 ise `categoryProductsMoved` olarak yazar. İki doküman çelişiyor → `rules/00 §5.2/9` gereği **DUR**; karar verilmeden yazılmaz. |
/// | Yeniden aktifleştirme | docs/18 §3 yalnızca `productActivated` tanımlar; kategori için karşılığı yoktur. Uydurulmaz. |
/// | Ürün alanlarına dokunmak | BR-CAT-003: pasifleştirme ürünleri **etkilemez** |
///
/// ## Transaction sınırı
///
/// rules/01 §5: transaction **yalnızca bu katmanda** açılır. Silme ve
/// benzersizlik kontrolleri, kontrol ile yazma arasında yarış oluşmaması için
/// yazma ile **aynı** transaction içindedir.
///
/// ## Audit
///
/// rules/03 §9/1: audit kaydı, kaydettiği işlemle **aynı transaction**
/// içindedir. REQ-AUDIT-007: audit yazımındaki hata ana işlemi başarısız
/// kılmaz — yakalanır ve log dosyasına yazılır.
///
/// Yalnızca **veriyi değiştiren** işlemler kaydedilir (docs/18 §4); reddedilen
/// çağrılar hiçbir şey değiştirmediği için kayıt üretmez.
library;

import 'dart:convert';

import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../data/dao/category_mapper.dart';
import '../../data/dao/daos.dart';
import '../../data/db/canteen_database.dart' show CanteenDatabase;
import '../../data/repositories/failures.dart';
import '../../domain/models/category.dart';
import 'category_failures.dart';

class CategoryService {
  /// docs/18 §2 — `entity_type`.
  static const String auditEntityType = 'category';

  // docs/18 §3 — Kategori / Tedarikçi / KDV tablosundaki action adları.
  static const String actionCreated = 'categoryCreated';
  static const String actionRenamed = 'categoryRenamed';
  static const String actionDeactivated = 'categoryDeactivated';
  static const String actionDeleted = 'categoryDeleted';

  final CanteenDatabase _db;
  final CategoriesDao _categories;
  final AuditLogsDao _auditLogs;
  final AppLogger? _logger;
  final DateTime Function() _clock;

  /// [clock] `rules/06 §7` gereği enjekte edilebilir; verilmezse veritabanının
  /// saat kaynağı kullanılır — tüm zaman damgaları tek kaynaktan gelir.
  ///
  /// [logger] yalnızca **audit yazımı başarısız olursa** kullanılır
  /// (REQ-AUDIT-007); yokluğunda servis doğru çalışmaya devam eder.
  CategoryService({
    required CanteenDatabase db,
    required CategoriesDao categories,
    required AuditLogsDao auditLogs,
    AppLogger? logger,
    DateTime Function()? clock,
  }) : _db = db,
       _categories = categories,
       _auditLogs = auditLogs,
       _logger = logger,
       _clock = clock ?? db.clock;

  // --- Okuma ---------------------------------------------------------------

  /// Kategori listesi.
  ///
  /// Varsayılan olarak **pasifler de** listelenir: yönetim ekranı pasif
  /// kategorileri görebilmelidir. Ürün formu ve satış ekranı filtresi
  /// [onlyActive] ile yalnızca aktifleri ister (docs/10 §1.3).
  ///
  /// Sıralama SQL tarafındadır: `sort_order`, sonra ad.
  Future<List<Category>> list({bool onlyActive = false}) async {
    final rows = onlyActive
        ? await _categories.listActive()
        : await _categories.listAll();
    return [for (final row in rows) row.toDomain()];
  }

  Future<Category?> findById(int id) async =>
      (await _categories.findById(id))?.toDomain();

  /// BR-PROD-003 · BR-CAT-004 — `Genel` sistem kategorisi (seed tarafından
  /// oluşturulur; bu servis sistem kategorisi **üretmez**).
  Future<Category?> systemCategory() async =>
      (await _categories.findSystemCategory())?.toDomain();

  // --- Yazma ---------------------------------------------------------------

  /// Yeni kategori oluşturur ve id'sini döndürür (REQ-CAT-001).
  ///
  /// REQ-CAT-005 · EC-CAT-003: ad **sistem genelinde benzersizdir** ve
  /// benzersizlik pasif kategorileri de kapsar. Karşılaştırma şemadaki
  /// `UNIQUE(name)` ile birebir aynıdır — büyük/küçük harf katlaması
  /// **eklenmez**; katlama bir şema kararı olurdu ve dokümanda yoktur.
  ///
  /// Ad yalnızca baştaki/sondaki boşluklardan arındırılır.
  Future<Result<int>> create({
    required String name,
    int sortOrder = 0,
    int? userId,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const Err(CategoryFailures.nameRequired);

    final now = _clock().toUtc();

    return _db.transaction(() async {
      if (await _categories.findByName(trimmed) != null) {
        return const Err<int>(CategoryFailures.nameExists);
      }
      try {
        final id = await _categories.insertCategory(
          name: trimmed,
          sortOrder: sortOrder,
          now: now,
        );
        await _writeAudit(
          action: actionCreated,
          now: now,
          userId: userId,
          entityId: id,
          newValue: {'name': trimmed, 'sort_order': sortOrder},
        );
        return Ok(id);
      } on Object catch (error) {
        // `ux_categories_name` yarışı — kontrol ile insert arasında.
        final failure = mapConstraintFailure(error);
        if (failure == null) rethrow;
        return const Err<int>(CategoryFailures.nameExists);
      }
    });
  }

  /// Kategori adını değiştirir (REQ-CAT-001).
  ///
  /// BR-CAT-004 · EC-CAT-001: `Genel` sistem kategorisinin adı **değiştirilemez.**
  Future<Result<void>> rename(int id, String name, {int? userId}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return const Err(CategoryFailures.nameRequired);

    final now = _clock().toUtc();

    return _db.transaction(() async {
      final current = await _categories.findById(id);
      if (current == null) return const Err<void>(CategoryFailures.notFound);
      if (current.isSystem) {
        return const Err<void>(CategoryFailures.systemProtected);
      }
      if (current.name == trimmed) return const Ok<void>(null);

      final clash = await _categories.findByName(trimmed);
      if (clash != null) return const Err<void>(CategoryFailures.nameExists);

      try {
        await _categories.updateName(id, trimmed);
      } on Object catch (error) {
        final failure = mapConstraintFailure(error);
        if (failure == null) rethrow;
        return const Err<void>(CategoryFailures.nameExists);
      }

      // docs/18 §2: yalnızca **değişen alanın** eski/yeni değeri yazılır.
      await _writeAudit(
        action: actionRenamed,
        now: now,
        userId: userId,
        entityId: id,
        oldValue: {'name': current.name},
        newValue: {'name': trimmed},
      );
      return const Ok<void>(null);
    });
  }

  /// Satış ekranı sıralamasını değiştirir (docs/10 §1.1 — "İsim ve sıralama
  /// değiştirilebilir").
  ///
  /// ## Neden audit kaydı yok
  ///
  /// docs/18 §3 kategori için dört action tanımlar: `categoryCreated`,
  /// `categoryRenamed`, `categoryDeactivated`, `categoryDeleted`. Sıralama için
  /// tanımlı bir action **yoktur** ve `rules/00 §6` dokümanda olmayan bir kaydı
  /// uydurmayı yasaklar. Sıralama finansal veya denetimsel bir değer taşımaz;
  /// yalnızca ekran düzenidir.
  ///
  /// Sistem kategorisi koruması BR-CAT-004'te **ad, pasifleştirme ve silme**
  /// ile sınırlıdır; sıralama kapsam dışıdır ve `Genel` de sıralanabilir.
  Future<Result<void>> updateSortOrder(int id, int sortOrder) async {
    final affected = await _categories.updateSortOrder(id, sortOrder);
    if (affected == 0) return const Err(CategoryFailures.notFound);
    return const Ok(null);
  }

  /// Kategoriyi pasifleştirir (REQ-CAT-001).
  ///
  /// **BR-CAT-003 · REQ-CAT-003 — bağlı ürünlere DOKUNULMAZ.** Ürünler geçerli
  /// kalır, satılabilir ve raporlanır; yalnızca yeni ürün ataması engellenir
  /// (bu engel ürün formunun [list] çağrısındaki `onlyActive` ile sağlanır).
  ///
  /// EC-CAT-002: içinde ürün olsa bile pasifleştirme mümkündür.
  /// BR-CAT-004 · EC-CAT-001: `Genel` pasifleştirilemez.
  ///
  /// Zaten pasif bir kategori için işlem **yinelenmez**: veri değişmediği için
  /// audit kaydı da üretilmez (docs/18 §4).
  Future<Result<void>> deactivate(int id, {int? userId}) async {
    final now = _clock().toUtc();

    return _db.transaction(() async {
      final current = await _categories.findById(id);
      if (current == null) return const Err<void>(CategoryFailures.notFound);
      if (current.isSystem) {
        return const Err<void>(CategoryFailures.systemProtected);
      }
      if (!current.isActive) return const Ok<void>(null);

      await _categories.setActive(id, false);
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

  /// **Koşullu** kalıcı silme — BR-CAT-005 · REQ-CAT-006 · docs/10 §1.2b.
  ///
  /// Silme yalnızca kategori **hiç kullanılmamışsa** yapılır:
  ///
  /// ```text
  /// Bu kategoriye atanmış ürün var mı?              (aktif veya pasif)
  ///   veya
  /// Bu kategori bir satış satırı snapshot'ında geçiyor mu?
  ///   ├── HAYIR → kalıcı silinir + audit (EC-CAT-005)
  ///   └── EVET  → Err; kullanıcı pasifleştirmeye yönlendirilir (EC-CAT-006)
  /// ```
  ///
  /// EC-CAT-006 kritik ayrımdır: ürünü kalmamış ama geçmiş satış snapshot'ında
  /// geçen bir kategori **silinmez** — silinirse geçmiş kategori raporu bozulur.
  ///
  /// İki sayım ve silme **aynı transaction** içindedir: aksi hâlde sayım ile
  /// silme arasında o kategoriye bir ürün eklenebilir ve `products.category_id`
  /// artık var olmayan bir satıra işaret ederdi.
  ///
  /// BR-CAT-004 · EC-CAT-001: `Genel` her koşulda korunur.
  Future<Result<void>> delete(int id, {int? userId}) async {
    final now = _clock().toUtc();

    return _db.transaction(() async {
      final current = await _categories.findById(id);
      if (current == null) return const Err<void>(CategoryFailures.notFound);
      if (current.isSystem) {
        return const Err<void>(CategoryFailures.systemProtected);
      }

      final productCount = await _categories.countProducts(id);
      final saleItemCount = await _categories.countSaleItemSnapshots(id);
      if (productCount > 0 || saleItemCount > 0) {
        return Err<void>(
          CategoryFailures.inUse(
            productCount: productCount,
            saleItemCount: saleItemCount,
          ),
        );
      }

      await _categories.deleteById(id);

      // docs/18 §3: `categoryDeleted` metadata'sı kategori adını taşır — kayıt
      // silindikten sonra `entity_id` tek başına anlamsız kalırdı.
      await _writeAudit(
        action: actionDeleted,
        now: now,
        userId: userId,
        entityId: id,
        metadata: {'name': current.name},
      );
      return const Ok<void>(null);
    });
  }

  /// Kategoriye atanmış ürün sayısı — pasifleştirme onayı bu sayıyı gösterir
  /// (docs/10 §1.3: "Bu kategoride 23 aktif ürün var").
  Future<int> productCount(int id) => _categories.countProducts(id);

  /// Audit kaydı — REQ-AUDIT-007: yazım hatası ana işlemi **başarısız kılmaz.**
  ///
  /// Deseni `FinancialAccessService._writeAudit` ile birebir aynıdır; ikisi de
  /// Faz 6'da genel `AuditService`'e devredilecektir (REQ-AUDIT-012).
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
