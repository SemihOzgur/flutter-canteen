/// Satış tamamlama testleri — **BR-SALE-001…011 · REQ-SALE-001…009 ·
/// docs/12 §6**
///
/// Test önceliği rules/06 §2: **Sale (transaction atomikliği, 5 snapshot
/// alanı)** 🔴 · **VAT** 🔴 · **Stock** 🔴 · **Profit** 🔴.
///
/// docs/27 §4: gerçek in-memory SQLite; mock veritabanı yoktur.
library;

import 'package:canteen/application/sales/cart_service.dart';
import 'package:canteen/application/sales/sale_failures.dart';
import 'package:canteen/application/sales/sale_service.dart';
import 'package:canteen/application/stock/stock_service.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, CartItem, Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/repositories/drift_product_repository.dart';
import 'package:canteen/data/repositories/drift_sale_repository.dart';
import 'package:canteen/data/repositories/drift_stock_repository.dart';
import 'package:canteen/domain/enums/cart_status.dart';
import 'package:canteen/domain/enums/sale_status.dart';
import 'package:canteen/domain/enums/stock_movement_type.dart';
import 'package:canteen/domain/enums/stock_reference_type.dart';
import 'package:canteen/domain/models/cart.dart';
import 'package:canteen/domain/models/sale.dart';
import 'package:canteen/domain/models/sale_return.dart';
import 'package:canteen/domain/repositories/sale_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late DateTime now;
  late CartService cartService;
  late SaleService service;
  late DriftStockRepository stockRepo;
  late int userId;
  late Cart cart;

  SaleService buildSaleService({SaleRepository? sales}) {
    return SaleService(
      db: db,
      cartService: cartService,
      carts: CartsDao(db),
      vatRates: VatRatesDao(db),
      appSettings: AppSettingsDao(db),
      auditLogs: AuditLogsDao(db),
      products: DriftProductRepository(db),
      sales: sales ?? DriftSaleRepository(db),
      stockService: StockService(
        db: db,
        stock: stockRepo,
        products: DriftProductRepository(db),
        clock: () => now,
      ),
      clock: () => now,
    );
  }

  setUp(() async {
    now = testEpochUtc;
    db = memoryDatabase(clock: () => now);
    stockRepo = DriftStockRepository(db);
    cartService = CartService(
      db: db,
      carts: CartsDao(db),
      cartItems: CartItemsDao(db),
      vatRates: VatRatesDao(db),
      products: DriftProductRepository(db),
      clock: () => now,
    );
    service = buildSaleService();
    userId = await insertTestUser(db);
    cart = await cartService.ensureActive(userId);
  });

  tearDown(() async => db.close());

  Future<int> vatRate(int bp) => VatRatesDao(db).insertVatRate(
    name: 'oran-$bp',
    rateBasisPoints: bp,
    isDefault: false,
    now: now,
  );

  Future<int> product({
    String name = 'Kola',
    int salePriceMinor = 12000,
    int purchasePriceMinor = 8000,
    int? vatRateId,
    int stockQuantity = 10,
    int? categoryId,
  }) async {
    final id = await insertTestProduct(
      db,
      name: name,
      salePriceMinor: salePriceMinor,
      purchasePriceMinor: purchasePriceMinor,
      categoryId: categoryId,
    );
    await (db.update(db.products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(
        vatRateId: Value(vatRateId),
        stockQuantity: Value(stockQuantity),
      ),
    );
    return id;
  }

  Future<void> addToCart(int productId, {int quantity = 1}) async {
    final result = await cartService.addProduct(
      cartId: cart.id,
      productId: productId,
      quantity: quantity,
    );
    expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
  }

  SaleReceipt ok(Result<SaleReceipt> result) {
    expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
    return result.valueOrNull!;
  }

  Future<List<SaleItem>> itemsOf(int saleId) =>
      DriftSaleRepository(db).itemsOf(saleId);

  // -------------------------------------------------------------------------
  // BR-SALE-001 — beş snapshot alanı
  // -------------------------------------------------------------------------

  group('REQ-SALE-002 — beş snapshot alanı', () {
    test('docs/12 §9 acceptance criteria birebir', () async {
      final category = await CategoriesDao(
        db,
      ).insertCategory(name: 'Atıştırmalık', sortOrder: 5, now: now);
      final rate = await vatRate(2000);
      final id = await product(
        name: 'Cips',
        salePriceMinor: 2000,
        purchasePriceMinor: 1200,
        vatRateId: rate,
        categoryId: category,
      );
      await addToCart(id);

      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );
      final item = (await itemsOf(receipt.saleId)).single;

      expect(item.productNameSnapshot, 'Cips');
      expect(item.unitPrice, const Money(2000));
      expect(item.purchasePriceSnapshot, const Money(1200));
      expect(item.vatRateSnapshotBp, 2000);
      expect(item.categoryIdSnapshot, category);
    });

    test('REQ-SALE-003 — ürün sonradan değişince satır DEĞİŞMEZ', () async {
      final oldCategory = await CategoriesDao(
        db,
      ).insertCategory(name: 'Eski', sortOrder: 1, now: now);
      final oldRate = await vatRate(2000);
      final id = await product(
        name: 'Cips',
        salePriceMinor: 2000,
        purchasePriceMinor: 1200,
        vatRateId: oldRate,
        categoryId: oldCategory,
      );
      await addToCart(id);
      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );

      // Beş alanın BEŞİ de değiştirilir.
      final newCategory = await CategoriesDao(
        db,
      ).insertCategory(name: 'Yeni', sortOrder: 2, now: now);
      final newRate = await vatRate(1000);
      await (db.update(db.products)..where((p) => p.id.equals(id))).write(
        ProductsCompanion(
          name: const Value('Cips XL'),
          salePriceMinor: const Value(3000),
          purchasePriceMinor: const Value(2500),
          vatRateId: Value(newRate),
          categoryId: Value(newCategory),
        ),
      );

      final item = (await itemsOf(receipt.saleId)).single;
      expect(item.productNameSnapshot, 'Cips');
      expect(item.unitPrice, const Money(2000));
      expect(item.purchasePriceSnapshot, const Money(1200));
      expect(item.vatRateSnapshotBp, 2000);
      expect(item.categoryIdSnapshot, oldCategory);

      final sale = (await DriftSaleRepository(
        db,
      ).findById(receipt.saleId)).valueOrNull!;
      expect(sale.grandTotal, const Money(2000), reason: 'Toplam değişmez.');
    });

    test('EC-SALE-018 — alış fiyatı ₺0 ise maliyet 0 yazılır', () async {
      final id = await product(purchasePriceMinor: 0, salePriceMinor: 12000);
      await addToCart(id);

      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );
      final item = (await itemsOf(receipt.saleId)).single;

      expect(item.purchasePriceSnapshot, Money.zero);
      final sale = (await DriftSaleRepository(
        db,
      ).findById(receipt.saleId)).valueOrNull!;
      expect(sale.costTotal, Money.zero);
    });

    test('REQ-FIN-008 — costTotal satır maliyetlerinin toplamıdır', () async {
      final a = await product(name: 'A', purchasePriceMinor: 800);
      final b = await product(name: 'B', purchasePriceMinor: 1500);
      await addToCart(a, quantity: 3);
      await addToCart(b, quantity: 2);

      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );
      final sale = (await DriftSaleRepository(
        db,
      ).findById(receipt.saleId)).valueOrNull!;

      expect(sale.costTotal, const Money(800 * 3 + 1500 * 2));
    });

    test('REQ-BARC-012 — barkodsuz ürün satılabilir, snapshot null', () async {
      final id = await product();
      await addToCart(id);

      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );

      expect((await itemsOf(receipt.saleId)).single.barcodeSnapshot, isNull);
    });

    test('barkodlu üründe BİRİNCİL barkod snapshot edilir', () async {
      final id = await product();
      final products = DriftProductRepository(db);
      await products.addBarcode(productId: id, barcode: '111');
      await products.addBarcode(productId: id, barcode: '222', isPrimary: true);
      await addToCart(id);

      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );

      expect((await itemsOf(receipt.saleId)).single.barcodeSnapshot, '222');
    });
  });

  // -------------------------------------------------------------------------
  // BR-VAT-003 — KDV fiyatın içinden
  // -------------------------------------------------------------------------

  group('BR-VAT-003 · EC-SALE-015 — KDV fiyatın İÇİNDEN çıkarılır', () {
    test('₺120,00 @ %20 → toplam 12000, KDV 2000, matrah 10000', () async {
      final rate = await vatRate(2000);
      await addToCart(await product(salePriceMinor: 12000, vatRateId: rate));

      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );
      final sale = (await DriftSaleRepository(
        db,
      ).findById(receipt.saleId)).valueOrNull!;

      expect(sale.grandTotal, const Money(12000));
      expect(sale.vatTotal, const Money(2000));
      expect(sale.subtotal, const Money(10000));
      expect(
        sale.grandTotal.minor,
        isNot(14400),
        reason: 'REGRESYON: KDV fiyatın ÜZERİNE eklenemez (BR-VAT-003).',
      );
    });

    test('invariant — subtotal + vatTotal == grandTotal', () async {
      final r20 = await vatRate(2000);
      final r10 = await vatRate(1000);
      await addToCart(
        await product(name: 'A', salePriceMinor: 3333, vatRateId: r20),
        quantity: 3,
      );
      await addToCart(
        await product(name: 'B', salePriceMinor: 1777, vatRateId: r10),
        quantity: 7,
      );

      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );
      final sale = (await DriftSaleRepository(
        db,
      ).findById(receipt.saleId)).valueOrNull!;

      expect(sale.isBalanced, isTrue);
      expect(sale.subtotal + sale.vatTotal, sale.grandTotal);
    });

    test('REQ-SALE-012 — genel toplam satır tutarlarının toplamıdır', () async {
      final rate = await vatRate(2000);
      await addToCart(
        await product(name: 'A', salePriceMinor: 2500, vatRateId: rate),
        quantity: 2,
      );
      await addToCart(
        await product(name: 'B', salePriceMinor: 4500, vatRateId: rate),
      );

      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );
      final items = await itemsOf(receipt.saleId);
      final sale = (await DriftSaleRepository(
        db,
      ).findById(receipt.saleId)).valueOrNull!;

      expect(sale.grandTotal, Money.sum(items.map((i) => i.lineTotal)));
      expect(sale.vatTotal, Money.sum(items.map((i) => i.lineVat)));
      expect(sale.subtotal, Money.sum(items.map((i) => i.lineNet)));
    });

    test('EC-SALE-016 — satış anındaki oran snapshot edilir', () async {
      final rate = await vatRate(2000);
      final id = await product(salePriceMinor: 12000, vatRateId: rate);
      await addToCart(id);

      // Sepet dururken oranın DEĞERİ değiştirilir.
      await VatRatesDao(db).updateVatRate(rate, rateBasisPoints: 1000);

      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );
      final item = (await itemsOf(receipt.saleId)).single;

      expect(
        item.vatRateSnapshotBp,
        1000,
        reason:
            'Satış anındaki oran kullanılır — sepete eklenirkenki değil '
            '(EC-SALE-016 · BR-VAT-002).',
      );
      expect(item.lineVat, const Money(1091));
    });

    test(
      'docs/08 §4 — oranı olmayan ürün VARSAYILAN oranı snapshot eder',
      () async {
        // Bu satırın atlanması sessiz bir PARA hatasıdır: ürüne oran
        // atanmamışsa varsayılan devreye girmezse satır %0 ile kaydedilir ve
        // KDV raporları kalıcı olarak eksik çıkar (BR-VAT-002 · REQ-VAT-003).
        final seeded = await VatRatesDao(db).findDefault();
        await VatRatesDao(db).updateVatRate(seeded!.id, rateBasisPoints: 2000);
        await addToCart(await product(salePriceMinor: 12000));

        final receipt = ok(
          await service.complete(cartId: cart.id, userId: userId),
        );
        final item = (await itemsOf(receipt.saleId)).single;

        expect(item.vatRateSnapshotBp, 2000);
        expect(item.lineVat, const Money(2000));
        expect(item.lineNet, const Money(10000));
      },
    );

    test(
      'docs/08 §4 — PASİF oran ürüne atanmışsa yine snapshot edilir',
      () async {
        // "Ürünün oranı pasifleştirilmiş → satışta o oran kullanılmaya devam
        // eder — snapshot mantığı gereği doğru davranıştır."
        final rate = await vatRate(2000);
        final id = await product(salePriceMinor: 12000, vatRateId: rate);
        await addToCart(id);
        await VatRatesDao(db).setActive(rate, false);

        final receipt = ok(
          await service.complete(cartId: cart.id, userId: userId),
        );

        expect((await itemsOf(receipt.saleId)).single.vatRateSnapshotBp, 2000);
      },
    );

    test('EC-SALE-017 — %0 oranlı ürün: KDV 0, matrah = brüt', () async {
      await addToCart(await product(salePriceMinor: 12000));

      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );
      final sale = (await DriftSaleRepository(
        db,
      ).findById(receipt.saleId)).valueOrNull!;

      expect(sale.vatTotal, Money.zero);
      expect(sale.subtotal, const Money(12000));
    });
  });

  // -------------------------------------------------------------------------
  // Stok defteri
  // -------------------------------------------------------------------------

  group('stok defteri — docs/12 §6.2 adım 3c–3d', () {
    Future<int> cachedStock(int productId) async => (await (db.select(
      db.products,
    )..where((p) => p.id.equals(productId))).getSingle()).stockQuantity;

    test('satış `sale` hareketi yazar ve önbelleği düşürür', () async {
      final id = await product(stockQuantity: 10);
      await addToCart(id, quantity: 3);

      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );

      final movements = await stockRepo.movementsOf(id);
      expect(movements, hasLength(1));
      final movement = movements.single;
      expect(movement.type, StockMovementType.sale);
      expect(movement.quantityDelta, -3);
      expect(movement.resultingStock, 7);
      expect(movement.referenceType, StockReferenceType.sale);
      expect(movement.referenceId, receipt.saleId);
      expect(
        movement.unitCost,
        isNull,
        reason: 'docs/13 §2 — `sale` hareketi birim maliyet taşımaz.',
      );

      expect(await cachedStock(id), 7);
      expect(await stockRepo.sumQuantityDelta(id), -3);
    });

    test(
      'BR-STOCK-006 — stok yetersizken satış YAPILIR, negatife düşer',
      () async {
        final id = await product(stockQuantity: 1);
        await addToCart(id, quantity: 4);

        final result = await service.complete(cartId: cart.id, userId: userId);

        expect(
          result.isOk,
          isTrue,
          reason: 'BR-STOCK-006: stok satışı ENGELLEMEZ, yalnızca uyarır.',
        );
        expect(await cachedStock(id), -3);
        expect((await stockRepo.movementsOf(id)).single.resultingStock, -3);
      },
    );

    test(
      'EC-CART-004 — aynı ürün iki satırda: iki hareket, ZİNCİRLİ stok',
      () async {
        final id = await product(salePriceMinor: 2500, stockQuantity: 10);
        await addToCart(id, quantity: 2);
        final second = await cartService.addProduct(
          cartId: cart.id,
          productId: id,
          quantity: 3,
          unitPrice: const Money(2000),
        );
        expect(second.valueOrNull!.lines, hasLength(2));

        final receipt = ok(
          await service.complete(cartId: cart.id, userId: userId),
        );

        // `movementsOf` tarihe göre sıralar; iki hareket aynı milisaniyede
        // yazıldığı için deterministik sıra id ile kurulur.
        final movements = [...await stockRepo.movementsOf(id)]
          ..sort((a, b) => a.id.compareTo(b.id));
        expect(movements, hasLength(2));
        expect(
          movements.map((m) => m.resultingStock),
          [8, 5],
          reason:
              'İkinci satırın resulting_stock\'u birincisini GÖRMEK zorundadır; '
              'aksi hâlde defter geriye dönük okunamaz (BR-STOCK-008).',
        );
        expect(await cachedStock(id), 5);
        expect(
          await cachedStock(id),
          await stockRepo.sumQuantityDelta(id) + 10,
          reason: 'BR-STOCK-002 — önbellek defterle tutarlıdır.',
        );
        expect(await itemsOf(receipt.saleId), hasLength(2));
      },
    );
  });

  // -------------------------------------------------------------------------
  // REQ-SALE-001 — ATOMİKLİK
  // -------------------------------------------------------------------------

  group('REQ-SALE-001 · EC-SALE-002 — atomiklik', () {
    test(
      '3. satır yazılırken hata → HİÇBİR kayıt oluşmaz, sepet KORUNUR',
      () async {
        final a = await product(name: 'A', stockQuantity: 10);
        final b = await product(name: 'B', stockQuantity: 10);
        final c = await product(name: 'C', stockQuantity: 10);
        await addToCart(a);
        await addToCart(b);
        await addToCart(c);

        final failing = buildSaleService(
          sales: _FailingSaleRepository(DriftSaleRepository(db), failOnItem: 3),
        );

        await expectLater(
          failing.complete(cartId: cart.id, userId: userId),
          throwsA(isA<StateError>()),
        );

        // docs/12 §9 REQ-SALE-001 acceptance criteria — altı madde.
        expect(await db.select(db.sales).get(), isEmpty);
        expect(await db.select(db.saleItems).get(), isEmpty);
        expect(await db.select(db.stockMovements).get(), isEmpty);
        for (final id in [a, b, c]) {
          final row = await (db.select(
            db.products,
          )..where((p) => p.id.equals(id))).getSingle();
          expect(
            row.stockQuantity,
            10,
            reason: 'Hiçbir ürünün stoğu değişmez.',
          );
        }
        final preserved = await cartService.load(cart.id, userId);
        expect(
          preserved.lines,
          hasLength(3),
          reason: 'Sepet olduğu gibi durur.',
        );
        expect(
          (await CartsDao(db).findById(cart.id))!.status,
          CartStatus.active,
        );
      },
    );

    test('rollback sonrası satış numarası sayacı da geri alınır', () async {
      final id = await product();
      await addToCart(id);

      final failing = buildSaleService(
        sales: _FailingSaleRepository(DriftSaleRepository(db), failOnItem: 1),
      );
      await expectLater(
        failing.complete(cartId: cart.id, userId: userId),
        throwsA(isA<StateError>()),
      );

      // Sayaç transaction içinde arttığı için rollback onu da geri alır;
      // aksi hâlde ilk gerçek satış 2026-000002 olurdu.
      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );
      expect(receipt.saleNumber, '2026-000001');
    });

    test(
      'EC-CART-010 — bozuk satır varsa satış YAPILMAZ (eksik tahsilat)',
      () async {
        final kept = await product(name: 'Kalan', salePriceMinor: 5000);
        final lost = await product(name: 'Kaybolan', salePriceMinor: 3000);
        await addToCart(kept);
        await addToCart(lost);

        // Bozulma senaryosu: yabancı anahtar normalde bunu engeller.
        await db.customStatement('PRAGMA foreign_keys = OFF');
        await db.customStatement('DELETE FROM products WHERE id = $lost');

        final loaded = await cartService.load(cart.id, userId);
        expect(loaded.lines, hasLength(1), reason: 'Bozuk satır düşer.');
        expect(loaded.droppedLineCount, 1);

        final result = await service.complete(cartId: cart.id, userId: userId);

        expect(
          result.failureOrNull,
          SaleFailures.productMissing,
          reason:
              'Kalan satırı satmak müşteriden EKSİK tahsilat demektir ve hiçbir '
              'yerde iz bırakmaz.',
        );
        expect(await db.select(db.sales).get(), isEmpty);
      },
    );

    test(
      'EC-CART-010 — açılışta bozuk satırlar temizlenir ve BİLDİRİLİR',
      () async {
        final kept = await product(name: 'Kalan');
        final lost = await product(name: 'Kaybolan');
        await addToCart(kept);
        await addToCart(lost);
        await db.customStatement('PRAGMA foreign_keys = OFF');
        await db.customStatement('DELETE FROM products WHERE id = $lost');

        final reopened = await cartService.ensureActive(userId);

        expect(reopened.droppedLineCount, 1);
        expect(reopened.hasDroppedLines, isTrue);
        expect(reopened.lines, hasLength(1));
        // Temizlik kalıcıdır: ikinci açılışta artık bildirim yok.
        final second = await cartService.ensureActive(userId);
        expect(second.droppedLineCount, 0);
        expect(second.lines, hasLength(1), reason: 'Sepetin kalanı KORUNUR.');
      },
    );
  });

  // -------------------------------------------------------------------------
  // Satış numarası — docs/12 §6.4
  // -------------------------------------------------------------------------

  group('REQ-SALE-005 — satış numarası', () {
    test('ilk satış 2026-000001, sonraki 2026-000002', () async {
      final id = await product(stockQuantity: 100);

      await addToCart(id);
      final first = ok(await service.complete(cartId: cart.id, userId: userId));

      cart = first.newCart;
      await addToCart(id);
      final second = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );

      expect(first.saleNumber, '2026-000001');
      expect(second.saleNumber, '2026-000002');
    });

    test('EC-SALE-011 — yıl değişince sayaç 1\'den başlar', () async {
      final id = await product(stockQuantity: 100);
      await addToCart(id);
      final first = ok(await service.complete(cartId: cart.id, userId: userId));
      expect(first.saleNumber, '2026-000001');

      now = DateTime.utc(2027, 6, 1, 9);
      cart = first.newCart;
      await addToCart(id);
      final next = ok(await service.complete(cartId: cart.id, userId: userId));

      expect(next.saleNumber, '2027-000001');
    });

    test('numara `sales` satırına yazılır ve benzersizdir', () async {
      final id = await product(stockQuantity: 100);
      await addToCart(id);
      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );

      final sale = (await DriftSaleRepository(
        db,
      ).findByNumber('2026-000001')).valueOrNull!;
      expect(sale.id, receipt.saleId);
      expect(sale.status, SaleStatus.completed);
    });
  });

  // -------------------------------------------------------------------------
  // Sepet devri — docs/12 §6.2 adım 4–5
  // -------------------------------------------------------------------------

  group('REQ-SALE-006 — satıştan sonra yeni boş sepet', () {
    test('eski sepet closed olur, yeni AKTİF sepet açılır', () async {
      await addToCart(await product());
      final oldCartId = cart.id;

      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );

      expect(
        (await CartsDao(db).findById(oldCartId))!.status,
        CartStatus.closed,
      );
      expect(receipt.newCart.id, isNot(oldCartId));
      expect(receipt.newCart.lines, isEmpty);

      final active = await CartsDao(db).listActive();
      expect(active, hasLength(1), reason: 'BR-CART-001 korunur.');
      expect(active.single.id, receipt.newCart.id);
    });

    test(
      'kapanan sepetin satırları satışa DÖNÜŞMÜŞ, sepette kalmamıştır',
      () async {
        await addToCart(await product());
        final receipt = ok(
          await service.complete(cartId: cart.id, userId: userId),
        );

        expect(await cartService.load(receipt.newCart.id, userId), isNotNull);
        expect(
          (await cartService.load(receipt.newCart.id, userId)).lines,
          isEmpty,
        );
        expect(await itemsOf(receipt.saleId), hasLength(1));
      },
    );
  });

  // -------------------------------------------------------------------------
  // Ön kontroller — docs/12 §6.1
  // -------------------------------------------------------------------------

  group('ön kontroller', () {
    test(
      'EC-SALE-001 · BR-CART-005 — boş sepetle satış tamamlanamaz',
      () async {
        final result = await service.complete(cartId: cart.id, userId: userId);

        expect(result.failureOrNull, SaleFailures.emptyCart);
        expect(await db.select(db.sales).get(), isEmpty);
      },
    );

    test(
      'REQ-SALE-008 · EC-SALE-008 — çift gönderim TEK satış üretir',
      () async {
        await addToCart(await product(stockQuantity: 100), quantity: 2);

        final results = await Future.wait([
          service.complete(cartId: cart.id, userId: userId),
          service.complete(cartId: cart.id, userId: userId),
          service.complete(cartId: cart.id, userId: userId),
        ]);

        expect(results.where((r) => r.isOk), hasLength(1));
        expect(
          results.where(
            (r) => r.failureOrNull == SaleFailures.alreadyInProgress,
          ),
          hasLength(2),
        );
        expect(await db.select(db.sales).get(), hasLength(1));
        expect(
          await db.select(db.stockMovements).get(),
          hasLength(1),
          reason: 'Stok yalnızca BİR kez düşer.',
        );
      },
    );
  });

  // -------------------------------------------------------------------------
  // Nakit — docs/12 §5
  // -------------------------------------------------------------------------

  group('nakit hesaplama — BR-SALE-007/008', () {
    test('REQ-SALE-007 — nakit girilmezse NULL kaydedilir', () async {
      await addToCart(await product(salePriceMinor: 12000));

      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );
      final sale = (await DriftSaleRepository(
        db,
      ).findById(receipt.saleId)).valueOrNull!;

      expect(sale.cashReceived, isNull);
      expect(sale.change, isNull);
      expect(receipt.change, isNull);
    });

    test('para üstü hesaplanır', () async {
      await addToCart(await product(salePriceMinor: 13500));

      final receipt = ok(
        await service.complete(
          cartId: cart.id,
          userId: userId,
          cashReceived: const Money(20000),
        ),
      );
      final sale = (await DriftSaleRepository(
        db,
      ).findById(receipt.saleId)).valueOrNull!;

      expect(sale.cashReceived, const Money(20000));
      expect(sale.change, const Money(6500));
      expect(receipt.change, const Money(6500));
    });

    test('EC-SALE-009 — alınan < toplam ise satış tamamlanmaz', () async {
      await addToCart(await product(salePriceMinor: 13500));

      final result = await service.complete(
        cartId: cart.id,
        userId: userId,
        cashReceived: const Money(10000),
      );

      expect(result.failureOrNull, SaleFailures.insufficientCash);
      expect(await db.select(db.sales).get(), isEmpty);
    });

    test('tam tutar kabul edilir, para üstü 0', () async {
      await addToCart(await product(salePriceMinor: 13500));

      final receipt = ok(
        await service.complete(
          cartId: cart.id,
          userId: userId,
          cashReceived: const Money(13500),
        ),
      );

      expect(receipt.change, Money.zero);
    });

    test('EC-SALE-010 — çok büyük tutar REDDEDİLMEZ', () async {
      await addToCart(await product(salePriceMinor: 13500));

      final receipt = ok(
        await service.complete(
          cartId: cart.id,
          userId: userId,
          cashReceived: const Money(10000000),
        ),
      );

      expect(receipt.change, const Money(10000000 - 13500));
    });

    test('negatif nakit reddedilir', () async {
      await addToCart(await product());

      final result = await service.complete(
        cartId: cart.id,
        userId: userId,
        cashReceived: const Money(-1),
      );

      expect(result.failureOrNull, SaleFailures.negativeCash);
    });
  });

  // -------------------------------------------------------------------------
  // Fiyat override — docs/12 §4 · REQ-CART-005 acceptance criteria
  // -------------------------------------------------------------------------

  group('BR-SALE-004 — fiyat override', () {
    test('docs/12 §9 REQ-CART-005 acceptance criteria birebir', () async {
      final id = await product(salePriceMinor: 2500);
      await addToCart(id);
      final loaded = await cartService.load(cart.id, userId);
      await cartService.overridePrice(
        cartId: cart.id,
        lineId: loaded.lines.single.id,
        unitPrice: const Money(2000),
      );

      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );
      final item = (await itemsOf(receipt.saleId)).single;

      expect(item.unitPrice, const Money(2000));
      expect(item.originalUnitPrice, const Money(2500));

      final row = await (db.select(
        db.products,
      )..where((p) => p.id.equals(id))).getSingle();
      expect(row.salePriceMinor, 2500, reason: 'Ürünün fiyatı DEĞİŞMEZ.');

      final logs = await AuditLogsDao(db).listRecent();
      expect(
        logs.where((l) => l.action == SaleService.actionPriceOverridden),
        hasLength(1),
      );
    });

    test('override yoksa fiyat audit kaydı YAZILMAZ', () async {
      await addToCart(await product());
      await service.complete(cartId: cart.id, userId: userId);

      final logs = await AuditLogsDao(db).listRecent();
      expect(
        logs.where((l) => l.action == SaleService.actionPriceOverridden),
        isEmpty,
      );
    });

    test(
      'REQ-CART-007 — bayat fiyat KORUNUR, liste fiyatı original olur',
      () async {
        final id = await product(salePriceMinor: 2500);
        await addToCart(id);
        // Sepet dururken ürünün fiyatı değişiyor (EC-CART-002).
        await (db.update(db.products)..where((p) => p.id.equals(id))).write(
          const ProductsCompanion(salePriceMinor: Value(3000)),
        );

        final receipt = ok(
          await service.complete(cartId: cart.id, userId: userId),
        );
        final item = (await itemsOf(receipt.saleId)).single;

        expect(
          item.unitPrice,
          const Money(2500),
          reason:
              'Kullanıcı müşteriye bu fiyatı söylemiş olabilir; sepetteki fiyat '
              'korunur (REQ-CART-007).',
        );
        expect(item.originalUnitPrice, const Money(3000));
      },
    );
  });

  // -------------------------------------------------------------------------
  // Audit — docs/18 §3
  // -------------------------------------------------------------------------

  group('audit — docs/18 §3', () {
    test('saleCompleted fiş no, toplam ve satır sayısı ile yazılır', () async {
      final rate = await vatRate(2000);
      await addToCart(
        await product(salePriceMinor: 12000, vatRateId: rate),
        quantity: 2,
      );

      final receipt = ok(
        await service.complete(cartId: cart.id, userId: userId),
      );

      final log = (await AuditLogsDao(db).listRecent()).firstWhere(
        (l) => l.action == SaleService.actionCompleted,
      );
      expect(log.entityType, 'sale');
      expect(log.entityId, receipt.saleId);
      expect(log.userId, userId);
      expect(log.newValue, contains('2026-000001'));
      expect(log.newValue, contains('24000'));
    });
  });

  // -------------------------------------------------------------------------
  // Sayımlar
  // -------------------------------------------------------------------------

  test('sales.item_count satır, unit_count adet sayar', () async {
    await addToCart(await product(name: 'A', stockQuantity: 50), quantity: 2);
    await addToCart(await product(name: 'B', stockQuantity: 50), quantity: 5);

    final receipt = ok(await service.complete(cartId: cart.id, userId: userId));
    final sale = (await DriftSaleRepository(
      db,
    ).findById(receipt.saleId)).valueOrNull!;

    expect(sale.itemCount, 2);
    expect(sale.unitCount, 7);
  });

  test('EC-SALE-013 — 100 satırlık satış tamamlanır', () async {
    for (var i = 0; i < 100; i++) {
      await addToCart(
        await product(name: 'Ürün $i', salePriceMinor: 100 + i),
        quantity: 2,
      );
    }

    final receipt = ok(await service.complete(cartId: cart.id, userId: userId));

    expect(await itemsOf(receipt.saleId), hasLength(100));
    expect(await db.select(db.stockMovements).get(), hasLength(100));
    final sale = (await DriftSaleRepository(
      db,
    ).findById(receipt.saleId)).valueOrNull!;
    expect(sale.unitCount, 200);
    expect(sale.isBalanced, isTrue);
  });
}

