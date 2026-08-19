/// Ürün yönetimi — **docs/09 · BR-PROD-001…014 · REQ-PROD-001…015**
///
/// ## Kapsam sınırı (Faz 3c)
///
/// | Kapsamda | Kapsamda **değil** |
/// |---|---|
/// | Ürün oluşturma / düzenleme | Favoriler (REQ-PROD-009) → **Faz 3d** |
/// | Barkod ekleme / silme | Görsel (REQ-IMG-*) → **Faz 3d** |
/// | Pasifleştirme / aktifleştirme | Scanner / HID girdisi → **Faz 4** |
/// | Koşullu kalıcı silme | Hızlı ekleme akışı (docs/09 §2.1) → **Faz 5** |
/// | Arama ve sayfalı listeleme | Toplu import (docs/09 §2.3) → **Faz 10** |
///
/// `is_favorite` ve `image_path` **okunur ama yazılmaz**: düzenleme bu iki
/// alanı daima mevcut değeriyle korur. Bugün yazılsalardı, 3d'nin görsel
/// yaşam döngüsü (orphan işaretleme — docs/21 §4) yarım kurulmuş olurdu.
///
/// ## Transaction sınırı
///
/// rules/01 §5: transaction **yalnızca bu katmanda** açılır.
/// rules/03 §10: "Ürün + barkod oluşturma" atomik olmak zorundadır —
/// `product + productBarcodes + initial hareket + audit` tek transaction'dır.
///
/// Kontrol ile yazma arasında yarış oluşmaması için benzersizlik ve kullanım
/// kontrolleri de yazma ile **aynı** transaction içindedir.
///
/// ⚠️ Bir `Err` **kendiliğinden rollback yapmaz** (drift yalnızca fırlatılan
/// hatada geri alır). Yazma başladıktan sonra reddedilen her durum bu yüzden
/// [_Abort] ile fırlatılır ve [_transactional] tarafından `Err`'e çevrilir.
/// Örnek: üç barkodun üçüncüsü başka ürüne aitse ürün de oluşmaz.
///
/// ## Audit
///
/// rules/03 §9/1: audit kaydı, kaydettiği işlemle **aynı transaction**
/// içindedir. REQ-AUDIT-007: audit yazımındaki hata ana işlemi başarısız
/// kılmaz — yakalanır ve log dosyasına yazılır.
///
/// Action adları **docs/18 §3'ten** alınır; orada olmayan bir action
/// uydurulmaz (rules/00 §6). Bunun bir sonucu vardır: ad, açıklama, marka,
/// gramaj, raf konumu ve KDV oranı değişikliklerinin docs/18 §3'te karşılığı
/// **yoktur** ve bu yüzden kaydedilmezler. Fiyat, maliyet, kategori,
/// tedarikçi ve minimum stok değişiklikleri kaydedilir.
library;

import 'dart:convert';

import '../../core/logging/app_logger.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart' show MoneyParser;
import '../../core/result/result.dart';
import '../../data/dao/daos.dart';
import '../../data/db/canteen_database.dart' show CanteenDatabase;
import '../../data/repositories/failures.dart';
import '../../domain/models/product.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/stock_repository.dart';
import '../../domain/services/barcode_rules.dart';
import '../../domain/services/product_rules.dart';
import '../stock/stock_service.dart';
import 'product_draft.dart';
import 'product_failures.dart';
import 'product_warnings.dart';

/// docs/18 §3 — `productCreated` metadata'sı "oluşturma yolu"nu taşır.
enum ProductCreationPath {
  /// docs/09 §2.2 — Ürünler ekranındaki tam form.
  detailed('detailed'),

  /// docs/09 §2.1 — barkod okutuldu, ürün bulunamadı (Faz 5).
  quick('quick'),

  /// docs/09 §2.3 — Excel/CSV import (Faz 10).
  import('import');

  final String wire;

  const ProductCreationPath(this.wire);
}

/// Kaydetme sonucu: ürün id'si + **engellenmeyen** uyarılar.
class ProductSaveOutcome {
  final int productId;
  final List<ProductWarning> warnings;

  const ProductSaveOutcome({required this.productId, this.warnings = const []});
}

/// Ürünün geçmiş kullanımı — silme/pasifleştirme onayı bu veriyle kurulur
/// (docs/09 §4).
///
/// Ekran metni bu sayılardan üretilir ("Bu ürün 47 satışta kullanılmış");
/// kararı veren **servistir**, dialog değil.
class ProductUsage {
  final int saleItemCount;
  final int stockMovementCount;
  final int stockQuantity;

