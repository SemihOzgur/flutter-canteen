/// Tutarlılık kontrolü ekranı — **docs/24 §3.3 · REQ-DATA-006/007 · OD-026**
///
/// | Test | Kural |
/// |---|---|
/// | Kontrol **otomatik düzeltmez** | rules/03 §2 |
/// | Düzeltme kullanıcının onayladığı miktarla yapılır | OD-026 |
/// | `Esc` düzeltmez | REQ-DATA-007 |
/// | Düzeltilemeyen sapmada düğme SUNULMAZ | docs/24 §3.3 |
library;

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/application/product/product_draft.dart';
import 'package:canteen/application/product/product_service.dart';
import 'package:canteen/application/product/providers.dart';
import 'package:canteen/application/stock/providers.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, Category, Product, Sale, SaleItem, StockMovement, Supplier;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/domain/enums/sale_status.dart';
import 'package:canteen/domain/enums/stock_movement_type.dart';
import 'package:canteen/domain/models/stock_movement.dart';
import 'package:canteen/presentation/maintenance/consistency_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late int userId;
  late int productId;

  setUp(() async {
    db = memoryDatabase();
    userId = await insertTestUser(db);
    final container = ProviderContainer(
      overrides: [canteenDatabaseProvider.overrideWithValue(db)],
    );
    await container.read(sessionServiceProvider).save(userId);
    final created = await container
        .read(productServiceProvider)
        .create(
          const ProductDraft(name: 'Kola', salePrice: Money(2500)),
          userId: userId,
          initialStock: 10,
        );
    productId = (created as Ok<ProductSaveOutcome>).value.productId;
    container.dispose();
  });

  tearDown(() => db.close());

  /// Önbelleği defterin arkasından bozar — bozulma senaryosu.
  Future<void> corruptCache(int value) =>
      (db.update(db.products)..where((p) => p.id.equals(productId))).write(
        ProductsCompanion(stockQuantity: Value(value)),
      );

  Future<int> cachedStock() async => (await (db.select(
    db.products,
  )..where((p) => p.id.equals(productId))).getSingle()).stockQuantity;

  Future<List<StockMovement>> movements() async {
    final container = ProviderContainer(
      overrides: [canteenDatabaseProvider.overrideWithValue(db)],
    );
    try {
      return await container.read(stockServiceProvider).movements(limit: 100);
    } finally {
      container.dispose();
    }
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [canteenDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: ConsistencyScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> run(WidgetTester tester) async {
    await tester.tap(find.byKey(ConsistencyScreen.runButtonKey));
    await tester.pumpAndSettle();
  }

  testWidgets('temiz veritabanında sapma bulunmaz', (tester) async {
    await pump(tester);

    await run(tester);

    expect(find.text(AppStringsTr.consistencyClean), findsOneWidget);
  });

  testWidgets('rules/03 §2 — kontrol OTOMATİK DÜZELTMEZ', (tester) async {
    await corruptCache(99);
    await pump(tester);

    await run(tester);

    expect(
      await cachedStock(),
      99,
      reason: 'Kontrol yalnızca RAPORLAR; sessizce düzeltmek sebebi gizler.',
    );
    expect(find.text(AppStringsTr.consistencyRepair), findsOneWidget);
  });

  testWidgets('OD-026 — defter değeriyle düzeltme hareket YAZMAZ', (
    tester,
  ) async {
    await corruptCache(99);
    await pump(tester);
    await run(tester);

    await tester.tap(find.byKey(Key('consistency_repair_$productId')));
    await tester.pumpAndSettle();
    // Dialog defterin değeriyle DOLU gelir — defter otoritedir.
    expect(
      tester
          .widget<TextField>(
            find.byKey(const Key('consistency_repair_quantity')),
          )
          .controller!
          .text,
      '10',
    );
    await tester.tap(find.byKey(const Key('consistency_repair_submit')));
    await tester.pumpAndSettle();

    expect(await cachedStock(), 10);
    expect(
      (await movements()).where((m) => m.type == StockMovementType.adjustment),
      isEmpty,
      reason: 'Defter zaten doğruysa ortada bir stok OLAYI yoktur.',
    );
    expect(find.text(AppStringsTr.consistencyClean), findsOneWidget);
  });

  testWidgets('OD-026 — FİZİKSEL sayımla düzeltme hareket YAZAR', (
    tester,
  ) async {
    await corruptCache(99);
    await pump(tester);
    await run(tester);

    await tester.tap(find.byKey(Key('consistency_repair_$productId')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('consistency_repair_quantity')),
      '15',
    );
    await tester.tap(find.byKey(const Key('consistency_repair_submit')));
    await tester.pumpAndSettle();

    expect(await cachedStock(), 15);
    final adjustment = (await movements()).firstWhere(
      (m) => m.type == StockMovementType.adjustment,
    );
    expect(adjustment.quantityDelta, 5, reason: 'Delta DEFTERDEN: 15 − 10.');
  });

  testWidgets('Esc düzeltmez — ayrı kod yolu', (tester) async {
    await corruptCache(99);
    await pump(tester);
    await run(tester);

    await tester.tap(find.byKey(Key('consistency_repair_$productId')));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(await cachedStock(), 99);
  });

  testWidgets('düzeltilemeyen sapmada düğme SUNULMAZ', (tester) async {
    // Bozuk satış toplamı defter mantığıyla kapatılamaz.
    await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            saleNumber: '2026-000001',
            status: SaleStatus.completed,
            subtotalMinor: 5000,
            vatTotalMinor: 0,
            grandTotalMinor: 5000,
            costTotalMinor: 0,
            itemCount: 0,
            unitCount: 0,
            userId: userId,
            completedAt: testEpochUtc,
            createdAt: testEpochUtc,
            updatedAt: testEpochUtc,
          ),
        );
    await pump(tester);

    await run(tester);

    expect(find.text(AppStringsTr.consistencyNotRepairable), findsWidgets);
    expect(find.text(AppStringsTr.consistencyRepair), findsNothing);
  });
}
