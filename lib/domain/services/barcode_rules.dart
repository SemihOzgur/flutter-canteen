/// Barkod normalizasyonu ve kontrol hanesi — **docs/11 §3 · BR-BARC-009**
///
/// Saf Dart (rules/01 §1). Scanner/HID girdisinin **ayrıştırılması** Faz 4
/// kapsamındadır; burada yalnızca ürün formunun barkod alanına giren metnin
/// kurallı hâle getirilmesi vardır.
///
/// ## Barkod METİNDİR
///
/// EC-PROD-014 · BR-BARC-009: barkod hiçbir aşamada sayısal tipe
/// dönüştürülmez. `0123456789012` (EAN-13) ile `123456789012` (UPC-A)
/// **farklı barkodlardır**; baştaki sıfır kaybolursa ürünler birbirine karışır.
library;

abstract final class BarcodeRules {
  /// docs/11 §3 — kaydetmeden ve aramadan önce uygulanır.
  ///
  /// 1. Baştaki/sondaki boşluklar kırpılır
  /// 2. Görünmez karakterler temizlenir (`\r`, `\n`, `\t`, sıfır genişlikli)
  /// 3. Büyük harfe çevrilir (Code 39 alfanümerik barkodlar için)
  /// 4. **Baştaki sıfırlar korunur**
  ///
  /// Kelime arası boşluk **silinmez**: Code 128 boşluk kodlayabilir ve
  /// docs/11 §3 yalnızca görünmez karakterleri sayar.
  static String normalize(String raw) {
    final buffer = StringBuffer();

    for (final rune in raw.trim().runes) {
      switch (rune) {
        // \t \n \v \f \r ve diğer C0 kontrol karakterleri
        case < 0x20:
        // DEL
        case 0x7F:
        // Sıfır genişlikli boşluk / birleştirici / BOM
        case 0x200B:
        case 0x200C:
        case 0x200D:
        case 0xFEFF:
          break;
        default:
          buffer.write(String.fromCharCode(rune).toUpperCase());
      }
    }

    return buffer.toString();
  }

  /// EAN-13 / EAN-8 / UPC-A kontrol hanesi doğrulaması.
  ///
  /// | Dönüş | Anlamı |
  /// |---|---|
  /// | `true` | Kontrol hanesi doğru |
  /// | `false` | Kontrol hanesi **yanlış** — EC-PROD-015: uyarılır, **engellenmez** |
  /// | `null` | Kural uygulanamaz (rakam dışı karakter veya farklı uzunluk) |
  ///
  /// docs/11 §3: "doğrulama yapılır ama engellenmez." Mağaza içi üretilmiş
  /// barkodlar ve fiyat gömülü barkodlar bu kurala uymayabilir; bu yüzden
  /// sonuç bir **uyarıdır**, bir kısıt değil.
  static bool? isChecksumValid(String barcode) {
    // EAN-8 (8) · UPC-A (12) · EAN-13 (13)
    if (barcode.length != 8 && barcode.length != 12 && barcode.length != 13) {
      return null;
    }

    final digits = <int>[];
    for (var i = 0; i < barcode.length; i++) {
      final code = barcode.codeUnitAt(i);
      if (code < 0x30 || code > 0x39) return null;
      digits.add(code - 0x30);
    }

    // Ağırlıklar kontrol hanesinden geriye doğru 3, 1, 3, 1 … şeklinde gider.
    // Bu tek kural üç standardın hepsini karşılar.
    var sum = 0;
    var weight = 3;
    for (var i = digits.length - 2; i >= 0; i--) {
      sum += digits[i] * weight;
      weight = weight == 3 ? 1 : 3;
    }

    return (10 - sum % 10) % 10 == digits.last;
  }
}