  const ProductUsage({
    required this.saleItemCount,
    required this.stockMovementCount,
    required this.stockQuantity,
  });

  /// BR-PROD-014 · EC-PROD-019 — hiç satılmamış **ve** hiç stok hareketi
  /// olmayan ürün kalıcı silinebilir.
  ///
  /// ⚠️ Başlangıç stoğuyla oluşturulan ürünün defterinde bir `initial`
  /// hareketi vardır (REQ-PROD-007); bu ürün EC-PROD-021 gereği kalıcı
  /// silinemez, yalnızca pasifleştirilir. Sıfır başlangıç stoğuyla açılan
  /// ürün ise hareket üretmez ve silinebilir.
  bool get canDeletePermanently =>
      saleItemCount == 0 && stockMovementCount == 0;
}

/// Yazma başladıktan sonra reddedilen durumlar için — transaction'ı geri alır.
class _Abort implements Exception {
  final Failure failure;
  const _Abort(this.failure);
}

class ProductService {
  /// docs/18 §2 — `entity_type`.
  static const String auditEntityType = 'product';

  // docs/18 §3 — Ürün tablosundaki action adları.
  static const String actionCreated = 'productCreated';
  static const String actionPriceChanged = 'productPriceChanged';
  static const String actionCostChanged = 'productCostChanged';
  static const String actionCategoryChanged = 'productCategoryChanged';
  static const String actionSupplierChanged = 'productSupplierChanged';
  static const String actionMinStockChanged = 'productMinStockChanged';
  static const String actionDeactivated = 'productDeactivated';
  static const String actionActivated = 'productActivated';
  static const String actionDeleted = 'productDeleted';
  static const String actionBarcodeAdded = 'barcodeAdded';
  static const String actionBarcodeRemoved = 'barcodeRemoved';

  final CanteenDatabase _db;
  final ProductRepository _products;
  final StockRepository _stock;
  final StockService _stockService;
  final CategoriesDao _categories;
  final SaleItemsDao _saleItems;
  final AuditLogsDao _auditLogs;
  final AppLogger? _logger;
  final DateTime Function() _clock;

  ProductService({
    required CanteenDatabase db,
    required ProductRepository products,
    required StockRepository stock,
    required StockService stockService,
    required CategoriesDao categories,
    required SaleItemsDao saleItems,
    required AuditLogsDao auditLogs,
    AppLogger? logger,
    DateTime Function()? clock,
  }) : _db = db,
       _products = products,
       _stock = stock,
       _stockService = stockService,
       _categories = categories,
       _saleItems = saleItems,
       _auditLogs = auditLogs,
       _logger = logger,
       _clock = clock ?? db.clock;

  // --- Fiyat girdisi -------------------------------------------------------

  /// REQ-FIN-006 — kullanıcı `25,50` · `25.50` · `25` · `₺25,50` yazabilir.
  ///
  /// Ayrıştırma `core/money`'deki **tek** parser'a devredilir (rules/01 §2);
  /// burada ikinci bir para ayrıştırıcısı yoktur.
  static Result<Money> parseSalePrice(String input) {
    if (input.trim().isEmpty) {
      return const Err(ProductFailures.salePriceRequired);
    }
    final money = MoneyParser.tryParse(input);
    if (money == null) return const Err(ProductFailures.priceInvalid);
    if (money.isNegative) return const Err(ProductFailures.salePriceNegative);
    return Ok(money);
  }

  /// BR-PROD-002 — boş bırakılırsa `0` kuruş. Alan asla `null` olmaz.
  static Result<Money> parsePurchasePrice(String input) {
    if (input.trim().isEmpty) return const Ok(Money.zero);
    final money = MoneyParser.tryParse(input);
    if (money == null) return const Err(ProductFailures.priceInvalid);
    if (money.isNegative) {
      return const Err(ProductFailures.purchasePriceNegative);
    }
    return Ok(money);
  }

  // --- Okuma ---------------------------------------------------------------

  Future<Product?> findById(int id) async =>
      (await _products.findById(id)).valueOrNull;

