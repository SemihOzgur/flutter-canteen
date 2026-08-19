/// Barkod normalizasyonu ve kontrol hanesi testleri —
/// **docs/11 §3 · BR-BARC-009 · EC-PROD-014/015**
library;

import 'package:canteen/domain/services/barcode_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalize — docs/11 §3', () {
    test('EC-PROD-014 · BR-BARC-009 — BAŞTAKİ SIFIR KORUNUR', () {
      expect(BarcodeRules.normalize('0123'), '0123');
      expect(BarcodeRules.normalize('0000000000000'), '0000000000000');
      expect(BarcodeRules.normalize(' 0123456789012 '), '0123456789012');
    });

    test('UPC-A ve EAN-13 baştaki sıfırla ayrışır — farklı barkodlardır', () {
      expect(
        BarcodeRules.normalize('0123456789012'),
        isNot(BarcodeRules.normalize('123456789012')),
      );
    });

    test('baştaki/sondaki boşluk kırpılır', () {
      expect(BarcodeRules.normalize('  8691234567890  '), '8691234567890');
    });

    test('görünmez karakterler temizlenir (scanner CR/LF ekler)', () {
      expect(BarcodeRules.normalize('8691234567890\r\n'), '8691234567890');
      expect(BarcodeRules.normalize('869\t123'), '869123');
      expect(BarcodeRules.normalize('​869﻿123'), '869123');
    });

    test('büyük harfe çevrilir — Code 39 alfanümerik', () {
      expect(BarcodeRules.normalize('ab-12c'), 'AB-12C');
    });

    test('boş girdi boş kalır', () {
      expect(BarcodeRules.normalize('   '), '');
      expect(BarcodeRules.normalize('\r\n'), '');
    });
  });

  group('kontrol hanesi — docs/11 §3 · EC-PROD-015', () {
    test('geçerli EAN-13', () {
      // Gerçek EAN-13 örnekleri.
      expect(BarcodeRules.isChecksumValid('4006381333931'), isTrue);
      expect(BarcodeRules.isChecksumValid('5901234123457'), isTrue);
    });

    test('geçersiz EAN-13 — son hane bozuk', () {
      expect(BarcodeRules.isChecksumValid('4006381333932'), isFalse);
      expect(BarcodeRules.isChecksumValid('5901234123458'), isFalse);
    });

    test('geçerli EAN-8', () {
      expect(BarcodeRules.isChecksumValid('96385074'), isTrue);
    });

    test('geçerli UPC-A', () {
      expect(BarcodeRules.isChecksumValid('036000291452'), isTrue);
    });

    test('kural uygulanamayan girdiler null döner', () {
      // Mağaza içi barkodlar ve Code 39 alfanümerikler kapsam dışıdır.
      expect(BarcodeRules.isChecksumValid('12345'), isNull);
      expect(BarcodeRules.isChecksumValid('ABC12345'), isNull);
      expect(BarcodeRules.isChecksumValid(''), isNull);
    });

    test('baştaki sıfırlı EAN-13 doğru hesaplanır', () {
      // UPC-A "036000291452" başına 0 eklenerek EAN-13 olur; kontrol hanesi
      // değişmez. Sayıya çevrilen bir implementasyon burada patlardı.
      expect(BarcodeRules.isChecksumValid('0036000291452'), isTrue);
    });
  });
}
