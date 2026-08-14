/// Ürün tabloları — docs/05-database-architecture.md §2.5–2.6
///
/// `products` · `product_barcodes`
library;

import 'package:drift/drift.dart';

import '../converters.dart';
import 'reference_tables.dart';

/// docs/05 §2.5
///
/// - `sale_price_minor` **KDV DAHİLDİR** (BR-VAT-003).
/// - Tüm parasal alanlar tam sayı kuruştur (BR-FIN-001 · REQ-DB-002).
/// - `stock_quantity` türetilmiş önbellektir; otorite `stock_movements`'tır
///   (BR-STOCK-002). **Negatif olabilir** (BR-STOCK-006).
/// - Ağırlık değeri ve birimi birlikte doldurulur (BR-PROD-011 · REQ-DB-011).
@TableIndex.sql(
  'CREATE INDEX ix_products_active_name ON products (is_active, name)',
)
@TableIndex.sql(
  'CREATE INDEX ix_products_category ON products (category_id, is_active)',
)
@TableIndex.sql('CREATE INDEX ix_products_supplier ON products (supplier_id)')
@TableIndex.sql(
  'CREATE INDEX ix_products_favorite ON products (is_favorite) '
  'WHERE is_favorite = 1',
)
@TableIndex.sql(
  'CREATE INDEX ix_products_lowstock ON products (minimum_stock, stock_quantity)',
)
class Products extends Table {
  @override
  String get tableName => 'products';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  TextColumn get description => text().nullable()();

  IntColumn get categoryId => integer().references(Categories, #id)();

  /// Serbest metin (BR-SUP-003) — ayrı `Brand` entity'si yoktur.
  TextColumn get brand => text().nullable()();

  /// Serbest metin (BR-SUP-004) — ayrı `Unit` entity'si yoktur.
  TextColumn get salesUnit => text().nullable()();

  /// Milli hassasiyet: 150 g → 150000. Yalnızca açıklayıcıdır; hiçbir
  /// fiyat/stok hesabına girmez (rules/02 §8).
  IntColumn get netWeightValue => integer().nullable()();

  /// g / kg / ml / lt
  TextColumn get netWeightUnit => text().nullable()();

  /// Hızlı eklemede boş bırakılabilir → `0` (asla `null`).
  IntColumn get purchasePriceMinor =>
      integer().withDefault(const Constant(0))();

  /// **KDV DAHİL** satış fiyatı (BR-VAT-003). `0` = ikram ürünü.
  IntColumn get salePriceMinor => integer()();

  IntColumn get vatRateId => integer().nullable().references(VatRates, #id)();

  /// Türetilmiş önbellek — yalnızca `StockService` üzerinden değişir (Faz 6).
  IntColumn get stockQuantity => integer().withDefault(const Constant(0))();

  IntColumn get minimumStock => integer().withDefault(const Constant(0))();

  IntColumn get supplierId => integer().nullable().references(Suppliers, #id)();

  TextColumn get shelfLocation => text().nullable()();

  /// **Göreli** yol (`images/<uuid>.jpg`) — mutlak yol asla (rules/03 §8).
  TextColumn get imagePath => text().nullable()();

  /// BR-PROD-008 — ayrı `Favorite` entity'si yoktur.
  BoolColumn get isFavorite => boolean().withDefault(const Constant(false))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  IntColumn get createdAt => integer().map(const UtcMillisConverter())();

  IntColumn get updatedAt => integer().map(const UtcMillisConverter())();

  @override
  List<String> get customConstraints => [
    'CHECK(purchase_price_minor >= 0)',
    'CHECK(sale_price_minor >= 0)',
    'CHECK(minimum_stock >= 0)',
    // BR-PROD-011 / REQ-DB-011 — ağırlık çifti birlikte NULL ya da birlikte dolu.
    'CHECK((net_weight_value IS NULL) = (net_weight_unit IS NULL))',
  ];
}

/// docs/05 §2.6 — BR-PROD-005: barkod **global** benzersizdir (pasif ürünler dahil).
///
/// `ux_barcode` satış hızının tamamının bağlı olduğu index'tir (docs/05 §3, 🔴).
@TableIndex.sql('CREATE UNIQUE INDEX ux_barcode ON product_barcodes (barcode)')
@TableIndex.sql(
  'CREATE INDEX ix_barcode_product ON product_barcodes (product_id)',
)
class ProductBarcodes extends Table {
  @override
  String get tableName => 'product_barcodes';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get productId => integer().references(Products, #id)();

  /// **Metin** olarak saklanır; baştaki sıfırlar korunur (rules/02 §10).
  TextColumn get barcode => text()();

  BoolColumn get isPrimary => boolean().withDefault(const Constant(false))();

  IntColumn get createdAt => integer().map(const UtcMillisConverter())();
}
