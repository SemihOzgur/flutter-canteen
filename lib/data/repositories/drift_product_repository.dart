/// [ProductRepository]'nin Drift implementasyonu.
///
/// Drift bağımlılığı **yalnızca bu katmanda** bulunur (rules/01 §1).
/// Domain katmanı bu dosyayı tanımaz; yalnızca arayüzü bilir.
library;

import 'package:drift/drift.dart';

import '../../core/money/money.dart';
import '../../core/result/result.dart';
import '../../domain/models/product.dart';
import '../../domain/repositories/product_repository.dart';
import '../db/canteen_database.dart' as db;
import 'failures.dart';

class DriftProductRepository implements ProductRepository {
  final db.CanteenDatabase _db;

  DriftProductRepository(this._db);

  static Product _toDomain(db.Product row) => Product(
    id: row.id,
    name: row.name,
    description: row.description,
    categoryId: row.categoryId,
    brand: row.brand,
    salesUnit: row.salesUnit,
    netWeightValue: row.netWeightValue,
    netWeightUnit: row.netWeightUnit,
    purchasePrice: Money(row.purchasePriceMinor),
    salePrice: Money(row.salePriceMinor),
    vatRateId: row.vatRateId,
    stockQuantity: row.stockQuantity,
    minimumStock: row.minimumStock,
    supplierId: row.supplierId,
    shelfLocation: row.shelfLocation,
    imagePath: row.imagePath,
    isFavorite: row.isFavorite,
    isActive: row.isActive,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  @override
  Future<Result<Product>> findById(int id) async {
    final row = await (_db.select(
      _db.products,
    )..where((p) => p.id.equals(id))).getSingleOrNull();

    if (row == null) return const Err(DataFailures.productNotFound);
    return Ok(_toDomain(row));
  }

  @override
  Future<Result<Product>> findByBarcode(String barcode) async {
    // ux_barcode index'i üzerinden — satış hızının bağlı olduğu sorgu.
    final query = _db.select(_db.productBarcodes).join([
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.productBarcodes.productId),
      ),
    ])..where(_db.productBarcodes.barcode.equals(barcode));

    final row = await query.getSingleOrNull();
    if (row == null) return const Err(DataFailures.productNotFound);
    return Ok(_toDomain(row.readTable(_db.products)));
  }

  @override
  Future<List<Product>> searchByName(String query, {int limit = 50}) async {
    // Pasif ürünler taranmaz (docs/05 §3.1); sıralama ve sayfalama SQL tarafında.
    final rows =
        await (_db.select(_db.products)
              ..where((p) => p.isActive.equals(true) & p.name.like('%$query%'))
              ..orderBy([(p) => OrderingTerm(expression: p.name)])
              ..limit(limit))
            .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<List<Product>> listActive({int limit = 100, int offset = 0}) async {
    final rows =
        await (_db.select(_db.products)
              ..where((p) => p.isActive.equals(true))
              ..orderBy([(p) => OrderingTerm(expression: p.name)])
              ..limit(limit, offset: offset))
            .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<Result<int>> create(NewProduct product) async {
    final now = _db.clock().toUtc();
    try {
      final id = await _db
          .into(_db.products)
          .insert(
            db.ProductsCompanion.insert(
              name: product.name,
              description: Value(product.description),
              categoryId: product.categoryId,
              brand: Value(product.brand),
              salesUnit: Value(product.salesUnit),
              netWeightValue: Value(product.netWeightValue),
              netWeightUnit: Value(product.netWeightUnit),
              purchasePriceMinor: Value(product.purchasePrice.minor),
              salePriceMinor: product.salePrice.minor,
              vatRateId: Value(product.vatRateId),
              minimumStock: Value(product.minimumStock),
              supplierId: Value(product.supplierId),
              shelfLocation: Value(product.shelfLocation),
              imagePath: Value(product.imagePath),
              isFavorite: Value(product.isFavorite),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return Ok(id);
    } on Object catch (error) {
      final failure = mapConstraintFailure(error);
      if (failure == null) rethrow;
      return Err(failure);
    }
  }

  @override
  Future<Result<void>> update(Product product) async {
    final affected =
        await (_db.update(
          _db.products,
        )..where((p) => p.id.equals(product.id))).write(
          db.ProductsCompanion(
            name: Value(product.name),
            description: Value(product.description),
            categoryId: Value(product.categoryId),
            brand: Value(product.brand),
            salesUnit: Value(product.salesUnit),
            netWeightValue: Value(product.netWeightValue),
            netWeightUnit: Value(product.netWeightUnit),
            purchasePriceMinor: Value(product.purchasePrice.minor),
            salePriceMinor: Value(product.salePrice.minor),
            vatRateId: Value(product.vatRateId),
            minimumStock: Value(product.minimumStock),
            supplierId: Value(product.supplierId),
            shelfLocation: Value(product.shelfLocation),
            imagePath: Value(product.imagePath),
            isFavorite: Value(product.isFavorite),
            isActive: Value(product.isActive),
            updatedAt: Value(_db.clock().toUtc()),
            // stock_quantity BİLİNÇLİ olarak yazılmaz — tek yazım noktası
            // StockService'tir (rules/02 §4, Faz 6).
          ),
        );

    if (affected == 0) return const Err(DataFailures.productNotFound);
    return const Ok(null);
  }

  @override
  Future<Result<int>> addBarcode({
    required int productId,
    required String barcode,
    bool isPrimary = false,
  }) async {
    try {
      final id = await _db
          .into(_db.productBarcodes)
          .insert(
            db.ProductBarcodesCompanion.insert(
              productId: productId,
              barcode: barcode,
              isPrimary: Value(isPrimary),
              createdAt: _db.clock().toUtc(),
            ),
          );
      return Ok(id);
    } on Object catch (error) {
      final failure = mapConstraintFailure(error);
      if (failure == null) rethrow;
      return Err(failure);
    }
  }

  @override
  Future<List<String>> barcodesOf(int productId) async {
    final rows = await (_db.select(
      _db.productBarcodes,
    )..where((b) => b.productId.equals(productId))).get();
    return rows.map((r) => r.barcode).toList();
  }
}
