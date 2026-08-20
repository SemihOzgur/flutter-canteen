/// Satış geçmişi ve detayı — **docs/12 §7 · docs/14 · REQ-SALE-010**
///
/// İptal ve iade **buradan** başlatılır (docs/14 §3–§4). Düğmelerin açık olup
/// olmadığına ekran karar vermez: `ReturnService.stateOf` sorar ve kural
/// `SaleStatusRules` içindedir (rules/01 §2).
///
/// ## Satış kaydı SİLİNEMEZ
///
/// REQ-RET-001 · BR-GEN-002: bu ekranda **"Sil" eylemi yoktur** ve
/// olmayacaktır. İptal edilmiş satış listede görünmeye devam eder; yalnızca
/// durumu değişir.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/sales/providers.dart';
import '../../application/sales/return_service.dart';
import '../../core/money/money_formatter.dart';
import '../../domain/enums/sale_status.dart';
import '../../domain/models/sale.dart';
import '../common/current_user.dart';
import 'return_dialogs.dart';

class SaleHistoryScreen extends ConsumerStatefulWidget {
  static const Key listKey = Key('sale_history_list');
  static const Key searchKey = Key('sale_history_search');
  static const Key statusFilterKey = Key('sale_history_status');

  const SaleHistoryScreen({super.key});

  @override
  ConsumerState<SaleHistoryScreen> createState() => _SaleHistoryScreenState();
}

