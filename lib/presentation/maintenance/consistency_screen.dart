/// Veri tutarlılığı kontrolü — **docs/24 §3.3 · REQ-DATA-006/007 ·
/// REQ-STOCK-012 · REQ-DB-008**
///
/// ## Otomatik düzeltme YOKTUR
///
/// rules/03 §2: sapma bulunduğunda **hiçbir şey değiştirilmez**; rapor
/// gösterilir. Düzeltme yalnızca kullanıcının bastığı düğmeyle ve gerçek
/// miktarı **onaylamasıyla** olur (OD-026) — sessizce düzeltmek sapmanın
/// sebebini gizler.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/maintenance/consistency_report.dart';
import '../../application/maintenance/providers.dart';
import '../common/current_user.dart';

class ConsistencyScreen extends ConsumerStatefulWidget {
  static const Key runButtonKey = Key('consistency_run');
  static const Key resultKey = Key('consistency_result');

  const ConsistencyScreen({super.key});

  @override
  ConsumerState<ConsistencyScreen> createState() => _ConsistencyScreenState();
}

class _ConsistencyScreenState extends ConsumerState<ConsistencyScreen> {
  ConsistencyReport? _report;
  bool _running = false;

  Future<void> _run() async {
    setState(() => _running = true);
    try {
      final report = await ref.read(consistencyServiceProvider).run();
      if (!mounted) return;
      setState(() => _report = report);
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// REQ-DATA-007 · OD-026 — kullanıcı **gerçek miktarı** onaylar.
  Future<void> _repair(ConsistencyFinding finding) async {
    final quantity = await showDialog<int>(
      context: context,
      builder: (_) => _RepairDialog(finding: finding),
    );
    if (!mounted || quantity == null) return;

    final userId = await currentUserId(ref);
    if (!mounted || userId == null) return;

    final result = await ref
        .read(consistencyServiceProvider)
        .repairStockQuantity(
          finding: finding,
          userId: userId,
          reason: AppStringsTr.consistencyTitle,
          physicalQuantity: quantity,
        );
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.isErr
                ? result.failureOrNull!.userMessage
                : AppStringsTr.consistencyRepaired,
          ),
        ),
      );
    if (result.isOk) await _run();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final report = _report;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStringsTr.consistencyTitle)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              key: ConsistencyScreen.runButtonKey,
              onPressed: _running ? null : () => unawaited(_run()),
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(
                _running
                    ? AppStringsTr.consistencyRunning
                    : AppStringsTr.consistencyRun,
              ),
            ),
            const SizedBox(height: 16),
            if (report != null)
              Expanded(
                child: Column(
                  key: ConsistencyScreen.resultKey,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      AppStringsTr.consistencySummary(
                        report.findings.length,
                        report.productsChecked,
                        report.salesChecked,
                      ),
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: report.isClean
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.check_circle_outline,
                                    size: 48,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(height: 8),
                                  const Text(AppStringsTr.consistencyClean),
                                ],
                              ),
                            )
                          : ListView(
                              children: [
                                for (final finding in report.findings)
                                  _findingTile(theme, finding),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _findingTile(ThemeData theme, ConsistencyFinding finding) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        key: Key(
          'consistency_finding_${finding.check.name}_${finding.entityId ?? 0}',
        ),
        leading: Icon(
          Icons.report_problem_outlined,
          color: theme.colorScheme.error,
        ),
        title: Text(
          AppStringsTr.consistencyCheckNames[finding.check.name] ??
              finding.check.name,
        ),
        subtitle: Text(
          '${finding.label ?? ""}\n'
          '${AppStringsTr.consistencyExpected}: ${finding.expected} · '
          '${AppStringsTr.consistencyActual}: ${finding.actual}',
        ),
        isThreeLine: true,
        trailing: finding.isRepairable
            ? TextButton(
                key: Key('consistency_repair_${finding.entityId}'),
                onPressed: () => unawaited(_repair(finding)),
                child: const Text(AppStringsTr.consistencyRepair),
              )
            // Düzeltilemeyen sapma için düğme SUNULMAZ — bozulmuş bir satış
            // toplamı defter mantığıyla kapatılamaz.
            : Text(
                AppStringsTr.consistencyNotRepairable,
                style: theme.textTheme.labelSmall,
              ),
      ),
    );
  }
}

class _RepairDialog extends StatefulWidget {
  final ConsistencyFinding finding;

  const _RepairDialog({required this.finding});

  @override
  State<_RepairDialog> createState() => _RepairDialogState();
}

class _RepairDialogState extends State<_RepairDialog> {
  late final TextEditingController _controller = TextEditingController(
    // Varsayılan **defterin** değeridir: defter otoritedir (BR-STOCK-001).
    text: widget.finding.expected,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final quantity = int.tryParse(_controller.text.trim());
    if (quantity == null) {
      setState(() => _error = AppStringsTr.stockQuantityInvalid);
      return;
    }
    Navigator.of(context).pop(quantity);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('consistency_repair_dialog'),
      title: const Text(AppStringsTr.consistencyRepairTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStringsTr.consistencyRepairBody(
                widget.finding.label ?? '',
                widget.finding.expected,
                widget.finding.actual,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('consistency_repair_quantity'),
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: AppStringsTr.consistencyRepairQuantity,
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStringsTr.cancelAction),
        ),
        FilledButton(
          key: const Key('consistency_repair_submit'),
          onPressed: _submit,
          child: const Text(AppStringsTr.consistencyRepair),
        ),
      ],
    );
  }
}
