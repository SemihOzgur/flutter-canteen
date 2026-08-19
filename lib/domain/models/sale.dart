/// Satış ve satış satırı — docs/04-domain-model.md §3.9
///
/// Saf Dart (rules/01 §1).
///
/// **Invariant:** `subtotal + vatTotal == grandTotal` (rules/02 §2).
library;

import '../../core/money/money.dart';
import '../enums/sale_status.dart';

class Sale {
  final int id;
  final String saleNumber;
  final SaleStatus status;

  /// KDV **hariç** matrah.
  final Money subtotal;

  final Money vatTotal;

  /// V1'de daima `Money.zero` (OD-007).
  final Money discountTotal;

  /// KDV **dahil** — müşteriden alınan tutar.
  final Money grandTotal;

  final Money costTotal;
  final Money? cashReceived;
  final Money? change;
  final int itemCount;
  final int unitCount;
  final int userId;
  final String? note;

  /// UTC — raporların zaman ekseni.
  final DateTime completedAt;
  final DateTime? cancelledAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Sale({
    required this.id,
    required this.saleNumber,
    required this.status,
    required this.subtotal,
    required this.vatTotal,
    required this.discountTotal,
    required this.grandTotal,
    required this.costTotal,
    required this.cashReceived,
    required this.change,
    required this.itemCount,
    required this.unitCount,
    required this.userId,
    required this.note,
    required this.completedAt,
    required this.cancelledAt,
    required this.createdAt,
    required this.updatedAt,
  });

  /// rules/02 §2 — fişteki satırlar elle toplandığında genel toplamı vermelidir.
  bool get isBalanced => subtotal + vatTotal == grandTotal;
}

/// **BR-SALE-001 — beş snapshot alanı.**
///
/// Geçmiş satışlar mevcut ürün verisinden yeniden hesaplanamaz (rules/02 §3).
class SaleItem {
  final int id;
  final int saleId;
  final int productId;

  /// SNAPSHOT 1/5.
  final String productNameSnapshot;

  final String? barcodeSnapshot;

  /// SNAPSHOT 2/5.
  final int? categoryIdSnapshot;

  final int quantity;

  /// SNAPSHOT 3/5 — **KDV dahil**.
  final Money unitPrice;

  final Money originalUnitPrice;

  /// SNAPSHOT 4/5.
  final Money purchasePriceSnapshot;

  /// SNAPSHOT 5/5 — basis point.
  final int vatRateSnapshotBp;

  final Money lineNet;
  final Money lineVat;
  final Money lineTotal;
  final int returnedQuantity;

  const SaleItem({
    required this.id,
    required this.saleId,
    required this.productId,
    required this.productNameSnapshot,
    required this.barcodeSnapshot,
    required this.categoryIdSnapshot,
    required this.quantity,
    required this.unitPrice,
    required this.originalUnitPrice,
    required this.purchasePriceSnapshot,
    required this.vatRateSnapshotBp,
    required this.lineNet,
    required this.lineVat,
    required this.lineTotal,
    required this.returnedQuantity,
  });

  /// İade edilebilir kalan miktar (BR-RET-002).
  int get remainingQuantity => quantity - returnedQuantity;
}

/// Henüz kaydedilmemiş satış başlığı (id yok).
///
/// **Yalnızca `SaleService`'in atomik transaction'ı içinde kullanılır**
/// (BR-SALE-005 · rules/01 §5). Toplamlar burada **hesaplanmaz**; çağıran
/// `VatCalculator` üzerinden hesaplayıp verir — ikinci bir KDV/toplam
/// implementasyonu yoktur (rules/01 §2).
class NewSale {
  final String saleNumber;
  final SaleStatus status;

  /// KDV **hariç** matrah.
  final Money subtotal;

  final Money vatTotal;

  /// KDV **dahil** — müşteriden alınan tutar.
  final Money grandTotal;

  /// Satır maliyet snapshot'larının toplamı (docs/05 §4 — denormalize).
  final Money costTotal;

  /// docs/12 §5 — nakit hesaplama **opsiyoneldir** (BR-SALE-007);
  /// girilmezse `null` kaydedilir.
  final Money? cashReceived;
  final Money? change;

  final int itemCount;
  final int unitCount;
  final int userId;
  final String? note;
  final DateTime completedAtUtc;

  const NewSale({
    required this.saleNumber,
    required this.status,
    required this.subtotal,
    required this.vatTotal,
    required this.grandTotal,
    required this.costTotal,
    required this.cashReceived,
    required this.change,
    required this.itemCount,
    required this.unitCount,
    required this.userId,
    required this.note,
    required this.completedAtUtc,
  });

  /// rules/02 §2 — `subtotal + vatTotal == grandTotal`.
  bool get isBalanced => subtotal + vatTotal == grandTotal;
}

/// Henüz kaydedilmemiş satış satırı — **BR-SALE-001: beş snapshot alanı.**
///
/// Alanların hepsi satış anında okunmuş **kopyalardır**; ürün sonradan
/// değişse de bu satır değişmez (REQ-SALE-003 · rules/02 §3).
class NewSaleItem {
  final int productId;

  /// SNAPSHOT 1/5.
  final String productNameSnapshot;

  final String? barcodeSnapshot;

  /// SNAPSHOT 2/5.
  final int? categoryIdSnapshot;

  final int quantity;

  /// SNAPSHOT 3/5 — **KDV dahil** uygulanan fiyat.
  final Money unitPrice;

  /// docs/12 §4 — o andaki liste fiyatı; override raporlaması bunun üzerinden
  /// yapılır (BR-SALE-004).
  final Money originalUnitPrice;

  /// SNAPSHOT 4/5 — kâr hesabının maliyet tarafı (REQ-FIN-008).
  final Money purchasePriceSnapshot;

  /// SNAPSHOT 5/5 — basis point (REQ-VAT-003).
  final int vatRateSnapshotBp;

  final Money lineNet;
  final Money lineVat;
  final Money lineTotal;

  const NewSaleItem({
    required this.productId,
    required this.productNameSnapshot,
    required this.barcodeSnapshot,
    required this.categoryIdSnapshot,
    required this.quantity,
    required this.unitPrice,
    required this.originalUnitPrice,
    required this.purchasePriceSnapshot,
    required this.vatRateSnapshotBp,
    required this.lineNet,
    required this.lineVat,
    required this.lineTotal,
  });

  /// docs/12 §4 — satır fiyatı satış sırasında değiştirildi mi?
  bool get isPriceOverridden => unitPrice != originalUnitPrice;
}