  /// Barkod ile ürün — bulunamazsa `null` (bilinmeyen barkod **beklenen** bir
  /// sonuçtur, rules/02 §10). Barkod önce normalize edilir (docs/11 §3).
  Future<Product?> findByBarcode(String barcode) async {
    final normalized = BarcodeRules.normalize(barcode);
    if (normalized.isEmpty) return null;
    return (await _products.findByBarcode(normalized)).valueOrNull;
  }

  /// REQ-PROD-010 · docs/09 §6 — Türkçe karakter ve büyük/küçük harf duyarsız
  /// arama; en fazla 50 sonuç, satış adedine göre sıralı.
  Future<List<Product>> search(
    String query, {
    bool includeInactive = false,
    int limit = ProductRules.searchResultLimit,
  }) => _products.search(query, includeInactive: includeInactive, limit: limit);

  /// REQ-PERF-006 — sayfalı ürün listesi.
  Future<List<Product>> list({
    bool includeInactive = false,
    int? categoryId,
    int limit = ProductRules.searchResultLimit,
    int offset = 0,
  }) => _products.list(
    includeInactive: includeInactive,
    categoryId: categoryId,
    limit: limit,
    offset: offset,
  );

  /// [list] ile aynı filtrenin toplam kayıt sayısı — sayfa göstergesi için.
  Future<int> count({bool includeInactive = false, int? categoryId}) =>
      _products.count(includeInactive: includeInactive, categoryId: categoryId);

  Future<List<String>> barcodesOf(int productId) =>
      _products.barcodesOf(productId);

  /// docs/09 §4 — silme/pasifleştirme onayının dayandığı sayılar.
  Future<Result<ProductUsage>> usage(int id) async {
    final product = await _products.findById(id);
    if (product.isErr) return const Err(ProductFailures.notFound);

    return Ok(
      ProductUsage(
        saleItemCount: await _saleItems.countOfProduct(id),
        stockMovementCount: await _stock.countMovements(id),
        stockQuantity: product.valueOrNull!.stockQuantity,
      ),
    );
  }

  /// Kaydetmeden **önce** gösterilecek uyarılar — EC-PROD-009/010 ·
  /// REQ-PROD-012.
  ///
  /// Ekran onay dialoglarını buna göre kurar. `create` ve `update` aynı
  /// hesabı tekrar yapar; böylece önizleme atlansa bile uyarı kaybolmaz
  /// (rules/01 §2 — tek implementasyon).
  Future<List<ProductWarning>> previewWarnings(
    ProductDraft draft, {
    int? productId,
  }) async {
    final validated = _validate(draft);
    if (validated.isErr) return const [];

    final category = await _resolveCategoryId(draft.categoryId);
    if (category == null) return const [];

    final current = productId == null
        ? null
        : (await _products.findById(productId)).valueOrNull;

    return _warningsFor(
      draft: validated.valueOrNull!,
      categoryId: category,
      current: current,
    );
  }

  // --- Yazma ---------------------------------------------------------------

