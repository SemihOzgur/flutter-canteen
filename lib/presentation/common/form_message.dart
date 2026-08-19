/// Form içi bildirim satırı — **rules/05 §5, §7 · REQ-UX-007/008/012**
///
/// | Kural | Karşılığı |
/// |---|---|
/// | Renk tek başına anlam taşımaz | Her durum **ikon + metin** ile de ifade edilir |
/// | Teknik hata kodu / stack trace gösterilmez | Yalnızca `Failure.userMessage` verilir |
/// | Form validasyonu satır içi ve kalıcıdır | Dialog değil, satır içi metin |
///
/// Çağıran **yalnızca kullanıcıya gösterilebilir Türkçe metin** geçirmelidir;
/// `AppException.technicalDetail` veya exception nesnesi buraya verilmez
/// (REQ-SEC-007).
///
/// ## rules/01 §3 — karar testi
///
/// Bugün dört somut kullanımı vardır (sihirbazın üç adımı + giriş ekranı);
/// aksi hâlde "ikon + metin" kuralı her ekranda elle tekrarlanırdı.
library;

import 'package:flutter/material.dart';

/// Bildirimin türü — ikon ve renk buradan türetilir (rules/05 §5).
enum FormMessageKind { error, info, warning }

class FormMessage extends StatelessWidget {
  final String message;
  final FormMessageKind kind;

  const FormMessage(
    this.message, {
    this.kind = FormMessageKind.error,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (IconData icon, Color color) = switch (kind) {
      FormMessageKind.error => (Icons.error_outline, theme.colorScheme.error),
      FormMessageKind.warning => (
        Icons.warning_amber_outlined,
        theme.colorScheme.onSurface,
      ),
      FormMessageKind.info => (
        Icons.info_outline,
        theme.colorScheme.onSurfaceVariant,
      ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
          ),
        ),
      ],
    );
  }
}
