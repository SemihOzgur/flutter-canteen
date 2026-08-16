/// [StockRepository]'nin Drift implementasyonu.
///
/// **Yazma yoktur:** `stock_quantity` ve stok defteri yalnızca `StockService`
/// üzerinden değişir (rules/02 §4, Faz 6).
library;

import 'package:drift/drift.dart';

import '../../core/money/money.dart';
import '../../core/result/result.dart';
import '../../domain/enums/stock_reference_type.dart';
import '../../domain/models/stock_movement.dart' as domain;
import '../../domain/repositories/stock_repository.dart';
import '../db/canteen_database.dart' as db;
import 'failures.dart';

class DriftStockRepository implements StockRepository {
  final db.CanteenDatabase _db;

  DriftStockRepository(this._db);

  static domain.StockMovement _toDomain(db.StockMovement row) =>
      domain.StockMovement(
        id: row.id,
        productId: row.productId,
        type: row.type,
        quantityDelta: row.quantityDelta,
        resultingStock: row.resultingStock,
        unitCost: row.unitCostMinor == null ? null : Money(row.unitCostMinor!),
        referenceType: row.referenceType,
        referenceId: row.referenceId,
        supplierId: row.supplierId,
        note: row.note,
        userId: row.userId,
        createdAt: row.createdAt,
      );

  @override
  Future<Result<domain.StockMovement>> findById(int id) async {
    final row = await (_db.select(
      _db.stockMovements,
    )..where((m) => m.id.equals(id))).getSingleOrNull();

    if (row == null) return const Err(DataFailures.stockMovementNotFound);
    return Ok(_toDomain(row));
  }

  @override
  Future<List<domain.StockMovement>> movementsOf(
    int productId, {
    int limit = 100,
    int offset = 0,
  }) async {
    // ix_movements_product_date üzerinden.
    final rows =
        await (_db.select(_db.stockMovements)
              ..where((m) => m.productId.equals(productId))
              ..orderBy([
                (m) => OrderingTerm(
                  expression: m.createdAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(limit, offset: offset))
            .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<int> sumQuantityDelta(int productId) async {
    // Toplama SQL tarafında yapılır; Dart'ta döngüyle toplanmaz (rules/01 §8).
    final total = _db.stockMovements.quantityDelta.sum();
    final row =
        await (_db.selectOnly(_db.stockMovements)
              ..addColumns([total])
              ..where(_db.stockMovements.productId.equals(productId)))
            .getSingle();
    return row.read(total) ?? 0;
  }

  @override
  Future<List<domain.StockMovement>> findByReference({
    required StockReferenceType referenceType,
    required int referenceId,
  }) async {
    // ix_movements_reference üzerinden.
    final rows =
        await (_db.select(_db.stockMovements)..where(
              (m) =>
                  m.referenceType.equalsValue(referenceType) &
                  m.referenceId.equals(referenceId),
            ))
            .get();
    return rows.map(_toDomain).toList();
  }
}
