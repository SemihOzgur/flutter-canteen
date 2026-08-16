/// Veritabanı açılış akışı — docs/06-database-migrations.md §3.
///
/// **Kritik sıra (rules/03 §5 · RSK-003):** Bu akış yalnızca single-instance
/// kilidi **alındıktan sonra** çağrılır. İkinci uygulama örneğinde veritabanı
/// hiç açılmaz.
///
/// ```text
/// user_version okunur (ham, Drift devreye girmeden)
///      ├── > desteklenen ──────► SchemaVersionException      (REQ-MIG-005)
///      ├── yarım migration ────► MigrationRecoveryRequired   (REQ-MIG-006)
///      ├── < desteklenen ──────► snapshot → migration → doğrula (REQ-MIG-002/004)
///      └── = desteklenen ──────► normal açılış
/// ```
library;

import 'dart:io';

import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../core/paths/app_paths.dart';
import 'canteen_database.dart';
import 'database_opener.dart';
import 'migrations/migration_coordinator.dart';
import 'migrations/migration_plan.dart';
import 'raw_sqlite_file.dart';
import 'schema_version.dart';

/// Açılışta ne olduğu — testler ve loglama için.
enum DatabaseOpenKind {
  /// Veritabanı ilk kez oluşturuldu (`onCreate` + seed).
  created,

  /// Şema güncel; migration çalışmadı.
  opened,

  /// Migration çalıştı ve doğrulandı.
  migrated,
}

class DatabaseOpenResult {
  final CanteenDatabase database;
  final DatabaseOpenKind kind;

  /// Migration çalıştıysa alınan pre-migration snapshot.
  final File? snapshot;

  const DatabaseOpenResult({
    required this.database,
    required this.kind,
    this.snapshot,
  });
}

class DatabaseBootstrap {
  final AppPaths paths;
  final AppLogger? logger;
  final DateTime Function() clock;
  final MigrationPlan migrationPlan;
  final int supportedSchemaVersion;

  DatabaseBootstrap({
    required this.paths,
    this.logger,
    DateTime Function()? clock,
    MigrationPlan? migrationPlan,
    this.supportedSchemaVersion = kSupportedSchemaVersion,
  }) : clock = clock ?? DateTime.now,
       migrationPlan = migrationPlan ?? MigrationPlan.empty;

  MigrationCoordinator get coordinator => MigrationCoordinator(
    databaseFilePath: paths.databaseFile,
    autoBackupsDirPath: paths.autoBackupsDir,
    clock: clock,
  );

  CanteenDatabase _database({required int schemaVersion, bool seed = true}) {
    return CanteenDatabase(
      openDatabaseFile(
        paths.databaseFile,
        supportedSchemaVersion: supportedSchemaVersion,
      ),
      migrationPlan: migrationPlan,
      clock: clock,
      schemaVersion: schemaVersion,
      applySeed: seed,
    );
  }

  /// Veritabanını açar; gerekiyorsa migration protokolünü yürütür.
  Future<DatabaseOpenResult> open() async {
    final raw = RawSqliteFile(paths.databaseFile);
    final existingVersion = await raw.readUserVersion();

    // REQ-MIG-005 — bağlantı setup'ı da bunu zorlar; burada erken ve net hata.
    if (existingVersion > supportedSchemaVersion) {
      throw SchemaVersionException(
        databaseVersion: existingVersion,
        supportedVersion: supportedSchemaVersion,
        userMessage:
            'Bu veritabanı daha yeni bir sürümle oluşturulmuş. '
            'Lütfen uygulamayı güncelleyin.',
        technicalDetail:
            'user_version=$existingVersion > supported=$supportedSchemaVersion',
      );
    }

    // Yeni kurulum — migration protokolü uygulanmaz.
    if (existingVersion == 0) {
      final db = _database(schemaVersion: supportedSchemaVersion);
      await db.customStatement('SELECT 1;'); // açılışı tetikle
      logger?.info('Veritabanı oluşturuldu (şema v$supportedSchemaVersion).');
      return DatabaseOpenResult(database: db, kind: DatabaseOpenKind.created);
    }

    await _assertNoPendingMigration(existingVersion);

    if (existingVersion == supportedSchemaVersion) {
      final db = _database(schemaVersion: supportedSchemaVersion);
      await db.customStatement('SELECT 1;');
      return DatabaseOpenResult(database: db, kind: DatabaseOpenKind.opened);
    }

    return _migrate(from: existingVersion);
  }

