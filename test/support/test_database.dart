/// Faz 2 test yardımcıları.
///
/// docs/27-testing-strategy.md §4: repository/DB testleri **gerçek in-memory
/// SQLite** üzerinde çalışır — mock veritabanı kullanılmaz.
library;

import 'dart:io';

import 'package:canteen/core/paths/app_paths.dart';
import 'package:canteen/data/db/canteen_database.dart';
import 'package:canteen/data/db/database_opener.dart';
import 'package:canteen/data/db/migrations/migration_plan.dart';
import 'package:canteen/data/db/schema_version.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

/// Deterministik zaman kaynağı (rules/06 §7).
///
/// `DateTime.now()` domain/test sınırlarına **parametre olarak** geçirilir.
class FakeClock {
  DateTime current;

  FakeClock(this.current);

  DateTime now() => current;

  /// `DateTime Function()` bekleyen API'lere geçirilecek referans.
  DateTime Function() get fn => now;

  void advance(Duration by) => current = current.add(by);
}

/// Testler için sabit bir başlangıç anı.
DateTime get testEpochUtc => DateTime.utc(2026, 8, 14, 1, 23, 45, 678);

/// In-memory veritabanı — her test temiz şemayla başlar.
CanteenDatabase memoryDatabase({
  DateTime Function()? clock,
  MigrationPlan? migrationPlan,
  int? schemaVersion,
  bool applySeed = true,
  int supportedSchemaVersion = kSupportedSchemaVersion,
}) {
  return CanteenDatabase(
    openDatabaseInMemory(supportedSchemaVersion: supportedSchemaVersion),
    clock: clock ?? () => testEpochUtc,
    migrationPlan: migrationPlan,
    schemaVersion: schemaVersion ?? supportedSchemaVersion,
    applySeed: applySeed,
  );
}

/// Geçici dizinde dosya tabanlı veritabanı — WAL ve migration testleri için.
CanteenDatabase fileDatabase(
  String path, {
  DateTime Function()? clock,
  MigrationPlan? migrationPlan,
  int? schemaVersion,
  bool applySeed = true,
  int supportedSchemaVersion = kSupportedSchemaVersion,
}) {
  return CanteenDatabase(
    openDatabaseFile(path, supportedSchemaVersion: supportedSchemaVersion),
    clock: clock ?? () => testEpochUtc,
    migrationPlan: migrationPlan,
    schemaVersion: schemaVersion ?? supportedSchemaVersion,
    applySeed: applySeed,
  );
}

/// Geçici veri dizini + [AppPaths].
class TempAppPaths {
  final Directory dir;
  final AppPaths paths;

  TempAppPaths._(this.dir, this.paths);

  static Future<TempAppPaths> create() async {
    final dir = Directory.systemTemp.createTempSync('canteen_db_');
    final paths = AppPaths(rootPath: dir.path);
    await paths.ensureDirectories();
    return TempAppPaths._(dir, paths);
  }

  void dispose() {
    deleteDirectoryWithRetry(dir);
  }
}

void deleteDirectoryWithRetry(
  Directory directory, {
  int maxAttempts = 5,
  Duration retryDelay = const Duration(milliseconds: 100),
  void Function()? deleteAction,
  bool windowsFileLockRetryEnabled = Platform.isWindows,
}) {
  if (!directory.existsSync()) return;

  var attempt = 0;
  while (true) {
    try {
      (deleteAction ?? () => directory.deleteSync(recursive: true)).call();
      return;
    } on PathAccessException catch (e) {
      attempt += 1;
      final isWindowsFileInUse =
          windowsFileLockRetryEnabled && e.osError?.errorCode == 32;
      if (!isWindowsFileInUse || attempt >= maxAttempts) rethrow;
      sleep(retryDelay);
    }
  }
}

/// Bir tablonun kolon adlarını ve SQL tiplerini döner.
Future<Map<String, String>> tableColumns(
  CanteenDatabase db,
  String table,
) async {
  // Tablo adları testin kendi sabitleridir; kullanıcı girdisi değildir.
  final rows = await db.customSelect('PRAGMA table_info($table);').get();
  return {
    for (final row in rows)
      row.data['name'] as String: (row.data['type'] as String).toUpperCase(),
  };
}

/// `sqlite_master` üzerindeki tablo adları (dahili `sqlite_*` hariç).
Future<List<String>> tableNames(CanteenDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'table' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name;",
      )
      .get();
  return rows.map((r) => r.data['name'] as String).toList();
}

/// Index adları.
Future<List<String>> indexNames(CanteenDatabase db) async {
  final rows = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type = 'index' "
        "AND name NOT LIKE 'sqlite_%' ORDER BY name;",
      )
      .get();
  return rows.map((r) => r.data['name'] as String).toList();
}

/// Bir sorgunun sorgu planı — index kullanımını **kanıtlamak** için.
Future<String> queryPlan(CanteenDatabase db, String sql) async {
  final rows = await db.customSelect('EXPLAIN QUERY PLAN $sql').get();
  return rows.map((r) => r.data['detail']).join(' | ');
}

/// Test verisi için minimum kullanıcı — FK gereksinimlerini karşılar.
Future<int> insertTestUser(CanteenDatabase db, {String username = 'kasa'}) {
  return db
      .into(db.users)
      .insert(
        UsersCompanion.insert(
          username: username,
          // Hash/salt yer tutucudur; gerçek hash'leme Faz 3'tür.
          passwordHash: 'x' * 64,
          passwordSalt: 'y' * 32,
          displayName: 'Test Kullanıcı',
          createdAt: testEpochUtc,
          updatedAt: testEpochUtc,
        ),
      );
}

/// Test verisi için ürün — `Genel` kategorisine bağlanır.
Future<int> insertTestProduct(
  CanteenDatabase db, {
  String name = 'Test Ürün',
  int salePriceMinor = 12000,
  int purchasePriceMinor = 8000,
  int? categoryId,
}) async {
  final category =
      categoryId ?? (await (db.select(db.categories)..limit(1)).getSingle()).id;

  return db
      .into(db.products)
      .insert(
        ProductsCompanion.insert(
          name: name,
          categoryId: category,
          salePriceMinor: salePriceMinor,
          purchasePriceMinor: Value(purchasePriceMinor),
          createdAt: testEpochUtc,
          updatedAt: testEpochUtc,
        ),
      );
}

/// Geçici dosya yolu üretir.
String tempDbPath(Directory dir, [String name = 'canteen.sqlite']) =>
    p.join(dir.path, name);
