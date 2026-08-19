/// Türkçe metin katlaması — **REQ-PROD-010 · docs/09 §6**
///
/// Ürün araması hem büyük/küçük harfe hem de Türkçe karakterlere **duyarsızdır**:
/// `ı/i` · `ş/s` · `ğ/g` · `ü/u` · `ö/o` · `ç/c`.
///
/// Saf Dart: Flutter, Drift veya dosya sistemi bağımlılığı **yoktur**
/// (rules/01 §1). Katlama tek merkezî implementasyondur (rules/01 §2): hem
/// SQLite'a kaydedilen skaler fonksiyon hem de Dart tarafındaki arama terimi
/// bu sınıfı kullanır. İkisi ayrı yazılsaydı sorgu, eşleşmesi gereken satırı
/// sessizce atlardı.
///
/// ## Neden `toLowerCase()` yetmez
///
/// Dart'ın `toLowerCase()`'i locale bağımsızdır ve Unicode kuralını uygular:
///
/// ```text
/// 'IŞIL'.toLowerCase()  →  'işil'      ← 'I' → 'i', beklenen 'ı'
/// 'İ'.toLowerCase()     →  'i' + U+0307 (birleşik nokta)
/// ```
///
/// Arama katlamasında `ı` ve `i` **zaten aynı harfe** indiği için bu fark
/// sonucu değiştirmez; yine de birleşik nokta atılmalıdır, aksi hâlde
/// `'İSTANBUL'` ile `'istanbul'` farklı dizeler olurdu.
///
/// ## `AuthService.normalizeUsername` ile ilişkisi
///
/// İkisi **farklı işlerdir** ve birleştirilemez:
///
/// | | Katlanan |
/// |---|---|
/// | `normalizeUsername` (REQ-AUTH-012) | yalnızca `ı/i` — kullanıcı adı **kimliktir** |
/// | [TurkishText.fold] (REQ-PROD-010) | altı Türkçe harf çifti — arama **hoşgörülü** olmalıdır |
///
/// Kullanıcı adı katlaması genişletilseydi `Şule` ile `Sule` aynı hesap olurdu.
library;

abstract final class TurkishText {
  /// Arama karşılaştırması için metni katlar.
  ///
  /// Sonuç yalnızca karşılaştırma amaçlıdır; kullanıcıya **gösterilmez** ve
  /// hiçbir yere kaydedilmez.
  static String fold(String value) {
    final buffer = StringBuffer();

    for (final rune in value.runes) {
      switch (rune) {
        // I (U+0049) · ı (U+0131) · İ (U+0130) · i (U+0069)
        case 0x0049:
        case 0x0131:
        case 0x0130:
        case 0x0069:
          buffer.write('i');
        // Ş (U+015E) · ş (U+015F)
        case 0x015E:
        case 0x015F:
          buffer.write('s');
        // Ğ (U+011E) · ğ (U+011F)
        case 0x011E:
        case 0x011F:
          buffer.write('g');
        // Ü (U+00DC) · ü (U+00FC)
        case 0x00DC:
        case 0x00FC:
          buffer.write('u');
        // Ö (U+00D6) · ö (U+00F6)
        case 0x00D6:
        case 0x00F6:
          buffer.write('o');
        // Ç (U+00C7) · ç (U+00E7)
        case 0x00C7:
        case 0x00E7:
          buffer.write('c');
        // Birleşik nokta (U+0307) — `'İ'.toLowerCase()` üretir; `İ` yukarıda
        // zaten `i`'ye indiği için burada kalanı atılır.
        case 0x0307:
          break;
        default:
          buffer.write(String.fromCharCode(rune).toLowerCase());
      }
    }

    return buffer.toString();
  }
}
