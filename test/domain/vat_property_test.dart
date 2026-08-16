/// KDV property testleri — 10.000 kombinasyon.
///
/// docs/27-testing-strategy.md §3.2:
///   "`net + kdv == brüt` invariant'ı (property test, 10.000 rastgele tutar × oran)"
///
/// BR-VAT-003 · REQ-VAT-007 · REQ-VAT-008
library;

import 'dart:math';

import 'package:canteen/core/money/money.dart';
import 'package:canteen/domain/services/vat_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Deterministik tohum (rules/06 §7 — determinizm).
  final random = Random(20260813);

  /// Gerçekçi KDV oranları + sınır değerler.
  const rates = <int>[0, 50, 100, 800, 1000, 1800, 2000, 2500, 10000];

  test('net + KDV == brüt — 10.000 kombinasyon', () {
    for (var i = 0; i < 10000; i++) {
      final gross = random.nextInt(100000000); // 0 – ₺1.000.000
      final rate = rates[random.nextInt(rates.length)];

      final r = VatCalculator.fromGross(gross: Money(gross), vatRateBp: rate);

      expect(
        r.net.minor + r.vat.minor,
        r.gross.minor,
        reason: 'gross=$gross rate=$rate',
      );
      expect(r.gross.minor, gross, reason: 'brüt değişmemeli');
      expect(r.vat.minor, greaterThanOrEqualTo(0));
      expect(r.net.minor, greaterThanOrEqualTo(0));
      expect(r.vat.minor, lessThanOrEqualTo(gross));
    }
  });

  test('KDV oranı arttıkça KDV bileşeni azalmaz — 10.000 kombinasyon', () {
    for (var i = 0; i < 10000; i++) {
      final gross = 1 + random.nextInt(10000000);

      var previous = -1;
      for (final rate in rates) {
        final vat = VatCalculator.fromGross(
          gross: Money(gross),
          vatRateBp: rate,
        ).vat.minor;
        expect(
          vat,
          greaterThanOrEqualTo(previous),
          reason: 'gross=$gross rate=$rate monotonluk bozuldu',
        );
        previous = vat;
      }
    }
  });

  test('satır toplamı = satırların toplamı — 10.000 sepet', () {
    for (var i = 0; i < 10000; i++) {
      final lineCount = 1 + random.nextInt(10);
      final lines = <VatBreakdown>[];

      for (var j = 0; j < lineCount; j++) {
        lines.add(
          VatCalculator.forLine(
            unitPrice: Money(1 + random.nextInt(500000)),
            quantity: 1 + random.nextInt(20),
            vatRateBp: rates[random.nextInt(rates.length)],
          ),
        );
      }

      final total = VatCalculator.aggregate(lines);

      expect(total.gross.minor, lines.fold(0, (s, l) => s + l.gross.minor));
      expect(total.net.minor + total.vat.minor, total.gross.minor);
    }
  });
}
