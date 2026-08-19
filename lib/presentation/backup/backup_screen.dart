/// Yedekleme ekranı — **docs/19 §3–§4 · REQ-BKUP-001/007/008/016**
///
/// Ayarlar → Yedekleme. İki işlem barındırır ve ikisi de geri alınamaz
/// sonuçlar doğurur:
///
/// | İşlem | Risk |
/// |---|---|
/// | Yedek Oluştur | Yok — yalnızca okur |
/// | **Yedekten Geri Yükle** | **Mevcut TÜM veriyi değiştirir** |
///
/// Geri yükleme burada **başlatılır** ama tamamlanması uygulamanın yeniden
/// başlatılmasını gerektirir: veritabanı bağlantısı kapatılır ve dosyalar
/// takas edilir (docs/19 §4 adım 12–14). Bağlantıyı yeniden kurup migration
/// çalıştırmak bootstrap'in işidir (docs/03 §6).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../app/l10n/app_strings_tr.dart';
import '../../application/backup/providers.dart';
import '../../application/backup/restore_service.dart';
import '../common/current_user.dart';
import 'restore_confirm_dialog.dart';

/// Kullanıcının yedek dosyası seçmesi — test bunu override eder.
typedef BackupFilePicker = Future<String?> Function();

class BackupScreen extends ConsumerStatefulWidget {
  static const Key createButtonKey = Key('backup_create');
  static const Key restoreButtonKey = Key('backup_restore');
  static const Key listKey = Key('backup_list');
  static const Key lastBackupKey = Key('backup_last');

  /// Dosya seçici — üretimde platform diyaloğu, testte sabit bir yol.
  final BackupFilePicker? filePicker;