  /// Yeni ürün oluşturur — **REQ-PROD-001…005 · REQ-PROD-007.**
  ///
  /// ```text
  /// Tek transaction (rules/03 §10):
  ///   products
  ///   product_barcodes      (0..N — BR-PROD-004)
  ///   stock_movements       (initial, yalnızca başlangıç stoğu > 0 ise)
  ///   products.stock_quantity
  ///   audit_logs            (productCreated)
  /// ```
  ///
  /// Barkodlardan biri **başka** bir ürüne aitse hiçbiri yazılmaz ve ürün de
  /// oluşmaz (EC-PROD-001). Aynı barkodun listede tekrarlanması sessizce
  /// yok sayılır (EC-PROD-003).
  ///
  /// [userId] zorunludur: stok hareketi `user_id` olmadan yazılamaz (şema) ve
  /// ürün işlemleri daima bir oturum içinde yapılır.
  Future<Result<ProductSaveOutcome>> create(
    ProductDraft draft, {
    required int userId,
    int initialStock = 0,
    List<String> barcodes = const [],
    ProductCreationPath creationPath = ProductCreationPath.detailed,
  }) async {
    final validated = _validate(draft);
    if (validated.isErr) return Err(validated.failureOrNull!);
    final input = validated.valueOrNull!;

    final normalizedBarcodes = _normalizeBarcodes(barcodes);
    if (normalizedBarcodes.isErr) return Err(normalizedBarcodes.failureOrNull!);

    final now = _clock().toUtc();

    return _transactional(() async {
      final categoryId = await _requireCategoryId(draft.categoryId);

      final warnings = await _warningsFor(
        draft: input,
        categoryId: categoryId,
        current: null,
      );

      final created = await _products.create(
        NewProduct(
          name: input.name,
          description: input.description,
          categoryId: categoryId,
          brand: input.brand,
          salesUnit: input.salesUnit,
          netWeightValue: input.netWeightValue,
          netWeightUnit: input.netWeightUnit,
          purchasePrice: input.purchasePrice,
          salePrice: input.salePrice,
          vatRateId: input.vatRateId,
          minimumStock: input.minimumStock,
          supplierId: input.supplierId,
          shelfLocation: input.shelfLocation,
        ),
      );
      if (created.isErr) throw _Abort(created.failureOrNull!);
      final productId = created.valueOrNull!;

      for (final barcode in normalizedBarcodes.valueOrNull!) {
        warnings.addAll(
          await _attachBarcode(
            productId: productId,
            barcode: barcode,
            now: now,
            userId: userId,
            // Barkod olayları `productCreated` kaydının parçasıdır; ürünle
            // birlikte eklenen barkodlar için ayrı `barcodeAdded` yazılmaz —
            // aksi hâlde tek bir kullanıcı eylemi N+1 satır üretirdi.
            writeAudit: false,
          ),
        );
      }

      // REQ-PROD-007 · BR-STOCK-003 — stok DOĞRUDAN yazılmaz; defter yazar.
      final stockResult = await _stockService.recordInitialStock(
        productId: productId,
        quantity: initialStock,
        userId: userId,
        // docs/13 §2 — `initial` için birim maliyet opsiyoneldir; o anda
        // bilinen maliyet alış fiyatıdır ve sonradan türetilemez.
        unitCost: input.purchasePrice,
      );
      if (stockResult.isErr) throw _Abort(stockResult.failureOrNull!);

      await _writeAudit(
        action: actionCreated,
        now: now,
        userId: userId,
        entityId: productId,
        newValue: {
          'name': input.name,
          'category_id': categoryId,
          'sale_price_minor': input.salePrice.minor,
          'purchase_price_minor': input.purchasePrice.minor,
        },
        // docs/18 §3 — `productCreated` metadata'sı oluşturma yolunu taşır.
        metadata: {
          'creation_path': creationPath.wire,
          'initial_stock': initialStock,
          'barcode_count': normalizedBarcodes.valueOrNull!.length,
        },
      );

      return ProductSaveOutcome(productId: productId, warnings: warnings);
    });
  }

  /// Ürünü günceller — **docs/09 §3.**
  ///
  /// Geçmiş satışlar **etkilenmez**: `sale_items` beş snapshot alanını taşır
  /// (rules/02 §3) ve buradan okunmaz da, yazılmaz da.
  ///
  /// `stock_quantity`, `is_favorite` ve `image_path` **korunur** (yukarıdaki
  /// kapsam notu).
  Future<Result<ProductSaveOutcome>> update(
    int id,
    ProductDraft draft, {
    required int userId,
  }) async {
    final validated = _validate(draft);
    if (validated.isErr) return Err(validated.failureOrNull!);
    final input = validated.valueOrNull!;

    final now = _clock().toUtc();

    return _transactional(() async {
      final found = await _products.findById(id);
      if (found.isErr) throw const _Abort(ProductFailures.notFound);
      final current = found.valueOrNull!;

      final categoryId = await _requireCategoryId(draft.categoryId);

      final warnings = await _warningsFor(
        draft: input,
        categoryId: categoryId,
        current: current,
      );

      final updated = await _products.update(
        Product(
          id: current.id,
          name: input.name,
          description: input.description,
          categoryId: categoryId,
          brand: input.brand,
          salesUnit: input.salesUnit,
          netWeightValue: input.netWeightValue,
          netWeightUnit: input.netWeightUnit,
          purchasePrice: input.purchasePrice,
          salePrice: input.salePrice,
          vatRateId: input.vatRateId,
          minimumStock: input.minimumStock,
          supplierId: input.supplierId,
          shelfLocation: input.shelfLocation,
          // Faz 3d'ye ait alanlar ve türetilmiş stok — olduğu gibi korunur.
          stockQuantity: current.stockQuantity,
          imagePath: current.imagePath,
          isFavorite: current.isFavorite,
          isActive: current.isActive,
          createdAt: current.createdAt,
          updatedAt: now,
        ),
      );
      if (updated.isErr) throw _Abort(updated.failureOrNull!);

      await _auditFieldChanges(
        current: current,
        input: input,
        categoryId: categoryId,
        now: now,
        userId: userId,
      );

      return ProductSaveOutcome(productId: id, warnings: warnings);
    });
  }