/// [SaleRepository.insertItem] N'inci çağrıda patlar — atomiklik testi için.
///
/// Diğer tüm çağrılar gerçek repository'ye devredilir.
class _FailingSaleRepository implements SaleRepository {
  final SaleRepository _inner;
  final int failOnItem;
  int _calls = 0;

  _FailingSaleRepository(this._inner, {required this.failOnItem});

  @override
  Future<int> insertItem(int saleId, NewSaleItem item) {
    _calls++;
    if (_calls == failOnItem) throw StateError('satır yazımı başarısız');
    return _inner.insertItem(saleId, item);
  }

  @override
  Future<int> insertSale(NewSale sale) => _inner.insertSale(sale);

  @override
  Future<Result<Sale>> findById(int id) => _inner.findById(id);

  @override
  Future<Result<Sale>> findByNumber(String saleNumber) =>
      _inner.findByNumber(saleNumber);

  @override
  Future<List<Sale>> list({
    DateTime? fromUtc,
    DateTime? toUtc,
    SaleStatus? status,
    int? userId,
    int? minTotalMinor,
    int? maxTotalMinor,
    String? saleNumber,
    int limit = 50,
    int offset = 0,
  }) => _inner.list(
    fromUtc: fromUtc,
    toUtc: toUtc,
    status: status,
    userId: userId,
    minTotalMinor: minTotalMinor,
    maxTotalMinor: maxTotalMinor,
    saleNumber: saleNumber,
    limit: limit,
    offset: offset,
  );

