/// Dashboard ekranı — **docs/15 · BR-AUTH-012/013 · REQ-VAT-009**
///
/// | Test | Kural |
/// |---|---|
/// | Kilit kapalıyken **hiçbir rakam** görünmez | BR-AUTH-012 |
/// | Kilit kapalıyken **hiçbir sorgu** çalışmaz | BR-AUTH-012 |
/// | Kilit açılınca KPI'lar dolar | docs/15 §3.1 |
/// | Kritik/negatif kartlar "şu an" etiketli | docs/15 §3.1 |
/// | Saatlik yoğunluk yalnızca ≥ 2 günde | docs/15 §3.3 |
/// | Kâr KDV **hariç** matrahtan | REQ-VAT-009 |
/// | Brüt/iptal/iade ayrı bölümde | docs/15 §5 |
///
/// ## Kapsanan requirement'lar (Faz 11 izlenebilirliği)
///
/// - **REQ-DASH-002** — aralık değişince yeniden hesaplanır
/// - **REQ-DASH-004** — stok kartları anlık
/// - **REQ-DASH-012** — parola doğrulanmadan veri sorgulanmaz/görünmez
/// - **REQ-DASH-013** — kâr KDV hariç, ciro KDV dahil; ayrım ekranda
library;

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/application/auth/financial_access_service.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/application/product/product_draft.dart';
import 'package:canteen/application/product/product_service.dart';
import 'package:canteen/application/product/providers.dart';
import 'package:canteen/application/sales/providers.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/money/money_formatter.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, CartItem, Category, Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/domain/models/sale_return.dart';
import 'package:canteen/presentation/dashboard/dashboard_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late ProviderContainer container;
  late int userId;

  const dashboardPassword = 'DASH-PW-TEST-5R9';

  setUp(() async {
    db = memoryDatabase();
    userId = await insertTestUser(db);
    container = ProviderContainer(
      overrides: [canteenDatabaseProvider.overrideWithValue(db)],
    );
    await container.read(sessionServiceProvider).save(userId);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  FinancialAccessService access() => container.read(financialAccessProvider);

  Future<void> unlock() async {
    await access().setPassword(dashboardPassword);
    final opened = await access().unlock(dashboardPassword);
    expect(opened.isErr, isFalse, reason: '${opened.failureOrNull}');
  }

  Future<int> createProduct({
    String name = 'Kola',
    int salePriceMinor = 12000,
    int purchasePriceMinor = 6000,
    int initialStock = 100,
    int minimumStock = 0,
  }) async {
    final result = await container
        .read(productServiceProvider)
        .create(
          ProductDraft(
            name: name,
            salePrice: Money(salePriceMinor),
            purchasePrice: Money(purchasePriceMinor),
            minimumStock: minimumStock,
          ),
          userId: userId,
          initialStock: initialStock,
        );
    return (result as Ok<ProductSaveOutcome>).value.productId;
  }

  Future<void> sell(int productId, {int quantity = 1}) async {
    final cart = await container.read(cartServiceProvider).ensureActive(userId);
    await container
        .read(cartServiceProvider)
        .addProduct(cartId: cart.id, productId: productId, quantity: quantity);
    final receipt = await container
        .read(saleServiceProvider)
        .complete(cartId: cart.id, userId: userId);
    expect(receipt.isErr, isFalse, reason: '${receipt.failureOrNull}');
  }

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: DashboardScreen(clock: () => testEpochUtc)),
      ),
    );
    await tester.pumpAndSettle();
  }

  Text kpiValue(WidgetTester tester, Key key) => tester.widget<Text>(
    find.descendant(of: find.byKey(key), matching: find.byType(Text)).at(1),
  );

  // -------------------------------------------------------------------------
  // BR-AUTH-012 — kilit
  // -------------------------------------------------------------------------

  group('BR-AUTH-012 — kilit kapalıyken', () {
    testWidgets('HİÇBİR rakam görünmez', (tester) async {
      final id = await createProduct(salePriceMinor: 12000);
      await sell(id, quantity: 3);

      await pump(tester);

      expect(find.byKey(DashboardScreen.lockedKey), findsOneWidget);
      expect(find.byKey(DashboardScreen.netRevenueKey), findsNothing);
      expect(
        find.text(MoneyFormatter.format(const Money(36000))),
        findsNothing,
        reason:
            'Kilit görsel bir perde DEĞİLDİR; rakam bulanık dahi olsa '
            'oluşmamalıdır (docs/15 §0).',
      );
    });

    testWidgets('kilit SONRADAN kapanınca ekrandaki veri KAYBOLUR', (
      tester,
    ) async {
      // En tehlikeli senaryo: kullanıcı dashboard'u açık bırakıp çıkış
      // yapıyor (logout kilidi kapatır — BR-AUTH-016). Eski veri ekranda
      // kalırsa sıradaki kullanıcı parolasız ciro görür.
      final id = await createProduct(salePriceMinor: 12000);
      await sell(id, quantity: 3);
      await unlock();
      await pump(tester);
      expect(find.byKey(DashboardScreen.netRevenueKey), findsOneWidget);

      access().lock();
      await tester.tap(find.byKey(const Key('dashboard_period_last7Days')));
      await tester.pumpAndSettle();

      expect(find.byKey(DashboardScreen.lockedKey), findsOneWidget);
      expect(
        find.byKey(DashboardScreen.netRevenueKey),
        findsNothing,
        reason: 'Kilitlenince önceki verinin ekranda KALMASI kabul edilemez.',
      );
      expect(
        find.text(MoneyFormatter.format(const Money(36000))),
        findsNothing,
      );
    });

    testWidgets('dönem değiştirmek de rakam ÜRETMEZ', (tester) async {
      await createProduct();
      await pump(tester);

      await tester.tap(find.byKey(const Key('dashboard_period_last30Days')));
      await tester.pumpAndSettle();

      expect(find.byKey(DashboardScreen.lockedKey), findsOneWidget);
      expect(find.byKey(DashboardScreen.netProfitKey), findsNothing);
    });
  });

  group('kilit AÇIKKEN — docs/15 §3', () {
    testWidgets('KPI kartları dolar', (tester) async {
      final id = await createProduct(
        salePriceMinor: 12000,
        purchasePriceMinor: 6000,
      );
      await sell(id, quantity: 3);
      await unlock();

      await pump(tester);

      expect(find.byKey(DashboardScreen.lockedKey), findsNothing);
      expect(
        kpiValue(tester, DashboardScreen.netRevenueKey).data,
        MoneyFormatter.format(const Money(36000)),
      );
    });

    testWidgets('REQ-VAT-009 — kâr KDV HARİÇ matrahtan', (tester) async {
      final rate = await VatRatesDao(db).insertVatRate(
        name: 'oran',
        rateBasisPoints: 2000,
        isDefault: false,
        now: testEpochUtc,
      );
      final id = await createProduct(
        salePriceMinor: 12000,
        purchasePriceMinor: 6000,
      );
      await (db.update(db.products)..where((p) => p.id.equals(id))).write(
        ProductsCompanion(vatRateId: Value(rate)),
      );
      await sell(id);
      await unlock();

      await pump(tester);

      expect(
        kpiValue(tester, DashboardScreen.netProfitKey).data,
        MoneyFormatter.format(const Money(4000)),
        reason:
            'Brüt cirodan hesaplansaydı ₺60,00 çıkardı — KDV işletmenin '
            'geliri değildir (BR-VAT-003).',
      );
    });

    testWidgets('BR-RET-007 — KPI NET ciroyu gösterir, brütü değil', (
      tester,
    ) async {
      // İade olmadan net ile brüt AYNIDIR; fark ancak iade/iptal varken
      // görünür. Testin o durumu kurması gerekir.
      final id = await createProduct(salePriceMinor: 12000);
      await sell(id, quantity: 3);
      final sale =
          (await container.read(saleServiceProvider).history(limit: 1)).single;
      final items = await container.read(saleServiceProvider).itemsOf(sale.id);
      await container
          .read(returnServiceProvider)
          .createReturn(
            saleId: sale.id,
            userId: userId,
            lines: [
              ReturnLineRequest(saleItemId: items.single.id, quantity: 1),
            ],
          );
      await unlock();

      await pump(tester);

      expect(
        kpiValue(tester, DashboardScreen.netRevenueKey).data,
        MoneyFormatter.format(const Money(24000)),
        reason: 'Brüt ₺360,00, iade ₺120,00 → NET ₺240,00 (BR-RET-007).',
      );
      // Brüt yine de ayrıntı bölümünde görünür (docs/15 §5).
      expect(
        find.text(MoneyFormatter.format(const Money(36000))),
        findsWidgets,
      );
    });

    testWidgets('docs/15 §3.1 — kritik/negatif kartlar "şu an" etiketli', (
      tester,
    ) async {
      await createProduct(name: 'Kritik', initialStock: 2, minimumStock: 5);
      await unlock();

      await pump(tester);

      expect(find.byKey(DashboardScreen.criticalStockKey), findsOneWidget);
      expect(find.byKey(DashboardScreen.negativeStockKey), findsOneWidget);
      expect(
        find.text(AppStringsTr.dashboardNowSuffix),
        findsNWidgets(2),
        reason:
            'Bu iki kart tarih aralığından BAĞIMSIZDIR; ayrım kartta '
            'belirtilmelidir.',
      );
    });

    testWidgets('docs/15 §3.3 — saatlik yoğunluk Bugün\'de GÖSTERİLMEZ', (
      tester,
    ) async {
      final id = await createProduct();
      await sell(id);
      await unlock();

      await pump(tester);
      expect(find.byKey(DashboardScreen.hourlyKey), findsNothing);

      await tester.tap(find.byKey(const Key('dashboard_period_last7Days')));
      await tester.pumpAndSettle();
      expect(find.byKey(DashboardScreen.hourlyKey), findsOneWidget);
    });

    testWidgets('docs/15 §5 — brüt/iptal/iade AYRI bölümde', (tester) async {
      final id = await createProduct(salePriceMinor: 12000);
      await sell(id, quantity: 2);
      await unlock();

      await pump(tester);

      // Varsayılan görünüm NETtir; ayrıntı ayrı bölümdedir.
      expect(find.text(AppStringsTr.dashboardBreakdownTitle), findsOneWidget);
      expect(find.text(AppStringsTr.dashboardGrossRevenue), findsOneWidget);
      expect(find.text(AppStringsTr.dashboardCancelled), findsOneWidget);
      expect(find.text(AppStringsTr.dashboardReturned), findsOneWidget);
    });

    testWidgets('en çok satan ürün snapshot ADIYLA listelenir', (tester) async {
      final id = await createProduct(name: 'Kola');
      await sell(id, quantity: 4);
      await (db.update(db.products)..where((p) => p.id.equals(id))).write(
        const ProductsCompanion(name: Value('Kola XL')),
      );
      await unlock();

      await pump(tester);

      expect(find.byKey(Key('dashboard_product_$id')), findsOneWidget);
      expect(find.text('Kola'), findsWidgets);
      expect(find.text('Kola XL'), findsNothing);
    });

    testWidgets('veri yokken boş durum gösterilir, çökmez', (tester) async {
      await unlock();

      await pump(tester);

      expect(find.byKey(DashboardScreen.lockedKey), findsNothing);
      expect(find.text(AppStringsTr.dashboardNoData), findsWidgets);
      expect(
        kpiValue(tester, DashboardScreen.netRevenueKey).data,
        MoneyFormatter.format(Money.zero),
      );
    });

    testWidgets('dönem değiştirince veri YENİDEN yüklenir', (tester) async {
      final id = await createProduct(salePriceMinor: 10000);
      await sell(id);
      await unlock();

      await pump(tester);
      expect(
        kpiValue(tester, DashboardScreen.netRevenueKey).data,
        MoneyFormatter.format(const Money(10000)),
      );

      await tester.tap(find.byKey(const Key('dashboard_period_yesterday')));
      await tester.pumpAndSettle();

      expect(
        kpiValue(tester, DashboardScreen.netRevenueKey).data,
        MoneyFormatter.format(Money.zero),
        reason: 'Dün satış yok.',
      );
    });
  });
}