  /// BR-PROD-009 · REQ-PROD-006 — ürünü pasife alır.
  ///
  /// Geçmiş kayıtlar korunur; ürün raporlarda görünmeye devam eder. Stoğu olan
  /// ürün için **uyarı** döner, işlem engellenmez (docs/09 §4).
  ///
  /// Zaten pasif ürün için işlem yinelenmez; veri değişmediği için audit kaydı
  /// da üretilmez (docs/18 §4).
  Future<Result<List<ProductWarning>>> deactivate(
    int id, {
    required int userId,
  }) async {
    final now = _clock().toUtc();

    return _transactional(() async {
      final found = await _products.findById(id);
      if (found.isErr) throw const _Abort(ProductFailures.notFound);
      final current = found.valueOrNull!;
      if (!current.isActive) return const <ProductWarning>[];

      await _products.setActive(id, false);
      await _writeAudit(
        action: actionDeactivated,
        now: now,
        userId: userId,
        entityId: id,
        oldValue: {'is_active': true},
        newValue: {'is_active': false},
        // docs/18 §3 — pasifleştirme metadata'sı stok miktarını taşır.
        metadata: {'stock_quantity': current.stockQuantity},
      );

      return [
        if (current.stockQuantity != 0)
          ProductWarnings.deactivatedWithStock(current.stockQuantity),
      ];
    });
  }

  /// Pasif ürünü yeniden aktifleştirir — docs/09 §4 (BR-BARC-007: pasif ürünün
  /// barkodu okutulduğunda "Aktifleştirilsin mi?" sorulur).
  Future<Result<void>> activate(int id, {required int userId}) async {
    final now = _clock().toUtc();

    return _transactional(() async {
      final found = await _products.findById(id);
      if (found.isErr) throw const _Abort(ProductFailures.notFound);
      if (found.valueOrNull!.isActive) return;

      await _products.setActive(id, true);
      await _writeAudit(
        action: actionActivated,
        now: now,
        userId: userId,
        entityId: id,
        oldValue: {'is_active': false},
        newValue: {'is_active': true},
        metadata: {'stock_quantity': found.valueOrNull!.stockQuantity},
      );
    });
  }

  /// **Koşullu** kalıcı silme — BR-PROD-014 · REQ-PROD-013 · EC-PROD-019.
  ///
  /// ```text
  /// Hiç satılmamış VE hiç stok hareketi yok
  ///   ├── EVET → ürün + barkodları kalıcı silinir + audit
  ///   └── HAYIR → Err; kullanıcı pasifleştirmeye yönlendirilir
  ///               (EC-PROD-020 satış, EC-PROD-021 stok hareketi)
  /// ```
  ///
  /// ⚠️ Başlangıç stoğuyla oluşturulan ürünün defterinde `initial` hareketi
  /// vardır; bu ürün **silinemez** (EC-PROD-021 — defter referansı korunur).
  ///
  /// İki sayım ve silme **aynı transaction** içindedir: aksi hâlde sayım ile
  /// silme arasında ürün satılabilir ve `sale_items.product_id` var olmayan
  /// bir satıra işaret ederdi.
  ///
  /// Silinen barkodlar benzersizlik havuzundan çıkar ve başka ürüne
  /// atanabilir (EC-PROD-022).
  Future<Result<void>> delete(int id, {required int userId}) async {
    final now = _clock().toUtc();

    return _transactional(() async {
      final found = await _products.findById(id);
      if (found.isErr) throw const _Abort(ProductFailures.notFound);
      final current = found.valueOrNull!;

      final saleItemCount = await _saleItems.countOfProduct(id);
      final movementCount = await _stock.countMovements(id);
      if (saleItemCount > 0 || movementCount > 0) {
        throw _Abort(
          ProductFailures.inUse(
            saleItemCount: saleItemCount,
            stockMovementCount: movementCount,
          ),
        );
      }

      final barcodes = await _products.barcodesOf(id);
      await _products.removeAllBarcodesOf(id);
      await _products.deleteById(id);

      // docs/18 §3 — `productDeleted` metadata'sı ürün adını ve barkodları
      // taşır: kayıt silindikten sonra `entity_id` tek başına anlamsız kalırdı.
      await _writeAudit(
        action: actionDeleted,
        now: now,
        userId: userId,
        entityId: id,
        metadata: {'name': current.name, 'barcodes': barcodes},
      );
    });
  }

