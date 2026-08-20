/// Satış iptali ve iade — **docs/14 · REQ-RET-001…012 · BR-RET-001/003/005/006**
///
/// Test önceliği rules/06 §2: **Return (kısmi iade, durum makinesi, snapshot
/// fiyat)** 🔴.
///
/// docs/27 §4: gerçek in-memory SQLite; mock veritabanı yoktur.
///
/// ## Kapsanan requirement'lar (Faz 11 izlenebilirliği)
///
/// - **REQ-RET-004** — iade satılanı aşamaz
/// - **REQ-RET-005** — iade snapshot fiyatla
/// - **REQ-RET-008** — iptal edilmiş satış tekrar iptal/iade edilemez
/// ## Kapsanan uç durumlar (docs/26 · Faz 11 izlenebilirliği)
///
/// - **EC-RET-001** — iptal edilmiş satış tekrar iptal edilemez
/// - **EC-RET-002** — iade edilmiş satış iptal edilemez
/// - **EC-RET-003** — satılandan fazla iade reddedilir
/// - **EC-RET-004** — tüm satırlar tek tek iade edilince `returned`
/// - **EC-RET-006** — iade ortasında hata → hiçbir kayıt oluşmaz
/// - **EC-RET-007** — fiyat değişmişse iade SNAPSHOT fiyattan
/// - **EC-RET-009** — `0` miktarla iade reddedilir
///
library;

