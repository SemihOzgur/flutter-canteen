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
import '../../app/theme/app_palette.dart';
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
              icon: Icons.payments_outlined,
              accent: AppPalette.revenue,
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
              icon: Icons.trending_up,
              accent: AppPalette.profit,
            ),
            _kpi(
              theme,
              title: AppStringsTr.dashboardSaleCount,
              value: '${summary.saleCount}',
              subtitle:
                  '${AppStringsTr.dashboardAverageSale}: '
                  '${MoneyFormatter.format(summary.averageSale)}',
              icon: Icons.receipt_long_outlined,
              accent: AppPalette.saleCount,
            ),
            _kpi(
              theme,
              title: AppStringsTr.dashboardUnitCount,
              value: '${summary.netUnitCount}',
              icon: Icons.shopping_basket_outlined,
              accent: AppPalette.unitCount,
            ),
            // docs/15 §3.1 — bu iki kart ANLIKTIR; ayrım kartta belirtilir.
            _kpi(
              theme,
              key: DashboardScreen.criticalStockKey,
              title: AppStringsTr.dashboardCriticalStock,
              value: '${data.criticalStockCount}',
              subtitle: AppStringsTr.dashboardNowSuffix,
              icon: Icons.warning_amber_outlined,
              // docs/15 §3.1 — sayı 0 olduğunda kart SAKİN görünür ve
              // dikkat çekmez; her zaman turuncu duran bir kart uyarı
              // olmaktan çıkıp dekora dönüşür.
              accent: data.criticalStockCount > 0
                  ? AppPalette.warning
                  : AppPalette.calm,
            ),
            _kpi(
              theme,
              key: DashboardScreen.negativeStockKey,
              title: AppStringsTr.dashboardNegativeStock,
              value: '${data.negativeStockCount}',
              subtitle: AppStringsTr.dashboardNowSuffix,
              icon: Icons.error_outline,
              accent: data.negativeStockCount > 0
                  ? AppPalette.danger
                  : AppPalette.calm,
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
    required IconData icon,
    required AccentColor accent,
    String? subtitle,
    Key? key,
  }) => SizedBox(
    width: 224,
    child: Material(
      key: key,
      color: accent.background,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: accent.foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: accent.foreground,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: accent.foreground,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: accent.foreground.withValues(alpha: 0.85),
                ),
              ),
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

  /// docs/15 §3.2 — alan dolgulu çizgi + **önceki dönem** karşılaştırması.
  Widget _trendChart(ThemeData theme, DashboardData data) {
    if (data.trend.isEmpty) {
      return _empty(theme);
    }

    // Tip ADLANDIRILMAZ: `TrendPoint` `data/` katmanında ve drift'e bağlı
    // bir dosyada yaşıyor; presentation onu import edemez (rules/01 §1).
    // Grafiğin ihtiyacı zaten yalnızca kuruş değerleri.
    List<FlSpot> spotsOf(List<int> revenues) => [
      for (var i = 0; i < revenues.length; i++)
        FlSpot(i.toDouble(), revenues[i] / 100),
    ];

    // İki seri aynı X ekseninde durur: "geçen dönemin 3. günü" ile "bu
    // dönemin 3. günü" karşılaştırılır. Önceki dönem daha uzunsa fazlası
    // kırpılır; kısa ise grafik erken biter — hizalama bozulmaz.
    final current = spotsOf([
      for (final point in data.trend) point.revenueMinor,
    ]);
    final previous = spotsOf([
      for (final point in data.previousTrend.take(data.trend.length))
        point.revenueMinor,
    ]);

    return SizedBox(
      height: 260,
      child: Padding(
        padding: const EdgeInsets.only(top: 8, right: 8),
        child: LineChart(
          LineChartData(
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) => FlLine(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
                strokeWidth: 1,
              ),
            ),
            titlesData: FlTitlesData(
              rightTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 56,
                  getTitlesWidget: (value, meta) => Text(
                    MoneyFormatter.compact(Money((value * 100).round())),
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  // Her etiketi yazmak eksende okunmaz bir şerit üretir.
                  interval: _labelInterval(data.trend.length),
                  getTitlesWidget: (value, meta) {
                    final index = value.round();
                    if (index < 0 || index >= data.trend.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _shortBucket(data.trend[index].bucket),
                        style: theme.textTheme.labelSmall,
                      ),
                    );
                  },
                ),
              ),
            ),
            borderData: FlBorderData(show: false),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => [
                  for (final spot in spots)
                    LineTooltipItem(
                      MoneyFormatter.format(Money((spot.y * 100).round())),
                      theme.textTheme.labelMedium!.copyWith(
                        color: spot.barIndex == 0
                            ? AppPalette.revenue.foreground
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: current,
                isCurved: true,
                curveSmoothness: 0.25,
                barWidth: 3,
                color: AppPalette.revenue.foreground,
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppPalette.revenue.foreground.withValues(alpha: 0.35),
                      AppPalette.revenue.foreground.withValues(alpha: 0.02),
                    ],
                  ),
                ),
                dotData: FlDotData(
                  // Nokta kalabalığı çizgiyi okunmaz yapar; az sayıda
                  // veri varken ise her nokta bilgi taşır.
                  show: current.length <= 14,
                  getDotPainter: (spot, percent, bar, index) =>
                      FlDotCirclePainter(
                        radius: 3,
                        color: AppPalette.revenue.foreground,
                        strokeWidth: 2,
                        strokeColor: theme.colorScheme.surface,
                      ),
                ),
              ),
              if (previous.isNotEmpty)
                LineChartBarData(
                  spots: previous,
                  isCurved: true,
                  curveSmoothness: 0.25,
                  barWidth: 2,
                  color: theme.colorScheme.outline.withValues(alpha: 0.75),
                  dashArray: const [5, 4],
                  dotData: const FlDotData(show: false),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Eksende en fazla ~8 etiket kalsın.
  static double _labelInterval(int count) =>
      count <= 8 ? 1 : (count / 8).ceilToDouble();

  /// `2026-08-14` → `08-14`, `13` → `13:00`.
  static String _shortBucket(String bucket) {
    if (bucket.length == 2) return '$bucket:00';
    if (bucket.length >= 10) return bucket.substring(5);
    return bucket;
  }

  Widget _empty(ThemeData theme) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 24),
    child: Row(
      children: [
        Icon(
          Icons.bar_chart_outlined,
          size: 18,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(width: 8),
        Text(
          AppStringsTr.dashboardNoData,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );

  /// docs/15 §3.3 — saatlik yoğunluk (0–23).
  Widget _hourlyChart(ThemeData theme, DashboardData data) {
    if (data.hourly.isEmpty) return _empty(theme);

    final maxCount = data.hourly
        .map((point) => point.saleCount)
        .reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
              strokeWidth: 1,
            ),
          ),
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (value, meta) =>
                    Text('${value.round()}', style: theme.textTheme.labelSmall),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: _labelInterval(data.hourly.length),
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  if (index < 0 || index >= data.hourly.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _shortBucket(data.hourly[index].bucket),
                      style: theme.textTheme.labelSmall,
                    ),
                  );
                },
              ),
            ),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                  BarTooltipItem(
                    AppStringsTr.dashboardHourlyTooltip(
                      _shortBucket(data.hourly[group.x].bucket),
                      rod.toY.round(),
                    ),
                    theme.textTheme.labelMedium!.copyWith(
                      color: theme.colorScheme.onInverseSurface,
                    ),
                  ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < data.hourly.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: data.hourly[i].saleCount.toDouble(),
                    width: 14,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(4),
                    ),
                    // En yoğun saat vurgulanır: personel planlaması için
                    // asıl bilgi "hangi saat" (docs/15 §3.3).
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: data.hourly[i].saleCount == maxCount
                          ? [
                              AppPalette.warning.foreground,
                              AppPalette.warning.foreground.withValues(
                                alpha: 0.6,
                              ),
                            ]
                          : [
                              AppPalette.unitCount.foreground,
                              AppPalette.unitCount.foreground.withValues(
                                alpha: 0.55,
                              ),
                            ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// docs/15 §3.4 — yatay sütun, ilk 10.
  ///
  /// Rakam yan yana yazılı bir listede "hangisi baskın?" sorusu göz
  /// karşılaştırmasıyla cevaplanamaz; çubuk uzunluğu bunu bir bakışta verir.
  Widget _topProducts(ThemeData theme, DashboardData data) {
    if (data.topProducts.isEmpty) return _empty(theme);

    // Çubuk, listenin SIRALANDIĞI ölçütü çizer.
    //
    // `ReportingDao.topProducts` `ORDER BY units DESC` ile gelir. Çubuğu
    // ciroya bağlamak, "en üstteki en uzun değil" gibi okunan ve kullanıcıyı
    // sıralamanın yanlış olduğuna inandıran bir grafik üretiyordu.
    final maxUnits = data.topProducts
        .map((product) => product.unitCount)
        .reduce((a, b) => a > b ? a : b);

    return Column(
      children: [
        for (final (index, product) in data.topProducts.indexed)
          Padding(
            key: Key('dashboard_product_${product.productId}'),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                SizedBox(
                  width: 180,
                  child: Text(
                    product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      // Sıfıra bölme: tek ürünlü ve cirosu 0 olan dönemde
                      // maxRevenue 0 olabilir.
                      value: maxUnits == 0 ? 0 : product.unitCount / maxUnits,
                      minHeight: 18,
                      backgroundColor:
                          theme.colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppPalette.categoryColor(index),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 72,
                  child: Text(
                    '${product.unitCount} adet',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                SizedBox(
                  width: 104,
                  child: Text(
                    MoneyFormatter.format(Money(product.revenueMinor)),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// docs/15 §3.6 — **donut grafik + yanında tablo**; 8'den fazla kategori
  /// varsa ilk 7 + "Diğer".
  ///
  /// Donut tek başına yetmez: dilimlerin **oranı** grafikten, tutarı ise
  /// tablodan okunur. Renk ikisinde de aynıdır (`AppPalette.categoryColor`),
  /// yoksa kullanıcı hangi dilimin hangi satır olduğunu bulamaz.
  Widget _categories(ThemeData theme, DashboardData data) {
    if (data.categories.isEmpty) return _empty(theme);

    final shown = data.categories.take(7).toList();
    final restRevenue = data.categories
        .skip(7)
        .fold(0, (sum, c) => sum + c.revenueMinor);

    final total = shown.fold(0, (sum, c) => sum + c.revenueMinor) + restRevenue;

    final slices = <({String name, int revenue, Color color, Key key})>[
      for (final (index, category) in shown.indexed)
        (
          name: category.name,
          revenue: category.revenueMinor,
          color: AppPalette.categoryColor(index),
          key: Key('dashboard_category_${category.categoryId ?? 0}'),
        ),
      if (restRevenue > 0)
        (
          name: AppStringsTr.dashboardOtherCategories,
          revenue: restRevenue,
          // "Diğer" gri kalır ki gerçek bir kategoriyle karışmasın.
          color: AppPalette.other,
          key: const Key('dashboard_category_other'),
        ),
    ];

    // Ciro 0 ise donut çizilemez (tüm dilimler 0). Tablo yine anlamlıdır.
    final chart = total == 0
        ? const SizedBox.shrink()
        : SizedBox(
            width: 200,
            height: 200,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                // Ortası boş: docs/15 "donut" diyor. Dolu pasta, küçük
                // dilimleri okunmaz hâle getirir.
                centerSpaceRadius: 52,
                startDegreeOffset: -90,
                sections: [
                  for (final slice in slices)
                    PieChartSectionData(
                      value: slice.revenue.toDouble(),
                      color: slice.color,
                      radius: 42,
                      showTitle: slice.revenue / total >= 0.08,
                      title: _percent(slice.revenue, total),
                      titleStyle: theme.textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          );

    final table = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final slice in slices)
          Padding(
            key: slice.key,
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: slice.color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    slice.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                // rules/05 §5 — pay renkle değil, METİNLE de verilir.
                Text(
                  _percent(slice.revenue, total),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 104,
                  child: Text(
                    MoneyFormatter.format(Money(slice.revenue)),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );

    // Dar pencerede (docs/23 §4 — 1366×768) grafik ve tablo yan yana
    // sığmazsa alt alta geçer; tablo asla kırpılmaz.
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 560) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (total > 0) Center(child: chart),
              const SizedBox(height: 16),
              table,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            chart,
            const SizedBox(width: 24),
            Expanded(child: table),
          ],
        );
      },
    );
  }

  /// `%12,5` — payda 0 ise `%0`.
  static String _percent(int value, int total) {
    if (total == 0) return '%0';
    final ratio = value * 1000 ~/ total; // binde
    return '%${(ratio / 10).toStringAsFixed(1).replaceAll('.', ',')}';
  }
}
