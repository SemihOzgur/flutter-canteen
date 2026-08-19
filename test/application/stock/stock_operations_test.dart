/// Faz 6 stok işlemleri — **docs/13 §5–§6 · REQ-STOCK-003/007/008/009 ·
/// BR-STOCK-009/010 · OD-025**
///
/// | Test | Kural |
/// |---|---|
/// | Giriş tek transaction — 10. satırda hata → hiçbir şey oluşmaz | REQ-STOCK-007 |
/// | Alış fiyatı yalnızca ONAYLANIRSA güncellenir | BR-STOCK-009 · REQ-STOCK-008 |
/// | Fire ve düzeltmede **sebep zorunlu** | BR-STOCK-010 |
/// | Fire birim maliyeti saklar | OD-025 |
/// | Hareket silinmez — **ters kayıt** açılır | REQ-STOCK-003 |
/// | `stock_quantity == Σ quantity_delta` | BR-STOCK-002/003 |
library;

import 'dart:math';

import 'package:canteen/application/audit/audit_actions.dart';
import 'package:canteen/application/audit/audit_service.dart';
import 'package:canteen/application/stock/stock_failures.dart';
import 'package:canteen/application/stock/stock_service.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, Category, Product, Sale, SaleItem, StockMovement, Supplier;
import 'package:canteen/data/repositories/drift_product_repository.dart';
import 'package:canteen/data/repositories/drift_stock_repository.dart';
import 'package:canteen/domain/enums/stock_movement_type.dart';
import 'package:canteen/domain/repositories/stock_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late StockRepository stock;
  late StockService service;
  late int userId;

  setUp(() async {
    db = memoryDatabase();
    stock = DriftStockRepository(db);
    service = StockService(
      db: db,
      stock: stock,
      products: DriftProductRepository(db),
      audit: AuditService(
        auditLogs: AuditLogsDao(db),
        clock: () => testEpochUtc,
      ),
      clock: () => testEpochUtc,
    );
    userId = await insertTestUser(db);
  });

  tearDown(() => db.close());

  Future<int> product({
    String name = 'Kola',
    int purchasePriceMinor = 1800,
    int stockQuantity = 0,
  }) async {
    final id = await insertTestProduct(
      db,
      name: name,
      purchasePriceMinor: purchasePriceMinor,
    );
    if (stockQuantity != 0) {
      await service.recordInitialStock(
        productId: id,
        quantity: stockQuantity,
        userId: userId,
      );
    }
    return id;
  }

  Future<int> cachedStock(int id) async => (await (db.select(
    db.products,
  )..where((p) => p.id.equals(id))).getSingle()).stockQuantity;

  Future<void> expectLedgerConsistent(int id) async {
    expect(
      await cachedStock(id),
      await stock.sumQuantityDelta(id),
      reason: 'BR-STOCK-002/003 — önbellek defterle aynı olmalıdır.',
    );
  }

  Future<List<AuditLog>> logs() => AuditLogsDao(db).listRecent();

  // -------------------------------------------------------------------------
  // Stok girişi — docs/13 §5
  // -------------------------------------------------------------------------

  group('stok girişi — REQ-STOCK-007/008', () {
    test('satırlar deftere `stockEntry` olarak yazılır', () async {
      final a = await product(name: 'Kola', stockQuantity: 98);
      final b = await product(name: 'Su', stockQuantity: 150);
      final supplierId = await SuppliersDao(
        db,
      ).insertSupplier(name: 'Kola A.Ş.', now: testEpochUtc);

      final result = await service.recordEntry(
        userId: userId,
        supplierId: supplierId,
        documentNumber: 'IRS-4412',
        lines: [
          StockEntryLine(
            productId: a,
            quantity: 24,
            unitCost: const Money(1800),
          ),
          StockEntryLine(
            productId: b,
            quantity: 48,
            unitCost: const Money(650),
          ),
        ],
      );

      expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
      final receipt = result.valueOrNull!;
      expect(receipt.lineCount, 2);
      expect(receipt.unitCount, 72);
      // docs/13 §5 örneği: 24×₺18,00 + 48×₺6,50 = ₺744,00
      expect(receipt.total, const Money(74400));

      expect(await cachedStock(a), 98 + 24);
      expect(await cachedStock(b), 150 + 48);
      await expectLedgerConsistent(a);
      await expectLedgerConsistent(b);

      final movements = await stock.movementsOf(a);
      final entry = movements.firstWhere(
        (m) => m.type == StockMovementType.stockEntry,
      );
      expect(entry.quantityDelta, 24);
      expect(entry.resultingStock, 122);
      expect(entry.unitCost, const Money(1800));
      expect(entry.supplierId, supplierId);
      expect(entry.note, 'IRS-4412');
    });

    test('unitCost verilmezse ürünün mevcut alış fiyatı kullanılır', () async {
      final id = await product(purchasePriceMinor: 1800);

      await service.recordEntry(
        userId: userId,
        lines: [StockEntryLine(productId: id, quantity: 10)],
      );

      final movement = (await stock.movementsOf(id)).single;
      expect(movement.unitCost, const Money(1800));
    });

    test(
      'BR-STOCK-009 — alış fiyatı yalnızca ONAYLANIRSA güncellenir',
      () async {
        final id = await product(purchasePriceMinor: 1800);

        await service.recordEntry(
          userId: userId,
          lines: [
            StockEntryLine(
              productId: id,
              quantity: 10,
              unitCost: const Money(2000),
            ),
          ],
        );

        final row = await (db.select(
          db.products,
        )..where((p) => p.id.equals(id))).getSingle();
        expect(
          row.purchasePriceMinor,
          1800,
          reason: 'Onay verilmediyse ürünün fiyatına DOKUNULMAZ.',
        );
      },
    );

    test(
      'REQ-STOCK-008 — onay verilirse güncellenir ve audit\'e yazılır',
      () async {
        final id = await product(purchasePriceMinor: 1800);

        await service.recordEntry(
          userId: userId,
          lines: [
            StockEntryLine(
              productId: id,
              quantity: 10,
              unitCost: const Money(2000),
              updateProductPurchasePrice: true,
            ),
          ],
        );

        final row = await (db.select(
          db.products,
        )..where((p) => p.id.equals(id))).getSingle();
        expect(row.purchasePriceMinor, 2000);

        final log = (await logs()).firstWhere(
          (l) => l.action == AuditActions.productCostChanged,
        );
        expect(log.oldValue, contains('1800'));
        expect(log.newValue, contains('2000'));
        // docs/18 §3 — `productCostChanged` metadata'sı KAYNAĞI taşır.
        expect(log.metadata, contains('stockEntry'));
      },
    );

    test(
      'REQ-STOCK-007 — satırlardan biri hatalıysa HİÇBİRİ yazılmaz',
      () async {
        final ok1 = await product(name: 'A', stockQuantity: 10);
        final ok2 = await product(name: 'B', stockQuantity: 10);

        final result = await service.recordEntry(
          userId: userId,
          lines: [
            StockEntryLine(productId: ok1, quantity: 5),
            StockEntryLine(productId: ok2, quantity: 5),
            // Var olmayan ürün — 3. satırda hata.
            const StockEntryLine(productId: 999999, quantity: 5),
          ],
        );

        expect(result.failureOrNull, StockFailures.productNotFound);
        expect(await cachedStock(ok1), 10, reason: 'Hiçbir stok DEĞİŞMEZ.');
        expect(await cachedStock(ok2), 10);
        final entries = (await stock.movementsOf(
          ok1,
        )).where((m) => m.type == StockMovementType.stockEntry);
        expect(entries, isEmpty, reason: 'Hiçbir hareket oluşmaz.');
      },
    );

    test('aynı ürün iki satırda: `resulting_stock` ZİNCİRLENİR', () async {
      final id = await product(stockQuantity: 10);

      await service.recordEntry(
        userId: userId,
        lines: [
          StockEntryLine(productId: id, quantity: 5),
          StockEntryLine(productId: id, quantity: 7),
        ],
      );

      final entries =
          [
              ...await stock.movementsOf(id),
            ].where((m) => m.type == StockMovementType.stockEntry).toList()
            ..sort((a, b) => a.id.compareTo(b.id));
      expect(entries.map((m) => m.resultingStock), [15, 22]);
      expect(await cachedStock(id), 22);
    });

    test('boş giriş ve geçersiz miktar reddedilir', () async {
      expect(
        (await service.recordEntry(
          userId: userId,
          lines: const [],
        )).failureOrNull,
        StockFailures.emptyEntry,
      );
      final id = await product();
      expect(
        (await service.recordEntry(
          userId: userId,
          lines: [StockEntryLine(productId: id, quantity: 0)],
        )).failureOrNull,
        StockFailures.entryQuantityInvalid,
      );
    });

    test(
      'audit: `stockEntryCreated` tedarikçi, satır ve tutar taşır',
      () async {
        final id = await product();
        final supplierId = await SuppliersDao(
          db,
        ).insertSupplier(name: 'Tedarikçi', now: testEpochUtc);

        await service.recordEntry(
          userId: userId,
          supplierId: supplierId,
          lines: [
            StockEntryLine(
              productId: id,
              quantity: 3,
              unitCost: const Money(1000),
            ),
          ],
        );

        final log = (await logs()).firstWhere(
          (l) => l.action == AuditActions.stockEntryCreated,
        );
        expect(log.metadata, contains('"supplier_id":$supplierId'));
        expect(log.metadata, contains('"line_count":1'));
        expect(log.metadata, contains('"total_minor":3000'));
      },
    );
  });

  // -------------------------------------------------------------------------
  // Fire — docs/13 §6
  // -------------------------------------------------------------------------

  group('fire — REQ-STOCK-009 · BR-STOCK-010', () {
    test('negatif hareket yazar ve sebebi saklar', () async {
      final id = await product(stockQuantity: 20, purchasePriceMinor: 1800);

      final result = await service.recordWaste(
        productId: id,
        quantity: 3,
        reason: 'Bozulma',
        userId: userId,
      );

      expect((result as Ok<int>).value, 17);
      final waste = (await stock.movementsOf(
        id,
      )).firstWhere((m) => m.type == StockMovementType.waste);
      expect(waste.quantityDelta, -3);
      expect(waste.resultingStock, 17);
      expect(waste.note, 'Bozulma');
      await expectLedgerConsistent(id);
    });

    test(
      'OD-025 — birim maliyet SAKLANIR (fire kâr raporunda giderdir)',
      () async {
        final id = await product(stockQuantity: 20, purchasePriceMinor: 1800);

        await service.recordWaste(
          productId: id,
          quantity: 3,
          reason: 'Kırılma',
          userId: userId,
        );

        final waste = (await stock.movementsOf(
          id,
        )).firstWhere((m) => m.type == StockMovementType.waste);
        expect(
          waste.unitCost,
          const Money(1800),
          reason:
              'Maliyet olay anında bilinir ve sonradan türetilemez; rapor '
              'anında güncel fiyattan hesaplamak kapanmış ayın kârını '
              'oynatırdı (rules/02 §3).',
        );
      },
    );

    test('SEBEP ZORUNLUDUR — boş ve yalnızca boşluk reddedilir', () async {
      final id = await product(stockQuantity: 20);

      for (final reason in ['', '   ', '\n']) {
        final result = await service.recordWaste(
          productId: id,
          quantity: 1,
          reason: reason,
          userId: userId,
        );
        expect(result.failureOrNull, StockFailures.reasonRequired);
      }
      expect(await cachedStock(id), 20);
    });

    test('miktar pozitif olmalıdır', () async {
      final id = await product(stockQuantity: 20);

      expect(
        (await service.recordWaste(
          productId: id,
          quantity: 0,
          reason: 'x',
          userId: userId,
        )).failureOrNull,
        StockFailures.wasteMustBePositive,
      );
    });

    test(
      'stok yetersizse fire yine yazılır — stok negatife düşebilir',
      () async {
        // Fire fiziksel bir gerçektir; sistemdeki stok yanlış olabilir
        // (BR-STOCK-006 ile aynı gerekçe).
        final id = await product(stockQuantity: 1);

        await service.recordWaste(
          productId: id,
          quantity: 5,
          reason: 'Bozulma',
          userId: userId,
        );

        expect(await cachedStock(id), -4);
        await expectLedgerConsistent(id);
      },
    );

    test('audit: `stockWasteRecorded` ürün, miktar ve SEBEP taşır', () async {
      final id = await product(stockQuantity: 20);

      await service.recordWaste(
        productId: id,
        quantity: 2,
        reason: 'Son kullanma',
        userId: userId,
      );

      final log = (await logs()).firstWhere(
        (l) => l.action == AuditActions.stockWasteRecorded,
      );
      expect(log.entityId, id);
      expect(log.metadata, contains('Son kullanma'));
      expect(log.metadata, contains('"quantity":2'));
    });
  });

  // -------------------------------------------------------------------------
  // Düzeltme — docs/13 §6
  // -------------------------------------------------------------------------

  group('düzeltme — REQ-DATA-007', () {
    test('hedef stok verilir, DELTA hesaplanır', () async {
      final id = await product(stockQuantity: 20);

      final result = await service.recordAdjustment(
        productId: id,
        newQuantity: 17,
        reason: 'Sayım',
        userId: userId,
      );

      expect((result as Ok<int>).value, 17);
      final adjustment = (await stock.movementsOf(
        id,
      )).firstWhere((m) => m.type == StockMovementType.adjustment);
      expect(adjustment.quantityDelta, -3);
      expect(adjustment.resultingStock, 17);
      await expectLedgerConsistent(id);
    });

    test('pozitif yön de desteklenir', () async {
      final id = await product(stockQuantity: 20);

      await service.recordAdjustment(
        productId: id,
        newQuantity: 25,
        reason: 'Kayıtsız giriş bulundu',
        userId: userId,
      );

      final adjustment = (await stock.movementsOf(
        id,
      )).firstWhere((m) => m.type == StockMovementType.adjustment);
      expect(adjustment.quantityDelta, 5);
    });

    test('BR-STOCK-004 — değişiklik yoksa hareket YAZILMAZ', () async {
      final id = await product(stockQuantity: 20);

      final result = await service.recordAdjustment(
        productId: id,
        newQuantity: 20,
        reason: 'Sayım',
        userId: userId,
      );

      expect(result.failureOrNull, StockFailures.adjustmentNoChange);
      final adjustments = (await stock.movementsOf(
        id,
      )).where((m) => m.type == StockMovementType.adjustment);
      expect(adjustments, isEmpty, reason: '`quantity_delta` 0 olamaz.');
    });

    test('SEBEP ZORUNLUDUR', () async {
      final id = await product(stockQuantity: 20);

      final result = await service.recordAdjustment(
        productId: id,
        newQuantity: 5,
        reason: '  ',
        userId: userId,
      );

      expect(result.failureOrNull, StockFailures.reasonRequired);
      expect(await cachedStock(id), 20);
    });

    test('audit: `stockAdjusted` eski/yeni stok ve SEBEP taşır', () async {
      final id = await product(stockQuantity: 20);

      await service.recordAdjustment(
        productId: id,
        newQuantity: 12,
        reason: 'Fiziksel sayım',
        userId: userId,
      );

      final log = (await logs()).firstWhere(
        (l) => l.action == AuditActions.stockAdjusted,
      );
      expect(log.oldValue, contains('20'));
      expect(log.newValue, contains('12'));
      expect(log.metadata, contains('Fiziksel sayım'));
    });
  });

  // -------------------------------------------------------------------------
  // Ters kayıt — REQ-STOCK-003 acceptance criteria
  // -------------------------------------------------------------------------

  group('REQ-STOCK-003 — hareket silinmez, TERS KAYIT açılır', () {
    test('docs/13 §10 acceptance criteria birebir', () async {
      final id = await product(stockQuantity: 10);
      // "Kullanıcı 200 adetlik bir stok girişini yanlışlıkla yapmış."
      await service.recordEntry(
        userId: userId,
        lines: [StockEntryLine(productId: id, quantity: 200)],
      );
      expect(await cachedStock(id), 210);

      final wrong = (await stock.movementsOf(
        id,
      )).firstWhere((m) => m.type == StockMovementType.stockEntry);

      final result = await service.reverseMovement(
        movementId: wrong.id,
        reason: 'Yanlış girildi',
        userId: userId,
      );

      expect((result as Ok<int>).value, 10);
      // "Orijinal hareket olduğu gibi durur."
      final original = await stock.findById(wrong.id);
      expect(original.isOk, isTrue);
      expect(original.valueOrNull!.quantityDelta, 200);
      // "Yeni bir adjustment hareketi eklenir."
      final adjustment = (await stock.movementsOf(
        id,
      )).firstWhere((m) => m.type == StockMovementType.adjustment);
      expect(adjustment.quantityDelta, -200);
      await expectLedgerConsistent(id);
    });

    test('sebep zorunludur, olmayan hareket reddedilir', () async {
      final id = await product(stockQuantity: 10);
      final movement = (await stock.movementsOf(id)).single;

      expect(
        (await service.reverseMovement(
          movementId: movement.id,
          reason: '',
          userId: userId,
        )).failureOrNull,
        StockFailures.reasonRequired,
      );
      expect(
        (await service.reverseMovement(
          movementId: 999999,
          reason: 'x',
          userId: userId,
        )).failureOrNull,
        StockFailures.movementNotFound,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Property test — rules/06 §2 · docs/31 Faz 6 çıkış kriteri
  // -------------------------------------------------------------------------

  test(
    'BR-STOCK-002/003 property — 1.000 rastgele hareket sonrası defter tutar',
    () async {
      // rules/06 §2 bu testi ADIYLA şart koşar:
      //   "Stock consistency | stock_quantity == Σ quantity_delta
      //    (property test, 1.000 rastgele hareket)"
      //
      // Tohum sabittir (rules/06 §7 — determinizm): başarısızlık tekrar
      // üretilebilir olmalıdır.
      final random = Random(20260819);
      final id = await product(stockQuantity: 500);

      var applied = 0;
      for (var i = 0; i < 1000; i++) {
        final current = await cachedStock(id);
        switch (random.nextInt(4)) {
          case 0:
            final r = await service.recordEntry(
              userId: userId,
              lines: [
                StockEntryLine(productId: id, quantity: 1 + random.nextInt(20)),
              ],
            );
            if (r.isOk) applied++;
          case 1:
            final r = await service.recordWaste(
              productId: id,
              quantity: 1 + random.nextInt(5),
              reason: 'rastgele fire $i',
              userId: userId,
            );
            if (r.isOk) applied++;
          case 2:
            // Hedef mevcut stoktan farklı olmalı, yoksa reddedilir.
            final target =
                current +
                (random.nextBool() ? 1 : -1) * (1 + random.nextInt(30));
            final r = await service.recordAdjustment(
              productId: id,
              newQuantity: target,
              reason: 'rastgele sayım $i',
              userId: userId,
            );
            if (r.isOk) applied++;
          case 3:
            final r = await service.recordSale(
              productId: id,
              quantity: 1 + random.nextInt(3),
              saleId: 1,
              userId: userId,
              nowUtc: testEpochUtc,
            );
            if (r.isOk) applied++;
        }

        // Invariant HER adımda korunur — yalnızca sonda değil. Sonda kontrol
        // etmek, arada bozulup kendi kendine düzelen bir hatayı kaçırırdı.
        expect(
          await cachedStock(id),
          await stock.sumQuantityDelta(id),
          reason: 'Adım $i sonrası defter ile önbellek ayrıştı.',
        );
      }

      expect(applied, greaterThan(900), reason: 'Hareketlerin çoğu uygulandı.');
      // BR-STOCK-005 — hiçbir hareket silinmemiştir.
      final movements = await stock.movementsOf(id, limit: 2000);
      expect(movements.length, applied + 1, reason: '+1 = `initial`');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
