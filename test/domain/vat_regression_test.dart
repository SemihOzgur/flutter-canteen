/// KDV REGRESYON KORUMASI.
///
/// rules/06 §2 · docs/27 §3.2:
///   "**VAT regresyonu** — KDV'nin fiyatın **üzerine eklenmediğini** doğrulayan
///    **açık test**"
///
/// BR-VAT-003: Satış fiyatı KDV DAHİLDİR. KDV fiyatın **içinden çıkarılır.**
///
/// Bu dosyanın tek amacı, ileride birinin KDV'yi fiyatın üzerine ekleyen bir
/// implementasyona geçmesini **derhal yakalamaktır.** Projedeki en kritik
/// finansal regresyon riski budur (docs/29 — kapanan RSK-009).
library;

import 'package:canteen/core/money/money.dart';
import 'package:canteen/domain/services/vat_calculator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('REGRESYON — KDV fiyatın ÜZERİNE EKLENMEZ (BR-VAT-003)', () {
    test('brüt tutar girdiyle birebir aynı kalır, büyümez', () {
      const enteredPrice = Money(12000); // kullanıcı ₺120,00 girdi

      final r = VatCalculator.fromGross(gross: enteredPrice, vatRateBp: 2000);

      // Müşteriden alınan tutar girilen fiyattır — REQ-VAT-007
      expect(
        r.gross.minor,
        12000,
        reason:
            'Brüt tutar girilen fiyattan FARKLI! KDV üzerine eklenmiş olabilir.',
      );

      // KDV hariç senaryosu olsaydı brüt 14400 olurdu — bu ASLA olmamalı
      expect(
        r.gross.minor,
        isNot(14400),
        reason: 'KDV fiyatın üzerine eklenmiş — BR-VAT-003 İHLALİ!',
      );
    });

    test('matrah brüt tutardan KÜÇÜKTÜR (KDV içeriden çıkarılıyor)', () {
      final r = VatCalculator.fromGross(
        gross: const Money(12000),
        vatRateBp: 2000,
      );

      expect(
        r.net.minor,
        lessThan(r.gross.minor),
        reason: 'Matrah brütten küçük olmalı; KDV içeriden çıkarılır.',
      );
      expect(r.net.minor, 10000);
    });

    test('KDV hariç formülü kullanılsaydı çıkacak değerler ÜRETİLMEZ', () {
      const gross = Money(10000);
      const rateBp = 2000;

      final r = VatCalculator.fromGross(gross: gross, vatRateBp: rateBp);

      // YANLIŞ (KDV hariç) formül: vat = net × bp / 10000 = 10000 × 0,20 = 2000
      const wrongVatIfExclusive = 2000;
      expect(
        r.vat.minor,
        isNot(wrongVatIfExclusive),
        reason:
            'KDV, matrah üzerinden hesaplanmış — yanlış formül kullanılıyor!',
      );

      // DOĞRU (KDV dahil) formül: 10000 × 2000 / 12000 = 1666,67 → 1667
      expect(r.vat.minor, 1667);
    });

    test('birden fazla oranda brüt korunur', () {
      for (final rate in [0, 100, 1000, 1800, 2000, 2500]) {
        const gross = Money(50000);
        final r = VatCalculator.fromGross(gross: gross, vatRateBp: rate);

        expect(
          r.gross.minor,
          50000,
          reason: 'rate=$rate için brüt değişti — KDV eklenmiş olabilir!',
        );
        expect(
          r.net.minor + r.vat.minor,
          50000,
          reason: 'rate=$rate invariant bozuldu',
        );
        expect(r.net.minor, lessThanOrEqualTo(50000));
      }
    });

    test('satır bazında da brüt = birim fiyat × miktar', () {
      final r = VatCalculator.forLine(
        unitPrice: const Money(2500),
        quantity: 4,
        vatRateBp: 2000,
      );

      expect(
        r.gross.minor,
        2500 * 4,
        reason:
            'Satır brütü birim fiyat × miktardan farklı — KDV eklenmiş olabilir!',
      );
      expect(r.gross.minor, 10000);
    });
  });
}
