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
