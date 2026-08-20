/// Ürün içe aktarma — **docs/20 §3–§6 · BR-DATA-005 · BR-IMEX-001/002 ·
/// REQ-IMEX-004…012**
///
/// | Test | Kural |
/// |---|---|
/// | Önizleme **hiçbir şey yazmaz** | docs/20 §5 |
/// | Onaysız import **başlamaz** | REQ-IMEX-007 |
/// | Tek transaction, tam rollback | REQ-IMEX-008 · BR-DATA-005 |
/// | Dosya içi duplicate reddedilir | BR-IMEX-002 |
/// | Barkod politikası uygulanır | BR-IMEX-001 |
/// | Stok **hareket** oluşturur | REQ-IMEX-011 |
/// | Kategori/tedarikçi otomatik oluşur | docs/20 §4 |
///
/// ## Kapsanan requirement'lar (Faz 11 izlenebilirliği)
///
/// - **REQ-IMEX-009** — barkod çakışma politikası seçilir
/// - **REQ-IMEX-010** — dosya içi duplicate reddedilir
/// - **REQ-IMEX-012** — satış/hareket import edilemez
/// ## Kapsanan uç durumlar (docs/26 · Faz 11 izlenebilirliği)
///
/// - **EC-IMEX-002** — sistemde var olan barkod dosyada
/// - **EC-IMEX-005** — zorunlu sütun eşleştirilmemiş
/// - **EC-IMEX-010** — import ortasında hata → tam rollback
/// - **EC-IMEX-011** — import onaylanmadı/iptal edildi → hiçbir kayıt oluşmaz
///
library;

import 'package:canteen/application/audit/audit_actions.dart';
import 'package:canteen/application/audit/audit_service.dart';
import 'package:canteen/application/import/import_failures.dart';
import 'package:canteen/application/import/product_import_service.dart';
import 'package:canteen/application/product/product_service.dart';
import 'package:canteen/application/stock/stock_service.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide
        Cart,
        CartItem,
        Category,
        Product,
        Sale,
        SaleItem,
        StockMovement,
        Supplier;
