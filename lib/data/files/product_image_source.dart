/// Ürün görselini **gösterim** için çözer — docs/21 §3 · BR-IMG-005.
///
/// ## Neden burada, presentation'da değil
///
/// `rules/01 §1`: presentation katmanı **dosya sistemi erişimi içeremez.**
/// Ekranlar `dart:io` görmez; yalnızca hazır bir [ImageProvider] alır ve
/// Flutter'ın `ImageCache`'i devreye girer (docs/21 §3 — liste kaydırılırken
/// tembel yükleme).
///
/// ## Neden typedef
///
/// `rules/01 §3` karar testi: (1) iki somut kullanım var — ürün listesi satırı
/// (40×40) ve ürün formu (200×200); (2) widget testinin gerçek diske
/// dokunmaması için enjekte edilebilir olması gerekiyor. Sınıf/servis
/// hiyerarşisi kurulmaz; typedef + tek fonksiyon yeterlidir (emsal:
/// `save_location_picker.dart`).
///
/// Yol **çözülemezse** `null` döner ve ekran varsayılan ikonu gösterir —
/// hata gösterilmez (BR-IMG-005 · REQ-IMG-009).
library;

import 'dart:io';

import 'package:flutter/widgets.dart' show FileImage, ImageProvider;

import 'product_image_store.dart';

/// Veri dizinine göreli yoldan gösterilebilir bir görsel kaynağı üretir.
typedef ProductImageSource = ImageProvider? Function(String? relativePath);

/// [ProductImageStore] üzerinden çözen üretim implementasyonu.
///
/// Dosyanın **var olup olmadığına burada bakılmaz**: diskte olmayan dosya
/// `Image`'ın `errorBuilder`'ına düşer ve varsayılan ikon gösterilir. Ayrıca
/// senkron `existsSync` çağrısı her liste satırında UI thread'i dosya
/// sistemine indirirdi (`rules/01 §8`).
ProductImageSource productImageSourceOf(ProductImageStore store) {
  return (relativePath) {
    final absolute = store.absolutePathOf(relativePath);
    return absolute == null ? null : FileImage(File(absolute));
  };
}
