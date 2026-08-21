/// Para biçimlendirme ve ayrıştırma — `tr_TR`.
///
/// BR-FIN-005 / REQ-FIN-005: `₺#.###,##` — binlik `.`, ondalık `,`, daima 2 basamak.
/// REQ-FIN-006: Girişte hem `,` hem `.` ondalık ayırıcısı kabul edilir.
///
/// **Bağımlılık notu:** `intl` paketi KULLANILMAZ.
/// `.claude/rules/01-architecture.md §7` soru 2 gereği bu biçim standart
/// kütüphaneyle deterministik olarak üretilebildiği için yeni bağımlılık eklenmemiştir.
///
/// Bkz. docs/07-financial-rules.md §6
library;

import 'money.dart';

/// `tr_TR` para biçimlendirmesi. Bu bir **presentation concern**'üdür;
/// domain katmanı biçimlendirilmiş string üretmez (rules/02 §1).
class MoneyFormatter {
  const MoneyFormatter._();

  static const String currencySymbol = '₺';
  static const String thousandsSeparator = '.';
  static const String decimalSeparator = ',';

  /// U+2212 MINUS SIGN — docs/07 §6.
  static const String minusSign = '−';

  /// `Money(2550)` → `₺25,50` · `Money(0)` → `₺0,00` · `Money(123400)` → `₺1.234,00`
  static String format(Money money) {
    final negative = money.isNegative;
    final abs = negative ? -money.minor : money.minor;

    final lira = abs ~/ 100;
    final kurus = abs % 100;

    final buffer = StringBuffer();
    if (negative) buffer.write(minusSign);
    buffer
      ..write(currencySymbol)
      ..write(_groupThousands(lira))
      ..write(decimalSeparator)
      ..write(kurus.toString().padLeft(2, '0'));
    return buffer.toString();
  }

  /// Grafik ekseni için **kısaltılmış** biçim: `₺1.500` → `₺1,5B`.
  ///
  /// Yalnızca eksen etiketleri ve grafik içi kısa gösterimler içindir.
  /// Fiş, sepet ve rapor tutarları **asla** kısaltılmaz — kullanıcı ödediği
  /// rakamı tam görmelidir (BR-FIN-005).
  ///
  /// `B` = bin, `M` = milyon (tr_TR).
  static String compact(Money money) {
    final negative = money.isNegative;
    final lira = (negative ? -money.minor : money.minor) ~/ 100;

    String body;
    if (lira >= 1000000) {
      body = '${_oneDecimal(lira / 1000000)}M';
    } else if (lira >= 1000) {
      body = '${_oneDecimal(lira / 1000)}B';
    } else {
      body = '$lira';
    }
    return '${negative ? minusSign : ''}$currencySymbol$body';
  }

  /// `1.5` → `1,5` · `2.0` → `2` (gereksiz `,0` eksende yer kaplar).
  static String _oneDecimal(double value) {
    final rounded = (value * 10).round() / 10;
    if (rounded == rounded.roundToDouble()) return '${rounded.round()}';
    return rounded.toStringAsFixed(1).replaceAll('.', decimalSeparator);
  }

  static String _groupThousands(int value) {
    final digits = value.toString();
    if (digits.length <= 3) return digits;

    final buffer = StringBuffer();
    final firstGroupLength = digits.length % 3;
    var index = 0;

    if (firstGroupLength > 0) {
      buffer.write(digits.substring(0, firstGroupLength));
      index = firstGroupLength;
    }
    while (index < digits.length) {
      if (buffer.isNotEmpty) buffer.write(thousandsSeparator);
      buffer.write(digits.substring(index, index + 3));
      index += 3;
    }
    return buffer.toString();
  }
}

/// Kullanıcı girdisini `Money`'ye çevirir.
///
/// Kabul edilen biçimler (docs/07 §6):
/// `25,50` · `25.50` · `25` · `₺25,50` · `1.234,56` · ` 25,50 `
class MoneyParser {
  const MoneyParser._();

  /// Ayrıştırılamayan girdide [FormatException] fırlatır.
  /// Beklenen kullanıcı hataları için [tryParse] tercih edilir.
  static Money parse(String input) {
    final result = tryParse(input);
    if (result == null) {
      throw FormatException('Geçersiz para değeri', input);
    }
    return result;
  }

  /// Ayrıştırılamazsa `null` döner.
  static Money? tryParse(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;

    // Para sembolü, boşluklar ve işaret
    text = text.replaceAll(MoneyFormatter.currencySymbol, '');
    text = text.replaceAll(' ', ''); // non-breaking space
    text = text.replaceAll(' ', '').trim();
    if (text.isEmpty) return null;

    var negative = false;
    if (text.startsWith(MoneyFormatter.minusSign) || text.startsWith('-')) {
      negative = true;
      text = text.substring(1);
    } else if (text.startsWith('+')) {
      text = text.substring(1);
    }
    if (text.isEmpty) return null;

    final hasComma = text.contains(',');
    final hasDot = text.contains('.');

    String integerPart;
    String fractionPart;

    if (hasComma && hasDot) {
      // tr_TR: nokta binlik, virgül ondalık → "1.234,56"
      if (text.lastIndexOf(',') < text.lastIndexOf('.')) return null;
      final parts = text.split(',');
      if (parts.length != 2) return null;
      integerPart = parts[0].replaceAll('.', '');
      fractionPart = parts[1];
    } else if (hasComma) {
      final parts = text.split(',');
      if (parts.length != 2) return null;
      integerPart = parts[0];
      fractionPart = parts[1];
    } else if (hasDot) {
      final parts = text.split('.');
      final last = parts.last;
      if (parts.length >= 3 && last.length == 3) {
        // "1.234.567" → yalnızca binlik ayırıcı
        integerPart = parts.join();
        fractionPart = '';
      } else if (parts.length == 2 && last.length == 3) {
        // "1.234" → tr_TR binlik okuması
        integerPart = parts.join();
        fractionPart = '';
      } else if (parts.length == 2 && last.length <= 2) {
        // "25.50" → ondalık ayırıcı olarak kabul (REQ-FIN-006)
        integerPart = parts[0];
        fractionPart = last;
      } else {
        return null;
      }
    } else {
      integerPart = text;
      fractionPart = '';
    }

    if (integerPart.isEmpty) integerPart = '0';
    if (!_isDigits(integerPart)) return null;
    if (fractionPart.isNotEmpty && !_isDigits(fractionPart)) return null;
    if (fractionPart.length > 2) return null;

    final lira = int.tryParse(integerPart);
    if (lira == null) return null;

    final kurus = fractionPart.isEmpty
        ? 0
        : int.parse(fractionPart.padRight(2, '0'));

    final total = lira * 100 + kurus;
    return Money(negative ? -total : total);
  }

  static bool _isDigits(String value) {
    if (value.isEmpty) return false;
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) return false;
    }
    return true;
  }
}