  // --- Barkod --------------------------------------------------------------

  /// Ürüne barkod ekler — **BR-PROD-004/005 · REQ-PROD-004/005.**
  ///
  /// | Durum | Davranış |
  /// |---|---|
  /// | Barkod **başka** ürüne ait | `Err` — sahip ürünün adı ve id'si döner (EC-PROD-001) |
  /// | Barkod **aynı** ürüne zaten ekli | Sessizce yok sayılır, `Ok` (EC-PROD-003) |
  /// | Kontrol hanesi geçersiz | Kaydedilir + **uyarı** (EC-PROD-015) |
  /// | Baştaki sıfır | **Korunur** (EC-PROD-014) |
  Future<Result<List<ProductWarning>>> addBarcode(
    int productId,
    String barcode, {
    required int userId,
    bool isPrimary = false,
  }) async {
    final normalized = BarcodeRules.normalize(barcode);
    if (normalized.isEmpty) return const Err(ProductFailures.barcodeRequired);

    final now = _clock().toUtc();

    return _transactional(() async {
      final found = await _products.findById(productId);
      if (found.isErr) throw const _Abort(ProductFailures.notFound);

      if (isPrimary) {
        // docs/04 §3.6 — ürün başına en fazla bir `is_primary`.
        await _products.clearPrimaryBarcodes(productId);
      }

      return _attachBarcode(
        productId: productId,
        barcode: normalized,
        now: now,
        userId: userId,
        isPrimary: isPrimary,
      );
    });
  }

  /// Barkodu siler — **EC-PROD-016.**
  ///
  /// Ürünün **son** barkodu da silinebilir; ürün barkodsuz kalır ve favoriler /
  /// arama üzerinden satılmaya devam eder (BR-PROD-004 · EC-PROD-002).
  /// Silinen barkod global benzersizlik havuzundan çıkar (docs/09 §3).
  Future<Result<void>> removeBarcode(
    int productId,
    String barcode, {
    required int userId,
  }) async {
    final normalized = BarcodeRules.normalize(barcode);
    if (normalized.isEmpty) return const Err(ProductFailures.barcodeRequired);

    final now = _clock().toUtc();

    return _transactional(() async {
      final removed = await _products.removeBarcode(
        productId: productId,
        barcode: normalized,
      );
      // Zaten yoksa veri değişmedi; audit kaydı da üretilmez (docs/18 §4).
      if (removed == 0) return;

      await _writeAudit(
        action: actionBarcodeRemoved,
        now: now,
        userId: userId,
        entityId: productId,
        metadata: {'barcode': normalized},
      );
    });
  }

  // --- İç yardımcılar ------------------------------------------------------

  /// Barkodu ürüne bağlar. **Çağıranın transaction'ı içinde** çalışır.
  Future<List<ProductWarning>> _attachBarcode({
    required int productId,
    required String barcode,
    required DateTime now,
    required int userId,
    bool isPrimary = false,
    bool writeAudit = true,
  }) async {
    final owner = await _products.findByBarcode(barcode);
    if (owner.isOk) {
      final ownerProduct = owner.valueOrNull!;
      // EC-PROD-003 — aynı ürüne ikinci kez: sessizce yok sayılır.
      if (ownerProduct.id == productId) return const [];

      // EC-PROD-001 — BR-PROD-010: pasif ürünler de kısıtı işgal eder.
      throw _Abort(
        ProductFailures.barcodeOwnedByOther(
          productName: ownerProduct.name,
          productId: ownerProduct.id,
        ),
      );
    }

    final added = await _products.addBarcode(
      productId: productId,
      barcode: barcode,
      isPrimary: isPrimary,
    );
    if (added.isErr) {
      // `ux_barcode` yarışı — kontrol ile insert arasında.
      final failure = added.failureOrNull!;
      throw _Abort(
        failure.code == DataFailures.barcodeExists.code
            ? ProductFailures.barcodeExists
            : failure,
      );
    }

    if (writeAudit) {
      await _writeAudit(
        action: actionBarcodeAdded,
        now: now,
        userId: userId,
        entityId: productId,
        metadata: {'barcode': barcode},
      );
    }

    // EC-PROD-015 — kontrol hanesi yanlışsa uyarılır, engellenmez.
    return [
      if (BarcodeRules.isChecksumValid(barcode) == false)
        ProductWarnings.barcodeChecksumInvalid,
    ];
  }

