/// Yedekleme ve geri yüklemenin **beklenen iş hataları** — docs/19 §4.
///
/// Hepsi kullanıcıya "ne oldu + ne yapmalıyım" biçiminde konuşur
/// (rules/05 §5); teknik detay log dosyasına gider (REQ-UX-008).
library;

import '../../core/result/result.dart';

abstract final class BackupFailures {
  // --- Yedek alma ----------------------------------------------------------

  static const Failure snapshotFailed = Failure(
    code: 'backup_snapshot_failed',
    userMessage:
        'Veritabanının anlık kopyası alınamadı. Disk alanını kontrol edip '
        'tekrar deneyin.',
  );

  /// docs/19 §3 adım 8 — yazılan arşiv **tekrar okunarak** doğrulanır.
  static const Failure verificationFailed = Failure(
    code: 'backup_verification_failed',
    userMessage:
        'Yedek oluşturuldu ama doğrulanamadı. Dosya kaydedilmedi; lütfen '
        'tekrar deneyin.',
  );

  static const Failure targetNotWritable = Failure(
    code: 'backup_target_not_writable',
    userMessage:
        'Seçilen klasöre yazılamıyor. Başka bir klasör seçin veya klasör '
        'izinlerini kontrol edin.',
  );

  // --- Geri yükleme: doğrulama (docs/19 §4 adım 1–9) -----------------------

  static const Failure notReadable = Failure(
    code: 'restore_not_readable',
    userMessage:
        'Dosya okunamadı. Geçerli bir yedek dosyası (.canteenbackup) seçin.',
  );

  static const Failure invalidArchive = Failure(
    code: 'restore_invalid_archive',
    userMessage:
        'Bu dosya geçerli bir yedek değil. Yanlış dosya seçmiş olabilirsiniz.',
  );

  static const Failure metadataInvalid = Failure(
    code: 'restore_metadata_invalid',
    userMessage: 'Yedeğin bilgi dosyası okunamadı. Dosya bozulmuş olabilir.',
  );

  /// REQ-BKUP-013 — daha yeni format reddedilir.
  static const Failure formatTooNew = Failure(
    code: 'restore_format_too_new',
    userMessage:
        'Bu yedek daha yeni bir uygulama sürümüyle alınmış. Geri yüklemek '
        'için uygulamayı güncelleyin.',
  );

  /// docs/19 §4 adım 4 — `schemaVersion > mevcut` reddedilir.
  static const Failure schemaTooNew = Failure(
    code: 'restore_schema_too_new',
    userMessage:
        'Bu yedek daha yeni bir veritabanı sürümüne ait. Geri yüklemek için '
        'uygulamayı güncelleyin.',
  );

  /// REQ-BKUP-006 — checksum uyuşmazlığı.
  static const Failure checksumMismatch = Failure(
    code: 'restore_checksum_mismatch',
    userMessage:
        'Yedek dosyası bozulmuş. Mevcut verilerinize dokunulmadı; başka bir '
        'yedek deneyin.',
  );

  static const Failure databaseCorrupt = Failure(
    code: 'restore_database_corrupt',
    userMessage: 'Yedekteki veritabanı bozuk. Mevcut verilerinize dokunulmadı.',
  );

  // --- Geri yükleme: uygulama (docs/19 §4 adım 10–22) ---------------------

  /// docs/19 §4 adım 11 — güvenlik yedeği alınamadıysa **restore yapılmaz.**
  static const Failure safetyBackupFailed = Failure(
    code: 'restore_safety_backup_failed',
    userMessage:
        'Mevcut verilerinizin güvenlik yedeği alınamadı. Geri yükleme '
        'başlatılmadı — verileriniz olduğu gibi duruyor.',
  );

  /// docs/19 §4 adım 17 — sayılar tutmuyorsa geri alınır.
  static const Failure verificationRolledBack = Failure(
    code: 'restore_rolled_back',
    userMessage:
        'Geri yükleme doğrulanamadı ve iptal edildi. Önceki verileriniz geri '
        'yüklendi.',
  );

  /// REQ-BKUP-008 — yazarak onay eşleşmedi.
  static const Failure notConfirmed = Failure(
    code: 'restore_not_confirmed',
    userMessage: 'Onay metni eşleşmedi. Geri yükleme başlatılmadı.',
  );
}
