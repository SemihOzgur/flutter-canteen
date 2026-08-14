/// İade tabloları — docs/05-database-architecture.md §2.9
///
/// `returns` · `return_items`
///
/// BR-RET-008: iade **iade tarihine** göre raporlanır; orijinal satışın tarihi
/// ve tutarı değişmez. İade tutarı **orijinal snapshot fiyattan** hesaplanır.
library;

import 'package:drift/drift.dart';

import '../converters.dart';
import 'reference_tables.dart';
import 'sale_tables.dart';

/// docs/05 §2.9
class Returns extends Table {
  @override
  String get tableName => 'returns';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get saleId => integer().references(Sales, #id)();

  /// 'full' | 'partial' — TEXT.
  TextColumn get type => text().map(const ReturnTypeConverter())();

  IntColumn get totalMinor => integer()();

  TextColumn get reason => text().nullable()();

  IntColumn get userId => integer().references(Users, #id)();

  IntColumn get createdAt => integer().map(const UtcMillisConverter())();
}

/// docs/05 §2.9
///
/// Bir satırın toplam iadesi satılan miktarı aşamaz — bu, `sale_items`
/// üzerindeki `returned_quantity <= quantity` CHECK'i ile de korunur.
class ReturnItems extends Table {
  @override
  String get tableName => 'return_items';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get returnId => integer().references(Returns, #id)();

  IntColumn get saleItemId => integer().references(SaleItems, #id)();

  IntColumn get quantity => integer()();

  /// Orijinal satış snapshot fiyatı — güncel fiyat kullanılmaz (rules/02 §7).
  IntColumn get unitPriceMinor => integer()();

  IntColumn get lineTotalMinor => integer()();

  @override
  List<String> get customConstraints => ['CHECK(quantity > 0)'];
}
