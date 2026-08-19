/// Tutarlılık kontrolünün sonucu — **docs/24 §3.3 · REQ-DATA-006 · REQ-DB-008**
///
/// Saf veri; hiçbir düzeltme kararı taşımaz. **Otomatik düzeltme yapılmaz**
/// (rules/03 §2): sapmanın nasıl kapatılacağına kullanıcı karar verir ve
/// düzeltme ters yönde bir `adjustment` hareketiyle yapılır.
library;

/// Sapmanın hangi denetimde bulunduğu.
enum ConsistencyCheck {
  /// `products.stock_quantity` = Σ `stock_movements.quantity_delta`
  stockQuantity,

  /// `sales.grand_total_minor` = Σ `sale_items.line_total_minor`
  saleTotals,

  /// `sales.item_count` / `unit_count` satırlarla tutarlı
  saleCounts,

  /// `sale_items.returned_quantity` = Σ `return_items.quantity`
  returnedQuantity,

  /// `products.image_path` işaret ettiği dosya mevcut
  missingImage,

  /// `PRAGMA foreign_key_check` boş
  foreignKeys,

  /// `PRAGMA integrity_check` = ok
  databaseIntegrity,
}

/// Tek bir sapma.
class ConsistencyFinding {
  final ConsistencyCheck check;

  /// İlgili kaydın kimliği (ürün, satış, satır …). Veritabanı seviyesindeki
  /// denetimlerde `null`.
  final int? entityId;

  /// Kullanıcıya gösterilecek ad — "Coca Cola 330ml", "2026-000148".
  final String? label;

  /// Olması gereken.
  final String expected;

  /// Bulunan.
  final String actual;

  const ConsistencyFinding({
    required this.check,
    required this.expected,
    required this.actual,
    this.entityId,
    this.label,
  });

  /// Yalnızca stok sapmaları `adjustment` hareketiyle düzeltilebilir
  /// (REQ-DATA-007). Diğerleri elle inceleme gerektirir — örneğin bozulmuş bir
  /// satış toplamı, defter mantığıyla kapatılamaz.
  bool get isRepairable => check == ConsistencyCheck.stockQuantity;

  @override
  String toString() =>
      'ConsistencyFinding(${check.name}, id: $entityId, '
      'expected: $expected, actual: $actual)';
}

class ConsistencyReport {
  final List<ConsistencyFinding> findings;

  /// Kontrolün çalıştığı an (UTC).
  final DateTime runAtUtc;

  /// Taranan ürün sayısı — raporun kapsamını gösterir.
  final int productsChecked;
  final int salesChecked;

  const ConsistencyReport({
    required this.findings,
    required this.runAtUtc,
    required this.productsChecked,
    required this.salesChecked,
  });

  bool get isClean => findings.isEmpty;

  Iterable<ConsistencyFinding> of(ConsistencyCheck check) =>
      findings.where((f) => f.check == check);

  /// REQ-DATA-007 — kullanıcı onayıyla düzeltilebilecek sapmalar.
  Iterable<ConsistencyFinding> get repairable =>
      findings.where((f) => f.isRepairable);
}
