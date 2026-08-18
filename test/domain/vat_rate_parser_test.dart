/// KDV oranı ayrıştırma — **BR-FIN-002 · rules/02 §1**
///
/// Oran daima **basis point tam sayıdır**: `%20 → 2000`, `%0,5 → 50`.
/// Hiçbir aşamada `double` kullanılmaz.
library;

import 'package:canteen/domain/services/vat_rate_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VatRateParser — tr_TR girdi', () {
    test('tam sayı yüzde basis point olur', () {
      expect(VatRateParser.tryParseBasisPoints('20'), 2000);
      expect(VatRateParser.tryParseBasisPoints('1'), 100);
      expect(VatRateParser.tryParseBasisPoints('0'), 0);
      expect(VatRateParser.tryParseBasisPoints('100'), 10000);
    });

    test('tr_TR ondalık VİRGÜL kabul edilir (%0,5 → 50)', () {
      expect(VatRateParser.tryParseBasisPoints('0,5'), 50);
      expect(VatRateParser.tryParseBasisPoints('0,05'), 5);
      expect(VatRateParser.tryParseBasisPoints('18,5'), 1850);
      expect(VatRateParser.tryParseBasisPoints('7,25'), 725);
    });

    test('nokta da ondalık ayırıcı olarak kabul edilir (REQ-FIN-006)', () {
      expect(VatRateParser.tryParseBasisPoints('0.5'), 50);
      expect(VatRateParser.tryParseBasisPoints('18.5'), 1850);
    });

    test('yüzde işareti başta veya sonda olabilir', () {
      expect(VatRateParser.tryParseBasisPoints('%20'), 2000);
      expect(VatRateParser.tryParseBasisPoints('20%'), 2000);
      expect(VatRateParser.tryParseBasisPoints('  %0,5  '), 50);
    });

    test('boş ve anlamsız girdi reddedilir', () {
      expect(VatRateParser.tryParseBasisPoints(''), isNull);
      expect(VatRateParser.tryParseBasisPoints('   '), isNull);
      expect(VatRateParser.tryParseBasisPoints('%'), isNull);
      expect(VatRateParser.tryParseBasisPoints('abc'), isNull);
      expect(VatRateParser.tryParseBasisPoints('%20%'), isNull);
    });

    test('iç boşluk MoneyParser davranışını devralır — yok sayılır', () {
      // `MoneyParser` kırılmaz boşluğu temizlemek için tüm boşlukları atar
      // (core/money/money_formatter.dart). Oran ayrıştırması aynı dilbilgisini
      // paylaştığı için bu davranışı da devralır; bu test onu **kayıt altına
      // alır**, böylece MoneyParser değişirse burada görünür.
      expect(VatRateParser.tryParseBasisPoints('2 0'), 2000);
    });

    test('negatif oran reddedilir (CHECK(rate_basis_points >= 0))', () {
      expect(VatRateParser.tryParseBasisPoints('-1'), isNull);
      expect(VatRateParser.tryParseBasisPoints('-0,5'), isNull);
      expect(VatRateParser.tryParseBasisPoints('%-20'), isNull);
    });

    test('ikiden fazla ondalık basamak reddedilir — tam sayı bp değildir', () {
      expect(VatRateParser.tryParseBasisPoints('0,005'), isNull);
      expect(VatRateParser.tryParseBasisPoints('20,123'), isNull);
    });

    test('para sembolü bir oran girdisinde kabul edilmez', () {
      expect(VatRateParser.tryParseBasisPoints('₺20'), isNull);
    });

    test('parseBasisPoints geçersiz girdide FormatException fırlatır', () {
      expect(
        () => VatRateParser.parseBasisPoints('abc'),
        throwsFormatException,
      );
      expect(VatRateParser.parseBasisPoints('%20'), 2000);
    });
  });

  group('Ölçek doğrulaması — rules/02 §1', () {
    test('dokümandaki üç örnek birebir tutar', () {
      // rules/02 §1: "%20 → 2000, %0,5 → 50"; docs/08 §3: "%1 → 100".
      expect(VatRateParser.tryParseBasisPoints('20'), 2000);
      expect(VatRateParser.tryParseBasisPoints('1'), 100);
      expect(VatRateParser.tryParseBasisPoints('0,5'), 50);
    });
  });
}
