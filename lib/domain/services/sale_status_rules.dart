/// Satış durumu makinesi — **docs/14 §2 · REQ-RET-007 · BR-RET-006**
///
/// Saf Dart, tek merkezî implementasyon (rules/01 §2). Durum **her iade
/// sonrası yeniden hesaplanır**; hiçbir yerde elle atanmaz.
///
/// ```text
///                     ┌───────────┐
///                     │ completed │
///                     └─────┬─────┘
///           ┌───────────────┼─────────────────┐
///           │ iptal         │ kısmi iade      │ tam iade
///           ▼               ▼                 ▼
///     ┌───────────┐  ┌──────────────────┐  ┌──────────┐
///     │ cancelled │  │partiallyReturned │  │ returned │
///     └───────────┘  └────────┬─────────┘  └──────────┘
///       (terminal)            │ ek iadeler  (terminal)
///                             ▼
///                        ┌──────────┐
///                        │ returned │
///                        └──────────┘
/// ```
library;

import '../enums/sale_status.dart';

abstract final class SaleStatusRules {
  /// docs/14 §2 — iade miktarlarından durumu türetir.
  ///
  /// ```text
  /// toplamIade == 0                → completed
  /// 0 < toplamIade < toplamSatilan → partiallyReturned
  /// toplamIade == toplamSatilan    → returned
  /// ```
  ///
  /// `cancelled` **buradan üretilmez**: iptal bir iade sonucu değil, ayrı bir
  /// kullanıcı eylemidir (docs/14 §1).
  static SaleStatus fromReturnedQuantities({
    required int totalSold,
    required int totalReturned,
  }) {
    if (totalReturned <= 0) return SaleStatus.completed;
    if (totalReturned >= totalSold) return SaleStatus.returned;
    return SaleStatus.partiallyReturned;
  }

  /// BR-RET-001 · BR-RET-006 — satış **iptal edilebilir mi?**
  ///
  /// İki koşul birlikte gerekir: durum `completed` olmalı **ve** hiç iade
  /// yapılmamış olmalı. İade yapılmış bir satışı iptal etmek, iade
  /// hareketlerinin üzerine bir de tam iptal hareketi yazardı ve stok iki kez
  /// geri eklenirdi.
  static bool canCancel({
    required SaleStatus status,
    required int totalReturned,
  }) => status == SaleStatus.completed && totalReturned == 0;

  /// BR-RET-006 — satıştan **iade yapılabilir mi?**
  ///
  /// İptal edilmiş satıştan iade yapılamaz: iptal zaten tüm stoğu geri
  /// eklemiştir. Tamamı iade edilmiş satışta da iade edilecek miktar kalmaz.
  static bool canReturn({
    required SaleStatus status,
    required int totalSold,
    required int totalReturned,
  }) {
    if (status == SaleStatus.cancelled) return false;
    return totalReturned < totalSold;
  }
}
