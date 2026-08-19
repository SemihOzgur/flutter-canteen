/// [StockRepository]'nin Drift implementasyonu.
///
/// **Yazmanın tek çağıranı `StockService`'tir:** `stock_quantity` ve stok
/// defteri yalnızca o servis üzerinden değişir (rules/02 §4). Transaction
/// sınırı da oradadır (rules/01 §5).
library;

import 'package:drift/drift.dart';

import '../../core/money/money.dart';
import '../../core/result/result.dart';
import '../../domain/enums/stock_movement_type.dart';
import '../../domain/enums/stock_reference_type.dart';
import '../../domain/models/stock_movement.dart' as domain;
import '../../domain/repositories/stock_repository.dart';
import '../db/canteen_database.dart' as db;
import '../db/converters.dart';
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
  Future<List<domain.StockMovement>> list({
    int? productId,
    StockMovementType? type,
    int? supplierId,
    int? userId,
    DateTime? fromUtc,
    DateTime? toUtc,
    int limit = 100,
    int offset = 0,
  }) async {
    const toMillis = UtcMillisConverter();

    final query = _db.select(_db.stockMovements)
      ..where((m) {
        // Filtre verilmediyse koşul EKLENMEZ; `1=1` gibi bir yer tutucu
        // sorgu planını gereksiz yere bulandırırdı.
        var condition = const Constant(true) as Expression<bool>;
        if (productId != null) {
          condition = condition & m.productId.equals(productId);
        }
        if (type != null) condition = condition & m.type.equalsValue(type);
        if (supplierId != null) {
          condition = condition & m.supplierId.equals(supplierId);
        }
        if (userId != null) condition = condition & m.userId.equals(userId);
        if (fromUtc != null) {
          condition =
              condition &
              m.createdAt.isBiggerOrEqualValue(toMillis.toSql(fromUtc));
        }
        if (toUtc != null) {
          condition =
              condition & m.createdAt.isSmallerThanValue(toMillis.toSql(toUtc));
        }
        return condition;
      })
      // En yeni üstte; eşit zamanlarda `id` deterministik sıra verir.
      ..orderBy([
        (m) => OrderingTerm(expression: m.createdAt, mode: OrderingMode.desc),
        (m) => OrderingTerm(expression: m.id, mode: OrderingMode.desc),
      ])
      ..limit(limit, offset: offset);

    return (await query.get()).map(_toDomain).toList();
  }

  @override
  Future<int> countMovements(int productId) async {
    final total = _db.stockMovements.id.count();
    final row =
        await (_db.selectOnly(_db.stockMovements)
              ..addColumns([total])
              ..where(_db.stockMovements.productId.equals(productId)))
            .getSingle();
    return row.read(total) ?? 0;
  }

  @override
  Future<int> appendMovement({
    required int productId,
    required StockMovementType type,
    required int quantityDelta,
    required int resultingStock,
    required int userId,
    required DateTime createdAtUtc,
    Money? unitCost,
    StockReferenceType? referenceType,
    int? referenceId,
    int? supplierId,
    String? note,
  }) {
    return _db
        .into(_db.stockMovements)
        .insert(
          db.StockMovementsCompanion.insert(
            productId: productId,
            type: type,
            quantityDelta: quantityDelta,
            resultingStock: resultingStock,
            unitCostMinor: Value(unitCost?.minor),
            referenceType: Value(referenceType),
            referenceId: Value(referenceId),
            supplierId: Value(supplierId),
            note: Value(note),
            userId: userId,
            createdAt: createdAtUtc.toUtc(),
          ),
        );
  }

  @override
  Future<int> readStockQuantity(int productId) async {
    final row =
        await (_db.selectOnly(_db.products)
              ..addColumns([_db.products.stockQuantity])
              ..where(_db.products.id.equals(productId)))
            .getSingleOrNull();
    return row?.read(_db.products.stockQuantity) ?? 0;
  }

  @override
  Future<int> writeStockQuantity(int productId, int quantity) {
    return (_db.update(
      _db.products,
    )..where((p) => p.id.equals(productId))).write(
      db.ProductsCompanion(
        stockQuantity: Value(quantity),
        updatedAt: Value(_db.clock().toUtc()),
      ),
    );
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
