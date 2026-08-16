/// Money property testleri — 10.000 kombinasyon.
///
/// docs/27-testing-strategy.md §3.1
/// BR-FIN-001 · BR-FIN-004 · BR-FIN-005
library;

import 'dart:math';

import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/money/money_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  /// Deterministik tohum — aynı girdi, aynı çıktı (rules/06 §7).
  final random = Random(20260813);

  test('format → parse tur döngüsü 10.000 değerde kayıpsızdır', () {
    for (var i = 0; i < 10000; i++) {
      final minor = random.nextInt(1000000000); // 0 – ₺10.000.000
      final money = Money(minor);
      final parsed = MoneyParser.parse(MoneyFormatter.format(money));
      expect(parsed.minor, minor, reason: 'minor=$minor');
    }
  });

  test('Money.sum toplamı 10.000 rastgele satırda birebir tutar', () {
    for (var i = 0; i < 10000; i++) {
      final lineCount = 1 + random.nextInt(20);
      final lines = <Money>[];
      var expected = 0;

      for (var j = 0; j < lineCount; j++) {
        final unitPrice = random.nextInt(100000); // ≤ ₺1.000
        final quantity = 1 + random.nextInt(50);
        lines.add(Money(unitPrice) * quantity);
        expected += unitPrice * quantity;
      }

      expect(Money.sum(lines).minor, expected);
    }
  });

  test('roundHalfUpDiv 10.000 kombinasyonda floor(a/b + 0.5) ile aynıdır', () {
    for (var i = 0; i < 10000; i++) {
      final numerator = random.nextInt(10000000);
      final denominator = 1 + random.nextInt(100000);

      final actual = Money.roundHalfUpDiv(numerator, denominator);

      // Bağımsız referans: tam sayı aritmetiğiyle floor((2a + b) / 2b)
      final expected = (2 * numerator + denominator) ~/ (2 * denominator);

      expect(actual, expected, reason: 'a=$numerator b=$denominator');
      // Sonuç daima gerçek bölümün ±1 komşuluğundadır.
      expect(actual, greaterThanOrEqualTo(numerator ~/ denominator));
      expect(actual, lessThanOrEqualTo(numerator ~/ denominator + 1));
    }
  });
}
