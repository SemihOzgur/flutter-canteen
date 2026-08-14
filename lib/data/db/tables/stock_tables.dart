/// Stok defteri — docs/05-database-architecture.md §2.10
///
/// **BR-STOCK-001: `stock_movements` stok geçmişinin OTORİTESİDİR.**
/// `products.stock_quantity` yalnızca türetilmiş bir önbellektir.
///
/// **BR-STOCK-005: kayıt yazıldıktan sonra UPDATE/DELETE edilmez.**
/// Yanlış hareket düzeltilmez; ters yönde yeni bir `adjustment` eklenir.
library;

import 'package:drift/drift.dart';

import '../converters.dart';
import 'product_tables.dart';
import 'reference_tables.dart';

/// docs/05 §2.10 · docs/13 §2
@TableIndex.sql(
  'CREATE INDEX ix_movements_product_date '
  'ON stock_movements (product_id, created_at)',
)
@TableIndex.sql(
  'CREATE INDEX ix_movements_date ON stock_movements (created_at)',
)
@TableIndex.sql(
  'CREATE INDEX ix_movements_reference '
  'ON stock_movements (reference_type, reference_id)',
)
class StockMovements extends Table {
  @override
  String get tableName => 'stock_movements';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get productId => integer().references(Products, #id)();

  /// 9 tip — docs/13 §2. TEXT olarak saklanır.
  TextColumn get type => text().map(const StockMovementTypeConverter())();

  /// BR-STOCK-004 — **asla `0` olamaz.** Pozitif veya negatif.
  IntColumn get quantityDelta => integer()();

  /// BR-STOCK-008 — hareket sonrası stok, her harekette kaydedilir.
  IntColumn get resultingStock => integer()();

  /// Yalnızca `stockEntry` / `initial` için.
  IntColumn get unitCostMinor => integer().nullable()();

  /// sale | return | import | manual | backupRestore — TEXT, NULL olabilir.
  TextColumn get referenceType =>
      text().nullable().map(nullableStockReferenceTypeConverter)();

  IntColumn get referenceId => integer().nullable()();

  IntColumn get supplierId => integer().nullable().references(Suppliers, #id)();

  /// BR-STOCK-010 — fire ve düzeltmede **zorunlu** (uygulama katmanında, Faz 6).
  TextColumn get note => text().nullable()();

  IntColumn get userId => integer().references(Users, #id)();

  IntColumn get createdAt => integer().map(const UtcMillisConverter())();

  @override
  List<String> get customConstraints => ['CHECK(quantity_delta <> 0)'];
}
