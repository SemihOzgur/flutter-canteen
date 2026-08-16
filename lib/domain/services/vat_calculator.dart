/// KDV hesaplama — **satış fiyatı KDV DAHİLDİR**.
///
/// BR-VAT-003: Ürünün satış fiyatı KDV dahildir. KDV fiyatın **içinden çıkarılır**,
///             üzerine EKLENMEZ.
/// BR-VAT-002: Her satış satırı KDV oranının snapshot'ını taşır (Faz 5).
/// BR-FIN-002: Oranlar basis point tam sayı olarak ifade edilir (%20 → 2000).
///
/// **Kaynak: docs/08-vat-rules.md §2.** Formül yalnızca burada, tek merkezî
/// implementasyon olarak yaşar (rules/01 §2). UI, dashboard ve raporlar bu
/// sınıfı kullanır; kendi içinde KDV hesabı yapmaz.
library;

import '../../core/money/money.dart';

/// Bir satırın veya toplamın KDV dökümü.
///
/// Invariant: `net + vat == gross`
class VatBreakdown {
  /// KDV **dahil** brüt tutar — müşteriden alınan tutar.
  final Money gross;

  /// KDV bileşeni.
  final Money vat;

  /// KDV **hariç** matrah.
  final Money net;

  const VatBreakdown({
    required this.gross,
    required this.vat,
    required this.net,
  });

  @override
  bool operator ==(Object other) =>
      other is VatBreakdown &&
      other.gross == gross &&
      other.vat == vat &&
      other.net == net;

  @override
  int get hashCode => Object.hash(gross, vat, net);

  @override
  String toString() =>
      'VatBreakdown(gross: ${gross.minor}, vat: ${vat.minor}, net: ${net.minor})';
}

/// KDV dahil fiyattan KDV çıkarımı.
class VatCalculator {
  const VatCalculator._();

  /// Basis point paydası: %100 → 10000 bp.
  static const int basisPointScale = 10000;

  /// KDV dahil brüt tutardan KDV'yi çıkarır.
  ///
  /// **Tek geçerli formül (docs/08 §2):**
  /// ```text
  /// vat = roundHalfUp( gross × vatBp / (10000 + vatBp) )
  /// net = gross − vat
  /// ```
  ///
  /// Örnek: `₺120,00` @ %20 → brüt 12000, KDV 2000, matrah 10000.
  ///
  /// BR-VAT-005: Oran `0` ise KDV `0`, matrah brüt tutara eşittir.
  static VatBreakdown fromGross({
    required Money gross,
    required int vatRateBp,
  }) {
    if (vatRateBp < 0) {
      throw ArgumentError.value(vatRateBp, 'vatRateBp', 'Negatif olamaz');
    }
    if (gross.isNegative) {
      throw ArgumentError.value(gross.minor, 'gross', 'Negatif olamaz');
    }

    if (vatRateBp == 0) {
      return VatBreakdown(gross: gross, vat: Money.zero, net: gross);
    }

    final vatMinor = Money.roundHalfUpDiv(
      gross.minor * vatRateBp,
      basisPointScale + vatRateBp,
    );
    final vat = Money(vatMinor);
    return VatBreakdown(gross: gross, vat: vat, net: gross - vat);
  }

  /// Bir satırın brüt tutarını hesaplar ve KDV'sini çıkarır.
  ///
  /// BR-SALE-011: Miktar pozitif tam sayıdır.
  /// Yuvarlama **yalnızca satır seviyesinde** yapılır (BR-FIN-003).
  static VatBreakdown forLine({
    required Money unitPrice,
    required int quantity,
    required int vatRateBp,
  }) {
    if (quantity <= 0) {
      throw ArgumentError.value(
        quantity,
        'quantity',
        'Pozitif tam sayı olmalıdır',
      );
    }
    return fromGross(gross: unitPrice * quantity, vatRateBp: vatRateBp);
  }

  /// Satır dökümlerini toplar.
  ///
  /// BR-FIN-004 / REQ-FIN-004: Genel toplam, **yuvarlanmış satır değerlerinin
  /// toplamıdır.** Bu sayede fişteki satırlar elle toplandığında genel toplam tutar.
  static VatBreakdown aggregate(Iterable<VatBreakdown> lines) {
    var gross = 0;
    var vat = 0;
    var net = 0;
    for (final line in lines) {
      gross += line.gross.minor;
      vat += line.vat.minor;
      net += line.net.minor;
    }
    return VatBreakdown(gross: Money(gross), vat: Money(vat), net: Money(net));
  }
}