  const BackupScreen({this.filePicker, super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  List<File> _backups = const [];
  Duration? _sinceLastBackup;
  bool _busy = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final service = ref.read(backupServiceProvider);
    final backups = service.listBackups();
    final since = await service.timeSinceLastBackup();
    if (!mounted) return;
    setState(() {
      _backups = backups;
      _sinceLastBackup = since;
    });
  }

  Future<void> _create() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final user = await currentUserId(ref);
      final result = await ref
          .read(backupServiceProvider)
          .create(createdBy: user == null ? null : '$user');
      if (!mounted) return;

      setState(() {
        _statusMessage = result.isErr
            ? result.failureOrNull!.userMessage
            : AppStringsTr.backupCreated(
                p.basename(result.valueOrNull!.file.path),
                _formatSize(result.valueOrNull!.sizeBytes),
              );
      });
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// docs/19 §4 — doğrulama → özet → **yazarak onay** → uygulama.
  Future<void> _restore(File file) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      // 1 — DOĞRULAMA. Diske dokunmaz; bozuk yedek burada reddedilir.
      final preview = await ref.read(restoreServiceProvider).validate(file);
      if (!mounted) return;
      if (preview.isErr) {
        setState(() => _statusMessage = preview.failureOrNull!.userMessage);
        return;
      }

      // 2 — ÖZET VE YAZARAK ONAY (REQ-BKUP-007/008).
      final confirmed = await showRestoreConfirmDialog(
        context,
        preview: preview.valueOrNull!,
      );
      if (!mounted || !confirmed) return;

      // 3 — UYGULAMA. Bağlantı kapatma SIRASI servise aittir; bağlantının
      // kendisi application katmanından gelir (rules/01 §1).
      final closeDatabase = ref.read(closeDatabaseProvider);
      final user = await currentUserId(ref);
      final result = await ref
          .read(restoreServiceProvider)
          .apply(
            preview: preview.valueOrNull!,
            confirmation: RestoreService.confirmationPhrase,
            createdBy: user == null ? null : '$user',
            closeDatabase: closeDatabase,
          );
      if (!mounted) return;

      setState(
        () => _statusMessage = result.isErr
            ? result.failureOrNull!.userMessage
            // Yeniden başlatma zorunludur: bağlantı kapandı, dosyalar takas
            // edildi. `finalize` (sayaç düzeltmesi, oturum, audit) bootstrap'te
            // yeni bağlantıyla çalışır (docs/19 §4 adım 16–21).
            : AppStringsTr.restoreSucceeded,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pickAndRestore() async {
    final picked = await (widget.filePicker?.call() ?? _defaultPicker());
    if (!mounted || picked == null) return;
    await _restore(File(picked));
  }

  /// Üretimde platform dosya diyaloğu; şimdilik yedek klasörü listelenir.
  Future<String?> _defaultPicker() async => null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStringsTr.backupTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            key: BackupScreen.lastBackupKey,
            _sinceLastBackup == null
                ? AppStringsTr.backupNeverTaken
                : AppStringsTr.backupLastTaken(_ago(_sinceLastBackup!)),
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  key: BackupScreen.createButtonKey,
                  onPressed: _busy ? null : () => unawaited(_create()),
                  icon: const Icon(Icons.save_outlined),
                  label: Text(
                    _busy
                        ? AppStringsTr.backupCreating
                        : AppStringsTr.backupCreateAction,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  key: BackupScreen.restoreButtonKey,
                  onPressed: _busy ? null : () => unawaited(_pickAndRestore()),
                  icon: const Icon(Icons.restore),
                  label: const Text(AppStringsTr.backupRestoreAction),
                ),
              ),
            ],
          ),
          if (_statusMessage != null) ...[
            const SizedBox(height: 12),
            Text(
              _statusMessage!,
              key: const Key('backup_status'),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          const SizedBox(height: 8),
          Text(AppStringsTr.backupAutoNotice, style: theme.textTheme.bodySmall),
          const Divider(height: 32),
          Text(
            AppStringsTr.backupListTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (_backups.isEmpty)
            Text(AppStringsTr.backupListEmpty, style: theme.textTheme.bodySmall)
          else
            Column(
              key: BackupScreen.listKey,
              children: [
                for (final backup in _backups)
                  ListTile(
                    key: Key('backup_file_${p.basename(backup.path)}'),
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(p.basename(backup.path)),
                    subtitle: Text(_formatSize(backup.lengthSync())),
                    trailing: TextButton(
                      key: Key('backup_restore_${p.basename(backup.path)}'),
                      onPressed: _busy
                          ? null
                          : () => unawaited(_restore(backup)),
                      child: const Text(AppStringsTr.restoreConfirmAction),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  static String _ago(Duration elapsed) {
    if (elapsed.inDays > 0) return '${elapsed.inDays} gün önce';
    if (elapsed.inHours > 0) return '${elapsed.inHours} saat önce';
    if (elapsed.inMinutes > 0) return '${elapsed.inMinutes} dakika önce';
    return 'az önce';
  }
}

/// REQ-BKUP-016 — satış ekranının üstündeki yedek hatırlatma çubuğu.
///
/// docs/19 §3: 7 günden uzun süredir yedek alınmadıysa **sarı**, 30 günü
/// geçerse **kırmızı** ve daha belirgin. Çubuk kapatılabilir ama ertesi gün
/// geri gelir — bu yüzden kapatma yalnızca bu oturumu etkiler.
class BackupReminderBanner extends ConsumerStatefulWidget {
  static const Key bannerKey = Key('backup_reminder_banner');
  static const Key actionKey = Key('backup_reminder_action');
  static const Key dismissKey = Key('backup_reminder_dismiss');

  const BackupReminderBanner({super.key});

  @override
  ConsumerState<BackupReminderBanner> createState() =>
      _BackupReminderBannerState();
}

class _BackupReminderBannerState extends ConsumerState<BackupReminderBanner> {
  bool _dismissed = false;
  bool _needed = false;
  bool _overdue = false;
  Duration? _elapsed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
  }

  Future<void> _check() async {
    final service = ref.read(backupServiceProvider);
    final needed = await service.needsBackupReminder();
    final overdue = await service.isBackupOverdue();
    final elapsed = await service.timeSinceLastBackup();
    if (!mounted) return;
    setState(() {
      _needed = needed;
      _overdue = overdue;
      _elapsed = elapsed;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_needed || _dismissed) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final color = _overdue
        ? theme.colorScheme.error
        : theme.colorScheme.tertiary;

    return Material(
      key: BackupReminderBanner.bannerKey,
      color: color.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _elapsed == null
                    ? AppStringsTr.backupReminderNever
                    : AppStringsTr.backupReminder(_elapsed!.inDays),
                style: TextStyle(
                  color: color,
                  fontWeight: _overdue ? FontWeight.bold : null,
                ),
              ),
            ),
            TextButton(
              key: BackupReminderBanner.actionKey,
              onPressed: () => unawaited(
                Navigator.of(
                  context,
                ).pushNamed('/backup').then((_) => _check()),
              ),
              child: const Text(AppStringsTr.backupReminderAction),
            ),
            IconButton(
              key: BackupReminderBanner.dismissKey,
              tooltip: AppStringsTr.backupReminderDismiss,
              icon: const Icon(Icons.close, size: 18),
              // Yalnızca bu oturumu etkiler; ertesi gün geri gelir
              // (docs/19 §3).
              onPressed: () => setState(() => _dismissed = true),
            ),
          ],
        ),
      ),
    );
  }
}
