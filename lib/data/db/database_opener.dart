/// Veritabanı bağlantısı açma ve SQLite yapılandırması.
///
/// docs/05-database-architecture.md §1 — REQ-DB-001 · REQ-DATA-002
///
/// | Ayar | Değer | Gerekçe |
/// |---|---|---|
/// | `journal_mode` | **WAL** | Elektrik kesintisi dayanıklılığı |
/// | `synchronous` | **FULL** | Satış kaybı kabul edilemez |
/// | `foreign_keys` | **ON** | Referans bütünlüğü |
/// | `busy_timeout` | 5000 ms | |
/// | `temp_store` | **MEMORY** | Rapor aggregation hızı |
///
/// Ayrıca **REQ-MIG-005 sürüm kapısı** burada uygulanır: bağlantı açılır açılmaz,
/// Drift herhangi bir migration çalıştırma fırsatı bulmadan `user_version`
/// kontrol edilir.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../../core/errors/app_exception.dart';
import 'schema_version.dart';

/// SQLite PRAGMA değerleri — testler bu sabitleri doğrular.
abstract final class SqlitePragmas {
  static const String journalModeWal = 'wal';

  /// `PRAGMA synchronous` FULL karşılığı.
  static const int synchronousFull = 2;

  /// `PRAGMA temp_store` MEMORY karşılığı.
  static const int tempStoreMemory = 2;

  static const int busyTimeoutMs = 5000;
}

/// Bağlantı kurulum adımlarını üretir.
///
/// [useWal] yalnızca dosya tabanlı veritabanları için anlamlıdır; in-memory
/// veritabanı WAL moduna geçemez.
DatabaseSetup buildDatabaseSetup({
  required bool useWal,
  int supportedSchemaVersion = kSupportedSchemaVersion,
}) {
  return (rawDb) {
    if (useWal) {
      rawDb.execute('PRAGMA journal_mode = WAL;');
    }
    rawDb.execute('PRAGMA synchronous = FULL;');
    rawDb.execute('PRAGMA foreign_keys = ON;');
    rawDb.execute('PRAGMA busy_timeout = ${SqlitePragmas.busyTimeoutMs};');
    rawDb.execute('PRAGMA temp_store = MEMORY;');

    // REQ-MIG-005 — kendi desteklediğinden yeni bir şemayı açmayı reddet.
    final rows = rawDb.select('PRAGMA user_version;');
    final version = rows.isEmpty ? 0 : rows.first.values.first as int? ?? 0;
    if (version > supportedSchemaVersion) {
      throw SchemaVersionException(
        databaseVersion: version,
        supportedVersion: supportedSchemaVersion,
        userMessage:
            'Bu veritabanı daha yeni bir sürümle oluşturulmuş. '
            'Lütfen uygulamayı güncelleyin.',
        technicalDetail:
            'user_version=$version > supported=$supportedSchemaVersion',
      );
    }
  };
}

/// Dosya tabanlı veritabanı bağlantısı (production).
QueryExecutor openDatabaseFile(
  String path, {
  int supportedSchemaVersion = kSupportedSchemaVersion,
  bool logStatements = false,
}) {
  return NativeDatabase(
    File(path),
    logStatements: logStatements,
    setup: buildDatabaseSetup(
      useWal: true,
      supportedSchemaVersion: supportedSchemaVersion,
    ),
  );
}

/// In-memory bağlantı (testler — docs/27 §4).
///
/// WAL uygulanmaz: in-memory veritabanları `journal_mode = memory` kullanır.
/// WAL'ın gerçekten etkin olduğu **dosya tabanlı** bir test ile doğrulanır.
QueryExecutor openDatabaseInMemory({
  int supportedSchemaVersion = kSupportedSchemaVersion,
  bool logStatements = false,
}) {
  return NativeDatabase.memory(
    logStatements: logStatements,
    setup: buildDatabaseSetup(
      useWal: false,
      supportedSchemaVersion: supportedSchemaVersion,
    ),
  );
}
