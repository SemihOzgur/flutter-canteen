/// Yönetim ekranlarının **gezinme katmanı kapısı** — OD-030 · BR-AUTH-018 ·
/// REQ-AUTH-030.
///
/// ## Neden rotanın içinde, çağıranın içinde değil
///
/// Ana ekran kilitli kutuları zaten gizler (REQ-AUTH-029) ve kilitli bir kutuya
/// basıldığında parolayı **önce** sorar. Ama bu bir *gezinme ayrıntısıdır* ve
/// unutulabilir: yeni bir ekran, yeni bir kısayol veya `pushNamed` çağrısı
/// eklendiğinde kapı sessizce atlanır. Kapı rota tanımının içinde olduğunda
/// atlanması için **bilinçli olarak sökülmesi** gerekir — desen
/// `FinancialGate`'in servis katmanındaki deseniyle aynıdır.
///
/// ## Kilitliyken çocuk widget KURULMAZ
///
/// [builder] yalnızca kilit açıkken çağrılır. Ekran hiç kurulmadığı için o
/// ekranın veri yükleyicisi de hiç başlamaz — kapı görsel bir perde değildir
/// (`rules/04 §4`).
///
/// ## Bu kapı BR-AUTH-012'nin yerine geçmez
///
/// Dashboard ve rapor **sorguları** ayrıca `FinancialAccessService.guard`
/// üzerinden geçmeye devam eder (Katman 1). Bu dosya yalnızca Katman 2'dir:
/// ekranın açılmasını engeller.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/auth/providers.dart';
import 'financial_access_dialog.dart';

class AdminGate extends ConsumerStatefulWidget {
  /// Test için sabit anahtarlar.
  static const Key noticeKey = Key('admin_gate_notice');
  static const Key unlockButtonKey = Key('admin_gate_unlock');
  static const Key backButtonKey = Key('admin_gate_back');

  /// Kilit **açıksa** çağrılır; kapalıyken hiç çağrılmaz.
  final WidgetBuilder builder;

  const AdminGate({super.key, required this.builder});

  @override
  ConsumerState<AdminGate> createState() => _AdminGateState();
}

class _AdminGateState extends ConsumerState<AdminGate> {
  /// Otomatik parola sorusu bir kez sorulur: kullanıcı vazgeçtiyse dialog
  /// yeniden açılmamalıdır (aksi hâlde `Esc` ile kapatılamayan bir döngü olur).
  bool _asked = false;

  @override
  void initState() {
    super.initState();
    // Kilit kapalıyken kullanıcı rotaya geldiyse (kısayol, doğrudan `pushNamed`)
    // parola **burada** sorulur; ekran açılmaz.
    if (!ref.read(financialAccessProvider).isUnlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _ask());
    }
  }

  Future<void> _ask() async {
    if (_asked || !mounted) return;
    _asked = true;

    final unlocked = await ensureFinancialAccess(context, ref);
    if (!mounted) return;

    if (unlocked) {
      setState(() {});
      return;
    }

    // EC-DASH-003 · EC-DASH-016: vazgeçildi → ekran açılmaz, çağırana dönülür.
    final navigator = Navigator.of(context);
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (ref.read(financialAccessProvider).isUnlocked) {
      return widget.builder(context);
    }
    return _LockedNotice(
      // Kullanıcı otomatik dialogu kapattıysa buradan tekrar deneyebilir.
      onUnlock: () {
        _asked = false;
        unawaited(_ask());
      },
    );
  }
}

/// Kilit kapalıyken gösterilen ekran.
///
/// `rules/05 §5`: "yetkiniz yok" **denmez** — bu projede yetki kavramı yoktur
/// (`rules/04 §2`). Mesaj ne olduğunu ve ne yapılacağını söyler.
class _LockedNotice extends StatelessWidget {
  final VoidCallback onUnlock;

  const _LockedNotice({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStringsTr.adminGateTitle)),
      body: Center(
        key: AdminGate.noticeKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_outline,
                size: 48,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                AppStringsTr.adminGateTitle,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                AppStringsTr.adminGateDescription,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    key: AdminGate.backButtonKey,
                    onPressed: () {
                      final navigator = Navigator.of(context);
                      if (navigator.canPop()) navigator.pop();
                    },
                    child: const Text(AppStringsTr.adminGateBackAction),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    key: AdminGate.unlockButtonKey,
                    onPressed: onUnlock,
                    child: const Text(AppStringsTr.adminGateUnlockAction),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
