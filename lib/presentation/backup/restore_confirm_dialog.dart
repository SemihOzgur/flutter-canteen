/// Geri yükleme onayı — **docs/19 §4 · REQ-BKUP-007/008/020**
///
/// ## Yazarak onay
///
/// REQ-BKUP-008: geri alınamaz bir işlem için **kasıtlı bir sürtünmedir.**
/// Kullanıcı `GERİ YÜKLE` yazmadan düğme etkinleşmez. Tek tık ile tüm satış
/// geçmişinin değişmesi kabul edilemez.
///
/// ## Ne kaybolacağı AÇIKÇA gösterilir
///
/// docs/19 §4: *"Özellikle 'şu anki veri daha fazla kayıt içeriyor' durumu
/// **açıkça vurgulanır**."* Karşılaştırma tablosu ve kaybolacak satış sayısı
/// bu yüzden vardır — kullanıcı neyi feda ettiğini görmeden onaylayamaz.
library;

import 'package:flutter/material.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/backup/restore_service.dart';

/// `true` → kullanıcı yazarak onayladı. `Esc`/bariyer/Vazgeç → `false`.
Future<bool> showRestoreConfirmDialog(
  BuildContext context, {
  required RestorePreview preview,
}) async {
  final result = await showDialog<bool>(
    context: context,
    // Yanlışlıkla dışarı tıklayıp "onayladım" sanma ihtimali yoktur; yine de
    // bariyer kapanışı `null` döner ve `?? false` ile reddedilir.
    builder: (dialogContext) => _RestoreConfirmDialog(preview: preview),
  );
  return result ?? false;
}

class _RestoreConfirmDialog extends StatefulWidget {
  final RestorePreview preview;

  const _RestoreConfirmDialog({required this.preview});

  @override
  State<_RestoreConfirmDialog> createState() => _RestoreConfirmDialogState();
}

class _RestoreConfirmDialogState extends State<_RestoreConfirmDialog> {
  final TextEditingController _confirmation = TextEditingController();

  @override
  void dispose() {
    _confirmation.dispose();
    super.dispose();
  }

  bool get _confirmed =>
      _confirmation.text.trim() == RestoreService.confirmationPhrase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final preview = widget.preview;
    final backup = preview.metadata.counts;
    final current = preview.current;

    return AlertDialog(
      key: const Key('restore_confirm_dialog'),
      title: const Text(AppStringsTr.restoreTitle),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStringsTr.restoreBackupDate(
                  _formatDate(preview.metadata.createdAtUtc),
                ),
              ),
              Text(
                AppStringsTr.restoreBackupAuthor(
                  preview.metadata.createdBy ?? '—',
                  preview.metadata.appVersion,
                ),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              _comparisonHeader(theme),
              _comparisonRow(
                AppStringsTr.restoreRowProducts,
                backup.products,
                current.products,
              ),
              _comparisonRow(
                AppStringsTr.restoreRowSales,
                backup.sales,
                current.sales,
              ),
              _comparisonRow(
                AppStringsTr.restoreRowStockMovements,
                backup.stockMovements,
                current.stockMovements,
              ),
              _comparisonRow(
                AppStringsTr.restoreRowImages,
                backup.images,
                current.images,
              ),
              // docs/19 §4 — kaybolacak satış AÇIKÇA vurgulanır.
              if (preview.currentHasMoreSales) ...[
                const SizedBox(height: 8),
                Text(
                  AppStringsTr.restoreSalesAtRisk(preview.salesAtRisk),
                  key: const Key('restore_sales_at_risk'),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
              if (preview.migrationRequired) ...[
                const SizedBox(height: 8),
                const Text(
                  AppStringsTr.restoreMigrationNotice,
                  key: Key('restore_migration_notice'),
                ),
              ],
              // REQ-BKUP-018 — eksik görsel engellemez, bilgilendirir.
              if (preview.missingImageCount > 0) ...[
                const SizedBox(height: 8),
                Text(
                  AppStringsTr.restoreMissingImages(preview.missingImageCount),
                  key: const Key('restore_missing_images'),
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: 16),
              Text(
                AppStringsTr.restoreWarning,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              // REQ-BKUP-020 — parolaların değişeceği ÖNCEDEN söylenir.
              const Text(
                AppStringsTr.restorePasswordWarning,
                key: Key('restore_password_warning'),
              ),
              const SizedBox(height: 16),
              Text(
                AppStringsTr.restoreConfirmPrompt(
                  RestoreService.confirmationPhrase,
                ),
              ),
              const SizedBox(height: 4),
              TextField(
                key: const Key('restore_confirm_field'),
                controller: _confirmation,
                autofocus: true,
                decoration: const InputDecoration(border: OutlineInputBorder()),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(AppStringsTr.cancelAction),
        ),
        FilledButton(
          key: const Key('restore_confirm_submit'),
          // REQ-BKUP-008 — metin eşleşmeden düğme ETKİNLEŞMEZ.
          onPressed: _confirmed ? () => Navigator.of(context).pop(true) : null,
          child: const Text(AppStringsTr.restoreConfirmAction),
        ),
      ],
    );
  }

  Widget _comparisonHeader(ThemeData theme) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(
      children: [
        const Expanded(flex: 3, child: SizedBox()),
        Expanded(
          flex: 2,
          child: Text(
            AppStringsTr.restoreColumnBackup,
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall,
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            AppStringsTr.restoreColumnCurrent,
            textAlign: TextAlign.right,
            style: theme.textTheme.labelSmall,
          ),
        ),
      ],
    ),
  );

  Widget _comparisonRow(String label, int backup, int current) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      children: [
        Expanded(flex: 3, child: Text(label)),
        Expanded(flex: 2, child: Text('$backup', textAlign: TextAlign.right)),
        Expanded(flex: 2, child: Text('$current', textAlign: TextAlign.right)),
      ],
    ),
  );

  static String _formatDate(DateTime utc) {
    final local = utc.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)}.${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
