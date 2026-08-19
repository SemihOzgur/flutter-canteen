/// KDV oranının **gösterim** biçimi — `%20` · `%0,5` · `%18,25`
///
/// ## Neden presentation katmanında
///
/// rules/02 §1: biçimlendirme bir **presentation concern**'üdür; domain
/// formatlanmış string üretmez. Buradaki dönüşüm bir hesap değil, basis point
/// tam sayısının tr_TR yazımıdır (rules/05 §4 — ondalık ayırıcı virgül).
///
/// Ters yön (kullanıcı girdisi → basis point) **buraya ait değildir**; onun tek
/// implementasyonu `domain/services/vat_rate_parser.dart` içindedir
/// (rules/01 §2). Bu dosya ikinci bir parser tanımlamaz.
///
/// ## rules/01 §3 — karar testi
///
/// Bugün KDV oranı yönetimi ekranı kullanır; ürün formu (Faz 3c) aynı gösterimi
/// isteyecektir. Tek yerde tutulmazsa `%0,5` gibi kenar durum iki ekranda
/// farklı yazılırdı.
library;

import '../../core/money/money_formatter.dart';

/// `2000 → "%20"` · `50 → "%0,5"` · `1825 → "%18,25"`
///
/// Tam sayı aritmetiği kullanılır; `double` dönüşümü yapılmaz (rules/02 §1).
String formatRateBasisPoints(int rateBasisPoints) {
  final whole = rateBasisPoints ~/ 100;
  final fraction = rateBasisPoints % 100;

  if (fraction == 0) return '%$whole';

  // Sondaki sıfır yazılmaz: %0,50 yerine %0,5.
  final digits = fraction % 10 == 0
      ? '${fraction ~/ 10}'
      : fraction.toString().padLeft(2, '0');

  return '%$whole${MoneyFormatter.decimalSeparator}$digits';
}