class _SaleHistoryScreenState extends ConsumerState<SaleHistoryScreen> {
  final TextEditingController _search = TextEditingController();
  List<Sale> _sales = const [];
  SaleStatus? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final sales = await ref
        .read(saleServiceProvider)
        .history(status: _status, saleNumber: _search.text, limit: 100);
    if (!mounted) return;
    setState(() {
      _sales = sales;
      _loading = false;
    });
  }

  Future<void> _openDetail(Sale sale) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SaleDetailScreen(saleId: sale.id),
      ),
    );
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStringsTr.saleHistoryTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    key: SaleHistoryScreen.searchKey,
                    controller: _search,
                    decoration: const InputDecoration(
                      hintText: AppStringsTr.saleHistorySearchHint,
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (_) => unawaited(_load()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<SaleStatus?>(
                    key: SaleHistoryScreen.statusFilterKey,
                    initialValue: _status,
                    decoration: const InputDecoration(
                      labelText: AppStringsTr.saleHistoryAllStatuses,
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem(
                        child: Text(AppStringsTr.saleHistoryAllStatuses),
                      ),
                      for (final status in SaleStatus.values)
                        DropdownMenuItem(
                          value: status,
                          child: Text(statusName(status)),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => _status = value);
                      unawaited(_load());
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _sales.isEmpty
                ? Center(
                    child: Text(
                      AppStringsTr.saleHistoryEmpty,
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    key: SaleHistoryScreen.listKey,
                    itemCount: _sales.length,
                    itemBuilder: (context, index) {
                      final sale = _sales[index];
                      return ListTile(
                        key: Key('sale_history_${sale.id}'),
                        title: Text(sale.saleNumber),
                        subtitle: Text(
                          '${statusName(sale.status)} · '
                          '${sale.itemCount} satır · ${sale.unitCount} adet',
                          style: sale.status == SaleStatus.cancelled
                              ? TextStyle(color: theme.colorScheme.error)
                              : null,
                        ),
                        trailing: Text(
                          MoneyFormatter.format(sale.grandTotal),
                          style: theme.textTheme.titleMedium,
                        ),
                        onTap: () => unawaited(_openDetail(sale)),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

String statusName(SaleStatus status) =>
    AppStringsTr.saleStatusNames[status.wire] ?? status.wire;

/// Satış detayı — docs/12 §7 · docs/14 §3–§4.
class SaleDetailScreen extends ConsumerStatefulWidget {
  static const Key cancelButtonKey = Key('sale_detail_cancel');
  static const Key returnButtonKey = Key('sale_detail_return');

  final int saleId;

  const SaleDetailScreen({required this.saleId, super.key});

  @override
  ConsumerState<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends ConsumerState<SaleDetailScreen> {
  SaleReturnState? _state;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final state = await ref.read(returnServiceProvider).stateOf(widget.saleId);
    if (!mounted) return;
    setState(() => _state = state.valueOrNull);
  }

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _cancel() async {
    final state = _state;
    if (state == null || _busy) return;

    final reason = await showCancelSaleDialog(
      context,
      saleNumber: state.sale.saleNumber,
      total: state.sale.grandTotal,
      itemCount: state.sale.itemCount,
    );
    if (!mounted || reason == null) return;

    final userId = await currentUserId(ref);
    if (!mounted || userId == null) return;

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(returnServiceProvider)
          .cancelSale(saleId: widget.saleId, userId: userId, reason: reason);
      _report(
        result.isErr
            ? result.failureOrNull!.userMessage
            : AppStringsTr.saleCancelled,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _createReturn() async {
    final state = _state;
    if (state == null || _busy) return;

    final request = await showReturnDialog(
      context,
      saleNumber: state.sale.saleNumber,
      items: state.items,
    );
    if (!mounted || request == null) return;

    final userId = await currentUserId(ref);
    if (!mounted || userId == null) return;

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(returnServiceProvider)
          .createReturn(
            saleId: widget.saleId,
            userId: userId,
            lines: request.lines,
            reason: request.reason,
          );
      _report(
        result.isErr
            ? result.failureOrNull!.userMessage
            : AppStringsTr.saleReturnSaved,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = _state;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          state?.sale.saleNumber ?? AppStringsTr.saleHistoryDetailTitle,
        ),
      ),
      body: state == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  statusName(state.sale.status),
                  key: const Key('sale_detail_status'),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _summary(theme, state),
                const SizedBox(height: 24),
                Text(
                  AppStringsTr.saleHistoryItems,
                  style: theme.textTheme.titleSmall,
                ),
                for (final item in state.items)
                  ListTile(
                    key: Key('sale_detail_item_${item.id}'),
                    dense: true,
                    title: Text(item.productNameSnapshot),
                    subtitle: Text(
                      '${MoneyFormatter.format(item.unitPrice)} × '
                      '${item.quantity}'
                      '${item.returnedQuantity > 0 ? " · ${item.returnedQuantity} ${AppStringsTr.saleHistoryReturnedBadge}" : ""}',
                    ),
                    trailing: Text(MoneyFormatter.format(item.lineTotal)),
                  ),
                const SizedBox(height: 24),
                Text(
                  AppStringsTr.saleHistoryReturns,
                  style: theme.textTheme.titleSmall,
                ),
                if (state.returns.isEmpty)
                  const Text(AppStringsTr.saleHistoryNoReturns)
                else
                  for (final value in state.returns)
                    ListTile(
                      key: Key('sale_detail_return_${value.id}'),
                      dense: true,
                      title: Text(MoneyFormatter.format(value.total)),
                      subtitle: Text(value.reason ?? ''),
                    ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: SaleDetailScreen.cancelButtonKey,
                        // BR-RET-001 · BR-RET-006 — karar servisindedir.
                        onPressed: state.canCancel && !_busy ? _cancel : null,
                        child: const Text(AppStringsTr.saleCancelAction),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: SaleDetailScreen.returnButtonKey,
                        onPressed: state.canReturn && !_busy
                            ? _createReturn
                            : null,
                        child: const Text(AppStringsTr.saleReturnAction),
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _summary(ThemeData theme, SaleReturnState state) {
    final sale = state.sale;
    Widget row(String label, String value, {Key? key}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium),
          Text(value, key: key, style: theme.textTheme.bodyMedium),
        ],
      ),
    );

    return Column(
      children: [
        row(AppStringsTr.saleSubtotal, MoneyFormatter.format(sale.subtotal)),
        row(AppStringsTr.saleVat, MoneyFormatter.format(sale.vatTotal)),
        row(
          AppStringsTr.saleHistoryCost,
          MoneyFormatter.format(sale.costTotal),
        ),
        // rules/05 §3 — kâr UI'da HESAPLANMAZ; matrah ve maliyet zaten
        // domain tarafından yazılmıştır, burada yalnızca farkları gösterilir.
        row(
          AppStringsTr.saleHistoryProfit,
          MoneyFormatter.format(sale.subtotal - sale.costTotal),
          key: const Key('sale_detail_profit'),
        ),
        if (sale.cashReceived != null) ...[
          row(
            AppStringsTr.saleHistoryCash,
            MoneyFormatter.format(sale.cashReceived!),
          ),
          row(
            AppStringsTr.saleHistoryChange,
            MoneyFormatter.format(sale.change ?? sale.cashReceived!),
          ),
        ],
        if (state.returns.isNotEmpty)
          row(
            AppStringsTr.saleHistoryReturns,
            MoneyFormatter.format(state.returnedTotal),
            key: const Key('sale_detail_returned_total'),
          ),
        const Divider(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              AppStringsTr.saleGrandTotal,
              style: theme.textTheme.titleMedium,
            ),
            Text(
              MoneyFormatter.format(sale.grandTotal),
              key: const Key('sale_detail_total'),
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ],
    );
  }
}
