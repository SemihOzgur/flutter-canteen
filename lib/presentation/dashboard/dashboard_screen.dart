/// Dashboard — **docs/15 · BR-AUTH-012/013 · REQ-DASH-***
///
/// ## Kilit bu ekranın ÖNÜNDEDİR
///
/// Ekran açılmadan `ensureFinancialAccess` çalışır (docs/22 F9). Kullanıcı
/// vazgeçerse ekran **hiç kurulmaz**. Kurulsa bile `DashboardService` kapının
/// arkasındadır: parola olmadan tek sorgu bile çalışmaz (BR-AUTH-012).
///
/// İki katman bilinçlidir — rota koruması bir gezinme ayrıntısıdır ve
/// unutulabilir; servis kapısı unutulamaz.
///
/// ## Burada hesap YAPILMAZ
///
/// rules/05 §3: net ciro, kâr ve marj `domain/services/report_metrics.dart`
/// içindedir. Bu ekran yalnızca **biçimlendirir** (`₺25,50` bir presentation
/// concern'üdür).
library;

import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/reporting/dashboard_service.dart';
import '../../application/reporting/providers.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../domain/services/report_period.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  static const Key periodSelectorKey = Key('dashboard_period');
  static const Key netRevenueKey = Key('dashboard_net_revenue');
  static const Key netProfitKey = Key('dashboard_net_profit');
  static const Key criticalStockKey = Key('dashboard_critical_stock');
  static const Key negativeStockKey = Key('dashboard_negative_stock');
  static const Key lockedKey = Key('dashboard_locked');
  static const Key trendKey = Key('dashboard_trend');
  static const Key hourlyKey = Key('dashboard_hourly');

  /// Dönem sınırlarının saati — **rules/06 §7.**
  ///
  /// `DateTime.now()` domain sınırlarına parametre olarak geçirilir; aksi
  /// hâlde "Bugün"ün ne olduğu testin çalıştığı güne bağlı olurdu.
  /// Üretimde `null`'dır.
  final DateTime Function()? clock;

  const DashboardScreen({this.clock, super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  ReportPeriodKind _kind = ReportPeriodKind.today;
  DashboardData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final period = ReportPeriod.of(_kind, (widget.clock ?? DateTime.now)());
    final result = await ref.read(dashboardServiceProvider).load(period);
    if (!mounted) return;
    setState(() {
      _loading = false;
      // BR-AUTH-012 — kilit kapalıysa veri YOKTUR; ekran boş kalır ve
      // sebebini söyler. Hiçbir rakam (bulanık dahi) oluşmamıştır.
      _data = result.valueOrNull;
      _error = result.failureOrNull?.userMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final data = _data;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStringsTr.dashboardTitle)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _periodSelector(),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : data == null
                ? Center(
                    child: Padding(
                      key: DashboardScreen.lockedKey,
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.lock_outline,
                            size: 48,
                            color: theme.colorScheme.outline,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            _error ?? AppStringsTr.dashboardNoData,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                : _content(theme, data),
          ),
        ],
      ),
    );
  }

  /// docs/15 §2 — tek global seçici tüm dashboard'ı yönetir.
  Widget _periodSelector() => Padding(
    padding: const EdgeInsets.all(12),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        key: DashboardScreen.periodSelectorKey,
        children: [
          for (final kind in ReportPeriodKind.values)
            if (kind != ReportPeriodKind.custom)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  key: Key('dashboard_period_${kind.name}'),
                  label: Text(
                    AppStringsTr.dashboardPeriodNames[kind.name] ?? kind.name,
                  ),
                  selected: _kind == kind,
                  onSelected: (_) {
                    setState(() => _kind = kind);
                    unawaited(_load());
                  },
                ),
              ),
        ],
      ),
    ),
  );

  Widget _content(ThemeData theme, DashboardData data) {
    final summary = data.summary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // docs/15 §3.1 — KPI şeridi.
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _kpi(
              theme,
              key: DashboardScreen.netRevenueKey,
              title: AppStringsTr.dashboardNetRevenue,
              value: MoneyFormatter.format(summary.netRevenue),
              subtitle: _changeText(data.revenueChangeBp),
            ),
            _kpi(
              theme,
              key: DashboardScreen.netProfitKey,
              title: AppStringsTr.dashboardNetProfit,
              value: MoneyFormatter.format(summary.netProfit),
              // REQ-VAT-009 — marj KDV hariç matrah üzerinden.
              subtitle:
                  '${AppStringsTr.dashboardMargin}: '
                  '%${(summary.profitMarginBp / 100).toStringAsFixed(1).replaceAll('.', ',')}',
            ),
            _kpi(
              theme,
              title: AppStringsTr.dashboardSaleCount,
              value: '${summary.saleCount}',
              subtitle:
                  '${AppStringsTr.dashboardAverageSale}: '
                  '${MoneyFormatter.format(summary.averageSale)}',
            ),
            _kpi(
              theme,
              title: AppStringsTr.dashboardUnitCount,
              value: '${summary.netUnitCount}',
            ),
            // docs/15 §3.1 — bu iki kart ANLIKTIR; ayrım kartta belirtilir.
            _kpi(
              theme,
              key: DashboardScreen.criticalStockKey,
              title: AppStringsTr.dashboardCriticalStock,
              value: '${data.criticalStockCount}',
              subtitle: AppStringsTr.dashboardNowSuffix,
              // Sayı 0 olduğunda kart sakin görünür, dikkat çekmez.
              accent: data.criticalStockCount > 0
                  ? theme.colorScheme.tertiary
                  : null,
            ),
            _kpi(
              theme,
              key: DashboardScreen.negativeStockKey,
              title: AppStringsTr.dashboardNegativeStock,
              value: '${data.negativeStockCount}',
              subtitle: AppStringsTr.dashboardNowSuffix,
              accent: data.negativeStockCount > 0
                  ? theme.colorScheme.error
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _section(
          theme,
          AppStringsTr.dashboardRevenueTrend,
          _trendChart(theme, data),
          key: DashboardScreen.trendKey,
        ),
        // docs/15 §3.3 — yalnızca aralık ≥ 2 gün olduğunda.
        if (data.period.showsHourlyDensity)
          _section(
            theme,
            AppStringsTr.dashboardHourlyDensity,
            _hourlyChart(theme, data),
            key: DashboardScreen.hourlyKey,
          ),
        _section(
          theme,
          AppStringsTr.dashboardTopProducts,
          _topProducts(theme, data),
        ),
        _section(
          theme,
          AppStringsTr.dashboardCategories,
          _categories(theme, data),
        ),
        _section(
          theme,
          AppStringsTr.dashboardBreakdownTitle,
          _breakdown(theme, data),
        ),
      ],
    );
  }

  /// docs/15 §5 — brüt/iptal/iade ayrıntısı **ayrı** bölümde; varsayılan
  /// görünüm nettir.
  Widget _breakdown(ThemeData theme, DashboardData data) {
    final summary = data.summary;
    Widget row(String label, Money value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(MoneyFormatter.format(value), style: theme.textTheme.bodyMedium),
        ],
      ),
    );

    return Column(
      children: [
        row(AppStringsTr.dashboardGrossRevenue, summary.grossRevenue),
        row(AppStringsTr.dashboardCancelled, summary.cancelled),
        row(AppStringsTr.dashboardReturned, summary.returned),
        row(AppStringsTr.dashboardWasteCost, summary.wasteCost),
        const Divider(),
        row(AppStringsTr.dashboardNetRevenue, summary.netRevenue),
      ],
    );
  }

  String? _changeText(int? bp) => bp == null
      ? AppStringsTr.dashboardNoComparison
      : AppStringsTr.dashboardChange(bp);

  Widget _kpi(
    ThemeData theme, {
    required String title,
    required String value,
    String? subtitle,
    Color? accent,
    Key? key,
  }) => SizedBox(
    width: 220,
    child: Card(
      key: key,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            Text(
              value,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: accent,
              ),
            ),
            if (subtitle != null)
              Text(subtitle, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    ),
  );

  Widget _section(ThemeData theme, String title, Widget child, {Key? key}) =>
      Padding(
        key: key,
        padding: const EdgeInsets.only(bottom: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            child,
          ],
        ),
      );

  Widget _trendChart(ThemeData theme, DashboardData data) {
    if (data.trend.isEmpty) {
      return Text(
        AppStringsTr.dashboardNoData,
        style: theme.textTheme.bodySmall,
      );
    }
    return SizedBox(
      height: 220,
      child: LineChart(
        LineChartData(
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (var i = 0; i < data.trend.length; i++)
                  FlSpot(i.toDouble(), data.trend[i].revenueMinor / 100),
              ],
              isCurved: true,
              barWidth: 2,
              color: theme.colorScheme.primary,
              belowBarData: BarAreaData(
                show: true,
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
              ),
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hourlyChart(ThemeData theme, DashboardData data) {
    if (data.hourly.isEmpty) {
      return Text(
        AppStringsTr.dashboardNoData,
        style: theme.textTheme.bodySmall,
      );
    }
    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          barGroups: [
            for (var i = 0; i < data.hourly.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: data.hourly[i].saleCount.toDouble(),
                    color: theme.colorScheme.secondary,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _topProducts(ThemeData theme, DashboardData data) {
    if (data.topProducts.isEmpty) {
      return Text(
        AppStringsTr.dashboardNoData,
        style: theme.textTheme.bodySmall,
      );
    }
    return Column(
      children: [
        for (final product in data.topProducts)
          ListTile(
            key: Key('dashboard_product_${product.productId}'),
            dense: true,
            title: Text(product.name),
            subtitle: Text('${product.unitCount} adet'),
            trailing: Text(MoneyFormatter.format(Money(product.revenueMinor))),
          ),
      ],
    );
  }

  /// docs/15 §3.6 — 8'den fazla kategori varsa ilk 7 + "Diğer".
  Widget _categories(ThemeData theme, DashboardData data) {
    if (data.categories.isEmpty) {
      return Text(
        AppStringsTr.dashboardNoData,
        style: theme.textTheme.bodySmall,
      );
    }
    final shown = data.categories.take(7).toList();
    final restRevenue = data.categories
        .skip(7)
        .fold(0, (sum, c) => sum + c.revenueMinor);

    return Column(
      children: [
        for (final category in shown)
          ListTile(
            key: Key('dashboard_category_${category.categoryId ?? 0}'),
            dense: true,
            title: Text(category.name),
            trailing: Text(MoneyFormatter.format(Money(category.revenueMinor))),
          ),
        if (restRevenue > 0)
          ListTile(
            key: const Key('dashboard_category_other'),
            dense: true,
            title: const Text(AppStringsTr.dashboardOtherCategories),
            trailing: Text(MoneyFormatter.format(Money(restRevenue))),
          ),
      ],
    );
  }
}
