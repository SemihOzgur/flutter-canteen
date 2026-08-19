/// Görsel format doğrulaması — **REQ-IMG-005 · rules/03 §8 · rules/04 §7**
///
/// > "Format doğrulaması **dosya içeriğinden** (magic bytes) yapılır,
/// > uzantıdan değil."
///
/// Uzantı kullanıcı tarafından yazılır ve yalan söyleyebilir: `virus.exe`
/// dosyası `foto.jpg` adıyla seçilebilir. Bu yüzden karar **daima** dosyanın
/// ilk baytlarına bakılarak verilir.
///
/// Saf fonksiyon: dosya sistemi ve Flutter bağımlılığı yoktur.
library;

import 'dart:typed_data';

/// İçerikten tanınan görsel formatı.
enum ImageFormat {
  jpeg('jpg', '.jpg'),
  png('png', '.png'),
  webp('webp', '.webp');

  /// [ImageOptimizationPolicy.allowedFormats] ile eşleşen ad.
  final String name;

  /// Dosya adı uzantısı (nokta dahil).
  final String extension;

  const ImageFormat(this.name, this.extension);
}

abstract final class ImageFormatDetector {
  /// İçerikten formatı çözer; tanınmazsa `null`.
  ///
  /// | Format | Magic bytes |
  /// |---|---|
  /// | JPEG | `FF D8 FF` |
  /// | PNG | `89 50 4E 47 0D 0A 1A 0A` |
  /// | WebP | `52 49 46 46 .. .. .. .. 57 45 42 50` (`RIFF….WEBP`) |
  static ImageFormat? detect(Uint8List bytes) {
    if (_startsWith(bytes, const [0xFF, 0xD8, 0xFF])) return ImageFormat.jpeg;

    if (_startsWith(bytes, const [
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
    ])) {
      return ImageFormat.png;
    }

    // RIFF konteynerinde format adı 8. bayttan sonra gelir; boyut alanı (4–7)
    // atlanır.
    if (bytes.length >= 12 &&
        _startsWith(bytes, const [0x52, 0x49, 0x46, 0x46]) &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return ImageFormat.webp;
    }

    return null;
  }

  static bool _startsWith(Uint8List bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var i = 0; i < prefix.length; i++) {
      if (bytes[i] != prefix[i]) return false;
    }
    return true;
  }
}
