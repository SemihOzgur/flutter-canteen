/// Repository testleri — **REQ-ARCH-004**
///
/// docs/27 §4: gerçek in-memory SQLite üzerinde çalışır.
///
/// Beklenen iş hataları `Result`/`Failure` ile döner; exception fırlatılmaz
/// (rules/06 §7).
library;

import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/result/result.dart';
// Drift, tablo satırları için domain modelleriyle aynı adlı sınıflar üretir.
// Testin ilgilendiği tipler DOMAIN tipleridir; Drift satır tipleri gizlenir.
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/repositories/drift_product_repository.dart';
import 'package:canteen/data/repositories/drift_sale_repository.dart';
import 'package:canteen/data/repositories/drift_stock_repository.dart';
import 'package:canteen/domain/enums/sale_status.dart';
import 'package:canteen/domain/enums/stock_movement_type.dart';
import 'package:canteen/domain/enums/stock_reference_type.dart';
import 'package:canteen/domain/models/product.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late DriftProductRepository products;
  late DriftSaleRepository sales;
  late DriftStockRepository stock;
  late int userId;
  late int categoryId;

  setUp(() async {
    db = memoryDatabase();
    products = DriftProductRepository(db);
    sales = DriftSaleRepository(db);
    stock = DriftStockRepository(db);
    userId = await insertTestUser(db);
    categoryId = (await (db.select(db.categories)..limit(1)).getSingle()).id;
  });

  tearDown(() => db.close());

  NewProduct draft(String name, {int price = 12000, int purchase = 8000}) =>
      NewProduct(
        name: name,
        categoryId: categoryId,
        salePrice: Money(price),
        purchasePrice: Money(purchase),
      );

  group('ProductRepository', () {
    test('create → findById tur atar, Money kayıpsız', () async {
      final created = await products.create(draft('Kola', price: 1250));
      expect(created, isA<Ok<int>>());

      final found = await products.findById((created as Ok<int>).value);
      final product = (found as Ok<Product>).value;

      expect(product.name, 'Kola');
      expect(product.salePrice, const Money(1250));
      expect(product.purchasePrice, const Money(8000));
      expect(product.isActive, isTrue);
      expect(product.createdAt.isUtc, isTrue);
    });

    test(
      'bulunamayan ürün → Failure(product_not_found), exception YOK',
      () async {
        final result = await products.findById(999999);

        expect(result.isErr, isTrue);
        expect(result.failureOrNull!.code, 'product_not_found');
        expect(result.failureOrNull!.userMessage, 'Ürün bulunamadı.');
      },
    );

    test('barkod ile bulunur — bilinen barkod akışı', () async {
      final id = ((await products.create(draft('Ayran'))) as Ok<int>).value;
      await products.addBarcode(productId: id, barcode: '8690000000001');

      final result = await products.findByBarcode('8690000000001');
      expect((result as Ok<Product>).value.id, id);
    });

    test('bilinmeyen barkod → Failure, exception YOK (rules/02 §10)', () async {
      final result = await products.findByBarcode('0000000000000');

      expect(result.isErr, isTrue);
      expect(result.failureOrNull!.code, 'product_not_found');
    });

    test('duplicate barkod → Failure(barcode_exists) — BR-PROD-005', () async {
      final first = ((await products.create(draft('Kola'))) as Ok<int>).value;
      final second = ((await products.create(draft('Su'))) as Ok<int>).value;

      await products.addBarcode(productId: first, barcode: '8690000000001');
      final result = await products.addBarcode(
        productId: second,
        barcode: '8690000000001',
      );

      expect(result.isErr, isTrue);
      expect(result.failureOrNull!.code, 'barcode_exists');
      expect(
        result.failureOrNull!.userMessage,
        'Bu barkod başka bir ürüne ait.',
      );
      // REQ-SEC-007 — SQLite metni kullanıcıya sızmaz.
      expect(result.failureOrNull!.userMessage, isNot(contains('UNIQUE')));
    });

    test('geçersiz kategori → Failure(invalid_reference)', () async {
      final result = await products.create(
        NewProduct(
          name: 'Hayalet',
          categoryId: 999999,
          salePrice: const Money(100),
        ),
      );

      expect(result.isErr, isTrue);
      expect(result.failureOrNull!.code, 'invalid_reference');
    });

    test('arama yalnızca AKTİF ürünleri döner', () async {
      final passive =
          ((await products.create(draft('Eski Kola'))) as Ok<int>).value;
      await products.create(draft('Yeni Kola'));

      await (db.update(db.products)..where((p) => p.id.equals(passive))).write(
        const ProductsCompanion(isActive: Value(false)),
      );

      final results = await products.search('Kola');
      expect(results.map((p) => p.name), ['Yeni Kola']);
    });

    test('arama limit uygular', () async {
      for (var i = 0; i < 10; i++) {
        await products.create(draft('Ürün $i'));
      }
      expect((await products.search('Ürün', limit: 3)).length, 3);
    });

    test('list sayfalama yapar', () async {
      for (var i = 0; i < 5; i++) {
        await products.create(draft('P$i'));
      }
      final page = await products.list(limit: 2, offset: 2);
      expect(page.length, 2);
    });

    test('update fiyatı değiştirir, stock_quantity\'ye DOKUNMAZ', () async {
      final id = ((await products.create(draft('Kola'))) as Ok<int>).value;

      // Stok defteri dışından gelmiş bir stok değeri.
      await (db.update(db.products)..where((p) => p.id.equals(id))).write(
        const ProductsCompanion(stockQuantity: Value(42)),
      );

      final current = ((await products.findById(id)) as Ok<Product>).value;
      final updated = Product(
        id: current.id,
        name: 'Kola 1L',
        description: current.description,
        categoryId: current.categoryId,
        brand: current.brand,
        salesUnit: current.salesUnit,
        netWeightValue: current.netWeightValue,
        netWeightUnit: current.netWeightUnit,
        purchasePrice: current.purchasePrice,
        salePrice: const Money(1500),
        vatRateId: current.vatRateId,
        // Kasıtlı olarak yanlış değer — repository bunu YAZMAMALI.
        stockQuantity: 999,
        minimumStock: current.minimumStock,
        supplierId: current.supplierId,
        shelfLocation: current.shelfLocation,
        imagePath: current.imagePath,
        isFavorite: current.isFavorite,
        isActive: current.isActive,
        createdAt: current.createdAt,
        updatedAt: current.updatedAt,
      );

      expect((await products.update(updated)).isOk, isTrue);

      final after = ((await products.findById(id)) as Ok<Product>).value;
      expect(after.name, 'Kola 1L');
      expect(after.salePrice, const Money(1500));
      expect(
        after.stockQuantity,
        42,
        reason:
            'rules/02 §4: stock_quantity yalnızca StockService üzerinden değişir.',
      );
    });

    test('var olmayan ürünü güncelleme → Failure', () async {
      final current = ((await products.create(draft('Kola'))) as Ok<int>).value;
      final product = ((await products.findById(current)) as Ok<Product>).value;

      await (db.delete(db.products)..where((p) => p.id.equals(current))).go();

      expect((await products.update(product)).isErr, isTrue);
    });

    test('bir ürünün birden fazla barkodu olabilir (BR-PROD-004)', () async {
      final id = ((await products.create(draft('Kola'))) as Ok<int>).value;
      await products.addBarcode(productId: id, barcode: '111', isPrimary: true);
      await products.addBarcode(productId: id, barcode: '222');

      expect(await products.barcodesOf(id), containsAll(['111', '222']));
    });
  });

  group('SaleRepository', () {
    Future<int> insertSale({
      required String number,
      required DateTime completedAt,
      SaleStatus status = SaleStatus.completed,
    }) => db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            saleNumber: number,
            status: status,
            subtotalMinor: 10000,
            vatTotalMinor: 2000,
            grandTotalMinor: 12000,
            costTotalMinor: 8000,
            itemCount: 1,
            unitCount: 1,
            userId: userId,
            completedAt: completedAt,
            createdAt: completedAt,
            updatedAt: completedAt,
          ),
        );

    test('findByNumber çalışır ve invariant korunur', () async {
      await insertSale(number: '2026-000001', completedAt: testEpochUtc);

      final result = await sales.findByNumber('2026-000001');
      final sale = (result as Ok).value;

      expect(sale.saleNumber, '2026-000001');
      expect(sale.grandTotal, const Money(12000));
      expect(sale.subtotal, const Money(10000));
      expect(sale.vatTotal, const Money(2000));
      expect(
        sale.isBalanced,
        isTrue,
        reason: 'rules/02 §2: subtotal + vatTotal == grandTotal',
      );
      expect(sale.discountTotal, Money.zero, reason: 'OD-007: V1\'de daima 0');
    });

    test('bulunamayan satış → Failure(sale_not_found)', () async {
      expect(
        (await sales.findById(12345)).failureOrNull!.code,
        'sale_not_found',
      );
      expect((await sales.findByNumber('yok')).isErr, isTrue);
    });

    test('tarih aralığı yarı açıktır [from, to)', () async {
      final day1 = DateTime.utc(2026, 8, 14, 9);
      final day2 = DateTime.utc(2026, 8, 15, 9);
      final day3 = DateTime.utc(2026, 8, 16, 9);

      await insertSale(number: 'A', completedAt: day1);
      await insertSale(number: 'B', completedAt: day2);
      await insertSale(number: 'C', completedAt: day3);

      final result = await sales.listCompletedBetween(
        fromUtc: DateTime.utc(2026, 8, 14),
        toUtc: DateTime.utc(2026, 8, 16),
      );

      expect(result.map((s) => s.saleNumber), ['B', 'A']);
    });

    test('milisaniye sınırı doğru uygulanır', () async {
      final boundary = DateTime.utc(2026, 8, 14, 12, 0, 0, 500);
      await insertSale(number: 'sinir', completedAt: boundary);

      // Üst sınır tam an → dışarıda (yarı açık).
      final excluded = await sales.listCompletedBetween(
        fromUtc: DateTime.utc(2026, 8, 14),
        toUtc: boundary,
      );
      expect(excluded, isEmpty);

      // 1 ms sonrası → içeride.
      final included = await sales.listCompletedBetween(
        fromUtc: DateTime.utc(2026, 8, 14),
        toUtc: boundary.add(const Duration(milliseconds: 1)),
      );
      expect(included.length, 1);
    });

    test('itemsOf 5 snapshot alanını döner (BR-SALE-001)', () async {
      final saleId = await insertSale(
        number: '2026-000002',
        completedAt: testEpochUtc,
      );
      final productId = await insertTestProduct(db);

      await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              saleId: saleId,
              productId: productId,
              productNameSnapshot: 'Satış Anındaki Ad',
              categoryIdSnapshot: Value(categoryId),
              quantity: 2,
              unitPriceMinor: 6000,
              originalUnitPriceMinor: 6500,
              purchasePriceSnapshotMinor: 4000,
              vatRateSnapshotBp: 2000,
              lineNetMinor: 10000,
              lineVatMinor: 2000,
              lineTotalMinor: 12000,
            ),
          );

      final items = await sales.itemsOf(saleId);
      final item = items.single;

      expect(item.productNameSnapshot, 'Satış Anındaki Ad');
      expect(item.unitPrice, const Money(6000));
      expect(item.purchasePriceSnapshot, const Money(4000));
      expect(item.vatRateSnapshotBp, 2000);
      expect(item.categoryIdSnapshot, categoryId);
      expect(item.originalUnitPrice, const Money(6500));
      expect(item.remainingQuantity, 2);
    });

    test('ürün değişince geçmiş satış DEĞİŞMEZ (rules/02 §3)', () async {
      final saleId = await insertSale(
        number: '2026-000003',
        completedAt: testEpochUtc,
      );
      final productId = await insertTestProduct(db, name: 'Eski Ad');

      await db
          .into(db.saleItems)
          .insert(
            SaleItemsCompanion.insert(
              saleId: saleId,
              productId: productId,
              productNameSnapshot: 'Eski Ad',
              quantity: 1,
              unitPriceMinor: 12000,
              originalUnitPriceMinor: 12000,
              purchasePriceSnapshotMinor: 8000,
              vatRateSnapshotBp: 2000,
              lineNetMinor: 10000,
              lineVatMinor: 2000,
              lineTotalMinor: 12000,
            ),
          );

      // Ürün tamamen değişiyor.
      await (db.update(
        db.products,
      )..where((p) => p.id.equals(productId))).write(
        const ProductsCompanion(
          name: Value('Yepyeni Ad'),
          salePriceMinor: Value(99999),
          purchasePriceMinor: Value(1),
        ),
      );

      final item = (await sales.itemsOf(saleId)).single;
      expect(item.productNameSnapshot, 'Eski Ad');
      expect(item.unitPrice, const Money(12000));
      expect(item.purchasePriceSnapshot, const Money(8000));
    });
  });

  group('StockRepository', () {
    Future<int> movement(
      int productId,
      int delta,
      int resulting, {
      StockMovementType type = StockMovementType.stockEntry,
      StockReferenceType? referenceType,
      int? referenceId,
      DateTime? at,
    }) => db
        .into(db.stockMovements)
        .insert(
          StockMovementsCompanion.insert(
            productId: productId,
            type: type,
            quantityDelta: delta,
            resultingStock: resulting,
            referenceType: Value(referenceType),
            referenceId: Value(referenceId),
            userId: userId,
            createdAt: at ?? testEpochUtc,
          ),
        );

    test('defter toplamı SQL tarafında hesaplanır', () async {
      final productId = await insertTestProduct(db);

      await movement(productId, 100, 100, type: StockMovementType.initial);
      await movement(productId, 20, 120);
      await movement(productId, -5, 115, type: StockMovementType.waste);

      expect(await stock.sumQuantityDelta(productId), 115);
    });

    test('hareketi olmayan ürün için toplam 0', () async {
      final productId = await insertTestProduct(db);
      expect(await stock.sumQuantityDelta(productId), 0);
    });

    test('BR-STOCK-002 invariant ölçülebilir: stok == Σ delta', () async {
      final productId = await insertTestProduct(db);
      await movement(productId, 10, 10, type: StockMovementType.initial);
      await movement(productId, -12, -2, type: StockMovementType.sale);

      // BR-STOCK-006 — negatif stok geçerlidir.
      final ledgerTotal = await stock.sumQuantityDelta(productId);
      expect(ledgerTotal, -2);

      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(ProductsCompanion(stockQuantity: Value(ledgerTotal)));

      final cached = (await (db.select(
        db.products,
      )..where((p) => p.id.equals(productId))).getSingle()).stockQuantity;

      expect(cached, ledgerTotal);
    });

    test('hareketler tarihe göre AZALAN sıralanır', () async {
      final productId = await insertTestProduct(db);
      await movement(productId, 1, 1, at: DateTime.utc(2026, 8, 14, 8));
      await movement(productId, 2, 3, at: DateTime.utc(2026, 8, 14, 10));

      final list = await stock.movementsOf(productId);
      expect(list.first.quantityDelta, 2, reason: 'En yeni hareket başta');
      expect(list.last.quantityDelta, 1);
    });

    test('referansa göre bulunur — satış iptali için gerekli', () async {
      final productId = await insertTestProduct(db);
      await movement(
        productId,
        -3,
        7,
        type: StockMovementType.sale,
        referenceType: StockReferenceType.sale,
        referenceId: 42,
      );
      await movement(productId, 5, 12);

      final found = await stock.findByReference(
        referenceType: StockReferenceType.sale,
        referenceId: 42,
      );

      expect(found.length, 1);
      expect(found.single.quantityDelta, -3);
      expect(found.single.type, StockMovementType.sale);
    });

    test('enum wire değerleri veritabanında METİN olarak saklanır', () async {
      final productId = await insertTestProduct(db);
      await movement(
        productId,
        4,
        4,
        type: StockMovementType.returnedToStock,
        referenceType: StockReferenceType.returnOperation,
        referenceId: 7,
      );

      final raw = await db
          .customSelect(
            'SELECT type, reference_type FROM stock_movements LIMIT 1;',
          )
          .getSingle();

      expect(
        raw.data['type'],
        'return',
        reason: 'docs/13 §2 tip adı — Dart adı farklı olabilir, wire aynı.',
      );
      expect(raw.data['reference_type'], 'return');
    });

    test('bulunamayan hareket → Failure', () async {
      expect(
        (await stock.findById(4242)).failureOrNull!.code,
        'stock_movement_not_found',
      );
    });
  });

  group('mimari sınır', () {
    test('repository domain tipleri döner — Drift satırı sızdırmaz', () async {
      final id = ((await products.create(draft('Kola'))) as Ok<int>).value;
      final result = await products.findById(id);
      final product = (result as Ok<Product>).value;

      // Domain modeli Money kullanır; Drift satırı int kullanırdı.
      expect(product.salePrice, isA<Money>());
      expect(product, isA<Product>());
    });
  });
}
