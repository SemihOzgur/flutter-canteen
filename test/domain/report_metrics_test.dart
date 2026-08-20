/// Rapor metrikleri — **BR-RET-007 · OD-028 · REQ-VAT-009 · docs/16 R5**
///
/// Test önceliği rules/06 §2: **Profit (maliyet snapshot'ı + KDV hariç
/// matrah)** 🔴.
///
/// Saf Dart: net ciro ve kâr formülleri burada, veritabanı olmadan sınanır.
library;

import 'package:canteen/core/money/money.dart';
import 'package:canteen/domain/services/report_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

ReportSummary summary({
  int gross = 0,
  int cancelled = 0,
  int returned = 0,
  int netBase = 0,
  int vat = 0,
  int cost = 0,
  int reversedCost = 0,
  int wasteCost = 0,
  int saleCount = 0,
  int unitCount = 0,
  int returnedUnitCount = 0,
}) => ReportSummary(
  grossRevenue: Money(gross),
  cancelled: Money(cancelled),
  returned: Money(returned),
  netBase: Money(netBase),
  vat: Money(vat),
  cost: Money(cost),
  reversedCost: Money(reversedCost),
  wasteCost: Money(wasteCost),
  saleCount: saleCount,
  unitCount: unitCount,
  returnedUnitCount: returnedUnitCount,
);

