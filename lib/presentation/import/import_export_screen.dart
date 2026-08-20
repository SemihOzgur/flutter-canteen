/// İçe / dışa aktarma — **docs/20 · REQ-IMEX-002…010**
///
/// ## Önizleme atlanamaz — REQ-IMEX-007
///
/// Akış tek yönlüdür: dosya seç → önizle → **onayla** → uygula. "İçe Aktar"
/// düğmesi önizleme oluşmadan hiç görünmez; servis de `confirmed: true`
/// olmadan çalışmaz. İki katman bilinçlidir — ekran bir gezinme ayrıntısıdır.
///
/// ## docs/20 §1 — asla import edilemeyenler ekranda YAZILI
///
/// Satış, satış satırı ve stok hareketi import edilemez. Bunu yalnızca kodda
/// engellemek yetmez: kullanıcı "neden yok?" diye aramadan önce cevabı
/// görmelidir.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/import/data_export_service.dart';
import '../../application/import/product_import_service.dart';
import '../../application/import/providers.dart';
import '../../application/reporting/providers.dart';
import '../../data/files/csv_writer.dart';
import '../../domain/services/product_import_rules.dart';
import '../common/current_user.dart';
import '../common/save_location_picker.dart';

/// Dosya içeriğini okur — testte override edilir.
typedef ImportFileReader = Future<({String name, String contents})?> Function();

class ImportExportScreen extends ConsumerStatefulWidget {
  static const Key pickFileKey = Key('import_pick_file');
  static const Key templateKey = Key('import_template');
  static const Key confirmKey = Key('import_confirm');
  static const Key previewKey = Key('import_preview');
  static const Key errorsCsvKey = Key('import_errors_csv');
  static const Key policyKey = Key('import_policy');

  /// Test ve platform ayrımı için.
  final ImportFileReader? fileReader;
  final SaveLocationPicker? savePicker;

  const ImportExportScreen({this.fileReader, this.savePicker, super.key});

  @override
  ConsumerState<ImportExportScreen> createState() => _ImportExportScreenState();
}

class _ImportExportScreenState extends ConsumerState<ImportExportScreen> {
  DuplicateBarcodePolicy _policy = DuplicateBarcodePolicy.skip;
  String? _fileName;
  String? _contents;
  ImportPreview? _preview;
  bool _busy = false;
  bool _onlyProblems = false;

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save(String suggestedName, String contents, String done) async {
    final picker = widget.savePicker ?? pickSaveLocation;
    final path = await picker(suggestedName);
    if (!mounted) return;
    if (path == null) {
      _notify(AppStringsTr.exportCancelled);
      return;
    }
    final written = await ref.read(reportFileWriterProvider)(path, contents);
    if (!mounted) return;
    _notify(written ? done : AppStringsTr.unexpectedErrorMessage);
  }

  /// REQ-IMEX-002 — kullanıcı önce **doğru şablonu** alır.
  Future<void> _downloadTemplate() => _save(
    'urun_sablonu.csv',
    DataExportService.template(),
    AppStringsTr.importTemplateSaved,
  );

  Future<void> _pickFile() async {
    final reader = widget.fileReader;
    if (reader == null) return;
    final file = await reader();
    if (!mounted || file == null) return;
    setState(() {
      _fileName = file.name;
      _contents = file.contents;
      _preview = null;
    });
    await _buildPreview();
  }

