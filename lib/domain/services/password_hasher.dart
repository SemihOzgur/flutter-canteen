/// Parola ve recovery code hash'leme — **BR-AUTH-011 · BR-SEC-001 · OD-003**
///
/// Aynı mekanizma üç yerde kullanılır (docs/17 §6):
/// kullanıcı parolası · dashboard parolası · recovery code.
///
/// ## Yöntem: kayıt başına rastgele salt + SHA-256
///
/// `docs/17` bcrypt/Argon2'yi **açıkça kapsam dışı** bırakır: tehdit modeli dar
/// (yerel, ağsız, tek makine), uzaktan saldırı yüzeyi yok. "Daha güvenli olur"
/// gerekçesiyle değiştirilemez — bu bir business kararıdır
/// (`rules/04 §6`, `docs/28` OD-003).
///
/// ## Düz metin YASAK
///
/// BR-SEC-001: düz metin parola veya kod hiçbir tabloya, log'a, audit kaydına,
/// export'a veya yedeğe yazılmaz. Bu sınıf yalnızca [PasswordHash] döndürür;
/// düz metni hiçbir yerde saklamaz.
library;

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Bir parolanın saklanabilir hâli: hash + onu üreten salt.
///
/// İkisi **birlikte** saklanır; salt gizli değildir, tekrarı engellemek içindir.
class PasswordHash {
  /// Hex kodlanmış SHA-256 çıktısı.
  final String hash;

  /// Hex kodlanmış, bu kayda özgü rastgele salt.
  final String salt;

  const PasswordHash({required this.hash, required this.salt});

  @override
  bool operator ==(Object other) =>
      other is PasswordHash && other.hash == hash && other.salt == salt;

  @override
  int get hashCode => Object.hash(hash, salt);

  /// Düz metin **sızdırmaz** — hash/salt değerleri de basılmaz (rules/04 §8).
  @override
  String toString() => 'PasswordHash(<gizli>)';
}

/// Salt'lı SHA-256 hash'leme.
///
/// Rastgelelik dışarıdan enjekte edilir (`rules/06 §7` — determinizm): test
/// tohumlu bir [Random] verir, üretim [Random.secure] kullanır.
class PasswordHasher {
  /// Salt uzunluğu (bayt). 16 bayt = 128 bit; sözlük/rainbow tablosu
  /// paylaşımını engellemek için fazlasıyla yeterlidir.
  static const int saltBytes = 16;

  final Random _random;

  /// Üretim kullanımı — kriptografik olarak güvenli entropi.
  PasswordHasher() : _random = Random.secure();

  /// Test kullanımı — deterministik entropi.
  const PasswordHasher.withRandom(Random random) : _random = random;

  /// Yeni bir salt üretip [plainText]'i hash'ler.
  ///
  /// Her çağrı **farklı** salt üretir; aynı parola iki kullanıcıda aynı hash'i
  /// vermez.
  PasswordHash hash(String plainText) {
    final salt = _generateSalt();
    return PasswordHash(hash: _digest(plainText, salt), salt: salt);
  }

  /// [plainText]'in [stored]'a karşılık gelip gelmediğini döndürür.
  ///
  /// Doğrulama, saklanan salt ile yeniden hash'leyip karşılaştırarak yapılır.
  bool verify(String plainText, PasswordHash stored) {
    final computed = _digest(plainText, stored.salt);
    return _constantTimeEquals(computed, stored.hash);
  }

  String _generateSalt() {
    final bytes = List<int>.generate(
      saltBytes,
      (_) => _random.nextInt(256),
      growable: false,
    );
    return _toHex(bytes);
  }

  /// `SHA-256(salt || plainText)` — UTF-8 baytları üzerinden.
  String _digest(String plainText, String salt) {
    final input = utf8.encode('$salt$plainText');
    return _toHex(sha256.convert(input).bytes);
  }

  static String _toHex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Uzunluk ve içerik farkını erken döndürmeyen karşılaştırma.
  ///
  /// Yerel bir uygulamada zamanlama saldırısı gerçekçi bir tehdit değildir;
  /// yine de hash karşılaştırmasında erken çıkış yapmamak ucuz bir alışkanlıktır.
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
