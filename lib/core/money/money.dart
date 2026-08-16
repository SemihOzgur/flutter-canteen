/// Para değeri — **tam sayı kuruş (minor unit)**.
///
/// BR-FIN-001: Tüm parasal değerler tam sayı kuruş olarak saklanır.
///             Floating point ile para hesabı YASAKTIR.
/// BR-FIN-003: Yuvarlama half-up kuralıyla yapılır.
///
/// Bkz. docs/07-financial-rules.md §1, §3
library;

/// Kuruş cinsinden parasal değer.
///
/// `₺25,50` → `Money(2550)`
///
/// Bu tip hiçbir koşulda `double` kullanmaz. Aritmetik tam sayı üzerinden yapılır.
class Money implements Comparable<Money> {
  /// Kuruş cinsinden değer. 64-bit signed integer.
  final int minor;

  const Money(this.minor);

  static const Money zero = Money(0);

  bool get isZero => minor == 0;
  bool get isNegative => minor < 0;

  Money operator +(Money other) => Money(minor + other.minor);
  Money operator -(Money other) => Money(minor - other.minor);
  Money operator -() => Money(-minor);

  /// Miktar ile çarpım. Miktar daima tam sayıdır (BR-SALE-011),
  /// bu nedenle çarpım kayıpsızdır ve yuvarlama gerektirmez.
  Money operator *(int quantity) => Money(minor * quantity);

  bool operator <(Money other) => minor < other.minor;
  bool operator <=(Money other) => minor <= other.minor;
  bool operator >(Money other) => minor > other.minor;
  bool operator >=(Money other) => minor >= other.minor;

  @override
  int compareTo(Money other) => minor.compareTo(other.minor);

  @override
  bool operator ==(Object other) => other is Money && other.minor == minor;

  @override
  int get hashCode => minor.hashCode;

  /// Hata ayıklama amaçlıdır. Kullanıcıya gösterim için `MoneyFormatter` kullanılır.
  @override
  String toString() => 'Money($minor)';

  /// Satır tutarlarının toplamı.
  ///
  /// BR-FIN-004 / REQ-FIN-004: Genel toplam, satır tutarlarının toplamına eşittir.
  /// Ara sonuç yuvarlaması yapılmadığı için sapma oluşmaz.
  static Money sum(Iterable<Money> values) {
    var total = 0;
    for (final v in values) {
      total += v.minor;
    }
    return Money(total);
  }

  /// Half-up tam sayı bölmesi.
  ///
  /// BR-FIN-003: Yuvarlama **half-up** (0,5 yukarı) kuralıyla yapılır.
  /// Banker's rounding kullanılmaz — Türkiye perakende pratiğine aykırıdır.
  ///
  /// `(2a + b) ~/ (2b)` formülü `floor(a/b + 0.5)` ile birebir aynıdır ve
  /// hiçbir noktada floating point kullanmaz.
  ///
  /// Yalnızca negatif olmayan pay ve pozitif payda için tanımlıdır; parasal
  /// tutarlar bu projede negatif saklanmaz (bkz. docs/07 §1).
  static int roundHalfUpDiv(int numerator, int denominator) {
    if (denominator <= 0) {
      throw ArgumentError.value(
        denominator,
        'denominator',
        'Pozitif olmalıdır',
      );
    }
    if (numerator < 0) {
      throw ArgumentError.value(numerator, 'numerator', 'Negatif olamaz');
    }
    return (2 * numerator + denominator) ~/ (2 * denominator);
  }
}