  /// Barkod listesini normalize eder ve **tekrarları eler** (EC-PROD-003).
  Result<List<String>> _normalizeBarcodes(List<String> barcodes) {
    final result = <String>[];
    for (final raw in barcodes) {
      final normalized = BarcodeRules.normalize(raw);
      if (normalized.isEmpty) return const Err(ProductFailures.barcodeRequired);
      if (!result.contains(normalized)) result.add(normalized);
    }
    return Ok(result);
  }

  /// BR-PROD-003 — kategori seçilmezse `Genel`.
  ///
  /// **Pasif kategori reddedilmez:** EC-PROD-005 gereği kategorisi
  /// pasifleştirilmiş ürün geçerli kalır ve düzenlenebilmelidir. Yeni ürün
  /// atamasında pasif kategorinin görünmemesi bir **liste filtresidir**
  /// (docs/10 §1.3, `CategoryService.list(onlyActive: true)`).
  Future<int?> _resolveCategoryId(int? categoryId) async {
    if (categoryId == null) {
      return (await _categories.findSystemCategory())?.id;
    }
    return (await _categories.findById(categoryId))?.id;
  }

  /// [_resolveCategoryId]'nin transaction içindeki hâli — bulunamazsa aborts.
  Future<int> _requireCategoryId(int? categoryId) async {
    final resolved = await _resolveCategoryId(categoryId);
    if (resolved != null) return resolved;
    throw _Abort(
      categoryId == null
          ? ProductFailures.generalCategoryMissing
          : ProductFailures.categoryNotFound,
    );
  }

  Future<List<ProductWarning>> _warningsFor({
    required _ValidDraft draft,
    required int categoryId,
    required Product? current,
  }) async {
    final warnings = <ProductWarning>[];

    // EC-PROD-009 — zararına satış: izin verilir, uyarılır.
    if (draft.purchasePrice > draft.salePrice) {
      warnings.add(ProductWarnings.purchaseAboveSale);
    }

    // EC-PROD-010 · BR-PROD-013 — aynı ad + aynı kategori.
    final duplicate = await _products.existsWithName(
      name: draft.name,
      categoryId: categoryId,
      excludeProductId: current?.id,
    );
    if (duplicate) warnings.add(ProductWarnings.duplicateName);

    // REQ-PROD-012 — satış fiyatı %50'den fazla değişiyor.
    if (current != null &&
        ProductRules.isSignificantPriceChange(
          current.salePrice,
          draft.salePrice,
        )) {
      warnings.add(ProductWarnings.largePriceChange);
    }

    return warnings;
  }

  /// docs/18 §3 — yalnızca **tanımlı** action'lar ve yalnızca **değişen**
  /// alanlar yazılır (docs/18 §2).
  Future<void> _auditFieldChanges({
    required Product current,
    required _ValidDraft input,
    required int categoryId,
    required DateTime now,
    required int userId,
  }) async {
    // REQ-PROD-008 — fiyat değişikliği eski ve yeni değeriyle yazılır.
    if (current.salePrice != input.salePrice) {
      await _writeAudit(
        action: actionPriceChanged,
        now: now,
        userId: userId,
        entityId: current.id,
        oldValue: {'sale_price_minor': current.salePrice.minor},
        newValue: {'sale_price_minor': input.salePrice.minor},
      );
    }

    if (current.purchasePrice != input.purchasePrice) {
      await _writeAudit(
        action: actionCostChanged,
        now: now,
        userId: userId,
        entityId: current.id,
        oldValue: {'purchase_price_minor': current.purchasePrice.minor},
        newValue: {'purchase_price_minor': input.purchasePrice.minor},
        // docs/18 §3 — `productCostChanged` metadata'sı kaynağı taşır.
        // Stok girişinden gelen maliyet değişikliği Faz 6'ya aittir.
        metadata: {'source': 'manual'},
      );
    }

    if (current.categoryId != categoryId) {
      await _writeAudit(
        action: actionCategoryChanged,
        now: now,
        userId: userId,
        entityId: current.id,
        oldValue: {'category_id': current.categoryId},
        newValue: {'category_id': categoryId},
      );
    }

    if (current.supplierId != input.supplierId) {
      await _writeAudit(
        action: actionSupplierChanged,
        now: now,
        userId: userId,
        entityId: current.id,
        oldValue: {'supplier_id': current.supplierId},
        newValue: {'supplier_id': input.supplierId},
      );
    }

    if (current.minimumStock != input.minimumStock) {
      await _writeAudit(
        action: actionMinStockChanged,
        now: now,
        userId: userId,
        entityId: current.id,
        oldValue: {'minimum_stock': current.minimumStock},
        newValue: {'minimum_stock': input.minimumStock},
      );
    }
  }

