/// Yarım kalmış migration kurtarması — **docs/06 §3 · REQ-MIG-006 ·
/// REQ-DATA-004**
///
/// docs/06 §3 "Açılışta yarım kalmış migration tespiti" dört adım tanımlar:
///
/// > 1. Kullanıcıya durum bildirilir.
/// > 2. Pre-migration snapshot varsa **otomatik geri yükleme önerilir**.
/// > 3. Kullanıcı onaylarsa snapshot geri yüklenir ve migration yeniden denenir.
/// > 4. Onaylamazsa uygulama kapanır (yarım şema ile çalışmaya izin verilmez).
///
/// Bu ekran 1–2'yi gösterir ve 3–4'ü çağırana bırakır.
///
/// ## Neden bir "hata ekranı" değil
///
/// Kullanıcının verisi burada **kaybolmuş değildir** — güncelleme öncesi
/// hâli yedektedir. Çıkışsız bir hata ekranı göstermek, kurtarılabilir bir
/// durumu kurtarılamaz gibi anlatırdı; kullanıcı da veritabanı dosyalarını
/// elle karıştırmaya kalkar ve asıl kaybı o zaman yaşardı.
///
/// ## Snapshot yoksa geri yükleme SUNULMAZ
///
/// Olmayan bir yedeği ima eden bir düğme, basıldığında hata veren bir
/// düğmedir. O durumda ekran ne yapılacağını söyler ve yalnızca kapanır —
/// yarım şemayla çalışmaya izin verilmez (docs/06 §3 adım 4).
library;

import 'package:flutter/material.dart';

import '../../app/l10n/app_strings_tr.dart';

class MigrationRecoveryScreen extends StatefulWidget {
  static const Key restoreButtonKey = Key('migration_recovery_restore');
  static const Key quitButtonKey = Key('migration_recovery_quit');
  static const Key messageKey = Key('migration_recovery_message');

  /// `null` ise geri yükleme sunulmaz (docs/06 §3).
  final String? snapshotPath;

  /// Snapshot'ı geri yükler ve migration'ı yeniden dener.
  ///
  /// Hata durumunda `false` döner; ekran açık kalır ve kullanıcı yine
  /// kapatabilir.
  final Future<bool> Function() onRestore;

  final VoidCallback onQuit;

  const MigrationRecoveryScreen({
    required this.snapshotPath,
    required this.onRestore,
    required this.onQuit,
    super.key,
  });

  @override
  State<MigrationRecoveryScreen> createState() =>
      _MigrationRecoveryScreenState();
}

class _MigrationRecoveryScreenState extends State<MigrationRecoveryScreen> {
  bool _working = false;
  String? _error;

  Future<void> _restore() async {
    if (_working) return;
    setState(() {
      _working = true;
      _error = null;
    });

    final ok = await widget.onRestore();
    if (!mounted) return;
    // Başarılıysa çağıran ekranı değiştirir; burada yalnızca hata durumu
    // ele alınır.
    if (!ok) {
      setState(() {
        _working = false;
        _error = AppStringsTr.migrationRecoveryFailed;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSnapshot = widget.snapshotPath != null;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.settings_backup_restore,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  AppStringsTr.migrationRecoveryTitle,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  key: MigrationRecoveryScreen.messageKey,
                  hasSnapshot
                      ? AppStringsTr.migrationRecoveryBody
                      : AppStringsTr.migrationRecoveryNoSnapshot,
                  textAlign: TextAlign.center,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                if (hasSnapshot)
                  FilledButton(
                    key: MigrationRecoveryScreen.restoreButtonKey,
                    onPressed: _working ? null : _restore,
                    child: Text(
                      _working
                          ? AppStringsTr.migrationRecoveryWorking
                          : AppStringsTr.migrationRecoveryAction,
                    ),
                  ),
                const SizedBox(height: 8),
                TextButton(
                  key: MigrationRecoveryScreen.quitButtonKey,
                  onPressed: _working ? null : widget.onQuit,
                  child: const Text(AppStringsTr.migrationRecoveryQuit),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