  /// docs/20 §5 — önizleme **hiçbir şey yazmaz.**
  Future<void> _buildPreview() async {
    final contents = _contents;
    if (contents == null) return;

    setState(() => _busy = true);
    try {
      final parsedHeader = contents.split('\n').first.split(RegExp(r'[;,\t]'));
      final result = await ref
          .read(productImportServiceProvider)
          .preview(
            contents: contents,
            mapping: ProductImportRules.autoMap(parsedHeader),
            policy: _policy,
          );
      if (!mounted) return;
      if (result.isErr) {
        setState(() => _preview = null);
        _notify(result.failureOrNull!.userMessage);
        return;
      }
      setState(() => _preview = result.valueOrNull);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// REQ-IMEX-007 — onay burada verilir.
  Future<void> _apply() async {
    final preview = _preview;
    if (preview == null || _busy) return;

    final userId = await currentUserId(ref);
    if (!mounted || userId == null) return;

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(productImportServiceProvider)
          .apply(preview: preview, userId: userId, confirmed: true);
      if (!mounted) return;
      if (result.isErr) {
        _notify(result.failureOrNull!.userMessage);
        return;
      }
      final value = result.valueOrNull!;
      setState(() {
        _preview = null;
        _fileName = null;
        _contents = null;
      });
      _notify(
        AppStringsTr.importDone(value.created, value.updated, value.skipped),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// REQ-IMEX-006 — hatalı satırlar CSV olarak indirilebilir.
  ///
  /// Yüzlerce satırlık bir dosyada hataları ekrandan tek tek not almak
  /// gerçekçi değildir (docs/20 §5).
  Future<void> _downloadErrors() async {
    final preview = _preview;
    if (preview == null) return;

    final csv = CsvWriter.encode([
      const ['Satır', 'Ürün adı', 'Sorun'],
      for (final row in preview.rejected)
        [
          row.lineNumber,
          row.name,
          row.issues.map((issue) => issue.message).join(' · '),
        ],
    ]);
    await _save('import_hatalari.csv', csv, AppStringsTr.importErrorsSaved);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = _preview;

    return Scaffold(
      appBar: AppBar(title: const Text(AppStringsTr.importExportTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            AppStringsTr.importPreviewTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            AppStringsTr.importForbiddenNotice,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton.icon(
                key: ImportExportScreen.templateKey,
                onPressed: () => unawaited(_downloadTemplate()),
                icon: const Icon(Icons.description_outlined),
                label: const Text(AppStringsTr.importTemplateDownload),
              ),
              FilledButton.icon(
                key: ImportExportScreen.pickFileKey,
                onPressed: _busy ? null : () => unawaited(_pickFile()),
                icon: const Icon(Icons.upload_file),
                label: const Text(AppStringsTr.importPickFile),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // docs/20 §4.1 — politika import ÖNCESİ seçilir.
          DropdownButtonFormField<DuplicateBarcodePolicy>(
            key: ImportExportScreen.policyKey,
            initialValue: _policy,
            decoration: const InputDecoration(
              labelText: AppStringsTr.importPolicyTitle,
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(
                value: DuplicateBarcodePolicy.skip,
                child: Text(AppStringsTr.importPolicySkip),
              ),
              DropdownMenuItem(
                value: DuplicateBarcodePolicy.updateExisting,
                child: Text(AppStringsTr.importPolicyUpdate),
              ),
              DropdownMenuItem(
                value: DuplicateBarcodePolicy.cancel,
                child: Text(AppStringsTr.importPolicyCancel),
              ),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() => _policy = value);
              unawaited(_buildPreview());
            },
          ),
          const SizedBox(height: 12),
          Text(
            _fileName == null
                ? AppStringsTr.importNoFile
                : AppStringsTr.importFileSelected(
                    _fileName!,
                    preview?.rows.length ?? 0,
                    preview?.separator ?? '',
                  ),
            style: theme.textTheme.bodyMedium,
          ),
          if (preview != null) ...[
            const SizedBox(height: 16),
            _previewSummary(theme, preview),
          ],
          const Divider(height: 32),
          Text(AppStringsTr.exportTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            AppStringsTr.exportRoundTripNotice,
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            children: [
              for (final target in DataExport.values)
                OutlinedButton(
                  key: Key('export_${target.name}'),
                  onPressed: () => unawaited(_export(target)),
                  child: Text(switch (target) {
                    DataExport.products => AppStringsTr.exportProducts,
                    DataExport.categories => AppStringsTr.exportCategories,
                    DataExport.suppliers => AppStringsTr.exportSuppliers,
                  }),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _export(DataExport target) async {
    final csv = await ref.read(dataExportServiceProvider).exportCsv(target);
    if (!mounted) return;
    await _save('${target.name}.csv', csv, AppStringsTr.exportSaved);
  }

  Widget _previewSummary(ThemeData theme, ImportPreview preview) {
    final visible = _onlyProblems
        ? preview.rows.where((row) => row.issues.isNotEmpty).toList()
        : preview.rows;

    return Column(
      key: ImportExportScreen.previewKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('✅ ${AppStringsTr.importPreviewCreate(preview.createCount)}'),
        if (preview.updateCount > 0)
          Text('🔄 ${AppStringsTr.importPreviewUpdate(preview.updateCount)}'),
        if (preview.warningCount > 0)
          Text('🟡 ${AppStringsTr.importPreviewWarning(preview.warningCount)}'),
        if (preview.rejectedCount > 0)
          Text(
            '🔴 ${AppStringsTr.importPreviewRejected(preview.rejectedCount)}',
            key: const Key('import_rejected_count'),
          ),
        if (preview.newCategories.isNotEmpty || preview.newSuppliers.isNotEmpty)
          Text(
            '➕ ${AppStringsTr.importPreviewNew(preview.newCategories.length, preview.newSuppliers.length)}',
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            ChoiceChip(
              label: const Text(AppStringsTr.importFilterAll),
              selected: !_onlyProblems,
              onSelected: (_) => setState(() => _onlyProblems = false),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              key: const Key('import_filter_problems'),
              label: const Text(AppStringsTr.importFilterProblems),
              selected: _onlyProblems,
              onSelected: (_) => setState(() => _onlyProblems = true),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 240,
          child: ListView(
            children: [
              for (final row in visible)
                ListTile(
                  key: Key('import_row_${row.lineNumber}'),
                  dense: true,
                  leading: Text('${row.lineNumber}'),
                  title: Text(row.name.isEmpty ? '(boş)' : row.name),
                  subtitle: row.issues.isEmpty
                      ? null
                      : Text(
                          row.issues.map((issue) => '$issue').join(' · '),
                          style: TextStyle(
                            color: row.isRejected
                                ? theme.colorScheme.error
                                : theme.colorScheme.tertiary,
                          ),
                        ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (preview.rejectedCount > 0)
              OutlinedButton(
                key: ImportExportScreen.errorsCsvKey,
                onPressed: () => unawaited(_downloadErrors()),
                child: const Text(AppStringsTr.importErrorsDownload),
              ),
            const Spacer(),
            FilledButton(
              key: ImportExportScreen.confirmKey,
              // REQ-IMEX-007 — onay; geçerli satır yoksa pasif.
              onPressed: preview.hasAnything && !_busy
                  ? () => unawaited(_apply())
                  : null,
              child: Text(
                AppStringsTr.importConfirmAction(preview.accepted.length),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
