/// Dashboard servisi — **BR-AUTH-012/013 · docs/15 · OD-028 · REQ-VAT-009**
///
/// ## Bu dosyanın en önemli testi
///
/// > **BR-AUTH-012 — parola doğrulanmadan hiçbir dashboard/rapor sorgusu
/// > çalıştırılmaz.**
///
/// Bunu "ekranda rakam görünmüyor" diye doğrulamak **yetmez**: sorgu çalışıp
/// sonucu gizlenmiş de olabilir. Burada bir **sorgu sayacı** kullanılır —
/// kilit kapalıyken sayacın `0` kalması gerekir.
library;

import 'package:canteen/application/audit/audit_service.dart';
import 'package:canteen/application/auth/financial_access_service.dart';
import 'package:canteen/application/reporting/dashboard_service.dart';
import 'package:canteen/application/sales/cart_service.dart';
import 'package:canteen/application/sales/return_service.dart';
import 'package:canteen/application/sales/sale_service.dart';
import 'package:canteen/application/stock/stock_service.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/dao/reporting_dao.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, CartItem, Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/repositories/drift_product_repository.dart';
import 'package:canteen/data/repositories/drift_sale_repository.dart';
import 'package:canteen/data/repositories/drift_stock_repository.dart';
import 'package:canteen/domain/models/sale_return.dart';
import 'package:canteen/domain/services/report_period.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

/// Her çağrıyı **sayan** sarmalayıcı — BR-AUTH-012'nin ölçüm noktası.
class _CountingReportingDao implements ReportingDao {
  final ReportingDao _inner;
  int calls = 0;

  /// docs/15 §3.3 — saatlik yoğunluk yalnızca aralık ≥ 2 gün olduğunda
  /// **sorgulanır**. Boş sonuç dönmesi yetmez: sorgunun hiç çalışmaması
  /// gerekir, aksi hâlde her dashboard açılışında gereksiz bir tarama olurdu.
  int hourlyCalls = 0;

  _CountingReportingDao(this._inner);

  @override
  Future<PeriodTotals> periodTotals({
    required int fromMillis,
    required int toMillis,
  }) {
    calls++;
    return _inner.periodTotals(fromMillis: fromMillis, toMillis: toMillis);
  }

  @override
  Future<List<TrendPoint>> revenueTrend({
    required int fromMillis,
    required int toMillis,
    required String format,
  }) {
    calls++;
    return _inner.revenueTrend(
      fromMillis: fromMillis,
      toMillis: toMillis,
      format: format,
    );
  }

  @override
  Future<List<TrendPoint>> hourlyDensity({
    required int fromMillis,
    required int toMillis,
  }) {
    calls++;
    hourlyCalls++;
    return _inner.hourlyDensity(fromMillis: fromMillis, toMillis: toMillis);
  }

  @override
  Future<List<ProductBreakdown>> topProducts({
    required int fromMillis,
    required int toMillis,
    int limit = 10,
  }) {
    calls++;
    return _inner.topProducts(
      fromMillis: fromMillis,
      toMillis: toMillis,
      limit: limit,
    );
  }

  @override
  Future<List<CategoryBreakdown>> categoryBreakdown({
    required int fromMillis,
    required int toMillis,
  }) {
    calls++;
    return _inner.categoryBreakdown(fromMillis: fromMillis, toMillis: toMillis);
  }

  @override
  Future<int> criticalStockCount() {
    calls++;
    return _inner.criticalStockCount();
  }

  @override
  Future<int> negativeStockCount() {
    calls++;
    return _inner.negativeStockCount();
  }

  @override
  Future<int> wasteCostMinor({required int fromMillis, required int toMillis}) {
    calls++;
    return _inner.wasteCostMinor(fromMillis: fromMillis, toMillis: toMillis);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    return super.noSuchMethod(invocation);
  }
}

