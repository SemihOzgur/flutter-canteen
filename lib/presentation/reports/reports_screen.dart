/// Raporlar — **docs/16 · BR-AUTH-013 · REQ-REP-***
///
/// Dashboard ile aynı kilidin arkasındadır ve **parola tekrar sorulmaz**:
/// kilit oturum kapsamlıdır (BR-AUTH-016). Kullanıcı Dashboard'ı açtıysa
/// Raporlar doğrudan gelir.
///
/// ## Dışa aktarma kilidin etrafından dolaşamaz
///
/// "CSV Olarak Kaydet" bir rapor **sorgusudur**; `ReportExportService` kapının
/// arkasındadır. Kilidi yalnızca ekranda uygulamak, bu düğmeyi bir kaçış yolu
/// hâline getirirdi.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/reporting/providers.dart';
import '../../application/reporting/report_export_service.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../data/dao/reporting_dao.dart';
import '../../domain/services/report_period.dart';
import '../common/save_location_picker.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  static const Key reportSelectorKey = Key('reports_selector');
  static const Key exportButtonKey = Key('reports_export');
  static const Key tableKey = Key('reports_table');
  static const Key lockedKey = Key('reports_locked');

  /// rules/06 §7 — dönem sınırlarının saati enjekte edilebilir.
  final DateTime Function()? clock;

  /// Test ve platform ayrımı için: dosya kaydetme yeri seçici.
  final SaveLocationPicker? savePicker;

  const ReportsScreen({this.clock, this.savePicker, super.key});

  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  ExportableReport _report = ExportableReport.productSales;
  ReportPeriodKind _kind = ReportPeriodKind.last30Days;
  List<ProductBreakdown> _products = const [];
  List<CategoryBreakdown> _categories = const [];
  bool _loading = true;
  bool _locked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  ReportPeriod get _period =>
      ReportPeriod.of(_kind, (widget.clock ?? DateTime.now)());

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = ref.read(dashboardServiceProvider);

    switch (_report) {
      case ExportableReport.productSales:
        final result = await service.productBreakdown(_period);
        if (!mounted) return;
        setState(() {
          _products = result.valueOrNull ?? const [];
          _categories = const [];
          _locked = result.isErr;
          _loading = false;
        });
      case ExportableReport.categorySales:
        final result = await service.categoryBreakdown(_period);
        if (!mounted) return;
        setState(() {
          _categories = result.valueOrNull ?? const [];
          _products = const [];
          _locked = result.isErr;
          _loading = false;
        });
    }
  }

  Future<void> _export() async {
    final result = await ref
        .read(reportExportServiceProvider)
        .exportCsv(report: _report, period: _period);
    if (!mounted) return;
    if (result.isErr) {
      _notify(result.failureOrNull!.userMessage);
      return;
    }

    final picker = widget.savePicker ?? pickSaveLocation;
    final path = await picker('${_report.name}_${_kind.name}.csv');
    if (!mounted) return;
    if (path == null) {
      _notify(AppStringsTr.reportExportCancelled);
      return;
    }

    // rules/03 §7 — dosya **baytları** yazılır; BOM metin olarak kaybolmaz.
    final written = await ref.read(reportFileWriterProvider)(
      path,
      result.valueOrNull!,
    );
    if (!mounted) return;
    _notify(
      written
          ? AppStringsTr.reportExported
          : AppStringsTr.unexpectedErrorMessage,
    );
  }

  void _notify(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rowCount = _report == ExportableReport.productSales
        ? _products.length
        : _categories.length;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStringsTr.reportsTitle)),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<ExportableReport>(
                    key: ReportsScreen.reportSelectorKey,
                    initialValue: _report,
                    decoration: const InputDecoration(
                      labelText: AppStringsTr.reportsTitle,
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: ExportableReport.productSales,
                        child: Text(AppStringsTr.reportProductSales),
                      ),
                      DropdownMenuItem(
                        value: ExportableReport.categorySales,
                        child: Text(AppStringsTr.reportCategorySales),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _report = value);
                      unawaited(_load());
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<ReportPeriodKind>(
                    key: const Key('reports_period'),
                    initialValue: _kind,
                    decoration: const InputDecoration(isDense: true),
                    items: [
                      for (final kind in ReportPeriodKind.values)
                        if (kind != ReportPeriodKind.custom)
                          DropdownMenuItem(
                            value: kind,
                            child: Text(
                              AppStringsTr.dashboardPeriodNames[kind.name] ??
                                  kind.name,
                            ),
                          ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _kind = value);
                      unawaited(_load());
                    },
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _locked
                ? Center(
                    child: Padding(
                      key: ReportsScreen.lockedKey,
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
                          const Text(AppStringsTr.financialAccessDescription),
                        ],
                      ),
                    ),
                  )
                : rowCount == 0
                ? Center(
                    child: Text(
                      AppStringsTr.reportEmpty,
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : _table(theme),
          ),
          if (!_locked) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          AppStringsTr.reportRowCount(rowCount),
                          style: theme.textTheme.bodyMedium,
                        ),
                        Text(
                          AppStringsTr.reportExportNotice,
                          style: theme.textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    key: ReportsScreen.exportButtonKey,
                    onPressed: rowCount == 0
                        ? null
                        : () => unawaited(_export()),
                    icon: const Icon(Icons.download),
                    label: const Text(AppStringsTr.reportExportCsv),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _table(ThemeData theme) {
    if (_report == ExportableReport.productSales) {
      return ListView.builder(
        key: ReportsScreen.tableKey,
        itemCount: _products.length,
        itemBuilder: (context, index) {
          final row = _products[index];
          return ListTile(
            key: Key('report_product_${row.productId}'),
            dense: true,
            title: Text(row.name),
            subtitle: Text(
              '${row.unitCount} ${AppStringsTr.reportColumnUnits.toLowerCase()}',
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(MoneyFormatter.format(Money(row.revenueMinor))),
                Text(
                  // REQ-VAT-009 — kâr KDV hariç matrahtan; hesap domain'de.
                  MoneyFormatter.format(Money(row.profitMinor)),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          );
        },
      );
    }

    return ListView.builder(
      key: ReportsScreen.tableKey,
      itemCount: _categories.length,
      itemBuilder: (context, index) {
        final row = _categories[index];
        return ListTile(
          key: Key('report_category_${row.categoryId ?? 0}'),
          dense: true,
          title: Text(row.name),
          subtitle: Text('${row.unitCount}'),
          trailing: Text(MoneyFormatter.format(Money(row.revenueMinor))),
        );
      },
    );
  }
}
