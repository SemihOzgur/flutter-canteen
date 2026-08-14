/// İade türü — docs/05-database-architecture.md §2.9 (`returns.type`).
///
/// BR-RET-002: kısmi iade desteklenir; tek satış durumuyla ifade edilemediği
/// için ayrı `returns` entity'si vardır (docs/04 §1).
library;

enum ReturnType {
  full('full'),
  partial('partial');

  /// Veritabanına yazılan metin. **Değiştirilemez.**
  final String wire;

  const ReturnType(this.wire);

  static ReturnType fromWire(String value) {
    for (final type in ReturnType.values) {
      if (type.wire == value) return type;
    }
    throw ArgumentError.value(value, 'value', 'Bilinmeyen iade türü');
  }
}
