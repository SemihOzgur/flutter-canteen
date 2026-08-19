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
}
