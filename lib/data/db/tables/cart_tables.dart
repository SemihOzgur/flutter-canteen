/// Sepet tabloları — docs/05-database-architecture.md §2.7
///
/// `carts` · `cart_items`
///
/// **Aktif sepet ile tamamlanmış satış kesinlikle ayrı veri yapılarındadır**
/// (rules/02 §12). Sepetin stok veya ciro etkisi yoktur.
library;

import 'package:drift/drift.dart';

import '../converters.dart';
import 'product_tables.dart';
import 'reference_tables.dart';

/// docs/05 §2.7
///
/// **BR-CART-001 — aynı anda yalnızca BİR aktif sepet.**
/// Bu invariant `ux_carts_active` kısmi benzersiz index'i ile **veritabanı
/// seviyesinde** zorlanır (REQ-DB-005); uygulama katmanına bırakılmaz.
@TableIndex.sql(
  "CREATE UNIQUE INDEX ux_carts_active ON carts (status) WHERE status = 'active'",
)
class Carts extends Table {
  @override
  String get tableName => 'carts';

  IntColumn get id => integer().autoIncrement()();

  /// 'active' | 'closed' | 'abandoned' — TEXT olarak saklanır.
  TextColumn get status => text().map(const CartStatusConverter())();

  IntColumn get userId => integer().references(Users, #id)();

  TextColumn get note => text().nullable()();

  IntColumn get createdAt => integer().map(const UtcMillisConverter())();

  IntColumn get updatedAt => integer().map(const UtcMillisConverter())();
}

/// docs/05 §2.7
///
/// `UNIQUE(cart_id, product_id, unit_price_minor)`: aynı fiyattaki aynı ürün
/// tek satırda birleşir — barkod tekrar okutulunca miktar artar (rules/02 §10).
class CartItems extends Table {
  @override
  String get tableName => 'cart_items';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get cartId =>
      integer().references(Carts, #id, onDelete: KeyAction.cascade)();

  IntColumn get productId => integer().references(Products, #id)();

  /// BR-SALE-011 — pozitif tam sayı. Ondalık/tartılı satış yoktur.
  IntColumn get quantity => integer()();

  /// **KDV dahil** birim fiyat.
  IntColumn get unitPriceMinor => integer()();

  BoolColumn get isPriceOverridden =>
      boolean().withDefault(const Constant(false))();

  IntColumn get addedAt => integer().map(const UtcMillisConverter())();

  IntColumn get updatedAt => integer().map(const UtcMillisConverter())();

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {cartId, productId, unitPriceMinor},
  ];

  @override
  List<String> get customConstraints => ['CHECK(quantity > 0)'];
}