  /// docs/09 §1 — alan doğrulaması. Saf; veritabanına dokunmaz.
  Result<_ValidDraft> _validate(ProductDraft draft) {
    final name = draft.name.trim();
    // EC-PROD-013 — yalnızca boşluktan oluşan ad reddedilir.
    if (name.isEmpty) return const Err(ProductFailures.nameRequired);
    if (name.length > ProductRules.nameMaxLength) {
      return const Err(ProductFailures.nameTooLong);
    }

    final description = ProductRules.normalizeOptional(draft.description);
    if (description != null &&
        description.length > ProductRules.descriptionMaxLength) {
      return const Err(ProductFailures.descriptionTooLong);
    }

    final shelfLocation = ProductRules.normalizeOptional(draft.shelfLocation);
    if (shelfLocation != null &&
        shelfLocation.length > ProductRules.shelfLocationMaxLength) {
      return const Err(ProductFailures.shelfLocationTooLong);
    }

    // BR-PROD-006 · EC-PROD-007/008 — `0` geçerli, negatif değil.
    if (draft.salePrice.isNegative) {
      return const Err(ProductFailures.salePriceNegative);
    }
    if (draft.purchasePrice.isNegative) {
      return const Err(ProductFailures.purchasePriceNegative);
    }
    if (draft.minimumStock < 0) {
      return const Err(ProductFailures.minimumStockNegative);
    }

    final netWeightUnit = ProductRules.normalizeOptional(draft.netWeightUnit);
    // BR-PROD-011 · EC-PROD-018 — çift kuralı. Şemadaki CHECK ile aynı kural;
    // burada anlaşılır Türkçe hataya çevrilir (REQ-SEC-007).
    if (!ProductRules.isWeightPairValid(draft.netWeightValue, netWeightUnit)) {
      return const Err(ProductFailures.netWeightPairIncomplete);
    }

    return Ok(
      _ValidDraft(
        name: name,
        description: description,
        brand: ProductRules.normalizeOptional(draft.brand),
        salesUnit: ProductRules.normalizeOptional(draft.salesUnit),
        netWeightValue: draft.netWeightValue,
        netWeightUnit: netWeightUnit,
        purchasePrice: draft.purchasePrice,
        salePrice: draft.salePrice,
        vatRateId: draft.vatRateId,
        minimumStock: draft.minimumStock,
        supplierId: draft.supplierId,
        shelfLocation: shelfLocation,
      ),
    );
  }

  /// Transaction sarmalayıcı — [_Abort] fırlatılırsa **her şey geri alınır**
  /// ve hata `Err`'e çevrilir.
  Future<Result<T>> _transactional<T>(Future<T> Function() body) async {
    try {
      return Ok(await _db.transaction(body));
    } on _Abort catch (abort) {
      return Err(abort.failure);
    }
  }

  /// Audit kaydı — REQ-AUDIT-007: yazım hatası ana işlemi **başarısız kılmaz.**
  ///
  /// Deseni `CategoryService._writeAudit` ile birebir aynıdır; ikisi de Faz
  /// 6'da genel `AuditService`'e devredilecektir (REQ-AUDIT-012).
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

/// Doğrulanmış ve normalize edilmiş taslak — yalnızca [ProductService] içinde.
class _ValidDraft {
  final String name;
  final String? description;
  final String? brand;
  final String? salesUnit;
  final int? netWeightValue;
  final String? netWeightUnit;
  final Money purchasePrice;
  final Money salePrice;
  final int? vatRateId;
  final int minimumStock;
  final int? supplierId;
  final String? shelfLocation;

  const _ValidDraft({
    required this.name,
    required this.description,
    required this.brand,
    required this.salesUnit,
    required this.netWeightValue,
    required this.netWeightUnit,
    required this.purchasePrice,
    required this.salePrice,
    required this.vatRateId,
    required this.minimumStock,
    required this.supplierId,
    required this.shelfLocation,
  });
}
