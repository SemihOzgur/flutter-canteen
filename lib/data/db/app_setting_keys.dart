/// `app_settings` anahtarları — docs/05-database-architecture.md §2.12
///
/// ⚠️ **BR-SEC-001 / REQ-DB-010:** Bu tabloya düz metin parola veya recovery
/// code **yazılmaz.** Yalnızca salt'lı SHA-256 hash'leri saklanır (Faz 3).
library;

abstract final class AppSettingKeys {
  /// `{ userId, loginAt }` — oturum (Faz 3).
  static const String session = 'session';

  /// Dashboard parolası — **hash** (BR-AUTH-009).
  static const String dashboardPasswordHash = 'dashboard_password_hash';
  static const String dashboardPasswordSalt = 'dashboard_password_salt';

  /// Recovery code — **hash** (BR-AUTH-015).
  static const String dashboardRecoveryHash = 'dashboard_recovery_hash';
  static const String dashboardRecoverySalt = 'dashboard_recovery_salt';

  /// Tek kullanımlık kontrolü (BR-AUTH-015).
  static const String dashboardRecoveryUsedAt = 'dashboard_recovery_used_at';

  /// Yarım kalmış migration bayrağı — docs/06 §3 adım 4 (REQ-MIG-006).
  static const String migrationInProgress = 'migration_in_progress';

  /// Yarım kalmış restore bayrağı — docs/19 (Faz 9).
  /// ⚠️ **OD-027 — ARTIK KULLANILMIYOR.**
  ///
  /// Yarım kalan restore işareti veri dizinindeki `restore_in_progress.json`
  /// dosyasındadır: restore veritabanı **dosyasını takas eder** ve içerideki
  /// bir bayrak tam da kesinti anında kaybolurdu.
  ///
  /// Anahtar kaldırılmadı: yayınlanmış bir anahtarı silmek eski kurulumlarda
  /// okunamayan bir kalıntı bırakırdı.
  static const String restoreInProgress = 'restore_in_progress';

  /// Görsel optimizasyon profili (OD-016).
  static const String imageOptimization = 'image_optimization';

  /// docs/19 §3 — son yedek zamanı (UTC ms).
  ///
  /// REQ-BKUP-016: 7 günden uzun süredir yedek alınmadıysa kullanıcı uyarılır.
  static const String lastBackupAt = 'last_backup_at';

  /// `sale_counter_<yıl>` anahtarını üretir.
  static String saleCounter(int year) => 'sale_counter_$year';
}
