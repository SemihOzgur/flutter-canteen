/// Ürün görselinin **üç** durumlu değişimi — docs/21 §2.
///
/// ## Neden bir tip gerekli
///
/// `Product.imagePath` nullable'dır ve nullable bir alanda güncelleme isteği
/// üç ayrı anlam taşır:
///
/// | İstek | Anlam | `image_path` |
/// |---|---|---|
/// | [KeepProductImage] | **Dokunma** — form görsele hiç dokunmadı | değişmez |
/// | [SetProductImage] | Yeni görsel | `images/<uuid>.jpg` |
/// | [ClearProductImage] | **Temizle** — kullanıcı görseli kaldırdı | `NULL` |
///
/// Tek bir `String? imagePath` parametresi bunları ayırt **edemez**: `null`
/// hem "dokunma" hem "temizle" anlamına gelirdi ve ikisinden biri sessizce
/// yanlış çalışırdı. Bu yüzden ayrım tip düzeyinde yapılır ve `switch`
/// exhaustive kalır.
library;

import '../../data/files/product_image_store.dart';

sealed class ProductImageChange {
  const ProductImageChange();
}

/// Mevcut görsel korunur (varsayılan).
final class KeepProductImage extends ProductImageChange {
  const KeepProductImage();
}

/// `temp/` altında hazır bekleyen optimize görsel kalıcı hâle getirilir.
final class SetProductImage extends ProductImageChange {
  final PreparedProductImage prepared;

  const SetProductImage(this.prepared);
}

/// Görsel kaldırılır; dosya **silinmez**, çöpe taşınır (BR-IMG-003).
final class ClearProductImage extends ProductImageChange {
  const ClearProductImage();
}
