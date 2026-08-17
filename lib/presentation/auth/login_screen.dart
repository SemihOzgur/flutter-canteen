/// Giriş ekranı — **iskelet** (docs/17 §3 · REQ-AUTH-001).
///
/// Form alanları, `Enter` ile ilerleme, odak yönetimi ve hata mesajları bir
/// sonraki adımda eklenecektir. Bu adımda yalnızca rota bağlanmıştır.
///
/// rules/05 §8: burada veritabanı sorgusu, dosya erişimi veya iş kuralı
/// **yoktur.**
library;

import 'package:flutter/material.dart';

import '../../app/l10n/app_strings_tr.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

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
                  Icons.storefront_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  AppStringsTr.loginTitle,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  AppStringsTr.loginDescription,
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
