/// Satış durumu — docs/04-domain-model.md §4.1
///
/// ```text
/// completed ──► cancelled            (terminal, BR-RET-006)
/// completed ──► partiallyReturned ──► returned  (terminal)
/// ```
///
/// **Saklama:** `sales.status` TEXT'tir (docs/05 §2.8).
/// BR-GEN-002 / BR-SALE-006: satış kayıtları silinmez, yalnızca durum değişir.
library;

enum SaleStatus {
  completed('completed'),
  cancelled('cancelled'),
  partiallyReturned('partiallyReturned'),
  returned('returned');

  /// Veritabanına yazılan metin. **Değiştirilemez.**
  final String wire;

  const SaleStatus(this.wire);

  /// `cancelled` ve `returned` terminaldir (docs/04 §4.1).
  bool get isTerminal =>
      this == SaleStatus.cancelled || this == SaleStatus.returned;

  static SaleStatus fromWire(String value) {
    for (final status in SaleStatus.values) {
      if (status.wire == value) return status;
    }
    throw ArgumentError.value(value, 'value', 'Bilinmeyen satış durumu');
  }
}
