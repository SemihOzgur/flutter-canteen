/// Parola hash'leme testleri — **BR-AUTH-011 · BR-SEC-001 · REQ-SEC-001/002**
///
/// docs/27 §3.6 önceliği: Authentication 🔴.
library;

import 'dart:math';

import 'package:canteen/domain/services/password_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('salt — kayıt başına rastgele (BR-AUTH-011)', () {
    test('aynı parola iki kez hash\'lenince FARKLI salt ve hash üretir', () {
      final hasher = PasswordHasher();

      final first = hasher.hash('aynı-parola');
      final second = hasher.hash('aynı-parola');

      expect(
        first.salt,
        isNot(second.salt),
        reason: 'BR-AUTH-011: salt kayıt başına rastgeledir.',
      );
      expect(
        first.hash,
        isNot(second.hash),
        reason:
            'Salt farklıysa hash de farklı olmalı — aksi hâlde salt hash\'e '
            'karışmıyor demektir.',
      );
    });

    test('1.000 salt üretiminde tekrar YOK', () {
      final hasher = PasswordHasher();
      final salts = <String>{};

      for (var i = 0; i < 1000; i++) {
        salts.add(hasher.hash('x').salt);
      }

      expect(salts.length, 1000);
    });

    test('salt 16 bayt = 32 hex karakter', () {
      expect(PasswordHasher().hash('x').salt, hasLength(32));
    });

    test('hash SHA-256 = 64 hex karakter', () {
      expect(PasswordHasher().hash('x').hash, hasLength(64));
    });
  });

  group('doğrulama', () {
    test('doğru parola kabul edilir', () {
      final hasher = PasswordHasher();
      final stored = hasher.hash('doğru-parola');

      expect(hasher.verify('doğru-parola', stored), isTrue);
    });

    test('yanlış parola reddedilir', () {
      final hasher = PasswordHasher();
      final stored = hasher.hash('doğru-parola');

      expect(hasher.verify('yanlış-parola', stored), isFalse);
      expect(hasher.verify('', stored), isFalse);
      expect(hasher.verify('doğru-parol', stored), isFalse);
      expect(hasher.verify('doğru-parolaa', stored), isFalse);
    });

    test('doğru parola YANLIŞ salt ile reddedilir', () {
      final hasher = PasswordHasher();
      final stored = hasher.hash('parola');
      final otherSalt = hasher.hash('parola');

      final mismatched = PasswordHash(hash: stored.hash, salt: otherSalt.salt);
      expect(hasher.verify('parola', mismatched), isFalse);
    });

    test('Türkçe karakter ve emoji içeren parola çalışır', () {
      final hasher = PasswordHasher();

      for (final parola in const ['şifreÇĞİÖÜ', 'gizli🔐kod', 'ğüşiöç']) {
        final stored = hasher.hash(parola);
        expect(hasher.verify(parola, stored), isTrue, reason: parola);
      }
    });

    test('büyük/küçük harf duyarlıdır', () {
      final hasher = PasswordHasher();
      final stored = hasher.hash('Parola');

      expect(hasher.verify('parola', stored), isFalse);
    });
  });

  group('determinizm — rules/06 §7', () {
    test('aynı tohumlu Random aynı salt\'ı üretir', () {
      final a = PasswordHasher.withRandom(Random(42));
      final b = PasswordHasher.withRandom(Random(42));

      expect(a.hash('parola'), b.hash('parola'));
    });

    test('aynı salt + aynı parola → aynı hash', () {
      final hasher = PasswordHasher();
      final stored = hasher.hash('parola');

      // Aynı salt'la yeniden doğrulama tekrarlanabilir olmalı.
      expect(hasher.verify('parola', stored), isTrue);
      expect(hasher.verify('parola', stored), isTrue);
    });
  });

  group('BR-SEC-001 — düz metin sızıntısı yok', () {
    test('PasswordHash.toString düz metin, hash veya salt SIZDIRMAZ', () {
      final hasher = PasswordHasher();
      final stored = hasher.hash('ÇOK-GİZLİ-PAROLA');

      final metin = stored.toString();
      expect(metin, isNot(contains('ÇOK-GİZLİ-PAROLA')));
      expect(
        metin,
        isNot(contains(stored.hash)),
        reason: 'rules/04 §8: hash değeri de loglanmaz.',
      );
      expect(metin, isNot(contains(stored.salt)));
    });

    test('hash çıktısı düz metni İÇERMEZ', () {
      final hasher = PasswordHasher();
      final stored = hasher.hash('parola123');

      expect(stored.hash, isNot(contains('parola123')));
      expect(stored.salt, isNot(contains('parola123')));
    });
  });
}