import 'package:canteen/application/audit/audit_actions.dart';
import 'package:canteen/application/audit/audit_service.dart';
import 'package:canteen/application/sales/cart_service.dart';
import 'package:canteen/application/sales/return_failures.dart';
import 'package:canteen/application/sales/return_service.dart';
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
import 'package:canteen/domain/enums/return_type.dart';
import 'package:canteen/domain/enums/sale_status.dart';
import 'package:canteen/domain/enums/stock_movement_type.dart';
import 'package:canteen/domain/enums/stock_reference_type.dart';
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
  late SaleService saleService;
  late ReturnService service;
  late DriftStockRepository stockRepo;
  late DriftSaleRepository saleRepo;
  late int userId;

  setUp(() async {
    now = testEpochUtc;
    db = memoryDatabase(clock: () => now);
    stockRepo = DriftStockRepository(db);
    saleRepo = DriftSaleRepository(db);
    final products = DriftProductRepository(db);
    final audit = AuditService(auditLogs: AuditLogsDao(db), clock: () => now);
    final stockService = StockService(
      db: db,
      stock: stockRepo,
      products: products,
      audit: audit,
      clock: () => now,
    );
    cartService = CartService(
      db: db,
      carts: CartsDao(db),
      cartItems: CartItemsDao(db),
      vatRates: VatRatesDao(db),
      products: products,
      clock: () => now,
    );
    saleService = SaleService(
      db: db,
      cartService: cartService,
      carts: CartsDao(db),
      vatRates: VatRatesDao(db),
      appSettings: AppSettingsDao(db),
      auditLogs: AuditLogsDao(db),
      products: products,
      sales: saleRepo,
      stockService: stockService,
      clock: () => now,
    );
    service = ReturnService(
      db: db,
      sales: saleRepo,
      stockService: stockService,
      audit: audit,
      clock: () => now,
    );
    userId = await insertTestUser(db);
  });

  tearDown(() => db.close());

  Future<int> product({
    String name = 'Kola',
    int salePriceMinor = 2500,
    int stockQuantity = 10,
  }) async {
    final id = await insertTestProduct(
      db,
      name: name,
      salePriceMinor: salePriceMinor,
    );
    await (db.update(db.products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(stockQuantity: Value(stockQuantity)),
    );
    return id;
  }

  /// Satış oluşturur ve `(saleId, satırlar)` döner.
  Future<({int saleId, List<SaleItem> items})> sell(
    Map<int, int> productQuantities,
  ) async {
    final cart = await cartService.ensureActive(userId);
    for (final entry in productQuantities.entries) {
      final added = await cartService.addProduct(
        cartId: cart.id,
        productId: entry.key,
        quantity: entry.value,
      );
      expect(added.isErr, isFalse, reason: '${added.failureOrNull}');
    }
    final receipt = await saleService.complete(cartId: cart.id, userId: userId);
    expect(receipt.isErr, isFalse, reason: '${receipt.failureOrNull}');
    final saleId = receipt.valueOrNull!.saleId;
    return (saleId: saleId, items: await saleRepo.itemsOf(saleId));
  }

  Future<int> stockOf(int productId) async => (await (db.select(
    db.products,
  )..where((p) => p.id.equals(productId))).getSingle()).stockQuantity;

  Future<SaleStatus> statusOf(int saleId) async =>
      (await saleRepo.findById(saleId)).valueOrNull!.status;

  Future<List<AuditLog>> logs() => AuditLogsDao(db).listRecent();

  // -------------------------------------------------------------------------
  // İPTAL — docs/14 §3
  // -------------------------------------------------------------------------

  group('REQ-RET-002 — satış iptali', () {
    test('docs/14 §8 acceptance criteria birebir', () async {
      // "3 satırlık (toplam 6 adet) satış; stoklar 10, 20, 30 →
      //  iptal sonrası 12, 21, 33"
      final a = await product(name: 'A', stockQuantity: 12);
      final b = await product(name: 'B', stockQuantity: 21);
      final c = await product(name: 'C', stockQuantity: 33);
      final sale = await sell({a: 2, b: 1, c: 3});
      expect(await stockOf(a), 10);
      expect(await stockOf(b), 20);
      expect(await stockOf(c), 30);

      final result = await service.cancelSale(
        saleId: sale.saleId,
        userId: userId,
        reason: 'Yanlış satış',
      );

      expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
      expect(await statusOf(sale.saleId), SaleStatus.cancelled);

      // "Satış kaydı ve satırları SİLİNMEMİŞTİR."
      expect(await saleRepo.itemsOf(sale.saleId), hasLength(3));

      // "Her ürün için type='saleCancellation' hareketi oluşur."
      for (final id in [a, b, c]) {
        final movements = await stockRepo.movementsOf(id);
        final cancellation = movements.firstWhere(
          (m) => m.type == StockMovementType.saleCancellation,
        );
        expect(cancellation.referenceType, StockReferenceType.sale);
        expect(cancellation.referenceId, sale.saleId);
        expect(
          cancellation.unitCost,
          isNull,
          reason: 'docs/13 §2 — iptal hareketi birim maliyet taşımaz.',
        );
      }

      // "Stoklar 12, 21, 33 olur."
      expect(await stockOf(a), 12);
      expect(await stockOf(b), 21);
      expect(await stockOf(c), 33);

      // "Audit log'a iptal kaydı yazılmıştır."
      final log = (await logs()).firstWhere(
        (l) => l.action == AuditActions.saleCancelled,
      );
      expect(log.entityId, sale.saleId);
      expect(log.metadata, contains('Yanlış satış'));
    });

    test('orijinal `sale` hareketi SİLİNMEZ — REQ-RET-006', () async {
      final id = await product(stockQuantity: 10);
      final sale = await sell({id: 3});

      await service.cancelSale(
        saleId: sale.saleId,
        userId: userId,
        reason: 'x',
      );

      final movements = await stockRepo.movementsOf(id);
      expect(
        movements.where((m) => m.type == StockMovementType.sale),
        hasLength(1),
        reason: 'BR-STOCK-005 — defter yalnızca ileri yazılır.',
      );
      expect(await stockOf(id), await stockRepo.sumQuantityDelta(id) + 10);
    });

    test('iptal sebebi ZORUNLUDUR', () async {
      final sale = await sell({await product(): 1});

      for (final reason in ['', '   ', '\n']) {
        final result = await service.cancelSale(
          saleId: sale.saleId,
          userId: userId,
          reason: reason,
        );
        expect(result.failureOrNull, ReturnFailures.reasonRequired);
      }
      expect(await statusOf(sale.saleId), SaleStatus.completed);
    });

    test('sebep satışın NOTUNA eklenir, mevcut not korunur', () async {
      final sale = await sell({await product(): 1});

      await service.cancelSale(
        saleId: sale.saleId,
        userId: userId,
        reason: 'Müşteri vazgeçti',
      );

      final row = await (db.select(
        db.sales,
      )..where((s) => s.id.equals(sale.saleId))).getSingle();
      expect(row.note, contains('Müşteri vazgeçti'));
      expect(row.cancelledAt, now);
    });

    test('BR-RET-006 — iptal edilmiş satış TEKRAR iptal edilemez', () async {
      final id = await product(stockQuantity: 10);
      final sale = await sell({id: 2});
      await service.cancelSale(
        saleId: sale.saleId,
        userId: userId,
        reason: 'x',
      );
      final stockAfterFirst = await stockOf(id);

      final second = await service.cancelSale(
        saleId: sale.saleId,
        userId: userId,
        reason: 'y',
      );

      expect(second.failureOrNull, ReturnFailures.alreadyCancelled);
      expect(
        await stockOf(id),
        stockAfterFirst,
        reason: 'Stok İKİNCİ kez geri eklenmemelidir.',
      );
    });

    test('BR-RET-001 — iade YAPILMIŞ satış iptal EDİLEMEZ', () async {
      final id = await product(stockQuantity: 10);
      final sale = await sell({id: 3});
      await service.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [
          ReturnLineRequest(saleItemId: sale.items.single.id, quantity: 1),
        ],
      );
      final stockAfterReturn = await stockOf(id);

      final result = await service.cancelSale(
        saleId: sale.saleId,
        userId: userId,
        reason: 'x',
      );

      expect(result.failureOrNull, ReturnFailures.cancelAfterReturn);
      expect(
        await stockOf(id),
        stockAfterReturn,
        reason:
            'İptal edilseydi iade hareketlerinin ÜZERİNE tam iptal yazılır ve '
            'stok iki kez geri eklenirdi.',
      );
    });

    test('olmayan satış iptal edilemez', () async {
      final result = await service.cancelSale(
        saleId: 999999,
        userId: userId,
        reason: 'x',
      );
      expect(result.failureOrNull, ReturnFailures.saleNotFound);
    });
  });

  // -------------------------------------------------------------------------
  // İADE — docs/14 §4
  // -------------------------------------------------------------------------

  group('REQ-RET-003/007 — kısmi iade ve durum makinesi', () {
    test('docs/14 §8 acceptance criteria birebir', () async {
      // "Su 500ml 3 adet satılmış → 1 adet iade → partiallyReturned →
      //  kalan 2 de iade → returned → tekrar iade EDİLEMEZ"
      final id = await product(
        name: 'Su',
        salePriceMinor: 1000,
        stockQuantity: 10,
      );
      final sale = await sell({id: 3});
      final itemId = sale.items.single.id;
      expect(await stockOf(id), 7);

      final first = await service.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [ReturnLineRequest(saleItemId: itemId, quantity: 1)],
      );
      expect(first.isErr, isFalse, reason: '${first.failureOrNull}');
      expect((await saleRepo.itemsOf(sale.saleId)).single.returnedQuantity, 1);
      expect(await statusOf(sale.saleId), SaleStatus.partiallyReturned);
      expect(await stockOf(id), 8, reason: 'Stok +1 artar.');

      final second = await service.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [ReturnLineRequest(saleItemId: itemId, quantity: 2)],
      );
      expect(second.isErr, isFalse, reason: '${second.failureOrNull}');
      expect((await saleRepo.itemsOf(sale.saleId)).single.returnedQuantity, 3);
      expect(await statusOf(sale.saleId), SaleStatus.returned);
      expect(await stockOf(id), 10);

      final third = await service.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [ReturnLineRequest(saleItemId: itemId, quantity: 1)],
      );
      expect(third.failureOrNull, ReturnFailures.exceedsRemaining);
    });

    test('tek seferde tam iade doğrudan `returned` yapar', () async {
      final id = await product(stockQuantity: 10);
      final sale = await sell({id: 2});

      final result = await service.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [
          ReturnLineRequest(saleItemId: sale.items.single.id, quantity: 2),
        ],
      );

      expect(result.valueOrNull!.saleStatus, SaleStatus.returned);
      // docs/14 §4 — bu TEK iadenin kapsamı `full`'dür.
      expect(
        (await saleRepo.returnsOf(sale.saleId)).single.type,
        ReturnType.full,
      );
    });

    test('kısmi iade `partial` türüyle kaydedilir', () async {
      final id = await product(stockQuantity: 10);
      final sale = await sell({id: 3});

      await service.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [
          ReturnLineRequest(saleItemId: sale.items.single.id, quantity: 1),
        ],
      );

      expect(
        (await saleRepo.returnsOf(sale.saleId)).single.type,
        ReturnType.partial,
      );
    });

    test('çok satırlı satışta yalnızca SEÇİLEN satır iade edilir', () async {
      final a = await product(name: 'A', stockQuantity: 10);
      final b = await product(name: 'B', stockQuantity: 10);
      final sale = await sell({a: 2, b: 3});
      final itemA = sale.items.firstWhere((i) => i.productId == a);

      await service.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [ReturnLineRequest(saleItemId: itemA.id, quantity: 1)],
      );

      final items = await saleRepo.itemsOf(sale.saleId);
      expect(items.firstWhere((i) => i.productId == a).returnedQuantity, 1);
      expect(items.firstWhere((i) => i.productId == b).returnedQuantity, 0);
      expect(await stockOf(a), 9);
      expect(await stockOf(b), 7, reason: 'B satırına DOKUNULMAZ.');
      expect(await statusOf(sale.saleId), SaleStatus.partiallyReturned);
    });
  });

  group('BR-RET-005 — iade tutarı SNAPSHOT fiyattan', () {
    test('docs/14 §8 acceptance criteria birebir', () async {
      // "Ürün ₺25,00'den satılmış, güncel fiyatı ₺30,00 → iade ₺25,00"
      final id = await product(salePriceMinor: 2500, stockQuantity: 10);
      final sale = await sell({id: 1});
      await (db.update(db.products)..where((p) => p.id.equals(id))).write(
        const ProductsCompanion(salePriceMinor: Value(3000)),
      );

      final result = await service.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [
          ReturnLineRequest(saleItemId: sale.items.single.id, quantity: 1),
        ],
      );

      expect(
        result.valueOrNull!.total,
        const Money(2500),
        reason:
            'Müşteri ₺25\'e aldığı ürün için ₺25 geri alır — güncel fiyat '
            'KULLANILMAZ.',
      );
      final returned = (await saleRepo.returnsOf(sale.saleId)).single;
      expect(returned.total, const Money(2500));
      final items = await saleRepo.returnItemsOf(returned.id);
      expect(items.single.unitPrice, const Money(2500));
      expect(items.single.lineTotal, const Money(2500));
    });

    test(
      'satış sırasında değiştirilmiş fiyat da snapshot\'tan gelir',
      () async {
        // docs/12 §4 fiyat override'ı; iade o fiyattan yapılır.
        final id = await product(salePriceMinor: 2500, stockQuantity: 10);
        final cart = await cartService.ensureActive(userId);
        await cartService.addProduct(
          cartId: cart.id,
          productId: id,
          quantity: 2,
        );
        final loaded = await cartService.load(cart.id, userId);
        await cartService.overridePrice(
          cartId: cart.id,
          lineId: loaded.lines.single.id,
          unitPrice: const Money(2000),
        );
        final receipt = await saleService.complete(
          cartId: cart.id,
          userId: userId,
        );
        final saleId = receipt.valueOrNull!.saleId;
        final items = await saleRepo.itemsOf(saleId);

        final result = await service.createReturn(
          saleId: saleId,
          userId: userId,
          lines: [ReturnLineRequest(saleItemId: items.single.id, quantity: 2)],
        );

        expect(result.valueOrNull!.total, const Money(4000));
      },
    );
  });

  group('doğrulama — docs/14 §4', () {
    test('BR-RET-003 — kalan miktardan fazlası REDDEDİLİR', () async {
      final id = await product(stockQuantity: 10);
      final sale = await sell({id: 2});

      final result = await service.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [
          ReturnLineRequest(saleItemId: sale.items.single.id, quantity: 3),
        ],
      );

      expect(result.failureOrNull, ReturnFailures.exceedsRemaining);
      expect(await stockOf(id), 8, reason: 'Hiçbir şey değişmez.');
    });

    test('aynı satır listede İKİ KEZ geçerse TOPLAMI kontrol edilir', () async {
      // Tek tek bakılsaydı 2 + 2 = 4 adet iade edilir ve satılan miktar
      // aşılırdı; şemadaki CHECK patlar, kullanıcı sebebini anlamazdı.
      final id = await product(stockQuantity: 10);
      final sale = await sell({id: 3});
      final itemId = sale.items.single.id;

      final result = await service.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [
          ReturnLineRequest(saleItemId: itemId, quantity: 2),
          ReturnLineRequest(saleItemId: itemId, quantity: 2),
        ],
      );

      expect(result.failureOrNull, ReturnFailures.exceedsRemaining);
    });

    test(
      'aynı satır iki kez geçse de TOPLAM sınırı aşmıyorsa birleşir',
      () async {
        final id = await product(stockQuantity: 10);
        final sale = await sell({id: 3});
        final itemId = sale.items.single.id;

        final result = await service.createReturn(
          saleId: sale.saleId,
          userId: userId,
          lines: [
            ReturnLineRequest(saleItemId: itemId, quantity: 1),
            ReturnLineRequest(saleItemId: itemId, quantity: 2),
          ],
        );

        expect(result.valueOrNull!.unitCount, 3);
        final returned = (await saleRepo.returnsOf(sale.saleId)).single;
        expect(
          await saleRepo.returnItemsOf(returned.id),
          hasLength(1),
          reason: 'Aynı satır için tek `return_items` kaydı oluşur.',
        );
        expect(
          (await saleRepo.itemsOf(sale.saleId)).single.returnedQuantity,
          3,
        );
      },
    );

    test('hiçbir şey seçilmezse REDDEDİLİR', () async {
      final sale = await sell({await product(): 2});

      for (final lines in [
        const <ReturnLineRequest>[],
        [ReturnLineRequest(saleItemId: sale.items.single.id, quantity: 0)],
      ]) {
        final result = await service.createReturn(
          saleId: sale.saleId,
          userId: userId,
          lines: lines,
        );
        expect(result.failureOrNull, ReturnFailures.nothingToReturn);
      }
    });

    test('başka satışın satırı REDDEDİLİR', () async {
      final first = await sell({await product(name: 'A'): 1});
      final second = await sell({await product(name: 'B'): 1});

      final result = await service.createReturn(
        saleId: first.saleId,
        userId: userId,
        lines: [
          ReturnLineRequest(saleItemId: second.items.single.id, quantity: 1),
        ],
      );

      expect(result.failureOrNull, ReturnFailures.lineNotInSale);
    });

    test('BR-RET-006 — İPTAL edilmiş satıştan iade YAPILAMAZ', () async {
      final id = await product(stockQuantity: 10);
      final sale = await sell({id: 2});
      await service.cancelSale(
        saleId: sale.saleId,
        userId: userId,
        reason: 'x',
      );
      final stockAfterCancel = await stockOf(id);

      final result = await service.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [
          ReturnLineRequest(saleItemId: sale.items.single.id, quantity: 1),
        ],
      );

      expect(result.failureOrNull, ReturnFailures.returnFromCancelled);
      expect(
        await stockOf(id),
        stockAfterCancel,
        reason: 'İptal zaten tüm stoğu geri eklemişti.',
      );
    });
  });

  group('stok defteri ve audit', () {
    test('iade hareketi İADEYE referans verir, satışa değil', () async {
      // Aynı satıştan birden fazla kısmi iade yapılabilir; hangi hareketin
      // hangi iadeye ait olduğu ayırt edilebilmelidir.
      final id = await product(stockQuantity: 10);
      final sale = await sell({id: 3});
      final itemId = sale.items.single.id;

      final first = await service.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [ReturnLineRequest(saleItemId: itemId, quantity: 1)],
      );
      final second = await service.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [ReturnLineRequest(saleItemId: itemId, quantity: 1)],
      );

      final movements = (await stockRepo.movementsOf(
        id,
      )).where((m) => m.type == StockMovementType.returnedToStock).toList();
      expect(movements, hasLength(2));
      expect(movements.map((m) => m.referenceId).toSet(), {
        first.valueOrNull!.returnId,
        second.valueOrNull!.returnId,
      });
      for (final movement in movements) {
        expect(movement.referenceType, StockReferenceType.returnOperation);
      }
    });

    test('aynı ürün iki satırdaysa `resulting_stock` ZİNCİRLENİR', () async {
      final id = await product(salePriceMinor: 2500, stockQuantity: 10);
      final cart = await cartService.ensureActive(userId);
      await cartService.addProduct(cartId: cart.id, productId: id, quantity: 2);
      await cartService.addProduct(
        cartId: cart.id,
        productId: id,
        quantity: 3,
        unitPrice: const Money(2000),
      );
      final receipt = await saleService.complete(
        cartId: cart.id,
        userId: userId,
      );
      final saleId = receipt.valueOrNull!.saleId;
      final items = await saleRepo.itemsOf(saleId);
      expect(items, hasLength(2));
      expect(await stockOf(id), 5);

      await service.cancelSale(saleId: saleId, userId: userId, reason: 'x');

      final cancellations =
          [...await stockRepo.movementsOf(id)]
              .where((m) => m.type == StockMovementType.saleCancellation)
              .toList()
            ..sort((a, b) => a.id.compareTo(b.id));
      expect(cancellations.map((m) => m.resultingStock), [7, 10]);
      expect(await stockOf(id), 10);
    });

    test('REQ-RET-012 — iade audit\'e SEBEPLE yazılır', () async {
      final sale = await sell({await product(): 2});

      await service.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [
          ReturnLineRequest(saleItemId: sale.items.single.id, quantity: 1),
        ],
        reason: 'Müşteri beğenmedi',
      );

      final log = (await logs()).firstWhere(
        (l) => l.action == AuditActions.saleReturned,
      );
      expect(log.entityId, sale.saleId);
      expect(log.metadata, contains('Müşteri beğenmedi'));
      expect(log.oldValue, contains('completed'));
      expect(log.newValue, contains('partiallyReturned'));
    });

    test('sebep verilmezse audit metadata\'sında sebep ALANI olmaz', () async {
      final sale = await sell({await product(): 2});

      await service.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [
          ReturnLineRequest(saleItemId: sale.items.single.id, quantity: 1),
        ],
      );

      final log = (await logs()).firstWhere(
        (l) => l.action == AuditActions.saleReturned,
      );
      expect(log.metadata, isNot(contains('"reason"')));
    });
  });

  group('REQ-RET-010 — atomiklik', () {
    test('iade sırasında hata → HİÇBİR kayıt oluşmaz', () async {
      final id = await product(stockQuantity: 10);
      final sale = await sell({id: 3});

      final failing = ReturnService(
        db: db,
        sales: _FailingSaleRepository(saleRepo),
        stockService: StockService(
          db: db,
          stock: stockRepo,
          products: DriftProductRepository(db),
          clock: () => now,
        ),
        clock: () => now,
      );

      await expectLater(
        failing.createReturn(
          saleId: sale.saleId,
          userId: userId,
          lines: [
            ReturnLineRequest(saleItemId: sale.items.single.id, quantity: 1),
          ],
        ),
        throwsA(isA<StateError>()),
      );

      expect(await db.select(db.returns).get(), isEmpty);
      expect(await db.select(db.returnItems).get(), isEmpty);
      expect((await saleRepo.itemsOf(sale.saleId)).single.returnedQuantity, 0);
      expect(await statusOf(sale.saleId), SaleStatus.completed);
      expect(await stockOf(id), 7, reason: 'Stok DEĞİŞMEZ.');
      expect(
        (await stockRepo.movementsOf(
          id,
        )).where((m) => m.type == StockMovementType.returnedToStock),
        isEmpty,
      );
    });
  });

  group('stateOf — ekran düğmeleri', () {
    test('tamamlanmış satış hem iptal hem iade edilebilir', () async {
      final sale = await sell({await product(): 2});

      final state = (await service.stateOf(sale.saleId)).valueOrNull!;

      expect(state.canCancel, isTrue);
      expect(state.canReturn, isTrue);
      expect(state.totalSold, 2);
      expect(state.totalReturned, 0);
    });

    test('kısmi iadeden sonra yalnızca iade edilebilir', () async {
      final sale = await sell({await product(): 3});
      await service.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [
          ReturnLineRequest(saleItemId: sale.items.single.id, quantity: 1),
        ],
      );

      final state = (await service.stateOf(sale.saleId)).valueOrNull!;

      expect(state.canCancel, isFalse);
      expect(state.canReturn, isTrue);
      expect(state.returnedTotal, const Money(2500));
    });

    test('iptalden sonra ikisi de KAPALI', () async {
      final sale = await sell({await product(): 2});
      await service.cancelSale(
        saleId: sale.saleId,
        userId: userId,
        reason: 'x',
      );

      final state = (await service.stateOf(sale.saleId)).valueOrNull!;

      expect(state.canCancel, isFalse);
      expect(state.canReturn, isFalse);
    });
  });
}

/// `insertReturnItem` ilk çağrıda patlar — atomiklik testi için.
class _FailingSaleRepository implements SaleRepository {
  final SaleRepository _inner;

  _FailingSaleRepository(this._inner);

  @override
  Future<int> insertReturnItem(int returnId, NewReturnItem item) =>
      throw StateError('iade satırı yazılamadı');

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

  @override
  Future<int> insertSale(NewSale sale) => _inner.insertSale(sale);

  @override
  Future<int> insertItem(int saleId, NewSaleItem item) =>
      _inner.insertItem(saleId, item);

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
  Future<int> incrementReturnedQuantity(int saleItemId, int by) =>
      _inner.incrementReturnedQuantity(saleItemId, by);

  @override
  Future<List<SaleReturn>> returnsOf(int saleId) => _inner.returnsOf(saleId);

  @override
  Future<List<SaleReturnItem>> returnItemsOf(int returnId) =>
      _inner.returnItemsOf(returnId);
}