  /// REQ-MIG-006 — `migration_in_progress` bayrağı duruyorsa yarım şemayla
  /// çalışmaya izin verilmez.
  Future<void> _assertNoPendingMigration(int existingVersion) async {
    // Mevcut şema versiyonuyla açılır: Drift migration çalıştırmaz, seed yazmaz.
    final probe = _database(schemaVersion: existingVersion, seed: false);
    MigrationFlag? flag;
    try {
      flag = await coordinator.readFlag(probe);
    } finally {
      await probe.close();
    }

    if (flag == null) return;

    final snapshot = coordinator.latestSnapshot();
    logger?.error(
      'Yarım kalmış migration tespit edildi (v${flag.from} → v${flag.to}).',
    );
    throw MigrationRecoveryRequiredException(
      fromVersion: flag.from,
      toVersion: flag.to,
      startedAtUtc: flag.startedAt,
      snapshotPath: snapshot?.path,
      userMessage:
          'Veritabanı güncellemesi yarım kalmış. Verileriniz güncelleme öncesi '
          'haline geri alınabilir.',
      technicalDetail:
          'migration_in_progress: v${flag.from} → v${flag.to}, '
          'snapshot=${snapshot?.path ?? "yok"}',
    );
  }

  /// docs/06 §3 adım 2–9.
  Future<DatabaseOpenResult> _migrate({required int from}) async {
    final coord = coordinator;

    // Adım 2–3: snapshot al ve doğrula. Şema versiyonu mevcut hâlinde açılır ki
    // Drift snapshot alınmadan migration'a başlamasın.
    final probe = _database(schemaVersion: from, seed: false);
    final File snapshot;
    try {
      snapshot = await coord.createSnapshot(probe, fromVersion: from);
      if (!await coord.verifySnapshot(snapshot)) {
        throw MigrationException(
          userMessage:
              'Güncelleme öncesi yedek alınamadı. Güncelleme yapılmadı, '
              'verileriniz değiştirilmedi.',
          technicalDetail: 'Snapshot doğrulaması başarısız: ${snapshot.path}',
        );
      }
      // Adım 4: bayrağı yaz.
      await coord.writeFlag(
        probe,
        MigrationFlag(
          from: from,
          to: supportedSchemaVersion,
          startedAt: clock().toUtc(),
        ),
      );
    } finally {
      await probe.close();
    }

    logger?.info(
      'Migration başlıyor: v$from → v$supportedSchemaVersion '
      '(snapshot alındı).',
    );

    // Adım 5: Drift onUpgrade'i tek transaction içinde çalıştırır (REQ-MIG-004).
    final db = _database(schemaVersion: supportedSchemaVersion);
    try {
      await db.customStatement('SELECT 1;');

      // Adım 6: referans bütünlüğü.
      final violations = await db
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      if (violations.isNotEmpty) {
        throw MigrationException(
          userMessage:
              'Güncelleme doğrulanamadı. Verileriniz güncelleme öncesi haline '
              'geri alındı.',
          technicalDetail:
              'foreign_key_check ${violations.length} ihlal döndürdü.',
        );
      }

      // Adım 9: bayrağı temizle. (Adım 8 user_version'ı Drift yazar.)
      await coord.clearFlag(db);
    } on Object {
      await db.close();
      // Adım 5–7 hatası: Drift transaction'ı geri aldı; şema v$from'da kaldı.
      // Bayrak duruyor → sonraki açılış REQ-MIG-006 kurtarma akışına girer.
      rethrow;
    }

    await coord.pruneSnapshots();
    logger?.info('Migration tamamlandı: v$from → v$supportedSchemaVersion.');

    return DatabaseOpenResult(
      database: db,
      kind: DatabaseOpenKind.migrated,
      snapshot: snapshot,
    );
  }
}
