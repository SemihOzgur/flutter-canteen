/// Görsel yükleme akışının **beklenen** hataları — REQ-IMG-004/005.
///
/// `rules/06 §7`: beklenen iş hataları `Result`/`Failure` ile döner.
/// Mesajlar Türkçedir (REQ-UX-007), `rules/05 §5` biçimindedir
/// (**ne oldu + ne yapmalıyım**) ve **dosya yolu/teknik detay içermez**
/// (REQ-SEC-007 · rules/04 §7).
library;

import '../../core/result/result.dart';

abstract final class ImageFailures {
  static const Failure sourceMissing = Failure(
    code: 'image_source_missing',
    userMessage:
        'Seçilen dosya bulunamadı. Dosya taşınmış veya silinmiş olabilir; '
        'yeniden seçin.',
  );

  /// REQ-IMG-005 — uzantı değil, **içerik** doğrulanır.
  static const Failure formatUnsupported = Failure(
    code: 'image_format_unsupported',
    userMessage:
        'Bu dosya desteklenen bir görsel değil. JPG, PNG veya WEBP bir dosya '
        'seçin.',
  );

  /// REQ-IMG-004 — çözülemeyen/bozuk dosya reddedilir.
  static const Failure unreadable = Failure(
    code: 'image_unreadable',
    userMessage:
        'Görsel okunamadı; dosya bozuk olabilir. Başka bir dosya seçin.',
  );

  /// REQ-IMG-004 — **yapılandırılmış** üst sınırı aşan dosya reddedilir.
  ///
  /// Sınır metne parametre olarak girer: değer `app_settings` üzerinden
  /// değiştirilebilir (OD-016), bu yüzden mesaja sabit yazılamaz.
  static Failure tooLarge(int maxBytes) => Failure(
    code: 'image_too_large',
    userMessage:
        'Görsel dosyası çok büyük. En fazla ${_megabytes(maxBytes)} MB '
        'boyutunda bir dosya seçin.',
  );

  static String _megabytes(int bytes) {
    const megabyte = 1024 * 1024;
    if (bytes % megabyte == 0) return (bytes ~/ megabyte).toString();
    // Bir ondalık basamak yeterli; tam sayı aritmetiğiyle üretilir.
    final tenths = (bytes * 10) ~/ megabyte;
    return '${tenths ~/ 10},${tenths % 10}';
  }
}
