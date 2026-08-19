/// Türkçe arama katlaması testleri — **REQ-PROD-010 · docs/09 §6**
///
/// Katlama saf domain kuralıdır; veritabanı gerekmez (rules/01 §2).
library;

import 'package:canteen/domain/services/turkish_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('altı Türkçe harf çifti katlanır (docs/09 §6)', () {
    const pairs = <String, String>{
      'ı': 'i',
      'I': 'i',
      'İ': 'i',
      'i': 'i',
      'ş': 's',
      'Ş': 's',
      'ğ': 'g',
      'Ğ': 'g',
      'ü': 'u',
      'Ü': 'u',
      'ö': 'o',
      'Ö': 'o',
      'ç': 'c',
      'Ç': 'c',
    };

    pairs.forEach((input, expected) {
      test('$input → $expected', () {
        expect(TurkishText.fold(input), expected);
      });
    });
  });

  test('büyük/küçük harf duyarsızdır', () {
    expect(TurkishText.fold('KOLA'), TurkishText.fold('kola'));
    expect(TurkishText.fold('Kola'), 'kola');
  });

  test('Dart\'ın toLowerCase() tuzağı: IŞIL', () {
    // 'IŞIL'.toLowerCase() → 'işil' üretir ('ışıl' değil). Katlamada `ı` ve `i`
    // aynı harfe indiği için sonuç yine de eşleşmelidir.
    expect(TurkishText.fold('IŞIL'), 'isil');
    expect(TurkishText.fold('ışıl'), 'isil');
    expect(TurkishText.fold('Işıl'), TurkishText.fold('ISIL'));
  });

  test('İ birleşik nokta bırakmaz', () {
    expect(TurkishText.fold('İSTANBUL'), 'istanbul');
    expect(TurkishText.fold('İstanbul'), TurkishText.fold('istanbul'));
    expect(TurkishText.fold('İ').length, 1);
  });

  test('gerçek ürün adları — arama eşleşmesi', () {
    expect(TurkishText.fold('Çilekli Süt'), 'cilekli sut');
    expect(TurkishText.fold('ÇİLEKLİ SÜT'), 'cilekli sut');
    expect(TurkishText.fold('Beyaz Peynir 500 g'), 'beyaz peynir 500 g');
    expect(TurkishText.fold('Ayçiçek Yağı'), 'aycicek yagi');
  });

  test('boş ve nötr girdiler', () {
    expect(TurkishText.fold(''), '');
    expect(TurkishText.fold('   '), '   ');
    expect(TurkishText.fold('8691234567890'), '8691234567890');
  });

  test('deterministiktir — aynı girdi aynı çıktı', () {
    const input = 'Şeftali Suyu ÖZEL';
    expect(TurkishText.fold(input), TurkishText.fold(input));
  });

  test('katlanmış metin idempotenttir', () {
    const input = 'Çğıöşü ÇĞIÖŞÜ';
    final once = TurkishText.fold(input);
    expect(TurkishText.fold(once), once);
  });
}
