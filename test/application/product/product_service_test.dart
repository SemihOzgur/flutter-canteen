/// Ürün yönetimi testleri —
/// **docs/09 · BR-PROD-001…014 · REQ-PROD-001…008/011/013/014**
///
/// docs/27 §4: gerçek in-memory SQLite üzerinde çalışır; mock veritabanı yoktur.
///
/// Kapsanan edge case'ler: EC-PROD-001…003 · 007…010 · 012…016 · 018…022.
library;

import 'package:canteen/application/product/product_draft.dart';
import 'package:canteen/application/product/product_service.dart';
import 'package:canteen/application/product/product_warnings.dart';
import 'package:canteen/application/stock/stock_service.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Category, Product, Supplier, VatRate;
import 'package:canteen/data/db/seed.dart';
import 'package:canteen/data/repositories/drift_product_repository.dart';
import 'package:canteen/data/repositories/drift_stock_repository.dart';
import 'package:canteen/domain/enums/sale_status.dart';
import 'package:canteen/domain/enums/stock_movement_type.dart';
import 'package:canteen/domain/repositories/stock_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'dart:io';

import 'package:canteen/core/paths/app_paths.dart';
import 'package:canteen/data/files/product_image_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late ProductService service;
  late StockRepository stock;
  late AuditLogsDao auditLogs;
  late int userId;

  late Directory imageRoot;

  setUp(() async {
    // Görsel deposu gerçek bir dizin ister; testler kullanıcı veri
    // dizinine DOKUNMAZ (BR-DATA-001).
    imageRoot = Directory.systemTemp.createTempSync('canteen_img_');
    db = memoryDatabase();
    stock = DriftStockRepository(db);
    auditLogs = AuditLogsDao(db);
    service = ProductService(
      db: db,
      products: DriftProductRepository(db),
      stock: stock,
      stockService: StockService(
        db: db,
        stock: stock,
        clock: () => testEpochUtc,
      ),
      categories: CategoriesDao(db),
      saleItems: SaleItemsDao(db),
      auditLogs: auditLogs,
      appSettings: AppSettingsDao(db),
      images: ProductImageStore(paths: AppPaths(rootPath: imageRoot.path)),
      clock: () => testEpochUtc,
    );
    userId = await insertTestUser(db);
  });

  tearDown(() async {
    await db.close();
    if (imageRoot.existsSync()) imageRoot.deleteSync(recursive: true);
  });

  ProductDraft draft({
    String name = 'Kola 330ml',
    int salePriceMinor = 12000,
    int purchasePriceMinor = 8000,
    int? categoryId,
    int? netWeightValue,
    String? netWeightUnit,
    String? description,
    String? shelfLocation,
    int minimumStock = 0,
    int? supplierId,
  }) => ProductDraft(
    name: name,
    salePrice: Money(salePriceMinor),
    purchasePrice: Money(purchasePriceMinor),
    categoryId: categoryId,
    netWeightValue: netWeightValue,
    netWeightUnit: netWeightUnit,
    description: description,
    shelfLocation: shelfLocation,
    minimumStock: minimumStock,
    supplierId: supplierId,
  );

  Future<int> createProduct({
    String name = 'Kola 330ml',
    int salePriceMinor = 12000,
    int purchasePriceMinor = 8000,
    int? categoryId,
    int initialStock = 0,
    List<String> barcodes = const [],
  }) async {
    final result = await service.create(
      draft(
        name: name,
        salePriceMinor: salePriceMinor,
        purchasePriceMinor: purchasePriceMinor,
        categoryId: categoryId,
      ),
      userId: userId,
      initialStock: initialStock,
      barcodes: barcodes,
    );
    return (result as Ok<ProductSaveOutcome>).value.productId;
  }

  Future<List<AuditLog>> auditOf(String action) async {
    final logs = await auditLogs.listRecent();
    return logs.where((log) => log.action == action).toList();
  }

  Future<int> generalCategoryId() async => (await (db.select(
    db.categories,
  )..where((c) => c.name.equals(Seed.generalCategoryName))).getSingle()).id;

  /// EC-PROD-020 kurulumu — ürünü satılmış hâle getirir.
  Future<void> insertSaleItemFor(int productId) async {
    final saleId = await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            saleNumber: '2026-000001',
            status: SaleStatus.completed,
            subtotalMinor: 10000,
            vatTotalMinor: 2000,
            grandTotalMinor: 12000,
            costTotalMinor: 8000,
            itemCount: 1,
            unitCount: 1,
            userId: userId,
            completedAt: testEpochUtc,
            createdAt: testEpochUtc,
            updatedAt: testEpochUtc,
          ),
        );

    await db
        .into(db.saleItems)
        .insert(
          SaleItemsCompanion.insert(
            saleId: saleId,
            productId: productId,
            productNameSnapshot: 'Kola 330ml',
            quantity: 1,
            unitPriceMinor: 12000,
            originalUnitPriceMinor: 12000,
            purchasePriceSnapshotMinor: 8000,
            vatRateSnapshotBp: 0,
            lineNetMinor: 12000,
            lineVatMinor: 0,
            lineTotalMinor: 12000,
          ),
        );
  }

  // -------------------------------------------------------------------------
  group('oluşturma — zorunlu alanlar (BR-PROD-001…003)', () {
    test('REQ-PROD-003 — kategori seçilmezse `Genel` kullanılır', () async {
      final id = await createProduct();
      final product = (await service.findById(id))!;
      expect(product.categoryId, await generalCategoryId());
    });

    test('REQ-PROD-002 — alış fiyatı boş bırakılırsa 0 kaydedilir', () async {
      final result = await service.create(
        ProductDraft(name: 'Poğaça', salePrice: const Money(1500)),
        userId: userId,
      );
      final id = (result as Ok<ProductSaveOutcome>).value.productId;

      final product = (await service.findById(id))!;
      expect(product.purchasePrice, Money.zero);
    });

    test('EC-PROD-013 — yalnızca boşluktan oluşan ad reddedilir', () async {
      final result = await service.create(draft(name: '   '), userId: userId);
      expect(result.isErr, isTrue);
      expect(result.failureOrNull!.code, 'product_name_required');
    });

    test('ad kırpılır (docs/09 §1)', () async {
      final id = await createProduct(name: '  Ayran  ');
      expect((await service.findById(id))!.name, 'Ayran');
    });

    test('EC-PROD-012 — 120 karakterden uzun ad reddedilir', () async {
      final result = await service.create(
        draft(name: 'A' * 121),
        userId: userId,
      );
      expect(result.failureOrNull!.code, 'product_name_too_long');

      final ok = await service.create(draft(name: 'A' * 120), userId: userId);
      expect(ok.isOk, isTrue);
    });

    test('EC-PROD-007 — satış fiyatı 0 geçerlidir (ikram ürünü)', () async {
      final id = await createProduct(salePriceMinor: 0);
      expect((await service.findById(id))!.salePrice, Money.zero);
    });

    test('EC-PROD-008 — negatif satış fiyatı reddedilir', () async {
      final result = await service.create(
        draft(salePriceMinor: -1),
        userId: userId,
      );
      expect(result.failureOrNull!.code, 'product_sale_price_negative');
    });

    test('BR-PROD-007 — negatif alış fiyatı reddedilir', () async {
      final result = await service.create(
        draft(purchasePriceMinor: -1),
        userId: userId,
      );
      expect(result.failureOrNull!.code, 'product_purchase_price_negative');
    });

    test('var olmayan kategori reddedilir', () async {
      final result = await service.create(
        draft(categoryId: 4242),
        userId: userId,
      );
      expect(result.failureOrNull!.code, 'product_category_not_found');
    });

    test('açıklama ve raf konumu uzunluk sınırları', () async {
      expect(
        (await service.create(
          draft(description: 'x' * 501),
          userId: userId,
        )).failureOrNull!.code,
        'product_description_too_long',
      );
      expect(
        (await service.create(
          draft(shelfLocation: 'x' * 51),
          userId: userId,
        )).failureOrNull!.code,
        'product_shelf_location_too_long',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('BR-PROD-011 · EC-PROD-018 — net ağırlık çifti', () {
    test('yalnızca değer girilirse ANLAŞILIR hata döner', () async {
      final result = await service.create(
        draft(netWeightValue: 150000),
        userId: userId,
      );

      expect(result.failureOrNull!.code, 'product_net_weight_pair_incomplete');
      // REQ-SEC-007 — ham veritabanı hatası sızmaz.
      expect(result.failureOrNull!.userMessage, isNot(contains('CHECK')));
      expect(result.failureOrNull!.userMessage, isNot(contains('SQLITE')));
    });

    test('yalnızca birim girilirse reddedilir', () async {
      final result = await service.create(
        draft(netWeightUnit: 'g'),
        userId: userId,
      );
      expect(result.failureOrNull!.code, 'product_net_weight_pair_incomplete');
    });

    test('ikisi birlikte girilirse kaydedilir (150 g → 150000)', () async {
      final result = await service.create(
        draft(netWeightValue: 150000, netWeightUnit: 'g'),
        userId: userId,
      );
      final id = (result as Ok<ProductSaveOutcome>).value.productId;

      final product = (await service.findById(id))!;
      expect(product.netWeightValue, 150000);
      expect(product.netWeightUnit, 'g');
    });
  });

  // -------------------------------------------------------------------------
  group('REQ-PROD-007 — başlangıç stoğu stok hareketi oluşturur', () {
    test('acceptance criteria: 50 adet → initial hareket + önbellek', () async {
      final id = await createProduct(initialStock: 50);

      final product = (await service.findById(id))!;
      expect(product.stockQuantity, 50);

      final movements = await stock.movementsOf(id);
      expect(movements.single.type, StockMovementType.initial);
      expect(movements.single.quantityDelta, 50);
      expect(movements.single.resultingStock, 50);

      // BR-STOCK-003 invariant'ı.
      expect(product.stockQuantity, await stock.sumQuantityDelta(id));
    });

    test('başlangıç stoğu 0 → defterde satır YOK', () async {
      final id = await createProduct();
      expect(await stock.movementsOf(id), isEmpty);
      expect((await service.findById(id))!.stockQuantity, 0);
    });

    test('negatif başlangıç stoğu ÜRÜNÜ DE oluşturmaz (rollback)', () async {
      final result = await service.create(
        draft(name: 'Hatalı'),
        userId: userId,
        initialStock: -3,
      );

      expect(result.isErr, isTrue);
      expect(
        await service.list(includeInactive: true),
        isEmpty,
        reason: 'Stok reddedilirse ürün de yazılmamalıdır (rules/03 §10).',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('barkod (BR-PROD-004/005 · EC-PROD-001…003/014…016)', () {
    test('EC-PROD-002 — barkodsuz ürün oluşturulabilir', () async {
      final id = await createProduct();
      expect(await service.barcodesOf(id), isEmpty);
    });

    test('REQ-PROD-004 — bir ürüne birden fazla barkod', () async {
      final id = await createProduct(
        barcodes: ['8691234567890', '4006381333931'],
      );
      expect(
        await service.barcodesOf(id),
        containsAll(<String>['8691234567890', '4006381333931']),
      );
    });

    test('EC-PROD-014 — baştaki sıfır KORUNUR', () async {
      final id = await createProduct(barcodes: ['0123']);
      expect(await service.barcodesOf(id), ['0123']);

      final found = await service.findByBarcode('0123');
      expect(found!.id, id);
      // Sayıya çevrilseydi '123' ile de bulunurdu.
      expect(await service.findByBarcode('123'), isNull);
    });

    test('barkod normalize edilir — CR/LF ve boşluk temizlenir', () async {
      final id = await createProduct(barcodes: [' 8691234567890\r\n']);
      expect(await service.barcodesOf(id), ['8691234567890']);
    });

    test('EC-PROD-003 — aynı barkod aynı ürüne ikinci kez: SESSİZ', () async {
      final id = await createProduct(barcodes: ['8691234567890']);

      final again = await service.addBarcode(
        id,
        '8691234567890',
        userId: userId,
      );

      expect(again.isOk, isTrue, reason: 'Hata gösterilmez.');
      expect(await service.barcodesOf(id), hasLength(1));
    });

    test('aynı barkod formda iki kez yazılırsa tek satır oluşur', () async {
      final id = await createProduct(
        barcodes: ['8691234567890', '8691234567890'],
      );
      expect(await service.barcodesOf(id), hasLength(1));
    });

    test('EC-PROD-001 — barkod başka ürüne aitse REDDEDİLİR', () async {
      final owner = await createProduct(
        name: 'Coca Cola 330ml',
        barcodes: ['8691234567890'],
      );
      final other = await createProduct(name: 'Su 500ml');

      final result = await service.addBarcode(
        other,
        '8691234567890',
        userId: userId,
      );

      expect(result.isErr, isTrue);
      // REQ-PROD-005 acceptance criteria: sahip ürünün ADI gösterilir.
      expect(
        result.failureOrNull!.userMessage,
        contains("'Coca Cola 330ml' ürününe ait"),
      );
      // "Ürüne git" için sahip ürünün id'si taşınır.
      expect(result.failureOrNull!.code, endsWith(':$owner'));
      expect(await service.barcodesOf(other), isEmpty);
    });

    test('BR-PROD-010 — PASİF ürünün barkodu da kısıtı işgal eder', () async {
      final owner = await createProduct(
        name: 'Eski Ürün',
        barcodes: ['8691234567890'],
      );
      await service.deactivate(owner, userId: userId);

      final other = await createProduct(name: 'Yeni Ürün');
      final result = await service.addBarcode(
        other,
        '8691234567890',
        userId: userId,
      );

      expect(result.isErr, isTrue);
    });

    test('çakışan barkod ÜRÜN OLUŞTURMAYI da geri alır', () async {
      await createProduct(name: 'Sahip', barcodes: ['8691234567890']);

      final result = await service.create(
        draft(name: 'Yeni'),
        userId: userId,
        initialStock: 10,
        barcodes: ['4006381333931', '8691234567890'],
      );

      expect(result.isErr, isTrue);
      expect(
        (await service.list()).map((p) => p.name),
        ['Sahip'],
        reason: 'Yarım ürün oluşamaz (rules/03 §10).',
      );
      // İlk barkod da yazılmamış olmalı — havuz serbest kalır.
      expect(await service.findByBarcode('4006381333931'), isNull);
    });

    test('EC-PROD-015 — geçersiz kontrol hanesi: UYARI, engel değil', () async {
      final result = await service.create(
        draft(),
        userId: userId,
        barcodes: ['4006381333932'],
      );

      expect(result.isOk, isTrue);
      final outcome = (result as Ok<ProductSaveOutcome>).value;
      expect(
        outcome.warnings.map((w) => w.code),
        contains(ProductWarnings.barcodeChecksumInvalid.code),
      );
      expect(await service.barcodesOf(outcome.productId), hasLength(1));
    });

    test('geçerli kontrol hanesinde uyarı YOK', () async {
      final result = await service.create(
        draft(),
        userId: userId,
        barcodes: ['4006381333931'],
      );
      expect((result as Ok<ProductSaveOutcome>).value.warnings, isEmpty);
    });

    test('EC-PROD-016 — son barkod silinebilir, audit yazılır', () async {
      final id = await createProduct(barcodes: ['8691234567890']);

      final removed = await service.removeBarcode(
        id,
        '8691234567890',
        userId: userId,
      );

      expect(removed.isOk, isTrue);
      expect(await service.barcodesOf(id), isEmpty);

      final logs = await auditOf(ProductService.actionBarcodeRemoved);
      expect(logs.single.entityId, id);
      expect(logs.single.metadata, contains('8691234567890'));

      // Barkod havuzdan çıkar — başka ürüne atanabilir.
      final other = await createProduct(name: 'Başka');
      expect(
        (await service.addBarcode(other, '8691234567890', userId: userId)).isOk,
        isTrue,
      );
    });

    test('barkod ekleme audit kaydı üretir', () async {
      final id = await createProduct();
      await service.addBarcode(id, '8691234567890', userId: userId);

      final logs = await auditOf(ProductService.actionBarcodeAdded);
      expect(logs.single.entityType, ProductService.auditEntityType);
      expect(logs.single.userId, userId);
    });

    test('boş barkod reddedilir', () async {
      final id = await createProduct();
      final result = await service.addBarcode(id, '  \r\n', userId: userId);
      expect(result.failureOrNull!.code, 'product_barcode_required');
    });

    test('docs/04 §3.6 — ürün başına en fazla bir birincil barkod', () async {
      final id = await createProduct(barcodes: ['8691234567890']);
      await service.addBarcode(id, '111', userId: userId, isPrimary: true);
      await service.addBarcode(id, '222', userId: userId, isPrimary: true);

      final rows = await ProductBarcodesDao(db).listOfProduct(id);
      expect(rows.where((b) => b.isPrimary), hasLength(1));
      expect(rows.firstWhere((b) => b.isPrimary).barcode, '222');
    });
  });

  // -------------------------------------------------------------------------
  group('uyarılar — izin verilir, engellenmez', () {
    test('EC-PROD-009 — alış fiyatı > satış fiyatı', () async {
      final result = await service.create(
        draft(salePriceMinor: 5000, purchasePriceMinor: 8000),
        userId: userId,
      );

      expect(result.isOk, isTrue);
      expect(
        (result as Ok<ProductSaveOutcome>).value.warnings.map((w) => w.code),
        contains(ProductWarnings.purchaseAboveSale.code),
      );
    });

    test('EC-PROD-010 — aynı ad + aynı kategori', () async {
      await createProduct(name: 'Ayran');

      final result = await service.create(draft(name: 'Ayran'), userId: userId);

      expect(result.isOk, isTrue, reason: 'BR-PROD-013: engellenmez.');
      expect(
        (result as Ok<ProductSaveOutcome>).value.warnings.map((w) => w.code),
        contains(ProductWarnings.duplicateName.code),
      );
    });

    test('aynı ad ama FARKLI kategori → uyarı yok', () async {
      await createProduct(name: 'Ayran');
      final other = await CategoriesDao(
        db,
      ).insertCategory(name: 'Süt Ürünleri', sortOrder: 1, now: testEpochUtc);

      final result = await service.create(
        draft(name: 'Ayran', categoryId: other),
        userId: userId,
      );
      expect((result as Ok<ProductSaveOutcome>).value.warnings, isEmpty);
    });

    test('ad karşılaştırması Türkçe karakter duyarsızdır', () async {
      await createProduct(name: 'Şeftali Suyu');

      final result = await service.create(
        draft(name: 'SEFTALI SUYU'),
        userId: userId,
      );
      expect(
        (result as Ok<ProductSaveOutcome>).value.warnings.map((w) => w.code),
        contains(ProductWarnings.duplicateName.code),
      );
    });

    test('previewWarnings kaydetmeden önce aynı sonucu verir', () async {
      await createProduct(name: 'Ayran');

      final warnings = await service.previewWarnings(
        draft(name: 'Ayran', salePriceMinor: 1000, purchasePriceMinor: 2000),
      );

      expect(
        warnings.map((w) => w.code),
        containsAll(<String>[
          ProductWarnings.duplicateName.code,
          ProductWarnings.purchaseAboveSale.code,
        ]),
      );
      expect(
        await service.list(),
        hasLength(1),
        reason: 'Önizleme hiçbir şey yazmaz.',
      );
    });

    test('REQ-PROD-012 — %50\'den fazla fiyat değişikliği uyarır', () async {
      final id = await createProduct(salePriceMinor: 2500);

      final result = await service.update(
        id,
        draft(salePriceMinor: 250000),
        userId: userId,
      );

      expect(result.isOk, isTrue);
      expect(
        (result as Ok<ProductSaveOutcome>).value.warnings.map((w) => w.code),
        contains(ProductWarnings.largePriceChange.code),
      );
    });

    test('küçük fiyat değişikliği uyarmaz', () async {
      final id = await createProduct(
        salePriceMinor: 2000,
        purchasePriceMinor: 1000,
      );
      final result = await service.update(
        id,
        draft(salePriceMinor: 2500, purchasePriceMinor: 1000),
        userId: userId,
      );
      expect((result as Ok<ProductSaveOutcome>).value.warnings, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  group('düzenleme (docs/09 §3)', () {
    test(
      'REQ-PROD-008 — fiyat değişikliği eski/yeni değerle yazılır',
      () async {
        final id = await createProduct(salePriceMinor: 2500);

        await service.update(id, draft(salePriceMinor: 3000), userId: userId);

        final logs = await auditOf(ProductService.actionPriceChanged);
        expect(logs.single.oldValue, contains('2500'));
        expect(logs.single.newValue, contains('3000'));
        expect(logs.single.entityId, id);
        expect(logs.single.userId, userId);
      },
    );

    test('alış fiyatı değişikliği ayrı action ile yazılır', () async {
      final id = await createProduct(purchasePriceMinor: 8000);
      await service.update(id, draft(purchasePriceMinor: 9000), userId: userId);

      final logs = await auditOf(ProductService.actionCostChanged);
      expect(logs.single.oldValue, contains('8000'));
      expect(logs.single.metadata, contains('manual'));
    });

    test('kategori, tedarikçi ve minimum stok değişiklikleri', () async {
      final id = await createProduct();
      final category = await CategoriesDao(
        db,
      ).insertCategory(name: 'Atıştırmalık', sortOrder: 1, now: testEpochUtc);
      final supplier = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Toptancı',
              createdAt: testEpochUtc,
              updatedAt: testEpochUtc,
            ),
          );

      await service.update(
        id,
        draft(categoryId: category, supplierId: supplier, minimumStock: 5),
        userId: userId,
      );

      expect(await auditOf(ProductService.actionCategoryChanged), hasLength(1));
      expect(await auditOf(ProductService.actionSupplierChanged), hasLength(1));
      expect(await auditOf(ProductService.actionMinStockChanged), hasLength(1));
    });

    test('değişmeyen alan için audit kaydı üretilmez (docs/18 §4)', () async {
      final id = await createProduct(salePriceMinor: 2500);
      await service.update(id, draft(salePriceMinor: 2500), userId: userId);

      expect(await auditOf(ProductService.actionPriceChanged), isEmpty);
      expect(await auditOf(ProductService.actionCostChanged), isEmpty);
    });

    test('stok, favori ve görsel alanlarına DOKUNULMAZ', () async {
      final id = await createProduct(initialStock: 20);

      // Faz 3d/6'ya ait alanlar dışarıdan set edilmiş olsun.
      await (db.update(db.products)..where((p) => p.id.equals(id))).write(
        const ProductsCompanion(
          isFavorite: Value(true),
          imagePath: Value('images/abc.jpg'),
        ),
      );

      await service.update(id, draft(name: 'Yeni Ad'), userId: userId);

      final product = (await service.findById(id))!;
      expect(product.name, 'Yeni Ad');
      expect(
        product.stockQuantity,
        20,
        reason: 'rules/02 §4 — tek yazım noktası StockService.',
      );
      expect(product.isFavorite, isTrue, reason: 'Faz 3d kapsamı korunur.');
      expect(product.imagePath, 'images/abc.jpg');
    });

    test('bulunamayan ürün → Err', () async {
      final result = await service.update(4242, draft(), userId: userId);
      expect(result.failureOrNull!.code, 'product_not_found');
    });

    test('geçersiz ürün güncellemesi hiçbir alanı değiştirmez', () async {
      final id = await createProduct(name: 'Kola 330ml');

      final result = await service.update(
        id,
        draft(name: 'Yeni', netWeightValue: 150000),
        userId: userId,
      );

      expect(result.isErr, isTrue);
      expect((await service.findById(id))!.name, 'Kola 330ml');
    });
  });

  // -------------------------------------------------------------------------
  group('pasifleştirme (BR-PROD-009 · REQ-PROD-006)', () {
    test('pasif ürün listede görünmez, includeInactive ile görünür', () async {
      final id = await createProduct();
      await service.deactivate(id, userId: userId);

      expect(await service.list(), isEmpty);
      expect((await service.list(includeInactive: true)).single.id, id);
    });

    test('docs/09 §4 — stoğu olan ürün UYARIYLA pasifleşir', () async {
      final id = await createProduct(initialStock: 47);

      final result = await service.deactivate(id, userId: userId);

      expect(result.isOk, isTrue, reason: 'Engellenmez.');
      final warnings = (result as Ok<List<ProductWarning>>).value;
      expect(warnings.single.message, contains('47'));
      expect((await service.findById(id))!.isActive, isFalse);
    });

    test('pasifleştirme audit metadata\'sı stok miktarını taşır', () async {
      final id = await createProduct(initialStock: 12);
      await service.deactivate(id, userId: userId);

      final logs = await auditOf(ProductService.actionDeactivated);
      expect(logs.single.metadata, contains('12'));
    });

    test('zaten pasif ürün için işlem yinelenmez', () async {
      final id = await createProduct();
      await service.deactivate(id, userId: userId);
      await service.deactivate(id, userId: userId);

      expect(await auditOf(ProductService.actionDeactivated), hasLength(1));
    });

    test('yeniden aktifleştirilebilir (BR-BARC-007)', () async {
      final id = await createProduct();
      await service.deactivate(id, userId: userId);

      final result = await service.activate(id, userId: userId);

      expect(result.isOk, isTrue);
      expect((await service.findById(id))!.isActive, isTrue);
      expect(await auditOf(ProductService.actionActivated), hasLength(1));
    });
  });

  // -------------------------------------------------------------------------
  group('kalıcı silme (BR-PROD-014 · REQ-PROD-013)', () {
    test('EC-PROD-019 — hiç kullanılmamış ürün kalıcı silinir', () async {
      final id = await createProduct(barcodes: ['8691234567890']);

      final usage = (await service.usage(id) as Ok<ProductUsage>).value;
      expect(usage.canDeletePermanently, isTrue);

      final result = await service.delete(id, userId: userId);

      expect(result.isOk, isTrue);
      expect(await service.findById(id), isNull);
      // EC-PROD-022 — barkod havuzdan çıkar.
      expect(await service.findByBarcode('8691234567890'), isNull);

      final logs = await auditOf(ProductService.actionDeleted);
      expect(logs.single.metadata, contains('8691234567890'));
      expect(logs.single.metadata, contains('Kola 330ml'));
    });

    test(
      'EC-PROD-022 — silinen ürünün barkodu yeni ürüne atanabilir',
      () async {
        final first = await createProduct(barcodes: ['8691234567890']);
        await service.delete(first, userId: userId);

        final second = await createProduct(
          name: 'Yeni Ürün',
          barcodes: ['8691234567890'],
        );
        expect(await service.barcodesOf(second), ['8691234567890']);
      },
    );

    test('EC-PROD-020 — satılmış ürün silinemez', () async {
      final id = await createProduct();
      await insertSaleItemFor(id);

      final usage = (await service.usage(id) as Ok<ProductUsage>).value;
      expect(usage.saleItemCount, 1);
      expect(usage.canDeletePermanently, isFalse);

      final result = await service.delete(id, userId: userId);

      expect(result.isErr, isTrue);
      expect(result.failureOrNull!.code, 'product_in_use');
      expect(result.failureOrNull!.userMessage, contains('1 satışta'));
      expect(await service.findById(id), isNotNull);
    });

    test('EC-PROD-021 — BAŞLANGIÇ STOĞU olan ürün de silinemez', () async {
      // `initial` de bir stok hareketidir: defter referansı korunur.
      final id = await createProduct(initialStock: 10);

      final usage = (await service.usage(id) as Ok<ProductUsage>).value;
      expect(usage.stockMovementCount, 1);
      expect(usage.canDeletePermanently, isFalse);

      final result = await service.delete(id, userId: userId);

      expect(result.isErr, isTrue);
      expect(result.failureOrNull!.userMessage, contains('stok hareketi'));
      expect(await service.findById(id), isNotNull);
    });

    test('başlangıç stoğu 0 olan ürün silinebilir', () async {
      final id = await createProduct(initialStock: 0);
      expect((await service.delete(id, userId: userId)).isOk, isTrue);
    });

    test('bulunamayan ürün → Err', () async {
      expect(
        (await service.delete(4242, userId: userId)).failureOrNull!.code,
        'product_not_found',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('REQ-FIN-006 — fiyat girdisi', () {
    test('virgül ve nokta kabul edilir', () {
      expect(
        (ProductService.parseSalePrice('25,50') as Ok<Money>).value,
        const Money(2550),
      );
      expect(
        (ProductService.parseSalePrice('25.50') as Ok<Money>).value,
        const Money(2550),
      );
      expect(
        (ProductService.parseSalePrice('₺1.234,56') as Ok<Money>).value,
        const Money(123456),
      );
    });

    test('boş satış fiyatı reddedilir, boş alış fiyatı 0 olur', () {
      expect(
        ProductService.parseSalePrice('').failureOrNull!.code,
        'product_sale_price_required',
      );
      expect(
        (ProductService.parsePurchasePrice('  ') as Ok<Money>).value,
        Money.zero,
      );
    });

    test('geçersiz metin reddedilir', () {
      expect(
        ProductService.parseSalePrice('abc').failureOrNull!.code,
        'product_price_invalid',
      );
    });

    test('negatif girdi reddedilir', () {
      expect(
        ProductService.parseSalePrice('-5').failureOrNull!.code,
        'product_sale_price_negative',
      );
      expect(
        ProductService.parsePurchasePrice('-5').failureOrNull!.code,
        'product_purchase_price_negative',
      );
    });
  });

  // -------------------------------------------------------------------------
  test('oluşturma audit kaydı — docs/18 §3 metadata', () async {
    final id = await createProduct(initialStock: 5, barcodes: ['0123']);

    final logs = await auditOf(ProductService.actionCreated);
    expect(logs.single.entityId, id);
    expect(logs.single.entityType, 'product');
    expect(logs.single.userId, userId);
    expect(logs.single.metadata, contains('detailed'));
    expect(logs.single.metadata, contains('"initial_stock":5'));
  });

  test('ürünle birlikte eklenen barkodlar ayrı audit üretmez', () async {
    await createProduct(barcodes: ['0123', '0456']);
    expect(await auditOf(ProductService.actionBarcodeAdded), isEmpty);
    expect(await auditOf(ProductService.actionCreated), hasLength(1));
  });
}