void main() {
  group('BR-RET-007 · OD-028 — net ciro', () {
    test('docs/14 §8 acceptance criteria: ₺1.000 satış, ₺150 iade → ₺850', () {
      final value = summary(gross: 100000, returned: 15000);

      expect(value.netRevenue, const Money(85000));
      // "Detayda brüt ₺1.000 ve iade ₺150 ayrı görünür."
      expect(value.grossRevenue, const Money(100000));
      expect(value.returned, const Money(15000));
    });

    test('iptal de düşülür — brüt iptalleri İÇERİR (OD-028)', () {
      // Brüt iptalleri içermeseydi `− iptal` terimi iptali İKİ KEZ düşerdi.
      final value = summary(gross: 100000, cancelled: 20000, returned: 15000);

      expect(value.netRevenue, const Money(65000));
    });

    test('hiç hareket yoksa net sıfırdır', () {
      expect(ReportSummary.empty.netRevenue, Money.zero);
      expect(ReportSummary.empty.netProfit, Money.zero);
      expect(ReportSummary.empty.profitMarginBp, 0);
      expect(ReportSummary.empty.averageSale, Money.zero);
    });

    test('tamamı iptal edilmiş dönemde net sıfırdır', () {
      final value = summary(gross: 50000, cancelled: 50000);

      expect(value.netRevenue, Money.zero);
    });

    test('net adet iade edilenleri düşer', () {
      final value = summary(unitCount: 100, returnedUnitCount: 12);

      expect(value.netUnitCount, 88);
    });
  });

  group('REQ-VAT-009 — kâr KDV HARİÇ matrahtan', () {
    test('brüt kâr = matrah − maliyet', () {
      // ₺120,00 KDV dahil satış (%20) → matrah ₺100,00, maliyet ₺60,00
      final value = summary(
        gross: 12000,
        netBase: 10000,
        vat: 2000,
        cost: 6000,
      );

      expect(value.grossProfit, const Money(4000));
      expect(
        value.grossProfit.minor,
        isNot(12000 - 6000),
        reason:
            'REGRESYON: kâr BRÜT cirodan hesaplanamaz — KDV işletmenin geliri '
            'değildir (BR-VAT-003).',
      );
    });

    test('docs/16 R5 — net kâr fire maliyetini DÜŞER', () {
      final value = summary(
        gross: 12000,
        netBase: 10000,
        cost: 6000,
        wasteCost: 1500,
      );

      expect(value.grossProfit, const Money(4000));
      expect(
        value.netProfit,
        const Money(2500),
        reason:
            'Fire dahil edilmezse kâr OLDUĞUNDAN YÜKSEK görünür (docs/16 R5).',
      );
    });

    test('iade edilen malın maliyeti kârdan GERİ EKLENİR', () {
      // İade edilen mal rafa döner; maliyeti o dönemin gideri değildir.
      final withoutReturn = summary(gross: 20000, netBase: 20000, cost: 12000);
      final withReturn = summary(
        gross: 20000,
        returned: 10000,
        netBase: 20000,
        cost: 12000,
        reversedCost: 6000,
      );

      expect(withoutReturn.netCost, const Money(12000));
      expect(withReturn.netCost, const Money(6000));
      // Yarısı iade edildi: matrah da yarıya iner, maliyet de.
      expect(withReturn.netBaseAfterReversals, const Money(10000));
      expect(withReturn.grossProfit, const Money(4000));
    });

    test('iptal/iade yoksa matrah OLDUĞU GİBİ kalır', () {
      final value = summary(gross: 20000, netBase: 16667, cost: 9000);

      expect(value.netBaseAfterReversals, const Money(16667));
    });

    test('brüt sıfırken matrah düşümü ÇÖKMEZ', () {
      // Sıfıra bölme: iptal edilmiş tek satışlık bir dönemde olabilir.
      final value = summary(gross: 0, cancelled: 0, netBase: 0);

      expect(value.netBaseAfterReversals, Money.zero);
      expect(value.profitMarginBp, 0);
    });

    test('kâr marjı basis point olarak hesaplanır', () {
      final value = summary(gross: 12000, netBase: 10000, cost: 7500);

      // (10000 − 7500) / 10000 = %25 → 2500 bp
      expect(value.profitMarginBp, 2500);
    });

    test('ZARAR durumunda marj NEGATİF döner, çökmez', () {
      // Maliyet matrahtan büyük: kantinde ikram/fire ağır bir günde olur.
      // İşaret ayrı taşınmasaydı `roundHalfUpDiv` burada exception fırlatırdı.
      final value = summary(gross: 12000, netBase: 10000, cost: 12500);

      expect(value.netProfit, const Money(-2500));
      expect(value.profitMarginBp, -2500);
    });

    test('fire kârı zarara çevirebilir', () {
      final value = summary(
        gross: 12000,
        netBase: 10000,
        cost: 9000,
        wasteCost: 3000,
      );

      expect(value.netProfit, const Money(-2000));
      expect(value.profitMarginBp, -2000);
    });

    test('negatif matrahta marj 0 döner — yanıltıcı yüzde gösterilmez', () {
      final value = summary(gross: 100, cancelled: 200, netBase: 100);

      expect(value.profitMarginBp, 0);
    });
  });

  group('docs/15 §3.1 — ortalama fiş', () {
    test('net ciro fiş sayısına bölünür', () {
      final value = summary(gross: 100000, returned: 10000, saleCount: 9);

      expect(value.averageSale, const Money(10000));
    });

    test('fiş yoksa sıfır — sıfıra bölme YOK', () {
      expect(summary(gross: 5000).averageSale, Money.zero);
    });
  });

  group('docs/15 §2 — dönem karşılaştırması', () {
    test('artış pozitif basis point', () {
      expect(
        ReportComparison.changeBp(
          current: const Money(11200),
          previous: const Money(10000),
        ),
        1200,
      );
    });

    test('azalış negatif', () {
      expect(
        ReportComparison.changeBp(
          current: const Money(8000),
          previous: const Money(10000),
        ),
        -2000,
      );
    });

    test('önceki dönem SIFIRSA `null` — "%∞" gösterilmez', () {
      expect(
        ReportComparison.changeBp(
          current: const Money(5000),
          previous: Money.zero,
        ),
        isNull,
        reason:
            '`null` "%0 değişim" DEĞİLDİR: sıfırdan çıkışın yüzdesi tanımsızdır '
            've karşılaştırma hiç gösterilmez.',
      );
    });

    test('değişim yoksa 0', () {
      expect(
        ReportComparison.changeBp(
          current: const Money(10000),
          previous: const Money(10000),
        ),
        0,
      );
    });
  });
}
