/// UUID v4 üretimi — **REQ-IMG-002** (görsel dosyaları UUID ile adlandırılır).
///
/// ## Neden ayrı paket eklenmedi
///
/// `rules/01 §7` dört soru: (1) gerekli — dosya adı UUID olmalı, (2) **Dart
/// standart kütüphanesiyle çözülebilir** — `Random.secure` + RFC 4122 bit
/// maskesi yeterli, (3) mevcut bağımlılıkların hiçbiri UUID üretmiyor,
/// (4) bakım maliyeti eklemenin gerekçesi yok. Soru (2) "evet" olduğu için
/// paket **eklenmez.**
///
/// ## Neden rastgelelik enjekte edilir
///
/// `rules/06 §7` — determinizm: testte tohumlu [Random] verilir ve üretilen
/// ad öngörülebilir olur. Üretimde daima [Random.secure] geçilir.
/// Desen `domain/services/recovery_code.dart` ile aynıdır.
library;

import 'dart:math';

/// RFC 4122 sürüm 4 (rastgele) UUID.
abstract final class UuidV4 {
  static const String _hex = '0123456789abcdef';

  /// `xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx` biçiminde yeni bir UUID.
  ///
  /// 13. hane daima `4` (sürüm), 17. hane `8/9/a/b` (varyant).
  static String generate(Random random) {
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));

    // Sürüm 4: yüksek nibble = 0100
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    // Varyant RFC 4122: iki yüksek bit = 10
    bytes[8] = (bytes[8] & 0x3f) | 0x80;

    final buffer = StringBuffer();
    for (var i = 0; i < bytes.length; i++) {
      if (i == 4 || i == 6 || i == 8 || i == 10) buffer.write('-');
      buffer
        ..write(_hex[(bytes[i] >> 4) & 0x0f])
        ..write(_hex[bytes[i] & 0x0f]);
    }
    return buffer.toString();
  }

  /// Bir metnin UUID v4 biçiminde olup olmadığı — testler ve dosya adı
  /// doğrulaması için.
  static bool isValid(String value) => _pattern.hasMatch(value);

  static final RegExp _pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
}
