/// Ürün yönetiminin ürettiği **beklenen iş hataları**.
///
/// rules/06 §7: beklenen iş hataları `Result`/`Failure` ile döner; exception
/// fırlatılmaz. Desen `application/reference/category_failures.dart` ile aynıdır.
///
/// Mesajlar Türkçedir (REQ-UX-007), teknik detay içermez (REQ-SEC-007) ve
/// rules/05 §5 biçimindedir: **ne oldu + ne yapmalıyım.**
///
/// ⚠️ Burada yalnızca **kaydı reddeden** durumlar vardır. "İzin verilir ama
/// uyarılır" durumları (EC-PROD-009/010/015) hata değildir; bkz.
/// `product_warnings.dart`.
library;

import '../../core/result/result.dart';
import '../../domain/services/product_rules.dart';

abstract final class ProductFailures {
  /// docs/09 §1 · EC-PROD-013 — yalnızca boşluktan oluşan ad reddedilir.
  static const Failure nameRequired = Failure(
    code: 'product_name_required',
    userMessage: 'Ürün adı boş olamaz.',
  );

  /// docs/09 §1 · EC-PROD-012 — form 120 karakterle sınırlar.
  static const Failure nameTooLong = Failure(
    code: 'product_name_too_long',
    userMessage:
        'Ürün adı en fazla ${ProductRules.nameMaxLength} karakter olabilir.',
  );

  static const Failure descriptionTooLong = Failure(
    code: 'product_description_too_long',
    userMessage:
        'Açıklama en fazla ${ProductRules.descriptionMaxLength} karakter '
        'olabilir.',
  );

  static const Failure shelfLocationTooLong = Failure(
    code: 'product_shelf_location_too_long',
    userMessage:
        'Raf konumu en fazla ${ProductRules.shelfLocationMaxLength} karakter '
        'olabilir.',
  );

  /// BR-PROD-006 · EC-PROD-008 — satış fiyatı negatif olamaz. `0` geçerlidir
  /// (ikram ürünü — EC-PROD-007).
  static const Failure salePriceNegative = Failure(
    code: 'product_sale_price_negative',
    userMessage: 'Satış fiyatı negatif olamaz. Örnek: 25,50',
  );

  /// BR-PROD-007 — alış fiyatı negatif olamaz.
  static const Failure purchasePriceNegative = Failure(
    code: 'product_purchase_price_negative',
    userMessage: 'Alış fiyatı negatif olamaz. Örnek: 18,75',
  );

  /// REQ-FIN-006 — `25,50` · `25.50` · `25` · `₺25,50` kabul edilir.
  static const Failure priceInvalid = Failure(
    code: 'product_price_invalid',
    userMessage: 'Fiyat geçersiz. Örnek: 25,50',
  );

  static const Failure salePriceRequired = Failure(
    code: 'product_sale_price_required',
    userMessage: 'Satış fiyatı zorunludur. Örnek: 25,50',
  );

  /// Şema: `CHECK(minimum_stock >= 0)`.
  static const Failure minimumStockNegative = Failure(
    code: 'product_minimum_stock_negative',
    userMessage: 'Minimum stok negatif olamaz.',
  );

  /// BR-PROD-011 · EC-PROD-018 — ağırlık değeri ve birimi birlikte doldurulur.
  ///
  /// Şemadaki `CHECK((net_weight_value IS NULL) = (net_weight_unit IS NULL))`
  /// aynı kuralı zorlar; bu mesaj kullanıcının ham veritabanı hatası
  /// görmemesi içindir (REQ-SEC-007).
  static const Failure netWeightPairIncomplete = Failure(
    code: 'product_net_weight_pair_incomplete',
    userMessage:
        'Net ağırlık için hem değer hem birim girilmelidir (örn. 150 g). '
        'Kullanmayacaksanız ikisini de boş bırakın.',
  );

  static const Failure notFound = Failure(
    code: 'product_not_found',
    userMessage: 'Ürün bulunamadı.',
  );

  /// BR-PROD-003 — kategori zorunludur.
  static const Failure categoryNotFound = Failure(
    code: 'product_category_not_found',
    userMessage: 'Seçilen kategori bulunamadı. Listeden bir kategori seçin.',
  );

  /// BR-PROD-003 · BR-CAT-004 — `Genel` sistem kategorisi seed tarafından
  /// oluşturulur. Bu hata yalnızca veritabanı bozulmuşsa görülebilir; kategori
  /// **burada üretilmez** (seed'in işidir).
  static const Failure generalCategoryMissing = Failure(
    code: 'product_general_category_missing',
    userMessage:
        'Varsayılan "Genel" kategorisi bulunamadı. Ürünü kaydetmek için bir '
        'kategori seçin.',
  );

  static const Failure barcodeRequired = Failure(
    code: 'product_barcode_required',
    userMessage: 'Barkod boş olamaz.',
  );

  /// BR-PROD-005 · REQ-PROD-005 · EC-PROD-001 — barkod **global** benzersizdir
  /// (pasif ürünler dâhil — BR-PROD-010).
  ///
  /// Sahip ürünün adı **ve id'si** döner: ekran "Ürüne git" bağlantısını
  /// bu id ile kurar (REQ-PROD-005 acceptance criteria).
  static Failure barcodeOwnedByOther({
    required String productName,
    required int productId,
  }) => Failure(
    code: 'product_barcode_exists:$productId',
    userMessage: "Bu barkod zaten '$productName' ürününe ait.",
  );

  /// Yarış durumu: kontrol ile yazma arasında aynı barkod başka bir ürüne
  /// eklendi. Sahip ürün artık güvenilir biçimde bilinemez.
  static const Failure barcodeExists = Failure(
    code: 'product_barcode_exists',
    userMessage: 'Bu barkod başka bir ürüne ait.',
  );

  /// BR-PROD-009 · EC-PROD-020/021 — kullanılmış ürün **silinemez**.
  ///
  /// Sayılar mesajdadır: kullanıcı "neden silemiyorum?" sorusunu ekranı terk
  /// etmeden yanıtlayabilmelidir (rules/05 §5).
  static Failure inUse({
    required int saleItemCount,
    required int stockMovementCount,
  }) {
    final reasons = <String>[
      if (saleItemCount > 0) '$saleItemCount satışta kullanılmış',
      if (stockMovementCount > 0)
        '$stockMovementCount stok hareketi kayıtlı (başlangıç stoğu dâhil)',
    ];
    return Failure(
      code: 'product_in_use',
      userMessage:
          'Bu ürün silinemez: ${reasons.join(', ')}. Geçmiş kayıtların '
          'bozulmaması için ürünü pasife alabilirsiniz; raporlarda görünmeye '
          'devam eder.',
    );
  }
}
