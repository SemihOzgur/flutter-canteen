/// Faz 1 temel ekranı.
///
/// Bu ekran yalnızca uygulamanın açıldığını doğrulayan bir iskelettir.
/// Satış ekranı Faz 5'te, Dashboard Faz 8'de eklenir.
///
/// rules/05 §8: UI'da veritabanı sorgusu, dosya erişimi veya finansal hesaplama
///              **bulunmaz.**
library;

import 'package:flutter/material.dart';

import '../../app/l10n/app_strings_tr.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStringsTr.appTitle)),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.storefront_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  AppStringsTr.foundationReady,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  AppStringsTr.foundationDescription,
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
