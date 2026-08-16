/// KDV hesaplama birim testleri.
///
/// docs/27-testing-strategy.md §3.2 · docs/08-vat-rules.md §2
/// BR-VAT-003 (KDV dahil) · REQ-VAT-007 · REQ-VAT-008 · BR-VAT-005 (oran yoksa 0)
library;

import 'package:canteen/core/money/money.dart';
import 'package:canteen/domain/services/vat_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VatCalculator.fromGross — docs/08 §2 doğrulanmış vektörler', () {
    test('12000 @ 2000bp → KDV 2000, matrah 10000', () {
      final r = VatCalculator.fromGross(
        gross: const Money(12000),
        vatRateBp: 2000,
      );
      expect(r.gross.minor, 12000);
      expect(r.vat.minor, 2000);
      expect(r.net.minor, 10000);
    });

    test('10000 @ 2000bp → KDV 1667, matrah 8333', () {
      final r = VatCalculator.fromGross(
        gross: const Money(10000),
        vatRateBp: 2000,
      );
      expect(r.gross.minor, 10000);
      expect(r.vat.minor, 1667);
      expect(r.net.minor, 8333);
    });

    test('BR-VAT-005 — oran 0 ise KDV 0, matrah brüte eşit', () {
      final r = VatCalculator.fromGross(
        gross: const Money(12000),
        vatRateBp: 0,
      );
      expect(r.vat.minor, 0);
      expect(r.net.minor, 12000);
      expect(r.gross.minor, 12000);
    });

    test('sıfır tutar', () {
      final r = VatCalculator.fromGross(gross: Money.zero, vatRateBp: 2000);
      expect(r.gross.minor, 0);
      expect(r.vat.minor, 0);
      expect(r.net.minor, 0);
    });

    test('kuruşluk sınır değerler', () {
      // 1 kuruş @ %20 → 1×2000/12000 = 0,1667 → half-up → 0
      expect(
        VatCalculator.fromGross(
          gross: const Money(1),
          vatRateBp: 2000,
        ).vat.minor,
        0,
      );
      // 3 kuruş @ %20 → 0,5 → half-up → 1
      expect(
        VatCalculator.fromGross(
          gross: const Money(3),
          vatRateBp: 2000,
        ).vat.minor,
        1,
      );
      // 7 kuruş @ %20 → 1,1667 → 1
      expect(
        VatCalculator.fromGross(
          gross: const Money(7),
          vatRateBp: 2000,
        ).vat.minor,
        1,
      );
    });

    test('farklı oranlar', () {
      // %10 → 11000 brütte KDV 1000
      final r10 = VatCalculator.fromGross(
        gross: const Money(11000),
        vatRateBp: 1000,
      );
      expect(r10.vat.minor, 1000);
      expect(r10.net.minor, 10000);

      // %1 → 10100 brütte KDV 100
      final r1 = VatCalculator.fromGross(
        gross: const Money(10100),
        vatRateBp: 100,
      );
      expect(r1.vat.minor, 100);
      expect(r1.net.minor, 10000);

      // %0,5 (50 bp) → 10050 brütte KDV 50
      final rHalf = VatCalculator.fromGross(
        gross: const Money(10050),
        vatRateBp: 50,
      );
      expect(rHalf.vat.minor, 50);
      expect(rHalf.net.minor, 10000);
    });

    test('geçersiz girdi reddedilir', () {
      expect(
        () => VatCalculator.fromGross(gross: const Money(100), vatRateBp: -1),
        throwsArgumentError,
      );
      expect(
        () =>
            VatCalculator.fromGross(gross: const Money(-100), vatRateBp: 2000),
        throwsArgumentError,
      );
    });
  });

  group('VatCalculator.forLine — BR-SALE-011', () {
    test('₺120,00 × 2 adet @ %20 → brüt 24000, KDV 4000, matrah 20000', () {
      final r = VatCalculator.forLine(
        unitPrice: const Money(12000),
        quantity: 2,
        vatRateBp: 2000,
      );
      expect(r.gross.minor, 24000);
      expect(r.vat.minor, 4000);
      expect(r.net.minor, 20000);
    });

    test('miktar pozitif tam sayı olmalıdır', () {
      expect(
        () => VatCalculator.forLine(
          unitPrice: const Money(100),
          quantity: 0,
          vatRateBp: 2000,
        ),
        throwsArgumentError,
      );
      expect(
        () => VatCalculator.forLine(
          unitPrice: const Money(100),
          quantity: -1,
          vatRateBp: 2000,
        ),
        throwsArgumentError,
      );
    });
  });

  group('VatCalculator.aggregate — REQ-FIN-004', () {
    test('toplam, yuvarlanmış satır değerlerinin toplamıdır', () {
      final lines = [
        VatCalculator.forLine(
          unitPrice: const Money(1233),
          quantity: 1,
          vatRateBp: 2000,
        ),
        VatCalculator.forLine(
          unitPrice: const Money(749),
          quantity: 3,
          vatRateBp: 2000,
        ),
        VatCalculator.forLine(
          unitPrice: const Money(99),
          quantity: 7,
          vatRateBp: 1000,
        ),
      ];
      final total = VatCalculator.aggregate(lines);

      expect(total.gross.minor, 1233 + 2247 + 693);
      expect(total.vat.minor, lines.fold(0, (s, l) => s + l.vat.minor));
      expect(total.net.minor, lines.fold(0, (s, l) => s + l.net.minor));
      // Invariant
      expect(total.net.minor + total.vat.minor, total.gross.minor);
    });

    test('farklı KDV oranlı satırlar bir arada toplanabilir', () {
      final lines = [
        VatCalculator.forLine(
          unitPrice: const Money(12000),
          quantity: 1,
          vatRateBp: 2000,
        ),
        VatCalculator.forLine(
          unitPrice: const Money(11000),
          quantity: 1,
          vatRateBp: 1000,
        ),
        VatCalculator.forLine(
          unitPrice: const Money(5000),
          quantity: 1,
          vatRateBp: 0,
        ),
      ];
      final total = VatCalculator.aggregate(lines);

      expect(total.gross.minor, 28000);
      expect(total.vat.minor, 2000 + 1000 + 0);
      expect(total.net.minor, 10000 + 10000 + 5000);
      expect(total.net.minor + total.vat.minor, total.gross.minor);
    });

    test('boş liste sıfır döner', () {
      final total = VatCalculator.aggregate(const []);
      expect(total.gross.minor, 0);
      expect(total.vat.minor, 0);
      expect(total.net.minor, 0);
    });
  });
}
