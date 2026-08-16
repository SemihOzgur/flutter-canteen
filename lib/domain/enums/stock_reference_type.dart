/// Stok hareketinin referans türü — docs/04-domain-model.md §3.11
///
/// `sale` | `return` | `import` | `manual` | `backupRestore`
///
/// BR-STOCK-010: her stok hareketi bir sebep **veya** referans taşır.
/// "Bu ürünün stoğu neden 12?" sorusu defterden geriye dönük yanıtlanabilmelidir.
///
/// `return` ve `import` Dart'ta sırasıyla ayrılmış sözcük ve yerleşik
/// tanımlayıcıdır; Dart adları farklı, [wire] değerleri dokümanla aynıdır.
library;

enum StockReferenceType {
  sale('sale'),
  returnOperation('return'),
  importOperation('import'),
  manual('manual'),
  backupRestore('backupRestore');

  /// Veritabanına yazılan metin. **Değiştirilemez.**
  final String wire;

  const StockReferenceType(this.wire);

  static StockReferenceType fromWire(String value) {
    for (final type in StockReferenceType.values) {
      if (type.wire == value) return type;
    }
    throw ArgumentError.value(value, 'value', 'Bilinmeyen referans türü');
  }
}
