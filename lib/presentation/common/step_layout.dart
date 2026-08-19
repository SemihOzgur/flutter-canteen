/// Çok adımlı akışların ortak yerleşimi: adım sayacı, başlık, açıklama, içerik.
///
/// ## rules/01 §3 — karar testi
///
/// 1. **Bugün en az iki somut kullanımı var mı?** Evet: kurulum sihirbazı
///    (docs/17 §4) ve dashboard parolası kurtarma akışı (docs/17 §8).
/// 2. Aksi hâlde iki ekran aynı düzeni ayrı ayrı taşır ve biri kaçınılmaz
///    olarak adım sayacını veya başlık hiyerarşisini farklı gösterir.
///
/// Burada iş kuralı, hesaplama veya veri erişimi **yoktur** (rules/05 §8).
library;

import 'package:flutter/material.dart';

class StepLayout extends StatelessWidget {
  /// Örn. "Adım 2 / 3" — kullanıcı kaç adım kaldığını görür.
  final String stepCounter;
  final String title;
  final String description;
  final List<Widget> children;

  const StepLayout({
    required this.stepCounter,
    required this.title,
    required this.description,
    required this.children,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          stepCounter,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(description, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 24),
        ...children,
      ],
    );
  }
}
