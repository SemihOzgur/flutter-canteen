/// Money birim testleri.
///
/// docs/27-testing-strategy.md §3.1
/// BR-FIN-001 (integer kuruş) · BR-FIN-003 (half-up) · BR-FIN-004 (toplam = satırlar)
/// BR-FIN-005 (tr_TR gösterim) · REQ-FIN-006 (`,` ve `.` kabulü)
library;

import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/money/money_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Money — aritmetik (BR-FIN-001)', () {
    test('toplama ve çıkarma kayıpsızdır', () {
      expect((const Money(2550) + const Money(1000)).minor, 3550);
      expect((const Money(2550) - const Money(1000)).minor, 1550);
    });

    test('miktarla çarpım tam sayıdır', () {
      expect((const Money(2550) * 3).minor, 7650);
      expect((const Money(1) * 7).minor, 7);
      expect((const Money(2550) * 1).minor, 2550);
    });

    test('karşılaştırma ve eşitlik', () {
      expect(const Money(100) < const Money(200), isTrue);
      expect(const Money(200) >= const Money(200), isTrue);
      expect(const Money(2550) == const Money(2550), isTrue);
      expect(const Money(2550).hashCode, const Money(2550).hashCode);
    });

    test('zero ve isZero', () {
      expect(Money.zero.minor, 0);
      expect(Money.zero.isZero, isTrue);
      expect(const Money(1).isZero, isFalse);
    });
  });

  group('Money.sum — REQ-FIN-004', () {
    test('satır tutarlarının toplamı genel toplama eşittir', () {
      // docs/07 §9 acceptance criteria: ₺12,33×1 + ₺7,49×3 + ₺0,99×7
      final lines = [
        const Money(1233) * 1,
        const Money(749) * 3,
        const Money(99) * 7,
      ];
      expect(Money.sum(lines).minor, 1233 + 2247 + 693);
      expect(Money.sum(lines).minor, 4173);
    });

    test('boş liste sıfır döner', () {
      expect(Money.sum(const []).minor, 0);
    });
  });

  group('Money.roundHalfUpDiv — BR-FIN-003', () {
    test('yarım değerler YUKARI yuvarlanır', () {
      expect(Money.roundHalfUpDiv(1, 2), 1); // 0,5 → 1
      expect(Money.roundHalfUpDiv(3, 2), 2); // 1,5 → 2
      expect(Money.roundHalfUpDiv(5, 2), 3); // 2,5 → 3  (banker's olsaydı 2)
    });

    test('yarımın altı aşağı, üstü yukarı', () {
      expect(Money.roundHalfUpDiv(1, 3), 0); // 0,33
      expect(Money.roundHalfUpDiv(2, 3), 1); // 0,67
      expect(Money.roundHalfUpDiv(1, 5), 0); // 0,2
      expect(Money.roundHalfUpDiv(3, 5), 1); // 0,6
    });

    test('tam bölünme', () {
      expect(Money.roundHalfUpDiv(10, 5), 2);
      expect(Money.roundHalfUpDiv(0, 7), 0);
    });

    test('geçersiz girdi reddedilir', () {
      expect(() => Money.roundHalfUpDiv(1, 0), throwsArgumentError);
      expect(() => Money.roundHalfUpDiv(1, -2), throwsArgumentError);
      expect(() => Money.roundHalfUpDiv(-1, 2), throwsArgumentError);
    });
  });

  group('MoneyFormatter.format — BR-FIN-005', () {
    test('temel biçimlendirme', () {
      expect(MoneyFormatter.format(const Money(2550)), '₺25,50');
      expect(MoneyFormatter.format(const Money(0)), '₺0,00');
      expect(MoneyFormatter.format(const Money(5)), '₺0,05');
      expect(MoneyFormatter.format(const Money(100)), '₺1,00');
    });

    test('daima iki ondalık basamak', () {
      expect(MoneyFormatter.format(const Money(2500)), '₺25,00');
      expect(MoneyFormatter.format(const Money(2505)), '₺25,05');
    });

    test('binlik ayırıcı nokta', () {
      expect(MoneyFormatter.format(const Money(123400)), '₺1.234,00');
      expect(MoneyFormatter.format(const Money(123456)), '₺1.234,56');
      expect(MoneyFormatter.format(const Money(100000000)), '₺1.000.000,00');
      expect(MoneyFormatter.format(const Money(99999)), '₺999,99');
    });

    test('negatif tutar U+2212 ile gösterilir', () {
      expect(MoneyFormatter.format(const Money(-2550)), '−₺25,50');
    });
  });

  group('MoneyParser — REQ-FIN-006', () {
    test('kabul edilen biçimler', () {
      expect(MoneyParser.parse('25,50').minor, 2550);
      expect(MoneyParser.parse('25.50').minor, 2550);
      expect(MoneyParser.parse('25').minor, 2500);
      expect(MoneyParser.parse('₺25,50').minor, 2550);
      expect(MoneyParser.parse(' 25,50 ').minor, 2550);
      expect(MoneyParser.parse('1.234,56').minor, 123456);
      expect(MoneyParser.parse('0,05').minor, 5);
      expect(MoneyParser.parse('0').minor, 0);
    });

    test('tek ondalık basamak ikiye tamamlanır', () {
      expect(MoneyParser.parse('25,5').minor, 2550);
    });

    test('tr_TR binlik okuması', () {
      expect(MoneyParser.parse('1.234').minor, 123400);
      expect(MoneyParser.parse('1.234.567').minor, 123456700);
    });

    test('negatif değer', () {
      expect(MoneyParser.parse('-25,50').minor, -2550);
      expect(MoneyParser.parse('−25,50').minor, -2550);
    });

    test('geçersiz girdi reddedilir', () {
      expect(MoneyParser.tryParse('abc'), isNull);
      expect(MoneyParser.tryParse(''), isNull);
      expect(MoneyParser.tryParse('   '), isNull);
      expect(MoneyParser.tryParse('25,5,5'), isNull);
      expect(MoneyParser.tryParse('25,555'), isNull); // 2'den fazla ondalık
      expect(MoneyParser.tryParse('12,34.56'), isNull); // ters sıra
      expect(() => MoneyParser.parse('abc'), throwsFormatException);
    });

    test('format → parse tur döngüsü kayıpsızdır', () {
      for (final minor in [0, 5, 99, 100, 2550, 123456, 100000000]) {
        final formatted = MoneyFormatter.format(Money(minor));
        expect(MoneyParser.parse(formatted).minor, minor, reason: formatted);
      }
    });
  });
}
