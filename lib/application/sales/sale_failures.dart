/// Satış tamamlamanın ürettiği **beklenen iş hataları**.
library;

import '../../core/result/result.dart';

abstract final class SaleFailures {
  /// BR-CART-005 · EC-SALE-001 — boş sepetle satış tamamlanamaz.
  static const Failure emptyCart = Failure(
    code: 'sale_cart_empty',
    userMessage: 'Sepet boş. Satışı tamamlamak için en az bir ürün ekleyin.',
  );

  /// BR-SALE-008 · EC-SALE-009 · REQ-FIN-007 — alınan nakit toplamdan azsa
  /// satış tamamlanamaz.
  ///
  /// Nakit girmek **opsiyoneldir** (BR-SALE-007); bu hata yalnızca kullanıcı
  /// bir tutar girdiğinde ve tutar yetmediğinde üretilir.
  static const Failure insufficientCash = Failure(
    code: 'sale_cash_insufficient',
    userMessage: 'Alınan tutar toplamdan az. Satış tamamlanamaz.',
  );

  static const Failure negativeCash = Failure(
    code: 'sale_cash_negative',
    userMessage: 'Alınan tutar negatif olamaz.',
  );

  /// REQ-SALE-008 · EC-SALE-008 — tamamlama sürerken ikinci istek.
  ///
  /// Butonun kilitlenmesi UI'nın işidir; bu koruma servisin kendisindedir.
  /// UI'ya güvenmek, "F12'ye üç kez basınca üç satış" hatasını bir widget
  /// ayrıntısına bağımlı kılardı.
  static const Failure alreadyInProgress = Failure(
    code: 'sale_in_progress',
    userMessage: 'Satış tamamlanıyor, lütfen bekleyin.',
  );

  /// EC-CART-010 — sepetteki ürün veritabanında bulunamıyor (bozulma).
  ///
  /// Satış **yapılmaz** — ve bu bir para güvenliğidir. Bozuk satır sepetten
  /// düşer; kalanı satmak müşteriden **eksik tahsilat** demektir ve hiçbir
  /// yerde iz bırakmaz. Kullanıcı bozulmayı görüp sepeti düzeltmelidir.
  ///
  /// Snapshot alanları okunamayan bir satır zaten yazılamaz; yarım satış
  /// oluşamaz (BR-SALE-005).
  static const Failure productMissing = Failure(
    code: 'sale_product_missing',
    userMessage:
        'Sepetteki bir ürün bulunamadı. Satırı kaldırıp tekrar deneyin.',
  );
}
