/// Satış numarası biçimi — **docs/12 §6.4 · REQ-SALE-005**
///
/// ```text
/// YYYY-NNNNNN        2026-000148
/// ```
///
/// Saf Dart ve deterministik (rules/06 §7): saat de sayaç da **parametredir**.
/// Sayacın artırılması ve benzersizliğin korunması `SaleService`'in
/// transaction'ına aittir (rules/01 §5); bu dosya yalnızca biçimi bilir.
library;

abstract final class SaleNumber {
  /// docs/12 §6.4 — sıra numarası altı hane sıfır dolgulu yazılır.
  static const int sequenceDigits = 6;

  /// `app_settings` anahtarı — sayaç **yıl başına** tutulur.
  ///
  /// EC-SALE-011: yıl değişince yeni yılın sayacı kendiliğinden `1`'den
  /// başlar, çünkü anahtar da değişir. Ayrı bir "yıl sonu sıfırlama" işi
  /// yoktur — olsaydı çalışmadığı yıl numaralar çakışırdı.
  static String counterKey(int year) => 'sale_counter_$year';

  /// **Yerel** yılı verir.
  ///
  /// Veriler UTC saklanır (BR-GEN-004) ama satış numarası kullanıcıya
  /// gösterilen bir etikettir; 1 Ocak 02:00'de kesilen fişin `2025-...`
  /// görünmesi kasada açıklanamaz.
  static int yearOf(DateTime at) => at.toLocal().year;

  /// docs/12 §6.4 biçimi.
  ///
  /// [sequence] pozitif olmalıdır: `0` bir satışı değil, "henüz satış yok"u
  /// anlatır ve fiş numarası olarak basılamaz.
  static String format({required int year, required int sequence}) {
    if (sequence <= 0) {
      throw ArgumentError.value(sequence, 'sequence', 'Pozitif olmalıdır');
    }
    return '$year-${sequence.toString().padLeft(sequenceDigits, '0')}';
  }

  /// [at] anındaki yıl için biçimlendirir.
  static String forDate(DateTime at, int sequence) =>
      format(year: yearOf(at), sequence: sequence);

  /// Bir satış numarasındaki sıra numarasını çözer; biçim tutmuyorsa `null`.
  ///
  /// docs/19 §5 · EC-SALE-012 — restore sonrası sayaç `MAX(sale_number)`'a
  /// göre düzeltilir. O düzeltme **Faz 9**'a aittir; burada yalnızca
  /// düzeltmenin dayanacağı çözümleme vardır ve ilgili yılın numarasını
  /// tanımayan bir sayaç düzeltmesi yazılamaz.
  static int? sequenceOf(String saleNumber, {required int year}) {
    final prefix = '$year-';
    if (!saleNumber.startsWith(prefix)) return null;
    return int.tryParse(saleNumber.substring(prefix.length));
  }
}
