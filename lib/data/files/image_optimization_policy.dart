/// Görsel optimizasyon profili — **OD-016 · docs/21 §0, §5**
///
/// > "Bu dokümandaki sayısal sınırlar **yapılandırılabilir teknik politikadır,
/// > business rule değildir.** Koda sabit yazılmazlar;
/// > `app_settings['image_optimization']` üzerinden değiştirilebilirler."
///
/// Bu yüzden sınırlar burada **varsayılan profil** olarak yaşar, `if` şartlarının
/// içine gömülmez: `AppSettingKeys.imageOptimization` altında bir profil varsa
/// o kullanılır, yoksa [defaults] geçerlidir.
///
/// ⚠️ Kesin olan (business) kısım optimizasyonun **yapılması** ve orijinal
/// dosyanın **saklanmamasıdır** (BR-IMG-002 · REQ-IMG-013). Sayılar kesin
/// değildir; kullanıcı/geliştirici değiştirebilir.
library;

import 'dart:convert';

/// Yüklenen görsele uygulanacak sınırlar.
class ImageOptimizationPolicy {
  /// docs/21 §5 — işlenmiş görselin uzun kenarı (varsayılan 1000 px).
  final int maxLongEdgePx;

  /// docs/21 §5 — yeniden kodlama kalitesi (varsayılan JPEG 85).
  final int jpegQuality;

  /// docs/21 §5 — kabul edilen en büyük **kaynak** dosya (varsayılan 10 MB).
  final int maxUploadBytes;

  /// docs/21 §5 — desteklenen formatlar. Doğrulama **dosya içeriğinden**
  /// yapılır (REQ-IMG-005); bu liste uzantı filtresi değil, izin listesidir.
  final List<String> allowedFormats;

  const ImageOptimizationPolicy({
    required this.maxLongEdgePx,
    required this.jpegQuality,
    required this.maxUploadBytes,
    required this.allowedFormats,
  });

  /// OD-016 başlangıç profili: 1000 px / JPEG 85 / 10 MB.
  static const ImageOptimizationPolicy defaults = ImageOptimizationPolicy(
    maxLongEdgePx: 1000,
    jpegQuality: 85,
    maxUploadBytes: 10 * 1024 * 1024,
    allowedFormats: ['jpg', 'jpeg', 'png', 'webp'],
  );

  /// `app_settings` değerinden profil çözer.
  ///
  /// Bozuk/eksik değer uygulamayı **çökertmez**: eksik alanlar varsayılandan
  /// tamamlanır, tamamen okunamayan değer [defaults]'a düşer. Görsel yükleme
  /// yolunun bir ayar yazım hatası yüzünden kırılması kabul edilemez.
  static ImageOptimizationPolicy decode(String? raw) {
    if (raw == null || raw.trim().isEmpty) return defaults;

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return defaults;
    }
    if (decoded is! Map<String, Object?>) return defaults;
    final parsed = decoded;

    int positiveInt(String key, int fallback) {
      final value = parsed[key];
      if (value is int && value > 0) return value;
      if (value is num && value > 0) return value.toInt();
      return fallback;
    }

    final quality = positiveInt('jpeg_quality', defaults.jpegQuality);
    final formats = parsed['allowed_formats'];

    return ImageOptimizationPolicy(
      maxLongEdgePx: positiveInt('max_long_edge_px', defaults.maxLongEdgePx),
      // JPEG kalitesi 1–100 aralığındadır; aralık dışı değer sessizce
      // kırpılmaz, varsayılana düşer (yanlış ayar sessiz kalite kaybı
      // yaratmasın).
      jpegQuality: quality >= 1 && quality <= 100
          ? quality
          : defaults.jpegQuality,
      maxUploadBytes: positiveInt('max_upload_bytes', defaults.maxUploadBytes),
      allowedFormats: formats is List && formats.isNotEmpty
          ? [
              for (final format in formats)
                if (format is String && format.trim().isNotEmpty)
                  format.trim().toLowerCase(),
            ]
          : defaults.allowedFormats,
    );
  }

  /// `app_settings` için serileştirme.
  String encode() => jsonEncode({
    'max_long_edge_px': maxLongEdgePx,
    'jpeg_quality': jpegQuality,
    'max_upload_bytes': maxUploadBytes,
    'allowed_formats': allowedFormats,
  });

  bool allows(String format) => allowedFormats.contains(format.toLowerCase());

  @override
  String toString() =>
      'ImageOptimizationPolicy($maxLongEdgePx px, q$jpegQuality, '
      '$maxUploadBytes B)';
}
