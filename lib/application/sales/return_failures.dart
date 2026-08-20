/// İade ve iptalin **beklenen iş hataları** — docs/14 §6.
library;

import '../../core/result/result.dart';

abstract final class ReturnFailures {
  static const Failure saleNotFound = Failure(
    code: 'return_sale_not_found',
    userMessage: 'Satış bulunamadı. Listeyi yenileyip tekrar deneyin.',
  );

  /// BR-RET-006 — iptal edilmiş satış tekrar iptal edilemez.
  static const Failure alreadyCancelled = Failure(
    code: 'return_already_cancelled',
    userMessage: 'Bu satış zaten iptal edilmiş.',
  );

  /// BR-RET-001 — iade yapılmış satış iptal EDİLEMEZ.
  ///
  /// Aksi hâlde iade hareketlerinin üzerine bir de tam iptal hareketi yazılır
  /// ve stok iki kez geri eklenirdi.
  static const Failure cancelAfterReturn = Failure(
    code: 'return_cancel_after_return',
    userMessage:
        'Bu satışta iade yapılmış; satış iptal edilemez. Kalan miktarı iade '
        'edebilirsiniz.',
  );

  /// BR-RET-006 — iptal edilmiş satıştan iade yapılamaz.
  static const Failure returnFromCancelled = Failure(
    code: 'return_from_cancelled',
    userMessage:
        'Bu satış iptal edilmiş; iade yapılamaz. Stok zaten geri eklendi.',
  );

  /// BR-RET-003 — bir satırın toplam iadesi satılan miktarı aşamaz.
  static const Failure exceedsRemaining = Failure(
    code: 'return_exceeds_remaining',
    userMessage: 'İade miktarı kalan miktardan fazla olamaz.',
  );

  /// docs/14 §4 — toplam iade miktarı `> 0` olmalıdır.
  static const Failure nothingToReturn = Failure(
    code: 'return_nothing_selected',
    userMessage: 'İade edilecek ürün seçilmedi.',
  );

  static const Failure lineNotInSale = Failure(
    code: 'return_line_not_in_sale',
    userMessage: 'Seçilen satır bu satışa ait değil.',
  );

  /// docs/14 §3 — iptal sebebi zorunludur (audit metadata'sı sebep taşır).
  static const Failure reasonRequired = Failure(
    code: 'return_reason_required',
    userMessage: 'Sebep zorunludur. Ne olduğunu kısaca yazın.',
  );
}
