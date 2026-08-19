/// Ürün işlemlerinin ürettiği **uyarılar** — izin verilir, engellenmez.
///
/// ## Neden servis katmanında
///
/// rules/05 §8 · rules/01 §1: iş kuralı doğrulaması UI'da yapılmaz. Aşağıdaki
/// uyarıların hepsi bir **iş kararıdır** (`docs/26 §1`): ürünün kaydedilmesine
/// izin verilir, ancak kullanıcı bilgilendirilir. Ekran bu listeyi yalnızca
/// **gösterir**; hangi durumun uyarı olduğuna karar vermez.
///
/// | Uyarı | Kaynak |
/// |---|---|
/// | Alış fiyatı > satış fiyatı | EC-PROD-009 |
/// | Aynı ad + aynı kategori | EC-PROD-010 · BR-PROD-013 |
/// | EAN-13/EAN-8/UPC kontrol hanesi geçersiz | EC-PROD-015 · docs/11 §3 |
/// | Satış fiyatı %50'den fazla değişiyor | REQ-PROD-012 |
/// | Stoğu olan ürün pasifleştiriliyor | docs/09 §4 |
/// | 30'dan fazla favori | docs/09 §5 |
///
/// Uyarı **hata değildir**: `Result` `Ok` döner, işlem tamamlanır.
library;

import '../../domain/services/product_rules.dart';

/// Kullanıcıya gösterilecek tek bir uyarı.
///
/// [code] test ve loglama içindir; [message] Türkçe kullanıcı metnidir
/// (REQ-UX-007).
class ProductWarning {
  final String code;
  final String message;

  const ProductWarning({required this.code, required this.message});

  @override
  String toString() => 'ProductWarning($code)';
}

abstract final class ProductWarnings {
  /// EC-PROD-009 — izin verilir; kâr raporunda negatif kâr görünür.
  static const ProductWarning purchaseAboveSale = ProductWarning(
    code: 'product_purchase_above_sale',
    message:
        'Alış fiyatı satış fiyatından yüksek. Bu ürün zararına satılacak ve '
        'kâr raporunda negatif görünecek.',
  );

  /// EC-PROD-010 · BR-PROD-013 — ad benzersiz olmak zorunda değildir.
  static const ProductWarning duplicateName = ProductWarning(
    code: 'product_duplicate_name',
    message:
        'Bu kategoride aynı adda bir ürün zaten var. Kaydetmeye devam '
        'edebilirsiniz.',
  );

  /// REQ-PROD-012 — yanlış kuruş/lira girişini yakalamak içindir.
  static const ProductWarning largePriceChange = ProductWarning(
    code: 'product_price_change_large',
    message:
        'Satış fiyatı %${ProductRules.significantPriceChangePercent}\'den '
        'fazla değişiyor. Tutarı doğru girdiğinizden emin olun.',
  );

  /// EC-PROD-015 · docs/11 §3 — "doğrulama yapılır ama engellenmez."
  ///
  /// Mağaza içi üretilmiş ve fiyat gömülü barkodlar bu kurala uymayabilir.
  static const ProductWarning barcodeChecksumInvalid = ProductWarning(
    code: 'product_barcode_checksum_invalid',
    message:
        'Bu barkod standart bir kontrol hanesine sahip değil. Mağaza içi '
        'barkodlarda bu normaldir; kayıt yapıldı.',
  );

  /// docs/09 §5 — "Öneri: 30'dan fazla favori eklenirse kullanıcı uyarılır."
  ///
  /// Engellemez: favori sayısına kısıt koyan bir kural yoktur.
  static ProductWarning tooManyFavorites(int favoriteCount) => ProductWarning(
    code: 'product_too_many_favorites',
    message:
        'Favori ürün sayısı $favoriteCount oldu. '
        '${ProductRules.favoriteWarningThreshold}\'dan fazla favori satış '
        'ekranını kalabalıklaştırabilir.',
  );

  /// docs/09 §4 — "Uyarılır ama engellenmez."
  static ProductWarning deactivatedWithStock(int stockQuantity) =>
      ProductWarning(
        code: 'product_deactivated_with_stock',
        message:
            'Bu ürünün $stockQuantity adet stoğu var. Pasif ürünler stok '
            'değeri raporunda ayrı gösterilir.',
      );
}
