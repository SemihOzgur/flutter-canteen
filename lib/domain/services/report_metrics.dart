/// Rapor metrikleri — **docs/14 §5 · docs/16 R5 · OD-028 · REQ-VAT-009**
///
/// Saf Dart, tek merkezî implementasyon (rules/01 §2): dashboard, raporlar ve
/// CSV dışa aktarma **aynı** hesabı kullanır. rules/05 §3 UI'da finansal
/// hesaplama yapılmasını yasaklar; ekranlar buradan gelen değerleri yalnızca
/// biçimlendirir.
library;

import '../../core/money/money.dart';

/// Bir dönemin net ciro/kâr tablosu.
class ReportSummary {
  /// TÜM satışların toplamı — **iptaller dâhil** (OD-028).
  final Money grossRevenue;

  final Money cancelled;
  final Money returned;

  /// KDV **hariç** matrah (satışlardan).
  final Money netBase;

  final Money vat;
  final Money cost;

  /// İptal ve iadelerin maliyet karşılığı.
  final Money reversedCost;

  /// docs/16 R5 — fire, kâr raporunda **gider**dir.
  final Money wasteCost;

  final int saleCount;
  final int unitCount;
  final int returnedUnitCount;

  const ReportSummary({
    required this.grossRevenue,
    required this.cancelled,
    required this.returned,
    required this.netBase,
    required this.vat,
    required this.cost,
    required this.reversedCost,
    required this.wasteCost,
    required this.saleCount,
    required this.unitCount,
    required this.returnedUnitCount,
  });

  static const ReportSummary empty = ReportSummary(
    grossRevenue: Money.zero,
    cancelled: Money.zero,
    returned: Money.zero,
    netBase: Money.zero,
    vat: Money.zero,
    cost: Money.zero,
    reversedCost: Money.zero,
    wasteCost: Money.zero,
    saleCount: 0,
    unitCount: 0,
    returnedUnitCount: 0,
  );

  /// **BR-RET-007 · OD-028 — `net = satış − iptal − iade`.**
  Money get netRevenue => grossRevenue - cancelled - returned;

  /// Net satılan adet — iade edilenler düşülmüş (docs/14 §5).
  int get netUnitCount => unitCount - returnedUnitCount;

  /// Net maliyet — iptal ve iadelerin maliyeti **geri eklenir**.
  ///
  /// İade edilen mal rafa döner; maliyeti o dönemin gideri değildir.
  Money get netCost => cost - reversedCost;

  /// **REQ-VAT-009 · REQ-REP-013 — kâr KDV HARİÇ matrahtan.**
  ///
  /// BR-VAT-003 gereği fiyat KDV dahildir ve **KDV işletmenin geliri
  /// değildir**; brüt cirodan hesaplanan bir kâr, devletin payını işletmenin
  /// kârı gibi gösterirdi.
  ///
  /// İptal ve iadelerin matrah karşılığı da düşülür: net ciro brütten ne
  /// kadar düştüyse, matrah da **aynı oranda** düşer. Oran kullanmak, satırları
  /// tek tek yeniden toplamaktan hem hızlı hem de yuvarlama açısından
  /// tutarlıdır — `netBase` zaten yuvarlanmış satır matrahlarının toplamıdır.
  Money get netBaseAfterReversals {
    if (grossRevenue.isZero) return Money.zero;
    final reversed = cancelled + returned;
    if (reversed.isZero) return netBase;
    final ratio = Money.roundHalfUpDiv(
      netBase.minor * reversed.minor,
      grossRevenue.minor,
    );
    return netBase - Money(ratio);
  }

  /// docs/16 R5 — `brüt kâr = matrah − maliyet`.
  Money get grossProfit => netBaseAfterReversals - netCost;

  /// docs/16 R5 — `net kâr = brüt kâr − fire maliyeti`.
  ///
  /// Fire dahil edilmezse kâr **olduğundan yüksek** görünür (docs/16 R5).
  Money get netProfit => grossProfit - wasteCost;

  /// Kâr marjı yüzdesi (basis point) — matrah sıfır veya negatifse `0`.
  ///
  /// **Kâr negatif olabilir** (zarar) ve marj o zaman negatiftir.
  /// `Money.roundHalfUpDiv` negatif pay kabul etmez (para değerleri için
  /// doğru bir kısıt), bu yüzden işaret ayrı taşınır — aksi hâlde zararda
  /// olan bir dönemde dashboard **çökerdi**.
  int get profitMarginBp {
    final base = netBaseAfterReversals;
    if (base.isZero || base.isNegative) return 0;
    return _signedBp(netProfit.minor, base.minor);
  }

  /// Yarıyı **sıfırdan uzağa** yuvarlayan işaretli basis point bölmesi.
  static int _signedBp(int numerator, int denominator) {
    final magnitude = Money.roundHalfUpDiv(
      numerator.abs() * 10000,
      denominator,
    );
    return numerator < 0 ? -magnitude : magnitude;
  }

  /// Ortalama fiş tutarı — docs/15 §3.1.
  Money get averageSale =>
      saleCount == 0 ? Money.zero : Money(netRevenue.minor ~/ saleCount);
}

/// İki dönem arasındaki yüzde değişim — docs/15 §2.
abstract final class ReportComparison {
  /// Basis point cinsinden değişim; önceki dönem `0` ise `null`.
  ///
  /// `null` **"%0 değişim" değildir**: sıfırdan bir değere çıkışın yüzdesi
  /// tanımsızdır ve `%∞` göstermek yerine karşılaştırma hiç gösterilmez.
  static int? changeBp({required Money current, required Money previous}) {
    if (previous.isZero) return null;
    final diff = current.minor - previous.minor;
    // Düşüş negatif bir değişimdir; `Money.roundHalfUpDiv` negatif pay kabul
    // etmez ve doğrudan çağrılsaydı ciro düşen her dönemde ÇÖKERDİ.
    return ReportSummary._signedBp(diff, previous.minor.abs());
  }
}
