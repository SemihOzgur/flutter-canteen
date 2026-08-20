/// Sepet işlemlerinin ürettiği **beklenen iş hataları**.
///
/// rules/06 §7: beklenen iş hataları `Result`/`Failure` ile döner; exception
/// fırlatılmaz.
library;

import '../../core/result/result.dart';

abstract final class CartFailures {
  /// EC-CART-010 — sepetteki ürün veritabanında bulunamıyor (bozulma).
  static const Failure productNotFound = Failure(
    code: 'cart_product_not_found',
    userMessage: 'Bu ürün bulunamadı. Ürün listesini yenileyip tekrar deneyin.',
  );

  static const Failure lineNotFound = Failure(
    code: 'cart_line_not_found',
    userMessage: 'Bu satır sepette bulunamadı. Sepet yenilendi.',
  );

  /// BR-SALE-011 — miktar pozitif tam sayıdır.
  ///
  /// `0` bir hata değil, **satırı silmektir** (EC-CART-003); bu hata yalnızca
  /// negatif miktar için üretilir.
  static const Failure negativeQuantity = Failure(
    code: 'cart_quantity_negative',
    // rules/05 §5 — "ne oldu + ne yapmalıyım". Yalnızca "negatif olamaz"
    // demek, kullanıcıya satırı nasıl kaldıracağını söylemez.
    userMessage: 'Miktar negatif olamaz. Satırı kaldırmak için 0 girin.',
  );

  /// EC-SALE-007 — negatif fiyat reddedilir (BR-PROD-006).
  ///
  /// `0` **reddedilmez**: ikram ürünü geçerli bir iş durumudur (EC-SALE-006).
  static const Failure negativePrice = Failure(
    code: 'cart_price_negative',
    userMessage: 'Fiyat negatif olamaz. Örnek: 25,50',
  );
}
