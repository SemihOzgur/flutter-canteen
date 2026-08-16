/// Recovery code üretimi ve normalizasyonu — **BR-AUTH-015/017 · REQ-AUTH-022**
///
/// Dashboard parolası unutulduğunda kullanılan **tek kullanımlık** koddur.
/// Kod yalnızca hash olarak saklanır ([PasswordHasher]); düz metni hiçbir
/// yerde tutulmaz (BR-SEC-001, `rules/04 §5`).
///
/// ## Biçim
///
/// ```text
/// XXXX-XXXX-XXXX-XXXX        örn.  A7K2-M9QX-4RTB-8ZWD
/// ```
///
/// ## Alfabe
///
/// `docs/17 §8` yalnızca şu kısıtı koyar: *16 karakter, 4'lü gruplar,
/// kriptografik rastgele, karışma riski olan `0/O` ve `1/I/l` **kullanılmaz***.
/// Tam karakter kümesini sabitlemez.
///
/// Bu kısıtı sağlayan küme burada seçilmiştir: `A–Z` (**I, L, O** çıkarılmış) +
/// `2–9` = **31 karakter**. 16 hane → `31^16` ≈ **79 bit** entropi; kod tek
/// kullanımlık ve yerel olduğu için fazlasıyla yeterlidir.
///
/// `L` de dışlanır: doküman karışanları `1/I/l` diye **küçük `l` ile birlikte**
/// sayar, ve elle yazılan bir kodda `l`/`1`/`I` ayrımı kaybolur. Aynı gerekçeyle
/// Crockford Base32 da `I`, `L`, `O`'yu dışlar. Entropi maliyeti (80 → 79 bit)
/// ihmal edilebilir.
library;

import 'dart:math';

/// Kurtarma kodu biçim kuralları ve üretimi.
///
/// Saf fonksiyonlar; rastgelelik dışarıdan enjekte edilir (`rules/06 §7`).
abstract final class RecoveryCode {
  /// İzin verilen karakterler — `0`, `1`, `I`, `L`, `O` bilinçli olarak yok.
  static const String alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

  /// Grup uzunluğu ve grup sayısı — `XXXX-XXXX-XXXX-XXXX`.
  static const int groupLength = 4;
  static const int groupCount = 4;

  /// Tire hariç toplam karakter sayısı.
  static const int length = groupLength * groupCount;

  static const String _separator = '-';

  /// Yeni bir kod üretir ve **gösterim biçiminde** döndürür.
  ///
  /// Üretimde [Random.secure] geçilmelidir; test tohumlu [Random] kullanır.
  static String generate(Random random) {
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return format(buffer.toString());
  }

  /// Kanonik kodu `XXXX-XXXX-XXXX-XXXX` biçimine sokar.
  static String format(String canonical) {
    final groups = <String>[];
    for (var i = 0; i < canonical.length; i += groupLength) {
      groups.add(
        canonical.substring(i, min(i + groupLength, canonical.length)),
      );
    }
    return groups.join(_separator);
  }

  /// Kullanıcı girdisini **kanonik** forma çevirir; geçersizse `null`.
  ///
  /// EC-REC-011: kullanıcı kodu tire olmadan, küçük harfle veya araya boşluk
  /// koyarak girebilir — hepsi aynı koda çözülmelidir. Karşılaştırma ve
  /// hash'leme **daima** bu kanonik form üzerinden yapılır, aksi hâlde doğru
  /// kod biçim farkı yüzünden reddedilirdi.
  ///
  /// `null` dönmesi "biçim geçersiz" demektir; "kod yanlış" demek **değildir**.
  /// Çağıran ikisini ayırt etmemeli, kullanıcıya aynı genel mesajı vermelidir
  /// (EC-AUTH-001 ile aynı gerekçe).
  static String? normalize(String input) {
    final buffer = StringBuffer();

    for (final rune in input.runes) {
      final char = String.fromCharCode(rune);
      if (char == _separator || char.trim().isEmpty) continue;

      // `toUpperCase` locale bağımsızdır: 'i' → 'I'. 'I' alfabede olmadığı
      // için zaten reddedilir — karışma riski taşıyan karakterler kabul
      // edilmez, sessizce başka bir karaktere eşlenmez.
      final upper = char.toUpperCase();
      if (!alphabet.contains(upper)) return null;
      buffer.write(upper);
    }

    return buffer.length == length ? buffer.toString() : null;
  }

  /// Girdi geçerli bir koda çözülüyor mu.
  static bool isValid(String input) => normalize(input) != null;
}
