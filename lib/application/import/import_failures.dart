/// Import/export'un **beklenen iş hataları** — docs/20.
library;

import '../../core/result/result.dart';

abstract final class ImportFailures {
  static const Failure fileUnreadable = Failure(
    code: 'import_file_unreadable',
    userMessage: 'Dosya okunamadı. Geçerli bir CSV dosyası seçin.',
  );

  static const Failure emptyFile = Failure(
    code: 'import_file_empty',
    userMessage: 'Dosya boş veya yalnızca başlık satırı içeriyor.',
  );

  /// docs/20 §4 — eşleşmemiş zorunlu sütun.
  static const Failure missingRequiredColumns = Failure(
    code: 'import_missing_columns',
    userMessage:
        'Zorunlu sütunlar eşleştirilmedi. Ürün adı ve satış fiyatı '
        'sütunlarını seçin.',
  );

  /// REQ-IMEX-007 — onaysız import yok.
  static const Failure notConfirmed = Failure(
    code: 'import_not_confirmed',
    userMessage:
        'İçe aktarma onaylanmadı. Önizlemeyi kontrol edip "İçe Aktar" '
        'düğmesine basın.',
  );

  /// docs/20 §4.1 — kullanıcı "iptal et" politikasını seçti.
  static const Failure cancelledByPolicy = Failure(
    code: 'import_cancelled_by_policy',
    userMessage: 'Barkod çakışması nedeniyle içe aktarma iptal edildi.',
  );

  static const Failure nothingToImport = Failure(
    code: 'import_nothing_valid',
    userMessage:
        'İçe aktarılabilecek geçerli satır yok. Hata listesini indirip '
        'dosyanızı düzeltin.',
  );
}
