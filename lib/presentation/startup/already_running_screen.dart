/// İkinci uygulama örneği engellendiğinde gösterilen ekran.
///
/// BR-GEN-005 / REQ-ARCH-005: Aynı veri dizini üzerinde ikinci örnek çalışamaz.
library;

import 'package:flutter/material.dart';

import '../../app/l10n/app_strings_tr.dart';

class AlreadyRunningScreen extends StatelessWidget {
  const AlreadyRunningScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 48,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  AppStringsTr.alreadyRunningTitle,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  AppStringsTr.alreadyRunningMessage,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
