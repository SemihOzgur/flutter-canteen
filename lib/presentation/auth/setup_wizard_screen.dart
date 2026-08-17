/// İlk kurulum sihirbazı — **iskelet** (docs/17 §4 · REQ-AUTH-016/022/024).
///
/// Bu adımda yalnızca **kaldığı adım** gösterilir; kullanıcı oluşturma, dashboard
/// parolası ve kurtarma kodu formları bir sonraki adımda eklenecektir.
///
/// H6 · EC-AUTH-008: sihirbaz üç ayrı transaction'dır ve yarım kalabilir; ekran
/// bu yüzden sabit bir adımdan değil, `SetupService`'in bildirdiği **ilk eksik
/// adımdan** başlar.
///
/// rules/05 §8: burada veritabanı sorgusu, dosya erişimi veya iş kuralı
/// **yoktur** — durum application katmanındaki servisten gelir.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/auth/providers.dart';
import '../../application/auth/setup_service.dart';

class SetupWizardScreen extends ConsumerWidget {
  const SetupWizardScreen({super.key});

  /// Kurulum durumunun kullanıcıya görünen karşılığı (rules/05 §4 — metinler
  /// merkezî dosyadadır).
  static String stepLabel(SetupState state) => switch (state) {
    SetupState.needsUser => AppStringsTr.setupStepUser,
    SetupState.needsDashboardPassword =>
      AppStringsTr.setupStepDashboardPassword,
    SetupState.needsRecoveryCode => AppStringsTr.setupStepRecoveryCode,
    SetupState.complete => AppStringsTr.setupComplete,
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final setupState = ref.watch(setupStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStringsTr.setupTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.settings_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  AppStringsTr.setupDescription,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                setupState.when(
                  data: (state) => Column(
                    children: [
                      Text(
                        AppStringsTr.setupStepPending,
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stepLabel(state),
                        style: theme.textTheme.titleMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                  loading: () => const CircularProgressIndicator(),
                  // REQ-SEC-007: teknik detay kullanıcıya gösterilmez.
                  error: (_, _) => Text(
                    AppStringsTr.unexpectedErrorMessage,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
