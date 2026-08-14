/// Stok hareket tipi — **docs/13-stock-system.md §2** (9 tip).
///
/// BR-STOCK-001: `stock_movements` stok geçmişinin otoritesidir.
/// BR-STOCK-004: `quantity_delta` asla `0` olamaz.
///
/// **Saklama:** `stock_movements.type` TEXT'tir (docs/05 §2.10).
///
/// ## `return` neden `returnedToStock` olarak adlandırıldı
///
/// Dokümandaki tip adı `return`'dür; ancak `return` Dart'ta **ayrılmış sözcüktür**
/// ve tanımlayıcı olarak kullanılamaz. Bu nedenle Dart adı farklıdır, veritabanına
/// yazılan [wire] değeri ise dokümanla **birebir aynıdır.**
///
/// ## Kaynak notu — rules/02 §4 ile fark
///
/// `rules/02-business-invariants.md §4` hareket tiplerini sayarken
/// `restoreBaseline`'ı **listelememektedir** (8 tip). `docs/13 §2` ise 9 tip
/// tanımlar. `rules/00-source-of-truth.md §2` gereği **`docs/` kazanır**;
/// bu enum docs/13'e uyar. Kural dosyasının düzeltilmesi önerilmiştir (GAP-2-001).
library;

enum StockMovementType {
  /// Ürün oluşturma — başlangıç stoğu. Ürün başına en fazla bir kez.
  initial('initial'),

  /// Kullanıcı stok girişi. Tedarikçi ve birim maliyet bağlanabilir.
  stockEntry('stockEntry'),

  /// Satış tamamlama (otomatik). `reference: sale`
  sale('sale'),

  /// Satış iptali (otomatik). `reference: sale`
  saleCancellation('saleCancellation'),

  /// İade (otomatik). `reference: return`
  ///
  /// Dart adı `return` olamaz — veritabanı değeri yine de `'return'`dür.
  returnedToStock('return'),

  /// Fire. Sebep zorunludur (BR-STOCK-010).
  waste('waste'),

  /// Sayım düzeltmesi. Sebep zorunludur (BR-STOCK-010).
  adjustment('adjustment'),

  /// Excel/CSV import. `reference: import`
  importAdjustment('importAdjustment'),

  /// Backup restore sonrası taban düzeltmesi (docs/19).
  restoreBaseline('restoreBaseline');

  /// Veritabanına yazılan metin. **Değiştirilemez** — defter kaydı bozulur.
  final String wire;

  const StockMovementType(this.wire);

  static StockMovementType fromWire(String value) {
    for (final type in StockMovementType.values) {
      if (type.wire == value) return type;
    }
    throw ArgumentError.value(value, 'value', 'Bilinmeyen stok hareket tipi');
  }
}
