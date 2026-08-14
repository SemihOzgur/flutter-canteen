/// Drift ↔ domain tip dönüştürücüleri.
///
/// Bu dosya iki **sessiz veri bozulması** riskini kapatır:
///
/// 1. **Zaman hassasiyeti (REQ-DB-003 · BR-GEN-004).**
///    Drift'in `DateTimeColumn` varsayılanı zamanı **unix SANİYE** (veya ISO
///    metin) olarak saklar. Doküman **unix MİLİSANİYE** şart koşar. Varsayılan
///    kullanılsaydı milisaniye bileşeni sessizce kaybolurdu. Bu nedenle tüm
///    zaman kolonları `IntColumn` + [UtcMillisConverter] ile tanımlanır.
///
/// 2. **Enum serileştirmesi.**
///    Drift'in varsayılanı enum'u **index tabanlı INTEGER** olarak saklar.
///    docs/05 §2 tüm enum kolonlarını **TEXT** olarak tanımlar ('active',
///    'completed', 'return' …). Aşağıdaki dönüştürücüler domain enum'unun
///    `wire` değerini kullanır; enum sırası değişse bile veri bozulmaz.
///
/// Bkz. docs/05-database-architecture.md §2 · docs/04-domain-model.md §4
library;

import 'package:drift/drift.dart';

import '../../domain/enums/cart_status.dart';
import '../../domain/enums/return_type.dart';
import '../../domain/enums/sale_status.dart';
import '../../domain/enums/stock_movement_type.dart';
import '../../domain/enums/stock_reference_type.dart';

/// UTC unix-**millisecond** ↔ [DateTime] dönüşümü (REQ-DB-003).
///
/// Okunan değer **daima UTC**'dir; yerel saate çevirme bir presentation
/// concern'üdür (BR-GEN-004).
class UtcMillisConverter extends TypeConverter<DateTime, int> {
  const UtcMillisConverter();

  @override
  DateTime fromSql(int fromDb) =>
      DateTime.fromMillisecondsSinceEpoch(fromDb, isUtc: true);

  @override
  int toSql(DateTime value) => value.toUtc().millisecondsSinceEpoch;
}

/// Nullable zaman kolonları için (`last_login_at`, `cancelled_at` …).
const nullableUtcMillisConverter = NullAwareTypeConverter<DateTime, int>.wrap(
  UtcMillisConverter(),
);

class CartStatusConverter extends TypeConverter<CartStatus, String> {
  const CartStatusConverter();

  @override
  CartStatus fromSql(String fromDb) => CartStatus.fromWire(fromDb);

  @override
  String toSql(CartStatus value) => value.wire;
}

class SaleStatusConverter extends TypeConverter<SaleStatus, String> {
  const SaleStatusConverter();

  @override
  SaleStatus fromSql(String fromDb) => SaleStatus.fromWire(fromDb);

  @override
  String toSql(SaleStatus value) => value.wire;
}

class ReturnTypeConverter extends TypeConverter<ReturnType, String> {
  const ReturnTypeConverter();

  @override
  ReturnType fromSql(String fromDb) => ReturnType.fromWire(fromDb);

  @override
  String toSql(ReturnType value) => value.wire;
}

class StockMovementTypeConverter
    extends TypeConverter<StockMovementType, String> {
  const StockMovementTypeConverter();

  @override
  StockMovementType fromSql(String fromDb) =>
      StockMovementType.fromWire(fromDb);

  @override
  String toSql(StockMovementType value) => value.wire;
}

class StockReferenceTypeConverter
    extends TypeConverter<StockReferenceType, String> {
  const StockReferenceTypeConverter();

  @override
  StockReferenceType fromSql(String fromDb) =>
      StockReferenceType.fromWire(fromDb);

  @override
  String toSql(StockReferenceType value) => value.wire;
}

/// `stock_movements.reference_type` NULL olabilir.
const nullableStockReferenceTypeConverter =
    NullAwareTypeConverter<StockReferenceType, String>.wrap(
      StockReferenceTypeConverter(),
    );
