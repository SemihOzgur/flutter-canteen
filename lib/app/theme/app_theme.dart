/// Uygulama teması.
///
/// rules/05 §5:
///   - Açık tema varsayılan (kasa ekranı genelde aydınlık ortamda)
///   - Ana font boyutu 14 px taban
///   - Tıklanabilir alan minimum 40×40 px
///   - Animasyon minimum
library;

import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  /// Taban font boyutu (rules/05 §5).
  static const double baseFontSize = 14;

  /// Minimum tıklanabilir alan (rules/05 §5).
  static const double minTapTarget = 40;

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: const Color(0xFF1565C0),
    );

    return base.copyWith(
      textTheme: base.textTheme
          .apply(fontSizeFactor: 1)
          .copyWith(
            bodyMedium: base.textTheme.bodyMedium?.copyWith(
              fontSize: baseFontSize,
            ),
          ),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}