void main() {
  late CanteenDatabase db;
  late DateTime now;
  late FinancialAccessService access;
  late _CountingReportingDao dao;
  late DashboardService service;
  late CartService cartService;
  late SaleService saleService;
  late ReturnService returnService;
  late int userId;

  const dashboardPassword = 'DASH-PW-8Q2M';

  setUp(() async {
    now = DateTime.utc(2026, 8, 14, 12);
    db = memoryDatabase(clock: () => now);
    final settings = AppSettingsDao(db);
    access = FinancialAccessService(
      db: db,
      settings: settings,
      auditLogs: AuditLogsDao(db),
      clock: () => now,
    );
    dao = _CountingReportingDao(ReportingDao(db));
    service = DashboardService(
      access: access,
      dao: dao,
      sales: DriftSaleRepository(db),
    );

    final products = DriftProductRepository(db);
    final audit = AuditService(auditLogs: AuditLogsDao(db), clock: () => now);
    final stockService = StockService(
      db: db,
      stock: DriftStockRepository(db),
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
      appSettings: settings,
      auditLogs: AuditLogsDao(db),
      products: products,
      sales: DriftSaleRepository(db),
      stockService: stockService,
      clock: () => now,
    );
    returnService = ReturnService(
      db: db,
      sales: DriftSaleRepository(db),
      stockService: stockService,
      audit: audit,
      clock: () => now,
    );
    userId = await insertTestUser(db);
  });

  tearDown(() => db.close());

  Future<void> unlock() async {
    await access.setPassword(dashboardPassword);
    final opened = await access.unlock(dashboardPassword);
    expect(opened.isErr, isFalse, reason: '${opened.failureOrNull}');
  }

  Future<int> product({
    String name = 'Kola',
    int salePriceMinor = 12000,
    int purchasePriceMinor = 6000,
    int stockQuantity = 100,
    int? vatRateId,
  }) async {
    final id = await insertTestProduct(
      db,
      name: name,
      salePriceMinor: salePriceMinor,
      purchasePriceMinor: purchasePriceMinor,
    );
    await (db.update(db.products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(
        stockQuantity: Value(stockQuantity),
        vatRateId: Value(vatRateId),
      ),
    );
    return id;
  }

  Future<int> sell(int productId, {int quantity = 1}) async {
    final cart = await cartService.ensureActive(userId);
    await cartService.addProduct(
      cartId: cart.id,
      productId: productId,
      quantity: quantity,
    );
    final receipt = await saleService.complete(cartId: cart.id, userId: userId);
    expect(receipt.isErr, isFalse, reason: '${receipt.failureOrNull}');
    return receipt.valueOrNull!.saleId;
  }

  ReportPeriod today() => ReportPeriod.of(ReportPeriodKind.today, now);

  // -------------------------------------------------------------------------
  // BR-AUTH-012 — kilit
  // -------------------------------------------------------------------------

  group('BR-AUTH-012 — kilit kapalıyken HİÇBİR sorgu çalışmaz', () {
    test('`load` kilit kapalıyken TEK sorgu bile yapmaz', () async {
      await product();

      final result = await service.load(today());

      expect(result.isErr, isTrue);
      expect(
        dao.calls,
        0,
        reason:
            'Kilit görsel bir perde DEĞİLDİR: sorgu çalışıp sonucu '
            'gizlenmiş olamaz (docs/15 §0).',
      );
    });

    test(
      '`summary`, `productBreakdown`, `categoryBreakdown` de sorgulamaz',
      () async {
        await product();

        expect((await service.summary(today())).isErr, isTrue);
        expect((await service.productBreakdown(today())).isErr, isTrue);
        expect((await service.categoryBreakdown(today())).isErr, isTrue);

        expect(dao.calls, 0);
      },
    );

    test('kilit AÇILINCA sorgular çalışır', () async {
      await product();
      await unlock();

      final result = await service.load(today());

      expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
      expect(dao.calls, greaterThan(0));
    });

    test('kilit TEKRAR kapanınca sorgular yeniden durur', () async {
      await unlock();
      await service.load(today());
      final afterUnlock = dao.calls;
      expect(afterUnlock, greaterThan(0));

      // BR-AUTH-016 — logout kilidi kapatır.
      access.lock();
      final result = await service.load(today());

      expect(result.isErr, isTrue);
      expect(
        dao.calls,
        afterUnlock,
        reason: 'Kilitlendikten sonra sayaç ARTMAMALIDIR.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // Net değerler — OD-028
  // -------------------------------------------------------------------------

  group('OD-028 — net ciro aritmetiği', () {
    test('satış → brüt = net', () async {
      final id = await product(salePriceMinor: 12000);
      await sell(id, quantity: 2);
      await unlock();

      final data = (await service.load(today())).valueOrNull!;

      expect(data.summary.grossRevenue, const Money(24000));
      expect(data.summary.netRevenue, const Money(24000));
      expect(data.summary.saleCount, 1);
      expect(data.summary.unitCount, 2);
    });

    test('İPTAL brütte KALIR ve netten düşer', () async {
      final id = await product(salePriceMinor: 12000);
      final saleId = await sell(id, quantity: 2);
      await returnService.cancelSale(
        saleId: saleId,
        userId: userId,
        reason: 'Yanlış satış',
      );
      await unlock();

      final data = (await service.load(today())).valueOrNull!;

      expect(
        data.summary.grossRevenue,
        const Money(24000),
        reason: 'OD-028 — brüt İPTALLERİ İÇERİR; içermeseydi iki kez düşerdi.',
      );
      expect(data.summary.cancelled, const Money(24000));
      expect(data.summary.netRevenue, Money.zero);
    });

    test('İADE netten düşer, brütte kalır', () async {
      final id = await product(salePriceMinor: 12000);
      final saleId = await sell(id, quantity: 3);
      final items = await DriftSaleRepository(db).itemsOf(saleId);
      await returnService.createReturn(
        saleId: saleId,
        userId: userId,
        lines: [ReturnLineRequest(saleItemId: items.single.id, quantity: 1)],
      );
      await unlock();

      final data = (await service.load(today())).valueOrNull!;

      expect(data.summary.grossRevenue, const Money(36000));
      expect(data.summary.returned, const Money(12000));
      expect(data.summary.netRevenue, const Money(24000));
      expect(data.summary.netUnitCount, 2);
    });

    test('OD-028 — iptal, İPTAL TARİHİNE yazılır', () async {
      // Satış dün, iptal bugün: dünün cirosu DEĞİŞMEZ, iptal bugüne düşer.
      now = DateTime.utc(2026, 8, 13, 12);
      final id = await product(salePriceMinor: 12000);
      final saleId = await sell(id);

      now = DateTime.utc(2026, 8, 14, 12);
      await returnService.cancelSale(
        saleId: saleId,
        userId: userId,
        reason: 'x',
      );
      await unlock();

      final yesterday = (await service.summary(
        ReportPeriod.of(ReportPeriodKind.yesterday, now),
      )).valueOrNull!;
      final todaySummary = (await service.summary(today())).valueOrNull!;

      expect(
        yesterday.grossRevenue,
        const Money(12000),
        reason: 'Kapanmış günün cirosu geriye dönük DEĞİŞMEZ (docs/14 §5).',
      );
      expect(yesterday.cancelled, Money.zero);
      expect(todaySummary.cancelled, const Money(12000));
      expect(todaySummary.grossRevenue, Money.zero);
    });

    test('BR-RET-008 — iade, İADE TARİHİNE yazılır', () async {
      now = DateTime.utc(2026, 8, 13, 12);
      final id = await product(salePriceMinor: 12000);
      final saleId = await sell(id, quantity: 2);
      final items = await DriftSaleRepository(db).itemsOf(saleId);

      now = DateTime.utc(2026, 8, 14, 12);
      await returnService.createReturn(
        saleId: saleId,
        userId: userId,
        lines: [ReturnLineRequest(saleItemId: items.single.id, quantity: 1)],
      );
      await unlock();

      final yesterday = (await service.summary(
        ReportPeriod.of(ReportPeriodKind.yesterday, now),
      )).valueOrNull!;
      final todaySummary = (await service.summary(today())).valueOrNull!;

      expect(yesterday.returned, Money.zero);
      expect(todaySummary.returned, const Money(12000));
    });
  });

  // -------------------------------------------------------------------------
  // Kâr — REQ-VAT-009
  // -------------------------------------------------------------------------

  group('REQ-VAT-009 — kâr KDV hariç matrahtan', () {
    test('₺120,00 @ %20, maliyet ₺60,00 → kâr ₺40,00', () async {
      final rate = await VatRatesDao(db).insertVatRate(
        name: 'oran',
        rateBasisPoints: 2000,
        isDefault: false,
        now: now,
      );
      final id = await product(
        salePriceMinor: 12000,
        purchasePriceMinor: 6000,
        vatRateId: rate,
      );
      await sell(id);
      await unlock();

      final data = (await service.load(today())).valueOrNull!;

      expect(data.summary.grossRevenue, const Money(12000));
      expect(data.summary.netBase, const Money(10000));
      expect(data.summary.vat, const Money(2000));
      expect(data.summary.cost, const Money(6000));
      expect(
        data.summary.grossProfit,
        const Money(4000),
        reason:
            'Brüt cirodan hesaplansaydı ₺60,00 çıkardı — KDV dahil edilmiş '
            'olurdu (BR-VAT-003).',
      );
    });

    test('docs/16 R5 — fire kârdan DÜŞÜLÜR', () async {
      final id = await product(salePriceMinor: 12000, purchasePriceMinor: 6000);
      await sell(id);
      await StockService(
        db: db,
        stock: DriftStockRepository(db),
        products: DriftProductRepository(db),
        clock: () => now,
      ).recordWaste(
        productId: id,
        quantity: 2,
        reason: 'Bozulma',
        userId: userId,
      );
      await unlock();

      final data = (await service.load(today())).valueOrNull!;

      expect(data.summary.wasteCost, const Money(12000));
      expect(
        data.summary.netProfit,
        data.summary.grossProfit - const Money(12000),
      );
    });
  });

  // -------------------------------------------------------------------------
  // Bileşenler — docs/15 §3
  // -------------------------------------------------------------------------

  group('docs/15 §3 — dashboard bileşenleri', () {
    test('kritik ve negatif stok ANLIK — tarih aralığından bağımsız', () async {
      await product(name: 'Negatif', stockQuantity: -3);
      final critical = await product(name: 'Kritik', stockQuantity: 2);
      await (db.update(db.products)..where((p) => p.id.equals(critical))).write(
        const ProductsCompanion(minimumStock: Value(5)),
      );
      await unlock();

      // Geçmiş bir dönem seçilse bile sayılar AYNI kalmalıdır.
      final data = (await service.load(
        ReportPeriod.of(ReportPeriodKind.yesterday, now),
      )).valueOrNull!;

      expect(data.negativeStockCount, 1);
      expect(data.criticalStockCount, 1);
    });

    test('en çok satan ürünler snapshot ADIYLA gelir', () async {
      final id = await product(name: 'Kola', salePriceMinor: 12000);
      await sell(id, quantity: 5);
      // Ürünün adı satıştan SONRA değişiyor.
      await (db.update(db.products)..where((p) => p.id.equals(id))).write(
        const ProductsCompanion(name: Value('Kola XL')),
      );
      await unlock();

      final data = (await service.load(today())).valueOrNull!;

      expect(data.topProducts.single.name, 'Kola');
      expect(data.topProducts.single.unitCount, 5);
    });

    test('iade edilen miktar en çok satandan DÜŞÜLÜR', () async {
      final id = await product(salePriceMinor: 12000);
      final saleId = await sell(id, quantity: 5);
      final items = await DriftSaleRepository(db).itemsOf(saleId);
      await returnService.createReturn(
        saleId: saleId,
        userId: userId,
        lines: [ReturnLineRequest(saleItemId: items.single.id, quantity: 2)],
      );
      await unlock();

      final data = (await service.load(today())).valueOrNull!;

      expect(data.topProducts.single.unitCount, 3);
      expect(data.topProducts.single.revenueMinor, 36000);
    });

    test('İPTAL edilmiş satış en çok satana HİÇ girmez', () async {
      final id = await product(salePriceMinor: 12000);
      final saleId = await sell(id, quantity: 5);
      await returnService.cancelSale(
        saleId: saleId,
        userId: userId,
        reason: 'x',
      );
      await unlock();

      final data = (await service.load(today())).valueOrNull!;

      expect(data.topProducts, isEmpty);
    });

    test('kategori dağılımı SNAPSHOT kategorisini kullanır', () async {
      final oldCategory = await CategoriesDao(
        db,
      ).insertCategory(name: 'Eski', sortOrder: 1, now: now);
      final id = await insertTestProduct(
        db,
        name: 'Kola',
        salePriceMinor: 12000,
        categoryId: oldCategory,
      );
      await (db.update(db.products)..where((p) => p.id.equals(id))).write(
        const ProductsCompanion(stockQuantity: Value(100)),
      );
      await sell(id, quantity: 2);

      final newCategory = await CategoriesDao(
        db,
      ).insertCategory(name: 'Yeni', sortOrder: 2, now: now);
      await (db.update(db.products)..where((p) => p.id.equals(id))).write(
        ProductsCompanion(categoryId: Value(newCategory)),
      );
      await unlock();

      final data = (await service.load(today())).valueOrNull!;

      expect(
        data.categories.single.name,
        'Eski',
        reason: 'BR-SALE-001 — geçmiş kategori raporu DEĞİŞMEZ.',
      );
    });

    test('saatlik yoğunluk tek günlük aralıkta HİÇ SORGULANMAZ', () async {
      final id = await product();
      await sell(id);
      await unlock();

      await service.load(today());
      expect(dao.hourlyCalls, 0, reason: 'docs/15 §3.3');

      await service.load(ReportPeriod.of(ReportPeriodKind.last30Days, now));
      expect(dao.hourlyCalls, 1);
    });

    test('son satışlar tarih aralığından BAĞIMSIZDIR', () async {
      final id = await product();
      await sell(id);
      await unlock();

      final data = (await service.load(
        ReportPeriod.of(ReportPeriodKind.yesterday, now),
      )).valueOrNull!;

      expect(data.recentSales, hasLength(1));
    });
  });

  group('docs/15 §2 — dönem karşılaştırması', () {
    test('önceki dönemin özeti ayrıca hesaplanır', () async {
      final id = await product(salePriceMinor: 10000);

      now = DateTime.utc(2026, 8, 13, 12);
      await sell(id, quantity: 1);

      now = DateTime.utc(2026, 8, 14, 12);
      await sell(id, quantity: 2);
      await unlock();

      final data = (await service.load(today())).valueOrNull!;

      expect(data.summary.netRevenue, const Money(20000));
      expect(data.previous.netRevenue, const Money(10000));
      expect(data.revenueChangeBp, 10000, reason: '%100 artış');
    });
  });
}
