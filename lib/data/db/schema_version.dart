/// Şema versiyonu — docs/06-database-migrations.md §1
///
/// ```text
/// schemaVersion = 1  →  v1.0.0 ile yayınlanan ilk şema
/// ```
///
/// `schemaVersion` **uygulama sürümünden bağımsızdır.** SQLite'ın `user_version`
/// alanında tutulur.
///
/// | Durum | Davranış |
/// |---|---|
/// | `db.version < supported` | Migration çalıştır |
/// | `db.version = supported` | Normal başlat |
/// | `db.version > supported` | **Başlatma** — `SchemaVersionException` (REQ-MIG-005) |
library;

/// Bu uygulama sürümünün desteklediği şema versiyonu.
///
/// Artırıldığında [MigrationPlan]'a karşılık gelen adım eklenmeli ve
/// `test/db/schema/v<N>.json` dump'ı repoya konmalıdır (REQ-MIG-008).
const int kSupportedSchemaVersion = 1;
