/// Recovery code testleri — **BR-AUTH-015/017 · REQ-AUTH-022 · EC-REC-011**
library;

import 'dart:math';

import 'package:canteen/domain/services/recovery_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('biçim — REQ-AUTH-022', () {
    test('XXXX-XXXX-XXXX-XXXX biçiminde üretilir', () {
      final code = RecoveryCode.generate(Random(1));

      expect(code, matches(RegExp(r'^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$')));
      expect(code, hasLength(19)); // 16 karakter + 3 tire
    });

    test('1.000 kodda YASAK karakter yok — 0 O 1 I l', () {
      final random = Random(7);

      for (var i = 0; i < 1000; i++) {
        final code = RecoveryCode.generate(random);
        for (final banned in const ['0', 'O', '1', 'I', 'L']) {
          expect(
            code,
            isNot(contains(banned)),
            reason:
                'docs/17 §8: karışma riski olan karakterler kullanılmaz. '
                'Üretilen: $code',
          );
        }
      }
    });

    test('alfabe 31 karakter ve karışan hiçbirini içermiyor', () {
      expect(RecoveryCode.alphabet, hasLength(31));
      for (final banned in const ['0', 'O', '1', 'I', 'L']) {
        expect(RecoveryCode.alphabet, isNot(contains(banned)));
      }
    });
  });

  group('rastgelelik', () {
    test('1.000 kodda tekrar YOK', () {
      final random = Random.secure();
      final codes = <String>{};

      for (var i = 0; i < 1000; i++) {
        codes.add(RecoveryCode.generate(random));
      }

      expect(codes.length, 1000);
    });

    test('alfabenin tamamı kullanılıyor — sistematik boşluk yok', () {
      final random = Random(99);
      final seen = <String>{};

      for (var i = 0; i < 2000; i++) {
        seen.addAll(RecoveryCode.generate(random).split('-').join().split(''));
      }

      expect(
        seen.length,
        RecoveryCode.alphabet.length,
        reason: '32 karakterin hepsi üretimde görülmeli.',
      );
    });

    test('aynı tohum aynı kodu üretir — rules/06 §7 determinizm', () {
      expect(
        RecoveryCode.generate(Random(42)),
        RecoveryCode.generate(Random(42)),
      );
    });
  });

  group('normalizasyon — EC-REC-011', () {
    const canonical = 'A7K2M9QX4RTB8ZWD';

    test('tire, boşluk ve harf durumu farkı AYNI koda çözülür', () {
      const variants = [
        'A7K2-M9QX-4RTB-8ZWD',
        'a7k2-m9qx-4rtb-8zwd',
        'A7K2M9QX4RTB8ZWD',
        'a7k2 m9qx 4rtb 8zwd',
        '  A7K2-m9QX-4rtb-8ZWD  ',
        'A7K2--M9QX--4RTB--8ZWD',
      ];

      for (final variant in variants) {
        expect(
          RecoveryCode.normalize(variant),
          canonical,
          reason: 'EC-REC-011: biçim farkı kodu geçersiz kılmamalı → $variant',
        );
      }
    });

    test('üretilen kod kendi normalizasyonuna eşit çözülür', () {
      final random = Random(3);

      for (var i = 0; i < 100; i++) {
        final code = RecoveryCode.generate(random);
        final normalized = RecoveryCode.normalize(code);

        expect(normalized, isNotNull);
        expect(RecoveryCode.format(normalized!), code);
      }
    });

    test('geçersiz girdiler null döner', () {
      const invalid = [
        '',
        'A7K2',
        'A7K2-M9QX-4RTB',
        'A7K2-M9QX-4RTB-8ZWD-EXTR', // çok uzun
        'A7K2-M9QX-4RTB-8ZW', // eksik
        'A7K2-M9QX-4RTB-8ZW!', // yasak sembol
        'O7K2-M9QX-4RTB-8ZWD', // O alfabede yok
        'I7K2-M9QX-4RTB-8ZWD', // I alfabede yok
        '07K2-M9QX-4RTB-8ZWD', // 0 alfabede yok
        '17K2-M9QX-4RTB-8ZWD', // 1 alfabede yok
      ];

      for (final input in invalid) {
        expect(
          RecoveryCode.normalize(input),
          isNull,
          reason: 'Geçersiz sayılmalıydı: "$input"',
        );
      }
    });

    test('küçük l ve i kabul EDİLMEZ — sessizce eşlenmez', () {
      // 'l' ve 'i' karışma riski taşıdığı için alfabede yok; başka bir
      // karaktere dönüştürülmeleri yanlış kodu doğru sanmaya yol açardı.
      expect(RecoveryCode.normalize('l7K2-M9QX-4RTB-8ZWD'), isNull);
      expect(RecoveryCode.normalize('i7K2-M9QX-4RTB-8ZWD'), isNull);
    });

    test('isValid normalize ile tutarlı', () {
      expect(RecoveryCode.isValid('a7k2m9qx4rtb8zwd'), isTrue);
      expect(RecoveryCode.isValid('A7K2'), isFalse);
    });
  });

  group('format', () {
    test('kanonik kodu 4\'lü gruplara böler', () {
      expect(RecoveryCode.format('A7K2M9QX4RTB8ZWD'), 'A7K2-M9QX-4RTB-8ZWD');
    });
  });
}
