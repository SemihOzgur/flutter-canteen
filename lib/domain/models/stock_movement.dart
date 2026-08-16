/// Stok defteri kaydı — docs/04-domain-model.md §3.11
///
/// **BR-STOCK-005: kayıt yazıldıktan sonra değiştirilemez ve silinemez.**
/// Düzeltme, ters yönde yeni bir `adjustment` hareketiyle yapılır.
library;

import '../../core/money/money.dart';
import '../enums/stock_movement_type.dart';
import '../enums/stock_reference_type.dart';

class StockMovement {
  final int id;
  final int productId;
  final StockMovementType type;

  /// BR-STOCK-004 — **asla `0` değildir.**
  final int quantityDelta;

  /// BR-STOCK-008 — hareket sonrası stok.
  final int resultingStock;

  /// Yalnızca `stockEntry` / `initial` için.
  final Money? unitCost;

  final StockReferenceType? referenceType;
  final int? referenceId;
  final int? supplierId;

  /// BR-STOCK-010 — fire ve düzeltmede zorunludur.
  final String? note;

  final int userId;

  /// UTC.
  final DateTime createdAt;

  const StockMovement({
    required this.id,
    required this.productId,
    required this.type,
    required this.quantityDelta,
    required this.resultingStock,
    required this.unitCost,
    required this.referenceType,
    required this.referenceId,
    required this.supplierId,
    required this.note,
    required this.userId,
    required this.createdAt,
  });
}
