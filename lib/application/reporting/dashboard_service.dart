/// Dashboard ve rapor verisi — **docs/15 · BR-AUTH-012/013**
///
/// ## Kilit görsel bir perde DEĞİLDİR
///
/// > **BR-AUTH-012 — Parola doğrulanmadan hiçbir dashboard/rapor sorgusu
/// > çalıştırılmaz.**
///
/// Bu sınıftaki **her** okuma [FinancialGate] üzerinden geçer. Kilit
/// kapalıyken sorgu fonksiyonu **çağrılmaz**: veritabanına gidilmez, KPI
/// hesaplanmaz, ekranda bulanık bir rakam bile oluşmaz. Kural UI'da gizlemeyle
/// değil, **burada** zorlanır (docs/15 §0 · rules/04 §4).
///
/// Kapı Faz 3'te yazılmıştı ve o gün tek tüketicisi yoktu; Faz 8 onu bağlar.
///
/// ## Hesap burada YAPILMAZ
///
/// rules/01 §2 · rules/05 §3: net ciro, kâr ve marj `domain/services/
/// report_metrics.dart` içindedir. Bu servis **sorguyu çalıştırır ve domain'e
/// verir**; ikinci bir formül tanımlamaz.
library;

import '../../core/money/money.dart';
import '../../core/result/result.dart';
import '../../data/dao/reporting_dao.dart';
import '../../domain/models/sale.dart';
import '../../domain/repositories/sale_repository.dart';
import '../../domain/services/report_metrics.dart';
import '../../domain/services/report_period.dart';
import '../auth/financial_access_service.dart';

/// Dashboard'ın tek yüklemede ihtiyaç duyduğu her şey.
class DashboardData {
  final ReportPeriod period;
  final ReportSummary summary;

  /// docs/15 §2 — aynı uzunlukta önceki dönem (KPI karşılaştırması).
  final ReportSummary previous;

  final List<TrendPoint> trend;
  final List<TrendPoint> hourly;
  final List<ProductBreakdown> topProducts;
  final List<CategoryBreakdown> categories;
  final List<Sale> recentSales;

  /// docs/15 §3.1 — **anlık**, tarih aralığından bağımsız.
  final int criticalStockCount;
  final int negativeStockCount;

  const DashboardData({
    required this.period,
    required this.summary,
    required this.previous,
    required this.trend,
    required this.hourly,
    required this.topProducts,
    required this.categories,
    required this.recentSales,
    required this.criticalStockCount,
    required this.negativeStockCount,
  });

  /// docs/15 §2 — KPI kartlarındaki yüzde değişim; önceki dönem boşsa `null`.
  int? get revenueChangeBp => ReportComparison.changeBp(
    current: summary.netRevenue,
    previous: previous.netRevenue,
  );

  int? get profitChangeBp => ReportComparison.changeBp(
    current: summary.netProfit,
    previous: previous.netProfit,
  );
}

class DashboardService {
  final FinancialAccessService _access;
  final ReportingDao _dao;
  final SaleRepository _sales;

  DashboardService({
    required FinancialAccessService access,
    required ReportingDao dao,
    required SaleRepository sales,
  }) : _access = access,
       _dao = dao,
       _sales = sales;

  /// BR-AUTH-012 — kilit kapalıysa **hiçbir sorgu çalışmaz.**
  ///
  /// `Err` döndüğünde `dao`'ya tek bir çağrı bile yapılmamıştır; bu,
  /// `test/application/reporting/` içinde **sorgu sayacıyla** doğrulanır.
  Future<Result<DashboardData>> load(ReportPeriod period) {
    return _access.gate(_dao).run((dao) async {
      final from = period.fromUtc.millisecondsSinceEpoch;
      final to = period.toUtc.millisecondsSinceEpoch;
      final previous = period.previous;

      return DashboardData(
        period: period,
        summary: await _summaryOf(dao, period),
        previous: await _summaryOf(dao, previous),
        trend: await dao.revenueTrend(
          fromMillis: from,
          toMillis: to,
          format: period.trendFormat,
        ),
        // docs/15 §3.3 — yalnızca aralık ≥ 2 gün olduğunda.
        hourly: period.showsHourlyDensity
            ? await dao.hourlyDensity(fromMillis: from, toMillis: to)
            : const [],
        topProducts: await dao.topProducts(fromMillis: from, toMillis: to),
        categories: await dao.categoryBreakdown(fromMillis: from, toMillis: to),
        // docs/15 §3.8 — son 10 satış (tarih aralığından bağımsız).
        recentSales: await _sales.list(limit: 10),
        criticalStockCount: await dao.criticalStockCount(),
        negativeStockCount: await dao.negativeStockCount(),
      );
    });
  }

  /// Yalnızca dönem özeti — rapor ekranlarının özet şeridi için.
  Future<Result<ReportSummary>> summary(ReportPeriod period) =>
      _access.gate(_dao).run((dao) => _summaryOf(dao, period));

  /// docs/16 R2 — ürün satış raporu.
  Future<Result<List<ProductBreakdown>>> productBreakdown(
    ReportPeriod period, {
    int limit = 500,
  }) => _access
      .gate(_dao)
      .run(
        (dao) => dao.topProducts(
          fromMillis: period.fromUtc.millisecondsSinceEpoch,
          toMillis: period.toUtc.millisecondsSinceEpoch,
          limit: limit,
        ),
      );

  /// docs/16 R6 — kategori raporu.
  Future<Result<List<CategoryBreakdown>>> categoryBreakdown(
    ReportPeriod period,
  ) => _access
      .gate(_dao)
      .run(
        (dao) => dao.categoryBreakdown(
          fromMillis: period.fromUtc.millisecondsSinceEpoch,
          toMillis: period.toUtc.millisecondsSinceEpoch,
        ),
      );

  static Future<ReportSummary> _summaryOf(
    ReportingDao dao,
    ReportPeriod period,
  ) async {
    final from = period.fromUtc.millisecondsSinceEpoch;
    final to = period.toUtc.millisecondsSinceEpoch;
    final totals = await dao.periodTotals(fromMillis: from, toMillis: to);

    return ReportSummary(
      grossRevenue: Money(totals.grossRevenueMinor),
      cancelled: Money(totals.cancelledMinor),
      returned: Money(totals.returnedMinor),
      netBase: Money(totals.netBaseMinor),
      vat: Money(totals.vatMinor),
      cost: Money(totals.costMinor),
      reversedCost: Money(totals.reversedCostMinor),
      wasteCost: Money(
        await dao.wasteCostMinor(fromMillis: from, toMillis: to),
      ),
      saleCount: totals.saleCount,
      unitCount: totals.unitCount,
      returnedUnitCount: totals.returnedUnitCount,
    );
  }
}
