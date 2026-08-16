/// Sepet durumu — docs/04-domain-model.md §4.2
///
/// ```text
/// active ──(satış tamamlandı)──────────► closed     (terminal)
/// active ──(temizlendi / devir)────────► abandoned  (terminal)
/// ```
///
/// **Saklama:** `carts.status` TEXT'tir (docs/05 §2.7). Değerler [wire] ile
/// açıkça sabitlenmiştir; Drift'in varsayılan enum serileştirmesi (index tabanlı
/// INTEGER) **kullanılmaz.**
library;

enum CartStatus {
  active('active'),
  closed('closed'),
  abandoned('abandoned');

  /// Veritabanına yazılan metin. **Değiştirilemez** — mevcut satırları bozar.
  final String wire;

  const CartStatus(this.wire);

  static CartStatus fromWire(String value) {
    for (final status in CartStatus.values) {
      if (status.wire == value) return status;
    }
    throw ArgumentError.value(value, 'value', 'Bilinmeyen sepet durumu');
  }
}