  @override
  Future<List<Sale>> listCompletedBetween({
    required DateTime fromUtc,
    required DateTime toUtc,
    int limit = 100,
    int offset = 0,
  }) => _inner.listCompletedBetween(
    fromUtc: fromUtc,
    toUtc: toUtc,
    limit: limit,
    offset: offset,
  );

  @override
  Future<List<SaleItem>> itemsOf(int saleId) => _inner.itemsOf(saleId);

  // --- Faz 7 yüzeyi: bu test kullanmaz, gerçek repository'ye devredilir ----

  @override
  Future<int> updateStatus(
    int saleId, {
    required SaleStatus status,
    DateTime? cancelledAtUtc,
    String? note,
  }) => _inner.updateStatus(
    saleId,
    status: status,
    cancelledAtUtc: cancelledAtUtc,
    note: note,
  );

  @override
  Future<int> insertReturn(NewReturn value) => _inner.insertReturn(value);

  @override
  Future<int> insertReturnItem(int returnId, NewReturnItem item) =>
      _inner.insertReturnItem(returnId, item);

  @override
  Future<int> incrementReturnedQuantity(int saleItemId, int by) =>
      _inner.incrementReturnedQuantity(saleItemId, by);

  @override
  Future<List<SaleReturn>> returnsOf(int saleId) => _inner.returnsOf(saleId);

  @override
  Future<List<SaleReturnItem>> returnItemsOf(int returnId) =>
      _inner.returnItemsOf(returnId);
}
