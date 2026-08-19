/// Görsel yeniden boyutlandırma ve yeniden kodlama — **BR-IMG-002 ·
/// REQ-IMG-003 · docs/21 §2 adım 4–5**
///
/// ## Neden isolate
///
/// `rules/01 §8`: **"UI thread hiçbir zaman ağır DB/dosya işiyle bloklanmaz."**
/// 10 MB'lık bir telefon fotoğrafını çözüp yeniden boyutlandırmak yüzlerce
/// milisaniye sürer; ana isolate'te yapılırsa uygulama donar. Bu bir performans
/// tercihi değil, kuraldır.
///
/// [optimizeImageInIsolate] üretim yoludur. [optimizeImageSync] aynı işi
/// senkron yapar ve testlerin isolate kurma maliyeti olmadan **aynı**
/// implementasyonu doğrulamasını sağlar (iki ayrı hesap yolu yoktur —
/// `rules/01 §2`).
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'image_format.dart';

/// Isolate'e gönderilen istek — yalnızca kopyalanabilir alanlar taşır.
class ImageOptimizeRequest {
  final Uint8List bytes;
  final ImageFormat sourceFormat;
  final int maxLongEdgePx;
  final int jpegQuality;

  const ImageOptimizeRequest({
    required this.bytes,
    required this.sourceFormat,
    required this.maxLongEdgePx,
    required this.jpegQuality,
  });
}

/// Optimize edilmiş çıktı.
class OptimizedImage {
  final Uint8List bytes;
  final ImageFormat format;
  final int width;
  final int height;

  const OptimizedImage({
    required this.bytes,
    required this.format,
    required this.width,
    required this.height,
  });
}

/// Enjekte edilebilir optimizasyon adımı — testler isolate kurmadan çalışabilir.
typedef ImageOptimizer =
    Future<OptimizedImage?> Function(ImageOptimizeRequest request);

/// Üretim yolu — ağır iş ayrı isolate'te yapılır (`rules/01 §8`).
Future<OptimizedImage?> optimizeImageInIsolate(ImageOptimizeRequest request) =>
    Isolate.run(() => optimizeImageSync(request));

/// Çözer, uzun kenarı sınıra indirir ve yeniden kodlar.
///
/// Çözülemeyen (bozuk) dosyada `null` döner — docs/21 §2 adım 3.
///
/// | Karar | Kural |
/// |---|---|
/// | Uzun kenar > sınır → küçültülür | docs/21 §2 adım 4 |
/// | Uzun kenar <= sınır → **büyütülmez** | Yapay büyütme kalite kazandırmaz |
/// | Kaynak PNG **ve** gerçekten şeffaf → PNG kalır | docs/21 §2 adım 5 |
/// | Diğer her durum → JPEG | Boyut/kalite dengesi (OD-016) |
OptimizedImage? optimizeImageSync(ImageOptimizeRequest request) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(request.bytes);
  } on Object {
    // Bozuk dosya `image` paketinde exception da fırlatabiliyor; her iki
    // durumda da sonuç aynıdır: reddedilir (REQ-IMG-004).
    return null;
  }
  if (decoded == null || decoded.width == 0 || decoded.height == 0) return null;

  final longEdge = decoded.width > decoded.height
      ? decoded.width
      : decoded.height;

  final img.Image resized;
  if (longEdge > request.maxLongEdgePx) {
    resized = decoded.width >= decoded.height
        ? img.copyResize(
            decoded,
            width: request.maxLongEdgePx,
            interpolation: img.Interpolation.average,
          )
        : img.copyResize(
            decoded,
            height: request.maxLongEdgePx,
            interpolation: img.Interpolation.average,
          );
  } else {
    resized = decoded;
  }

  final keepPng =
      request.sourceFormat == ImageFormat.png && _hasTransparency(resized);

  return OptimizedImage(
    bytes: keepPng
        ? img.encodePng(resized)
        : img.encodeJpg(resized, quality: request.jpegQuality),
    format: keepPng ? ImageFormat.png : ImageFormat.jpeg,
    width: resized.width,
    height: resized.height,
  );
}

/// Alfa kanalı **var** olması şeffaflık demek değildir; tamamen opak bir PNG
/// JPEG'e çevrilerek küçültülebilir. Bu yüzden gerçekten saydam bir piksel
/// aranır. Tarama küçültülmüş görsel üzerinde yapılır (en fazla sınır² piksel).
bool _hasTransparency(img.Image image) {
  if (!image.hasAlpha) return false;
  final opaque = image.maxChannelValue;
  for (final pixel in image) {
    if (pixel.a < opaque) return true;
  }
  return false;
}
