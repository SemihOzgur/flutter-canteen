/// Stok işlemlerinin ürettiği **beklenen iş hataları**.
///
/// rules/06 §7: beklenen iş hataları `Result`/`Failure` ile döner; exception
/// fırlatılmaz. Desen `application/reference/category_failures.dart` ile aynıdır.
library;

import '../../core/result/result.dart';

abstract final class StockFailures {
  /// docs/13 §2 — `initial` hareketinin yönü **artıdır**.
  ///
  /// Negatif bir başlangıç stoğu defterin ilk satırını anlamsız kılar; stok
  /// negatife yalnızca satışla düşebilir (BR-STOCK-006).
  static const Failure negativeInitialStock = Failure(
    code: 'stock_initial_negative',
    userMessage: 'Başlangıç stoğu negatif olamaz. 0 veya daha büyük girin.',
  );

  /// docs/13 §2 — `initial` hareketi **ürün başına en fazla bir kez** yazılır.
  ///
  /// Kullanıcı bu hatayı normal akışta göremez: başlangıç stoğu yalnızca ürün
  /// oluşturulurken yazılır. Yine de savunma olarak vardır — ikinci bir
  /// `initial` hareketi defteri geriye dönük okunamaz hâle getirirdi.
  static const Failure alreadyInitialized = Failure(
    code: 'stock_already_initialized',
    userMessage:
        'Bu ürünün stok geçmişi zaten başlamış. Stok değişikliği için stok '
        'giriş veya düzeltme işlemini kullanın.',
  );

  /// BR-STOCK-004 — `quantity_delta` asla `0` olamaz; satış hareketi de
  /// negatif yönde **pozitif** bir miktar taşır.
  ///
  /// Normal akışta görülmez: sepet satırı `CHECK(quantity > 0)` altındadır.
  /// Yine de vardır — sıfır miktarlı bir hareket defteri okunamaz hâle
  /// getirir, negatif miktarlı bir "satış" ise stoğu **artırırdı**.
  static const Failure nonPositiveSaleQuantity = Failure(
    code: 'stock_sale_quantity_invalid',
    userMessage: 'Satış miktarı en az 1 olmalıdır.',
  );

  /// docs/13 §6 — fire ve düzeltme için **sebep zorunludur** (BR-STOCK-010).
  ///
  /// "Bu ürünün stoğu neden 12?" sorusu defterden yanıtlanabilmelidir; sebepsiz
  /// bir düzeltme bu zincirin kopduğu yerdir.
  static const Failure reasonRequired = Failure(
    code: 'stock_reason_required',
    userMessage: 'Sebep zorunludur. Ne olduğunu kısaca yazın.',
  );

  /// docs/13 §6 — fire yalnızca **negatif** yönlüdür.
  static const Failure wasteMustBePositive = Failure(
    code: 'stock_waste_invalid',
    userMessage: 'Fire miktarı en az 1 olmalıdır.',
  );

  /// BR-STOCK-004 — `quantity_delta` asla `0` olamaz.
  ///
  /// Düzeltmede kullanıcı mevcut stoğun aynısını girmiş olabilir; bu bir hata
  /// değil ama deftere yazılacak bir hareket de değildir.
  static const Failure adjustmentNoChange = Failure(
    code: 'stock_adjustment_no_change',
    userMessage: 'Yeni stok mevcut stokla aynı. Değişiklik yapılmadı.',
  );

  /// docs/13 §5 — stok girişi en az bir satır içermelidir (REQ-STOCK-007).
  static const Failure emptyEntry = Failure(
    code: 'stock_entry_empty',
    userMessage: 'Stok girişi boş. En az bir ürün ekleyin.',
  );

  /// Stok girişi satırı pozitif miktar taşır.
  static const Failure entryQuantityInvalid = Failure(
    code: 'stock_entry_quantity_invalid',
    userMessage: 'Giriş miktarı en az 1 olmalıdır.',
  );

  static const Failure negativePurchasePrice = Failure(
    code: 'stock_purchase_price_negative',
    userMessage: 'Alış fiyatı negatif olamaz. Örnek: 18,00',
  );

  /// REQ-STOCK-003 · docs/13 §10 — hareket düzeltilemez, **ters kayıt** açılır.
  static const Failure movementNotFound = Failure(
    code: 'stock_movement_not_found',
    userMessage: 'Bu stok hareketi bulunamadı.',
  );

  static const Failure productNotFound = Failure(
    code: 'stock_product_not_found',
    userMessage: 'Ürün bulunamadı. Listeyi yenileyip tekrar deneyin.',
  );
}
