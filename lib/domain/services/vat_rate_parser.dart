/// Kullanıcının yazdığı KDV oranını **basis point tam sayıya** çevirir.
///
/// BR-FIN-002 · rules/02 §1: oranlar basis point tam sayıdır —
/// `%20 → 2000`, `%1 → 100`, `%0,5 → 50`. Ondalık oran hiçbir yerde `double`
/// olarak tutulmaz.
///
/// ## Neden domain'de ve neden tek yer
///
/// `rules/01 §2`: aynı dönüşüm birden fazla yerde yazılamaz. Oran girdisi hem
/// KDV yönetimi ekranından hem de (Faz 3c'de) ürün formundan gelecektir; ikisi
/// de bu tek implementasyonu çağırır. UI yalnızca metni iletir.
///
/// ## tr_TR ondalık dilbilgisi neden yeniden yazılmadı
///
/// `MoneyParser` (`core/money/money_formatter.dart`) tr_TR ondalık kuralını
/// zaten uygular ve test edilmiştir: virgül ondalık, nokta binlik, en fazla iki
/// ondalık basamak. `%0,5` → `50` dönüşümü ile `₺0,50` → `50` dönüşümü **birebir
/// aynı ölçeklemedir** (değer × 100, half-up olmadan, tam sayı). Aynı dilbilgisini
/// ikinci kez yazmak `rules/01 §2`'nin yasakladığı çift implementasyondur; bu
/// nedenle ayrıştırma ona devredilir, bu sınıf yalnızca **oran anlamını** ekler:
/// `%` işaretini kabul eder ve negatif oranı reddeder.
///
/// İkiden fazla ondalık basamak (`%0,005`) reddedilir — tam sayı basis point
/// olarak ifade edilemez.
library;

import '../../core/money/money_formatter.dart';

abstract final class VatRateParser {
  /// Ayrıştırılamayan girdide `null` döner (beklenen kullanıcı hatası).
  ///
  /// Kabul edilen biçimler: `20` · `%20` · `20%` · `0,5` · `0.5` · ` %18 `
  static int? tryParseBasisPoints(String input) {
    var text = input.trim();
    if (text.isEmpty) return null;

    // Yüzde işareti başta veya sonda olabilir; ikisi birden olamaz.
    if (text.startsWith('%')) {
      text = text.substring(1);
    } else if (text.endsWith('%')) {
      text = text.substring(0, text.length - 1);
    }
    text = text.trim();
    if (text.isEmpty || text.contains('%')) return null;

    // Para sembolü bir oran girdisinde anlamsızdır; MoneyParser onu sessizce
    // atardı, burada açıkça reddedilir.
    if (text.contains(MoneyFormatter.currencySymbol)) return null;

    final parsed = MoneyParser.tryParse(text);
    if (parsed == null) return null;

    // Negatif oran yoktur (docs/05 §2.4 — CHECK(rate_basis_points >= 0)).
    if (parsed.isNegative) return null;

    return parsed.minor;
  }

  /// Ayrıştırılamayan girdide [FormatException] fırlatır.
  ///
  /// Beklenen kullanıcı hataları için [tryParseBasisPoints] tercih edilir
  /// (rules/06 §7 — beklenen iş hataları `Result`/`Failure` ile döner).
  static int parseBasisPoints(String input) {
    final result = tryParseBasisPoints(input);
    if (result == null) {
      throw FormatException('Geçersiz KDV oranı', input);
    }
    return result;
  }
}
