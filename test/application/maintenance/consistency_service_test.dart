/// Tutarlılık kontrolü — **docs/24 §3.3 · REQ-STOCK-012 · REQ-DATA-006/007 ·
/// REQ-DB-008**
///
/// | Test | Kural |
/// |---|---|
/// | Temiz veritabanında sapma yok | REQ-STOCK-012 |
/// | `stock_quantity` sapması bulunur | rules/03 §2 |
/// | **Otomatik düzeltme YAPILMAZ** | rules/03 §2 |
/// | Düzeltme `adjustment` hareketiyle olur | REQ-DATA-007 |
/// | Satış toplamı / sayaç sapmaları bulunur | docs/24 §3.3 |
/// | Eksik görsel dosyası bulunur | docs/24 §3.3 |
/// | Çalıştırma audit'e yazılır | docs/18 §3 |
/// ## Kapsanan uç durumlar (docs/26 · Faz 11 izlenebilirliği)
///
/// - **EC-STOCK-004** — `stock_quantity` defterle uyuşmuyor
///
library;

import 'dart:io';

import 'package:canteen/application/audit/audit_actions.dart';
import 'package:canteen/application/audit/audit_service.dart';
import 'package:canteen/application/maintenance/consistency_report.dart';
import 'package:canteen/application/maintenance/consistency_service.dart';
import 'package:canteen/application/stock/stock_service.dart';
import 'package:canteen/data/dao/consistency_dao.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, Category, Product, Sale, SaleItem, StockMovement, Supplier;
import 'package:canteen/data/repositories/drift_product_repository.dart';
import 'package:canteen/data/repositories/drift_stock_repository.dart';
import 'package:canteen/domain/enums/sale_status.dart';
import 'package:canteen/domain/enums/stock_movement_type.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late Directory imagesDir;
  late StockService stockService;
  late ConsistencyService service;
  late int userId;

  setUp(() async {
    db = memoryDatabase();
    imagesDir = Directory.systemTemp.createTempSync('canteen_images_');
    final audit = AuditService(
      auditLogs: AuditLogsDao(db),
      clock: () => testEpochUtc,
    );
    stockService = StockService(
      db: db,
      stock: DriftStockRepository(db),
      products: DriftProductRepository(db),
      audit: audit,
      clock: () => testEpochUtc,
    );
    service = ConsistencyService(
      dao: ConsistencyDao(db),
      stockService: stockService,
      audit: audit,
      imagesDirectory: imagesDir.path,
      clock: () => testEpochUtc,
    );
    userId = await insertTestUser(db);
  });

  tearDown(() async {
    await db.close();
    if (imagesDir.existsSync()) imagesDir.deleteSync(recursive: true);
  });

  Future<int> product({String name = 'Kola', int initialStock = 10}) async {
    final id = await insertTestProduct(db, name: name);
    if (initialStock != 0) {
      await stockService.recordInitialStock(
        productId: id,
        quantity: initialStock,
        userId: userId,
      );
    }
    return id;
  }

  /// Önbelleği defterin ARKASINDAN bozar — bozulma senaryosu.
  ///
  /// `StockService` dışından yazmak tam olarak rules/02 §4'ün yasakladığı
  /// şeydir; test bu yasağın ihlal edildiği durumu **tespit edebildiğimizi**
  /// doğrular.
  Future<void> corruptCache(int productId, int value) =>
      (db.update(db.products)..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(stockQuantity: Value(value)),
      );

  test('temiz veritabanında sapma bulunmaz', () async {
    await product(name: 'A');
    await product(name: 'B', initialStock: 0);

    final report = await service.run();

    expect(report.isClean, isTrue, reason: '${report.findings}');
    expect(report.productsChecked, 2);
  });

  group('stok sapması — rules/03 §2', () {
    test('önbellek defterden saparsa BULUNUR', () async {
      final id = await product(name: 'Kola');
      await corruptCache(id, 99);

      final report = await service.run();

      final finding = report.of(ConsistencyCheck.stockQuantity).single;
      expect(finding.entityId, id);
      expect(finding.label, 'Kola');
      expect(finding.expected, '10', reason: 'Defter otoritedir.');
      expect(finding.actual, '99');
      expect(finding.isRepairable, isTrue);
    });

    test('hiç hareketi olmayan ürünün önbelleği de denetlenir', () async {
      final id = await product(name: 'Boş', initialStock: 0);
      await corruptCache(id, 7);

      final report = await service.run();

      expect(report.of(ConsistencyCheck.stockQuantity), hasLength(1));
    });

    test('OTOMATİK DÜZELTME YAPILMAZ', () async {
      final id = await product();
      await corruptCache(id, 99);

      await service.run();

      final row = await (db.select(
        db.products,
      )..where((p) => p.id.equals(id))).getSingle();
      expect(
        row.stockQuantity,
        99,
        reason:
            'rules/03 §2: sapma otomatik düzeltilmez. Sessizce düzeltmek '
            'sapmanın SEBEBİNİ gizler.',
      );
    });

    test(
      'OD-026 — DEFTERE güvenilirse hareket yazılmaz, önbellek tazelenir',
      () async {
        final id = await product();
        await corruptCache(id, 99);
        final finding = (await service.run()).repairable.single;

        final result = await service.repairStockQuantity(
          finding: finding,
          userId: userId,
          reason: 'Tutarlılık kontrolü düzeltmesi',
        );

        expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
        final adjustments = (await DriftStockRepository(
          db,
        ).movementsOf(id)).where((m) => m.type == StockMovementType.adjustment);
        expect(
          adjustments,
          isEmpty,
          reason:
              'Defter zaten doğruysa ortada bir stok OLAYI yoktur; hareket '
              'yazmak denetim izine olmayan bir olay eklerdi.',
        );

        final after = await service.run();
        expect(
          after.of(ConsistencyCheck.stockQuantity),
          isEmpty,
          reason: 'Düzeltmeden sonra sapma KAPANMIŞ olmalıdır.',
        );
      },
    );

    test(
      'OD-026 — FİZİKSEL sayım farklıysa `adjustment` hareketi yazılır',
      () async {
        final id = await product();
        await corruptCache(id, 99);
        final finding = (await service.run()).repairable.single;

        // Kullanıcı rafı saymış: gerçekte 15 var.
        final result = await service.repairStockQuantity(
          finding: finding,
          userId: userId,
          reason: 'Fiziksel sayım',
          physicalQuantity: 15,
        );

        expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
        final adjustment = (await DriftStockRepository(db).movementsOf(
          id,
        )).firstWhere((m) => m.type == StockMovementType.adjustment);
        expect(
          adjustment.quantityDelta,
          5,
          reason: 'Delta DEFTERDEN hesaplanır: 15 − 10 = 5.',
        );
        expect(adjustment.resultingStock, 15);
        expect(adjustment.note, 'Fiziksel sayım');

        final after = await service.run();
        expect(after.of(ConsistencyCheck.stockQuantity), isEmpty);
      },
    );

    test('düzeltme audit\'e `consistencyRepair` kaynağıyla yazılır', () async {
      final id = await product();
      await corruptCache(id, 99);
      final finding = (await service.run()).repairable.single;

      await service.repairStockQuantity(
        finding: finding,
        userId: userId,
        reason: 'Sapma kapatıldı',
      );

      final log = (await AuditLogsDao(
        db,
      ).listRecent()).firstWhere((l) => l.action == AuditActions.stockAdjusted);
      expect(log.oldValue, contains('99'));
      expect(log.newValue, contains('10'));
      expect(log.metadata, contains('consistencyRepair'));
      expect(log.metadata, contains('"movement_written":false'));
    });

    test('düzeltilemeyen sapma için düzeltme REDDEDİLİR', () async {
      const finding = ConsistencyFinding(
        check: ConsistencyCheck.saleTotals,
        entityId: 1,
        expected: '100',
        actual: '200',
      );

      final result = await service.repairStockQuantity(
        finding: finding,
        userId: userId,
        reason: 'x',
      );

      expect(result.isErr, isTrue);
    });
  });

  group('satış sapmaları — docs/24 §3.3', () {
    Future<int> corruptSale({
      required int grandTotal,
      required int lineTotal,
      required int itemCount,
      required int unitCount,
    }) async {
      final productId = await product(name: 'Satılan');
      final saleId = await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              saleNumber: '2026-000001',
              status: SaleStatus.completed,
              subtotalMinor: grandTotal,
              vatTotalMinor: 0,
              grandTotalMinor: grandTotal,
              costTotalMinor: 0,
              itemCount: itemCount,
              unitCount: unitCount,
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
              productNameSnapshot: 'Satılan',
              quantity: 1,
              unitPriceMinor: lineTotal,
              originalUnitPriceMinor: lineTotal,
              purchasePriceSnapshotMinor: 0,
              vatRateSnapshotBp: 0,
              lineNetMinor: lineTotal,
              lineVatMinor: 0,
              lineTotalMinor: lineTotal,
            ),
          );
      return saleId;
    }

    test('`grand_total` satırlarla uyuşmazsa bulunur', () async {
      await corruptSale(
        grandTotal: 5000,
        lineTotal: 3000,
        itemCount: 1,
        unitCount: 1,
      );

      final report = await service.run();

      final finding = report.of(ConsistencyCheck.saleTotals).single;
      expect(finding.expected, '3000');
      expect(finding.actual, '5000');
      expect(
        finding.isRepairable,
        isFalse,
        reason: 'Bozulmuş satış toplamı defter mantığıyla kapatılamaz.',
      );
    });

    test('`item_count`/`unit_count` uyuşmazsa bulunur', () async {
      await corruptSale(
        grandTotal: 3000,
        lineTotal: 3000,
        itemCount: 5,
        unitCount: 9,
      );

      final report = await service.run();

      final finding = report.of(ConsistencyCheck.saleCounts).single;
      expect(finding.expected, '1 satır / 1 adet');
      expect(finding.actual, '5 satır / 9 adet');
    });
  });

  group('görsel dosyaları — docs/24 §3.3', () {
    test('eksik dosya bulunur, mevcut dosya bulunmaz', () async {
      final missing = await product(name: 'Görselsiz', initialStock: 0);
      final present = await product(name: 'Görselli', initialStock: 0);
      await (db.update(db.products)..where((p) => p.id.equals(missing))).write(
        const ProductsCompanion(imagePath: Value('images/yok.jpg')),
      );
      await (db.update(db.products)..where((p) => p.id.equals(present))).write(
        const ProductsCompanion(imagePath: Value('images/var.jpg')),
      );
      File(p.join(imagesDir.path, 'var.jpg')).writeAsStringSync('x');

      final report = await service.run();

      final findings = report.of(ConsistencyCheck.missingImage);
      expect(findings, hasLength(1));
      expect(findings.single.entityId, missing);
    });

    test('hızlı sürüm dosya sistemine DOKUNMAZ', () async {
      // docs/24 §3.3 — yedek alma öncesi otomatik çalışan sürüm hızlı olmalıdır.
      final id = await product(initialStock: 0);
      await (db.update(db.products)..where((p) => p.id.equals(id))).write(
        const ProductsCompanion(imagePath: Value('images/yok.jpg')),
      );

      final report = await service.run(quick: true);

      expect(report.of(ConsistencyCheck.missingImage), isEmpty);
    });
  });

  test('veritabanı bütünlüğü ve yabancı anahtarlar denetlenir', () async {
    await product();

    final report = await service.run();

    expect(report.of(ConsistencyCheck.foreignKeys), isEmpty);
    expect(report.of(ConsistencyCheck.databaseIntegrity), isEmpty);
  });

  test(
    'docs/18 §3 — çalıştırma `consistencyCheckRun` olarak yazılır',
    () async {
      final id = await product();
      await corruptCache(id, 99);

      await service.run();

      final log = (await AuditLogsDao(db).listRecent()).firstWhere(
        (l) => l.action == AuditActions.consistencyCheckRun,
      );
      expect(log.entityType, AuditEntities.system);
      expect(log.metadata, contains('"finding_count":1'));
    },
  );
}
