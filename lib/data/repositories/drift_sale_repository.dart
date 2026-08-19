/// [SaleRepository]'nin Drift implementasyonu.
///
/// Yazma metotları **transaction açmaz**: satışın atomikliği `SaleService`'e
/// aittir (rules/01 §5). Bkz. `domain/repositories/sale_repository.dart`.
library;

import 'package:drift/drift.dart';

import '../../core/money/money.dart';
import '../../core/result/result.dart';
import '../../domain/models/sale.dart' as domain;
import '../../domain/repositories/sale_repository.dart';
import '../db/canteen_database.dart' as db;
import '../db/converters.dart';
import 'failures.dart';

class DriftSaleRepository implements SaleRepository {
  final db.CanteenDatabase _db;

  DriftSaleRepository(this._db);

  static domain.Sale _toDomain(db.Sale row) => domain.Sale(
    id: row.id,
    saleNumber: row.saleNumber,
    status: row.status,
    subtotal: Money(row.subtotalMinor),
    vatTotal: Money(row.vatTotalMinor),
    discountTotal: Money(row.discountTotalMinor),
    grandTotal: Money(row.grandTotalMinor),
    costTotal: Money(row.costTotalMinor),
    cashReceived: row.cashReceivedMinor == null
        ? null
        : Money(row.cashReceivedMinor!),
    change: row.changeMinor == null ? null : Money(row.changeMinor!),
    itemCount: row.itemCount,
    unitCount: row.unitCount,
    userId: row.userId,
    note: row.note,
    completedAt: row.completedAt,
    cancelledAt: row.cancelledAt,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  static domain.SaleItem _itemToDomain(db.SaleItem row) => domain.SaleItem(
    id: row.id,
    saleId: row.saleId,
    productId: row.productId,
    productNameSnapshot: row.productNameSnapshot,
    barcodeSnapshot: row.barcodeSnapshot,
    categoryIdSnapshot: row.categoryIdSnapshot,
    quantity: row.quantity,
    unitPrice: Money(row.unitPriceMinor),
    originalUnitPrice: Money(row.originalUnitPriceMinor),
    purchasePriceSnapshot: Money(row.purchasePriceSnapshotMinor),
    vatRateSnapshotBp: row.vatRateSnapshotBp,
    lineNet: Money(row.lineNetMinor),
    lineVat: Money(row.lineVatMinor),
    lineTotal: Money(row.lineTotalMinor),
    returnedQuantity: row.returnedQuantity,
  );

  @override
  Future<Result<domain.Sale>> findById(int id) async {
    final row = await (_db.select(
      _db.sales,
    )..where((s) => s.id.equals(id))).getSingleOrNull();

    if (row == null) return const Err(DataFailures.saleNotFound);
    return Ok(_toDomain(row));
  }

  @override
  Future<Result<domain.Sale>> findByNumber(String saleNumber) async {
    final row =
        await (_db.select(_db.sales)
              ..where((s) => s.saleNumber.equals(saleNumber))
              ..limit(1))
            .getSingleOrNull();

    if (row == null) return const Err(DataFailures.saleNotFound);
    return Ok(_toDomain(row));
  }

  @override
  Future<List<domain.Sale>> listCompletedBetween({
    required DateTime fromUtc,
    required DateTime toUtc,
    int limit = 100,
    int offset = 0,
  }) async {
    // ix_sales_completed_at üzerinden — [fromUtc, toUtc) yarı açık aralık.
    //
    // `completed_at` unix-ms INTEGER'dır (REQ-DB-003); karşılaştırma da SQL
    // tipinde yapılır. Dönüşüm tek merkezden gelir — ikinci bir zaman
    // implementasyonu yoktur.
    const toMillis = UtcMillisConverter();
    final fromMs = toMillis.toSql(fromUtc);
    final toMs = toMillis.toSql(toUtc);

    final rows =
        await (_db.select(_db.sales)
              ..where(
                (s) =>
                    s.completedAt.isBiggerOrEqualValue(fromMs) &
                    s.completedAt.isSmallerThanValue(toMs),
              )
              ..orderBy([
                (s) => OrderingTerm(
                  expression: s.completedAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(limit, offset: offset))
            .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<int> insertSale(domain.NewSale sale) {
    return _db
        .into(_db.sales)
        .insert(
          db.SalesCompanion.insert(
            saleNumber: sale.saleNumber,
            status: sale.status,
            subtotalMinor: sale.subtotal.minor,
            vatTotalMinor: sale.vatTotal.minor,
            grandTotalMinor: sale.grandTotal.minor,
            costTotalMinor: sale.costTotal.minor,
            cashReceivedMinor: Value(sale.cashReceived?.minor),
            changeMinor: Value(sale.change?.minor),
            itemCount: sale.itemCount,
            unitCount: sale.unitCount,
            userId: sale.userId,
            note: Value(sale.note),
            completedAt: sale.completedAtUtc,
            createdAt: sale.completedAtUtc,
            updatedAt: sale.completedAtUtc,
          ),
        );
  }

  @override
  Future<int> insertItem(int saleId, domain.NewSaleItem item) {
    return _db
        .into(_db.saleItems)
        .insert(
          db.SaleItemsCompanion.insert(
            saleId: saleId,
            productId: item.productId,
            // BR-SALE-001 — beş snapshot alanı burada kalıcılaşır.
            productNameSnapshot: item.productNameSnapshot,
            barcodeSnapshot: Value(item.barcodeSnapshot),
            categoryIdSnapshot: Value(item.categoryIdSnapshot),
            quantity: item.quantity,
            unitPriceMinor: item.unitPrice.minor,
            originalUnitPriceMinor: item.originalUnitPrice.minor,
            purchasePriceSnapshotMinor: item.purchasePriceSnapshot.minor,
            vatRateSnapshotBp: item.vatRateSnapshotBp,
            lineNetMinor: item.lineNet.minor,
            lineVatMinor: item.lineVat.minor,
            lineTotalMinor: item.lineTotal.minor,
          ),
        );
  }

  @override
  Future<List<domain.SaleItem>> itemsOf(int saleId) async {
    final rows = await (_db.select(
      _db.saleItems,
    )..where((i) => i.saleId.equals(saleId))).get();
    return rows.map(_itemToDomain).toList();
  }
}
