/// Satış tabloları — docs/05-database-architecture.md §2.8
///
/// `sales` · `sale_items`
library;

import 'package:drift/drift.dart';

import '../converters.dart';
import 'product_tables.dart';
import 'reference_tables.dart';

/// docs/05 §2.8
///
/// **Invariant:** `subtotal_minor + vat_total_minor == grand_total_minor`
/// (rules/02 §2). `subtotal` KDV **hariç** matrah, `grand_total` KDV **dahil**
/// müşteriden alınan tutardır.
///
/// `discount_total_minor` şemada mevcuttur ancak **V1'de daima `0`**'dır
/// (OD-007 · rules/02 §11.1).
@TableIndex.sql('CREATE UNIQUE INDEX ux_sales_number ON sales (sale_number)')
@TableIndex.sql('CREATE INDEX ix_sales_completed_at ON sales (completed_at)')
@TableIndex.sql(
  'CREATE INDEX ix_sales_status_date ON sales (status, completed_at)',
)
class Sales extends Table {
  @override
  String get tableName => 'sales';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get saleNumber => text()();

  /// completed | cancelled | partiallyReturned | returned — TEXT.
  TextColumn get status => text().map(const SaleStatusConverter())();

  /// KDV **HARİÇ** toplam (matrah).
  IntColumn get subtotalMinor => integer()();

  IntColumn get vatTotalMinor => integer()();

  /// V1'de daima 0 (OD-007).
  IntColumn get discountTotalMinor =>
      integer().withDefault(const Constant(0))();

  /// KDV **DAHİL** — müşteriden alınan tutar.
  IntColumn get grandTotalMinor => integer()();

  IntColumn get costTotalMinor => integer()();

  IntColumn get cashReceivedMinor => integer().nullable()();

  IntColumn get changeMinor => integer().nullable()();

  IntColumn get itemCount => integer()();

  IntColumn get unitCount => integer()();

  IntColumn get userId => integer().references(Users, #id)();

  TextColumn get note => text().nullable()();

  /// Raporların zaman ekseni.
  IntColumn get completedAt => integer().map(const UtcMillisConverter())();

  IntColumn get cancelledAt =>
      integer().nullable().map(nullableUtcMillisConverter)();

  IntColumn get createdAt => integer().map(const UtcMillisConverter())();

  IntColumn get updatedAt => integer().map(const UtcMillisConverter())();
}

/// docs/05 §2.8 — **BR-SALE-001: beş snapshot alanı.**
///
/// Geçmiş satışlar mevcut ürün verisinden yeniden hesaplanamaz (rules/02 §3).
/// Raporlar `products` tablosuna JOIN yapmaz; snapshot alanlarını kullanır.
///
/// Snapshot alanları yazıldıktan sonra **immutable**'dır.
@TableIndex.sql('CREATE INDEX ix_sale_items_sale ON sale_items (sale_id)')
@TableIndex.sql('CREATE INDEX ix_sale_items_product ON sale_items (product_id)')
class SaleItems extends Table {
  @override
  String get tableName => 'sale_items';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get saleId => integer().references(Sales, #id)();

  IntColumn get productId => integer().references(Products, #id)();

  /// SNAPSHOT 1/5 — satış anındaki ürün adı.
  TextColumn get productNameSnapshot => text()();

  TextColumn get barcodeSnapshot => text().nullable()();

  /// SNAPSHOT 2/5 — satış anındaki kategori.
  IntColumn get categoryIdSnapshot => integer().nullable()();

  /// BR-SALE-011 — pozitif tam sayı.
  IntColumn get quantity => integer()();

  /// SNAPSHOT 3/5 — satış anındaki birim fiyat (**KDV dahil**).
  IntColumn get unitPriceMinor => integer()();

  /// O andaki liste fiyatı — fiyat override'ını raporlamak için.
  IntColumn get originalUnitPriceMinor => integer()();

  /// SNAPSHOT 4/5 — satış anındaki alış fiyatı (kâr hesabı için).
  IntColumn get purchasePriceSnapshotMinor => integer()();

  /// SNAPSHOT 5/5 — satış anındaki KDV oranı (basis point).
  /// KDV raporları bu alandan gruplanır; `vat_rates`'e JOIN yapılmaz.
  IntColumn get vatRateSnapshotBp => integer()();

  /// KDV hariç.
  IntColumn get lineNetMinor => integer()();

  IntColumn get lineVatMinor => integer()();

  /// = `unit_price_minor × quantity` (KDV dahil).
  IntColumn get lineTotalMinor => integer()();

  /// Türetilmiş — `return_items` toplamı (docs/05 §4).
  IntColumn get returnedQuantity => integer().withDefault(const Constant(0))();

  @override
  List<String> get customConstraints => [
    'CHECK(quantity > 0)',
    'CHECK(returned_quantity >= 0 AND returned_quantity <= quantity)',
  ];
}