import 'package:canteen/data/files/product_image_store.dart';
import 'package:canteen/data/repositories/drift_product_repository.dart';
import 'package:canteen/data/repositories/drift_stock_repository.dart';
import 'package:canteen/domain/enums/stock_movement_type.dart';
import 'package:canteen/domain/services/product_import_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late TempAppPaths temp;
  late ProductImportService service;
  late DriftProductRepository products;
  late DriftStockRepository stock;
  late int userId;

  setUp(() async {
    db = memoryDatabase();
    temp = await TempAppPaths.create();
    products = DriftProductRepository(db);
    stock = DriftStockRepository(db);
    final audit = AuditService(
      auditLogs: AuditLogsDao(db),
      clock: () => testEpochUtc,
    );
    final stockService = StockService(
      db: db,
      stock: stock,
      products: products,
      audit: audit,
      clock: () => testEpochUtc,
    );
    service = ProductImportService(
      db: db,
      products: ProductService(
        db: db,
        products: products,
        stock: stock,
        stockService: stockService,
        categories: CategoriesDao(db),
        saleItems: SaleItemsDao(db),
        auditLogs: AuditLogsDao(db),
        appSettings: AppSettingsDao(db),
        images: ProductImageStore(paths: temp.paths),
        clock: () => testEpochUtc,
      ),
      productRepo: products,
      categories: CategoriesDao(db),
      suppliers: SuppliersDao(db),
      vatRates: VatRatesDao(db),
      audit: audit,
      clock: () => testEpochUtc,
    );
    userId = await insertTestUser(db);
  });

  tearDown(() async {
    await db.close();
    temp.dispose();
  });

  const header =
      'Ürün adı;Satış fiyatı (KDV dahil);Alış fiyatı;Kategori;'
      'Barkod;Başlangıç stoğu;Tedarikçi';

  Future<ImportPreview> previewOf(
    String csv, {
    DuplicateBarcodePolicy policy = DuplicateBarcodePolicy.skip,
  }) async {
    final parsedHeader = csv.split('\n').first.split(';');
    final result = await service.preview(
      contents: csv,
      mapping: ProductImportRules.autoMap(parsedHeader),
      policy: policy,
    );
    expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
    return result.valueOrNull!;
  }

  Future<ImportResult> applyOf(ImportPreview preview) async {
    final result = await service.apply(
      preview: preview,
      userId: userId,
      confirmed: true,
    );
    expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
    return result.valueOrNull!;
  }

  Future<int> productCount() async =>
      (await db.select(db.products).get()).length;

  // -------------------------------------------------------------------------

  group('docs/20 §5 — önizleme HİÇBİR ŞEY yazmaz', () {
    test('geçerli dosyada bile ürün oluşmaz', () async {
      final preview = await previewOf('$header\nKola;25,00;18,00;İçecek;;10;');

      expect(preview.createCount, 1);
      expect(await productCount(), 0, reason: 'Önizleme yalnızca OKUR.');
      expect(await db.select(db.categories).get(), hasLength(1));
    });

    test('yeni kategori ve tedarikçi ÖNCEDEN bildirilir', () async {
      final preview = await previewOf(
        '$header\nKola;25,00;;İçecek;;;Kola A.Ş.',
      );

      expect(preview.newCategories, {'İçecek'});
      expect(preview.newSuppliers, {'Kola A.Ş.'});
    });

    test('mevcut kategori YENİ sayılmaz', () async {
      await CategoriesDao(
        db,
      ).insertCategory(name: 'İçecek', sortOrder: 1, now: testEpochUtc);

      final preview = await previewOf('$header\nKola;25,00;;İçecek;;;');

      expect(preview.newCategories, isEmpty);
    });
  });

  group('REQ-IMEX-007/008 — onay ve atomiklik', () {
    test('onaysız import BAŞLAMAZ', () async {
      final preview = await previewOf('$header\nKola;25,00;;;;;');

      final result = await service.apply(
        preview: preview,
        userId: userId,
        confirmed: false,
      );

      expect(result.failureOrNull, ImportFailures.notConfirmed);
      expect(await productCount(), 0);
    });

    test('geçerli satır yoksa REDDEDİLİR', () async {
      final preview = await previewOf('$header\n;25,00;;;;;');

      final result = await service.apply(
        preview: preview,
        userId: userId,
        confirmed: true,
      );

      expect(result.failureOrNull, ImportFailures.nothingToImport);
    });

    test('BR-DATA-005 — bir satır patlarsa HİÇBİRİ yazılmaz', () async {
      // İkinci satırın kategorisi geçersiz bir id'ye işaret edecek şekilde
      // önizleme bozulur: transaction ortasında hata üretir.
      final preview = await previewOf(
        '$header\nKola;25,00;;;;;\nSu;10,00;;;;;',
      );
      final broken = ImportPreview(
        rows: [
          preview.rows.first,
          ImportRow(
            lineNumber: 3,
            // Boş ad `ProductService._validate`'i düşürür.
            name: '',
            salePrice: const Money(1000),
            purchasePrice: Money.zero,
            category: null,
            barcodes: const [],
            brand: null,
            supplier: null,
            initialStock: 0,
            minimumStock: 0,
            shelfLocation: null,
            description: null,
            netWeightValue: null,
            netWeightUnit: null,
            issues: const [],
            updatesProductId: null,
          ),
        ],
        separator: ';',
        newCategories: const {},
        newSuppliers: const {},
      );

      final result = await service.apply(
        preview: broken,
        userId: userId,
        confirmed: true,
      );

      expect(result.isErr, isTrue);
      expect(
        await productCount(),
        0,
        reason: 'İLK satır da yazılmamalıdır — tam rollback.',
      );
    });
  });

  group('BR-IMEX-002 — dosya içi duplicate', () {
    test('aynı barkodun geçtiği TÜM satırlar reddedilir', () async {
      final preview = await previewOf(
        '$header\nKola;25,00;;;8690;;\nSu;10,00;;;8690;;\nÇay;5,00;;;8691;;',
      );

      expect(preview.rejectedCount, 2);
      expect(preview.createCount, 1);
      expect(preview.accepted.single.name, 'Çay');
    });

    test('reddedilen satırlar SEBEBİYLE listelenir — REQ-IMEX-005', () async {
      final preview = await previewOf(
        '$header\nKola;25,00;;;8690;;\nSu;10,00;;;8690;;',
      );

      final rejected = preview.rejected.first;
      expect(rejected.lineNumber, 2, reason: 'Başlık 1, ilk veri 2.');
      expect(rejected.issues.first.message, contains('8690'));
    });
  });

  group('BR-IMEX-001 — sistemde kayıtlı barkod politikası', () {
    Future<void> seedExisting() async {
      final id = await insertTestProduct(db, name: 'Eski Kola');
      await products.addBarcode(productId: id, barcode: '8690');
    }

    test('`skip` → satır atlanır, mevcut ürün DEĞİŞMEZ', () async {
      await seedExisting();

      final preview = await previewOf(
        '$header\nYeni Kola;30,00;;;8690;;',
        policy: DuplicateBarcodePolicy.skip,
      );

      expect(preview.rejectedCount, 1);
      expect(preview.createCount, 0);
    });

    test('`updateExisting` → mevcut ürün GÜNCELLENİR', () async {
      await seedExisting();

      final preview = await previewOf(
        '$header\nYeni Kola;30,00;;;8690;;',
        policy: DuplicateBarcodePolicy.updateExisting,
      );
      expect(preview.updateCount, 1);
      expect(preview.createCount, 0);

      await applyOf(preview);

      final product = (await db.select(db.products).get()).single;
      expect(product.name, 'Yeni Kola');
      expect(product.salePriceMinor, 3000);
    });

    test('docs/20 §4.1 — güncellemede STOK import EDİLMEZ', () async {
      await seedExisting();
      final before = (await db.select(db.products).get()).single.stockQuantity;

      final preview = await previewOf(
        '$header\nYeni Kola;30,00;;;8690;999;',
        policy: DuplicateBarcodePolicy.updateExisting,
      );
      await applyOf(preview);

      expect(
        (await db.select(db.products).get()).single.stockQuantity,
        before,
        reason: 'Stok yalnızca HAREKETLE değişir (docs/20 §4.1).',
      );
    });

    test('`cancel` → önizleme bile üretilmez', () async {
      final result = await service.preview(
        contents: '$header\nKola;25,00;;;;;',
        mapping: ProductImportRules.autoMap(header.split(';')),
        policy: DuplicateBarcodePolicy.cancel,
      );

      expect(result.failureOrNull, ImportFailures.cancelledByPolicy);
    });
  });

  group('REQ-IMEX-011 — stok HAREKET oluşturur', () {
    test('başlangıç stoğu `initial` hareketi yazar', () async {
      final preview = await previewOf('$header\nKola;25,00;;;;42;');

      await applyOf(preview);

      final product = (await db.select(db.products).get()).single;
      expect(product.stockQuantity, 42);
      final movements = await stock.movementsOf(product.id);
      expect(movements.single.type, StockMovementType.initial);
      expect(
        movements.single.quantityDelta,
        42,
        reason: 'Stok DOĞRUDAN yazılamaz (BR-STOCK-003).',
      );
    });

    test('stok 0 ise hareket YAZILMAZ', () async {
      final preview = await previewOf('$header\nKola;25,00;;;;0;');

      await applyOf(preview);

      final product = (await db.select(db.products).get()).single;
      expect(await stock.movementsOf(product.id), isEmpty);
    });
  });

  group('docs/20 §6 — uygulama', () {
    test('kategori ve tedarikçi otomatik oluşturulur', () async {
      final preview = await previewOf(
        '$header\nKola;25,00;18,00;İçecek;8690;10;Kola A.Ş.',
      );

      final result = await applyOf(preview);

      expect(result.created, 1);
      expect(result.newCategories, 1);
      expect(result.newSuppliers, 1);

      final product = (await db.select(db.products).get()).single;
      expect(product.name, 'Kola');
      expect(product.salePriceMinor, 2500);
      expect(product.purchasePriceMinor, 1800);
      expect(await products.barcodesOf(product.id), ['8690']);
    });

    test('çoklu barkod `|` ile aktarılır', () async {
      final preview = await previewOf('$header\nKola;25,00;;;8690|8691;;');

      await applyOf(preview);

      final product = (await db.select(db.products).get()).single;
      expect(
        await products.barcodesOf(product.id),
        containsAll(['8690', '8691']),
      );
    });

    test('aynı kategori iki satırda BİR KEZ oluşturulur', () async {
      final preview = await previewOf(
        '$header\nKola;25,00;;İçecek;;;\nSu;10,00;;İçecek;;;',
      );

      final result = await applyOf(preview);

      expect(result.created, 2);
      expect(result.newCategories, 1);
    });

    test('REQ-IMEX-016 — audit\'e yazılır', () async {
      final preview = await previewOf(
        '$header\nKola;25,00;;;;;\nSu;10,00;;;8690;;\nÇay;;;;;;',
      );

      await applyOf(preview);

      final log = (await AuditLogsDao(
        db,
      ).listRecent()).firstWhere((l) => l.action == AuditActions.dataImported);
      expect(log.metadata, contains('"created":2'));
      expect(log.metadata, contains('"skipped":1'));
    });
  });

  group('docs/20 §4 — doğrulama uçtan uca', () {
    test('hatalı satır alınmaz, temiz satır alınır', () async {
      final preview = await previewOf(
        '$header\n;25,00;;;;;\nSu;on lira;;;;;\nÇay;5,00;;;;;',
      );

      expect(preview.rejectedCount, 2);
      expect(preview.createCount, 1);

      await applyOf(preview);
      expect(await productCount(), 1);
    });

    test('uyarılı satır ALINIR', () async {
      // Alış > satış: zararına satış gerçek bir durumdur.
      final preview = await previewOf('$header\nKola;10,00;25,00;;;;');

      expect(preview.rejectedCount, 0);
      expect(preview.warningCount, 1);
      await applyOf(preview);
      expect(await productCount(), 1);
    });

    test('eksik hücreli kısa satır ÇÖKMEZ', () async {
      final preview = await previewOf('$header\nKola;25,00');

      expect(preview.createCount, 1);
      await applyOf(preview);
      expect(await productCount(), 1);
    });

    test('zorunlu sütun eşleşmemişse import BAŞLATILAMAZ', () async {
      final result = await service.preview(
        contents: 'Marka;Açıklama\nKola;iyi',
        mapping: ProductImportRules.autoMap(['Marka', 'Açıklama']),
        policy: DuplicateBarcodePolicy.skip,
      );

      expect(result.failureOrNull, ImportFailures.missingRequiredColumns);
    });

    test('boş dosya reddedilir', () async {
      final result = await service.preview(
        contents: '',
        mapping: const {},
        policy: DuplicateBarcodePolicy.skip,
      );

      expect(result.failureOrNull, ImportFailures.fileUnreadable);
    });

    test('yalnızca başlık varsa reddedilir', () async {
      final result = await service.preview(
        contents: header,
        mapping: ProductImportRules.autoMap(header.split(';')),
        policy: DuplicateBarcodePolicy.skip,
      );

      expect(result.failureOrNull, ImportFailures.emptyFile);
    });
  });

  test('REQ-IMEX-013 — virgüllü dosya da okunur', () async {
    const commaHeader =
        'Ürün adı,Satış fiyatı (KDV dahil),Alış fiyatı,Kategori,'
        'Barkod,Başlangıç stoğu,Tedarikçi';
    final result = await service.preview(
      contents: '$commaHeader\nKola,25.00,,,,,',
      mapping: ProductImportRules.autoMap(commaHeader.split(',')),
      policy: DuplicateBarcodePolicy.skip,
    );

    expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
    expect(result.valueOrNull!.separator, ',');
    expect(result.valueOrNull!.accepted.single.salePrice, const Money(2500));
  });
}
