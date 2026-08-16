/// SQLite yapılandırma testleri — **REQ-DB-001 · REQ-DATA-002**
///
/// docs/05 §1 · rules/03 §1.
///
/// WAL yalnızca **dosya tabanlı** veritabanında doğrulanabilir: in-memory
/// veritabanları `journal_mode = memory` kullanır. Bu yüzden yapılandırma
/// testleri gerçek bir dosya üzerinde çalışır.
///
/// Dosya üç katmanı ayrı ayrı doğrular:
///
/// 1. `openDatabaseFile()` — yardımcı factory
/// 2. `DatabaseBootstrap.open()` — **gerçek üretim yolu** (GAP-2-016)
/// 3. `buildDiagnosticSetup()` / `RawSqliteFile` — salt-okuma tanı bağlantısı
///    (GAP-2-015)
library;

import 'dart:io';

import 'package:canteen/core/errors/app_exception.dart';
import 'package:canteen/data/db/canteen_database.dart';
import 'package:canteen/data/db/database_bootstrap.dart';
import 'package:canteen/data/db/database_opener.dart';
import 'package:canteen/data/db/migrations/migration_plan.dart';
import 'package:canteen/data/db/raw_sqlite_file.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/test_database.dart';

/// Drift açılışta bir şema kullanıcısı ister; tanı bağlantısı için etkisizdir.
class _InertExecutorUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

/// Verilen [setup] ile ham bir bağlantı açıp tek bir PRAGMA okur.
///
/// [setup] `null` bırakılırsa **yapılandırılmamış** bağlantı ölçülür — GAP-2-015
/// öncesi davranışın referansı budur.
Future<Object?> _rawPragma(
  String dbPath,
  String name, {
  DatabaseSetup? setup,
}) async {
  final executor = NativeDatabase(
    File(dbPath),
    enableMigrations: false,
    setup: setup,
  );
  try {
    await executor.ensureOpen(_InertExecutorUser());
    final rows = await executor.runSelect('PRAGMA $name;', const []);
    return rows.isEmpty ? null : rows.first.values.first;
  } finally {
    await executor.close();
  }
}

void main() {
  group('openDatabaseFile — yardımcı factory', () {
    late Directory dir;
    late CanteenDatabase db;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('canteen_cfg_');
      db = fileDatabase(tempDbPath(dir));
      await db.customStatement('SELECT 1;'); // bağlantıyı aç
    });

    tearDown(() async {
      await db.close();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    Future<Object?> pragma(String name) async {
      final row = await db.customSelect('PRAGMA $name;').getSingle();
      return row.data.values.first;
    }

    test('journal_mode = WAL — elektrik kesintisi dayanıklılığı', () async {
      expect(await pragma('journal_mode'), SqlitePragmas.journalModeWal);
    });

    test('synchronous = FULL — satış kaybı kabul edilemez', () async {
      expect(await pragma('synchronous'), SqlitePragmas.synchronousFull);
    });

    test('foreign_keys = ON — referans bütünlüğü', () async {
      expect(await pragma('foreign_keys'), 1);
    });

    test('busy_timeout = 5000 ms', () async {
      expect(await pragma('busy_timeout'), SqlitePragmas.busyTimeoutMs);
    });

    test('temp_store = MEMORY — rapor aggregation hızı', () async {
      expect(
        await pragma('temp_store'),
        SqlitePragmas.tempStoreMemory,
        reason: 'rules/03 §1 — temp_store MEMORY olmalıdır.',
      );
    });

    test('WAL gerçekten aktif — -wal yan dosyası oluşur', () async {
      await insertTestUser(db);
      final wal = File('${tempDbPath(dir)}-wal');
      expect(
        wal.existsSync(),
        isTrue,
        reason: 'WAL modunda yazma sonrası -wal dosyası bulunmalıdır.',
      );
    });

    test('yeniden açılışta yapılandırma korunur', () async {
      await db.close();
      db = fileDatabase(tempDbPath(dir));
      await db.customStatement('SELECT 1;');

      expect(await pragma('journal_mode'), SqlitePragmas.journalModeWal);
      expect(await pragma('foreign_keys'), 1);
      expect(await pragma('temp_store'), SqlitePragmas.tempStoreMemory);
    });
  });

  // ---------------------------------------------------------------------------
  // GAP-2-016 — gerçek üretim yolu
  // ---------------------------------------------------------------------------

  /// Yukarıdaki grup yalnızca `fileDatabase()` **yardımcısını** ölçer.
  /// Üretimde bağlantı `DatabaseBootstrap.open()` üzerinden kurulur; asıl
  /// doğrulanması gereken odur.
  group('DatabaseBootstrap.open() — üretim bağlantısı (GAP-2-016)', () {
    late TempAppPaths temp;

    setUp(() async => temp = await TempAppPaths.create());
    tearDown(() => temp.dispose());

    Future<Object?> pragmaOf(CanteenDatabase db, String name) async {
      final row = await db.customSelect('PRAGMA $name;').getSingle();
      return row.data.values.first;
    }

    test('ilk açılışta (created) beş PRAGMA da uygulanır', () async {
      final result = await DatabaseBootstrap(paths: temp.paths).open();
      addTearDown(result.database.close);
      final db = result.database;

      expect(result.kind, DatabaseOpenKind.created);
      expect(
        await pragmaOf(db, 'journal_mode'),
        SqlitePragmas.journalModeWal,
        reason: 'REQ-DB-001: elektrik kesintisi dayanıklılığı.',
      );
      expect(
        await pragmaOf(db, 'synchronous'),
        SqlitePragmas.synchronousFull,
        reason: 'REQ-DB-001: satış kaybı kabul edilemez.',
      );
      expect(await pragmaOf(db, 'foreign_keys'), 1);
      expect(await pragmaOf(db, 'busy_timeout'), SqlitePragmas.busyTimeoutMs);
      expect(await pragmaOf(db, 'temp_store'), SqlitePragmas.tempStoreMemory);
    });

    test('ikinci açılışta (opened) beş PRAGMA da uygulanır', () async {
      final first = await DatabaseBootstrap(paths: temp.paths).open();
      await first.database.close();

      final result = await DatabaseBootstrap(paths: temp.paths).open();
      addTearDown(result.database.close);
      final db = result.database;

      expect(result.kind, DatabaseOpenKind.opened);
      expect(await pragmaOf(db, 'journal_mode'), SqlitePragmas.journalModeWal);
      expect(await pragmaOf(db, 'synchronous'), SqlitePragmas.synchronousFull);
      expect(await pragmaOf(db, 'foreign_keys'), 1);
      expect(await pragmaOf(db, 'busy_timeout'), SqlitePragmas.busyTimeoutMs);
      expect(await pragmaOf(db, 'temp_store'), SqlitePragmas.tempStoreMemory);
    });

    test('migration sonrası (migrated) beş PRAGMA da uygulanır', () async {
      final first = await DatabaseBootstrap(paths: temp.paths).open();
      await first.database.close();

      // v1 → v2: açılış `migrated` yolundan geçer.
      final plan = MigrationPlan([
        MigrationStep.sql(
          from: 1,
          to: 2,
          statements: const [
            'ALTER TABLE products ADD COLUMN shelf_note TEXT NULL;',
          ],
        ),
      ]);

      final result = await DatabaseBootstrap(
        paths: temp.paths,
        migrationPlan: plan,
        supportedSchemaVersion: 2,
      ).open();
      addTearDown(result.database.close);
      final db = result.database;

      expect(
        result.kind,
        DatabaseOpenKind.migrated,
        reason: 'Test yanlış yolu ölçüyorsa anlamsızdır.',
      );
      expect(await pragmaOf(db, 'journal_mode'), SqlitePragmas.journalModeWal);
      expect(await pragmaOf(db, 'synchronous'), SqlitePragmas.synchronousFull);
      expect(await pragmaOf(db, 'foreign_keys'), 1);
      expect(await pragmaOf(db, 'busy_timeout'), SqlitePragmas.busyTimeoutMs);
      expect(await pragmaOf(db, 'temp_store'), SqlitePragmas.tempStoreMemory);
    });

    test('üretim veritabanı dosyası gerçekten WAL modunda', () async {
      final result = await DatabaseBootstrap(paths: temp.paths).open();
      addTearDown(result.database.close);

      await insertTestUser(result.database);

      expect(
        File('${temp.paths.databaseFile}-wal').existsSync(),
        isTrue,
        reason:
            'WAL yalnızca ayar değil, dosya davranışı olarak da aktif '
            'olmalıdır.',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // GAP-2-015 — salt-okuma tanı bağlantısı
  // ---------------------------------------------------------------------------

  group('buildDiagnosticSetup — tanı bağlantısı (GAP-2-015)', () {
    late TempAppPaths temp;

    setUp(() async => temp = await TempAppPaths.create());
    tearDown(() => temp.dispose());

    /// Tanı sorgularının çalışabileceği gerçek bir veritabanı bırakır.
    Future<void> seedDatabaseFile() async {
      final result = await DatabaseBootstrap(paths: temp.paths).open();
      await result.database.close();
    }

    test('yapılandırılmamış bağlantı KÖTÜ değerlerle açılır — regresyon '
        'referansı', () async {
      await seedDatabaseFile();
      final path = temp.paths.databaseFile;

      expect(
        await _rawPragma(path, 'busy_timeout'),
        0,
        reason: 'setup verilmezse SQLite varsayılanı 0\'dır — GAP-2-015 buydu.',
      );
      expect(await _rawPragma(path, 'temp_store'), 0);
    });

    test('buildDiagnosticSetup ortak PRAGMA\'ların üçünü de uygular', () async {
      await seedDatabaseFile();
      final path = temp.paths.databaseFile;
      final setup = buildDiagnosticSetup();

      expect(
        await _rawPragma(path, 'busy_timeout', setup: setup),
        SqlitePragmas.busyTimeoutMs,
        reason: 'Kilit tutulurken anında SQLITE_BUSY ile düşmemeli.',
      );
      expect(
        await _rawPragma(path, 'temp_store', setup: setup),
        SqlitePragmas.tempStoreMemory,
        reason: 'integrity_check geçici dosyaları diske taşmamalı.',
      );
      expect(
        await _rawPragma(path, 'synchronous', setup: setup),
        SqlitePragmas.synchronousFull,
        reason:
            'Bu bağlantı WAL checkpoint\'i ile ana dosyaya YAZABİLİR; '
            'docs/05 §1 FULL gerektirir. WAL dosyasında varsayılan NORMAL(1) '
            'olduğu için açıkça yazılmazsa sağlanmaz.',
      );
    });

    test('buildDiagnosticSetup journal_mode\'a DOKUNMAZ', () async {
      // Taze, WAL olmayan bir dosya: tanı bağlantısı onu WAL\'a çevirmemeli.
      final plain = File('${temp.paths.databaseFile}.plain');
      final seed = NativeDatabase(plain, enableMigrations: false);
      await seed.ensureOpen(_InertExecutorUser());
      await seed.runCustom('CREATE TABLE t (id INTEGER);', const []);
      await seed.close();

      final before = await _rawPragma(plain.path, 'journal_mode');
      expect(before, isNot(SqlitePragmas.journalModeWal));

      await _rawPragma(
        plain.path,
        'user_version',
        setup: buildDiagnosticSetup(),
      );

      expect(
        await _rawPragma(plain.path, 'journal_mode'),
        before,
        reason:
            'journal_mode dosyaya YAZILIR; tanı bağlantısı onu '
            'değiştiremez.',
      );
      expect(File('${plain.path}-wal').existsSync(), isFalse);
      expect(File('${plain.path}-shm').existsSync(), isFalse);
    });

    test(
      'sürüm kapısı UYGULANMAZ — readUserVersion 99 döner, fırlatmaz',
      () async {
        final first = await DatabaseBootstrap(paths: temp.paths).open();
        await first.database.customStatement('PRAGMA user_version = 99;');
        await first.database.close();

        // REQ-MIG-005 tespiti buna dayanır: saptamak için OKUYABİLMELİ.
        expect(
          await RawSqliteFile(temp.paths.databaseFile).readUserVersion(),
          99,
          reason: 'buildDatabaseSetup bağlansaydı burada exception fırlardı.',
        );

        // Kapı, üretim yolunda (bootstrap) hâlâ çalışıyor olmalı.
        await expectLater(
          DatabaseBootstrap(paths: temp.paths).open(),
          throwsA(isA<SchemaVersionException>()),
        );
      },
    );

    test('snapshot doğrulaması snapshot dosyasını DEĞİŞTİRMEZ', () async {
      final bootstrap = DatabaseBootstrap(paths: temp.paths);
      final result = await bootstrap.open();
      addTearDown(result.database.close);
      await insertTestUser(result.database);

      final snapshot = await bootstrap.coordinator.createSnapshot(
        result.database,
        fromVersion: 1,
      );
      final bytesBefore = snapshot.readAsBytesSync();
      final journalBefore = await _rawPragma(snapshot.path, 'journal_mode');
      // mtime taşıyıcı bir alandır: pruneSnapshots ve latestSnapshot
      // snapshot'ları `statSync().modified`'a göre SIRALAR. Doğrulama mtime'ı
      // değiştirirse kurtarma adayı sırası bozulur.
      final modifiedBefore = snapshot.statSync().modified;

      // Üretimdeki doğrulama yolu — RawSqliteFile.isIntegral() kullanır.
      expect(await bootstrap.coordinator.verifySnapshot(snapshot), isTrue);

      expect(
        File('${snapshot.path}-wal').existsSync(),
        isFalse,
        reason: 'Doğrulama, doğruladığı snapshot\'ın yanına -wal bırakamaz.',
      );
      expect(File('${snapshot.path}-shm').existsSync(), isFalse);
      expect(await _rawPragma(snapshot.path, 'journal_mode'), journalBefore);
      expect(
        snapshot.readAsBytesSync(),
        orderedEquals(bytesBefore),
        reason: 'Snapshot içeriği bit düzeyinde AYNI kalmalı.',
      );
      expect(snapshot.statSync().modified, modifiedBefore);
    });
  });

  // ---------------------------------------------------------------------------
  // GAP-2-015 — wiring'in DAVRANIŞSAL kanıtı
  // ---------------------------------------------------------------------------

  /// Yukarıdaki grup `buildDiagnosticSetup()`'ı ölçer; bu grup onun
  /// `RawSqliteFile`'a **gerçekten bağlandığını** kanıtlar. Kaynak metnine
  /// bakan bir guard bunu kanıtlayamaz: çağrı yorum içinde de durabilir,
  /// biçimlendirme değişince de kırılır.
  group('RawSqliteFile busy_timeout — uçtan uca kilit çekişmesi', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('canteen_busy_'));
    tearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });

    /// Üzerinde ÖZEL kilit tutulan, rollback-journal bir veritabanı bırakır.
    ///
    /// WAL **kullanılamaz**: WAL'da okurlar yazarı beklemez, dolayısıyla
    /// çekişme hiç oluşmazdı.
    Future<QueryExecutor> lockedDatabase(String path) async {
      final holder = NativeDatabase(File(path), enableMigrations: false);
      await holder.ensureOpen(_InertExecutorUser());
      await holder.runCustom('PRAGMA journal_mode = DELETE;', const []);
      await holder.runCustom('CREATE TABLE t (id INTEGER);', const []);
      await holder.runCustom('BEGIN EXCLUSIVE;', const []);
      return holder;
    }

    test(
      'kilit tutulurken ANINDA düşmez — beklemeye geçer',
      () async {
        final path = p.join(dir.path, 'locked.sqlite');
        final holder = await lockedDatabase(path);

        // `isIntegral()` gerçekten bağlantı açar; `readUserVersion()` artık
        // başlıktan okuduğu için kilide hiç takılmaz (aşağıdaki ayrı test).
        final sw = Stopwatch()..start();
        await RawSqliteFile(path).isIntegral();
        sw.stop();

        await holder.runCustom('ROLLBACK;', const []);
        await holder.close();

        expect(
          sw.elapsedMilliseconds,
          greaterThan(1000),
          reason:
              'GAP-2-015: busy_timeout bağlanmamışsa 0 ms\'de SQLITE_BUSY ile '
              'düşer ve kullanıcıya asılsız "veritabanı bozuk" hatası '
              'gösterilir. Ölçülen: ${sw.elapsedMilliseconds} ms.',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'yapılandırmasız bağlantı AYNI kilitte anında düşer — kontrast',
      () async {
        final path = p.join(dir.path, 'contrast.sqlite');
        final holder = await lockedDatabase(path);

        final sw = Stopwatch()..start();
        try {
          // setup: null → GAP-2-015 öncesi davranış.
          await _rawPragma(path, 'user_version');
        } on Object {
          // Beklenen: beklemeden SQLITE_BUSY.
        }
        sw.stop();

        await holder.runCustom('ROLLBACK;', const []);
        await holder.close();

        expect(
          sw.elapsedMilliseconds,
          // Mutlak bir hız iddiası DEĞİL: kanıtlanan şey 5 sn'lik busy
          // timeout'un DEVREYE GİRMEDİĞİdir. Yüklü makinede saniyelik
          // duraklamalar olabildiği için eşik timeout'un yarısıdır.
          lessThan(SqlitePragmas.busyTimeoutMs ~/ 2),
          reason:
              'Yapılandırmasız bağlantı beklemeden düşer — düzeltmenin '
              'kapattığı davranış budur. Ölçülen: ${sw.elapsedMilliseconds} ms.',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  });

  // ---------------------------------------------------------------------------
  // rules/03 §3 kural 9 — desteklenmeyen şema AÇILMADAN reddedilir
  // ---------------------------------------------------------------------------

  group('readUserVersion — veritabanını AÇMADAN okur', () {
    late TempAppPaths temp;

    setUp(() async => temp = await TempAppPaths.create());
    tearDown(() => temp.dispose());

    test('daha yeni şemalı veritabanı OKUNURKEN DEĞİŞTİRİLMEZ', () async {
      final first = await DatabaseBootstrap(paths: temp.paths).open();
      await first.database.customStatement('PRAGMA user_version = 99;');
      await first.database.close();

      final file = File(temp.paths.databaseFile);
      final bytesBefore = file.readAsBytesSync();
      final modifiedBefore = file.statSync().modified;

      expect(
        await RawSqliteFile(temp.paths.databaseFile).readUserVersion(),
        99,
      );

      expect(
        file.readAsBytesSync(),
        orderedEquals(bytesBefore),
        reason:
            'rules/03 §3 kural 9: desteklenmeyen şema versiyonu REDDEDİLİR. '
            'Reddetmeden önce dosyaya dokunulamaz.',
      );
      expect(file.statSync().modified, modifiedBefore);
      expect(File('${temp.paths.databaseFile}-wal').existsSync(), isFalse);
      expect(File('${temp.paths.databaseFile}-shm').existsSync(), isFalse);
    });

    test(
      'kilitli veritabanında bile beklemeden döner — bağlantı açmıyor',
      () async {
        final dir = Directory.systemTemp.createTempSync('canteen_hdr_');
        addTearDown(() => dir.deleteSync(recursive: true));
        final path = p.join(dir.path, 'locked.sqlite');

        final holder = NativeDatabase(File(path), enableMigrations: false);
        await holder.ensureOpen(_InertExecutorUser());
        await holder.runCustom('PRAGMA journal_mode = DELETE;', const []);
        await holder.runCustom('PRAGMA user_version = 3;', const []);
        await holder.runCustom('CREATE TABLE t (id INTEGER);', const []);
        await holder.runCustom('BEGIN EXCLUSIVE;', const []);

        final sw = Stopwatch()..start();
        final version = await RawSqliteFile(path).readUserVersion();
        sw.stop();

        await holder.runCustom('ROLLBACK;', const []);
        await holder.close();

        expect(version, 3);
        expect(
          sw.elapsedMilliseconds,
          // Mutlak bir hız iddiası DEĞİL: kanıtlanan şey 5 sn'lik busy
          // timeout'un DEVREYE GİRMEDİĞİdir. Yüklü makinede saniyelik
          // duraklamalar olabildiği için eşik timeout'un yarısıdır.
          lessThan(SqlitePragmas.busyTimeoutMs ~/ 2),
          reason: 'Başlıktan okuma kilitten etkilenmez.',
        );
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'WAL\'da checkpoint\'lenmemiş çerçeve varsa SQLite\'a düşer',
      () async {
        // Başlık bu durumda BAYATTIR (ölçüldü: başlık 0, gerçek 7). Yanlış `0`
        // "yeni kurulum" sayılıp mevcut veritabanının üzerine şema kurdururdu.
        final result = await DatabaseBootstrap(paths: temp.paths).open();
        final db = result.database;
        await db.customStatement('PRAGMA wal_autocheckpoint = 0;');
        await db.customStatement('PRAGMA user_version = 7;');
        await insertTestUser(db);

        final wal = File('${temp.paths.databaseFile}-wal');
        expect(
          wal.existsSync() && wal.lengthSync() > 0,
          isTrue,
          reason: 'Senaryo kurulamadıysa test anlamsızdır.',
        );

        expect(
          await RawSqliteFile(temp.paths.databaseFile).readUserVersion(),
          7,
          reason: 'Bayat başlık değil, GERÇEK sürüm dönmelidir.',
        );

        await db.close();
      },
    );

    test('bozuk dosya DatabaseException — SQLite açılmadan', () async {
      final dir = Directory.systemTemp.createTempSync('canteen_bad_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bad = File(p.join(dir.path, 'garbage.sqlite'))
        ..writeAsBytesSync(List<int>.filled(200, 0x41));

      await expectLater(
        RawSqliteFile(bad.path).readUserVersion(),
        throwsA(isA<DatabaseException>()),
      );
    });

    test('bozuk dosyada isIntegral FIRLATMAZ, false döner', () async {
      // Sözleşme: "bozuk mu?" sorusunun yanıtı true/false olmalıdır. Kapanış
      // hatası uçuştaki exception'ın yerine geçseydi burada fırlardı ve
      // kurtarma akışı çökerdi.
      final dir = Directory.systemTemp.createTempSync('canteen_int_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final bad = File(p.join(dir.path, 'garbage.sqlite'))
        ..writeAsBytesSync(List<int>.filled(4096, 0x41));

      expect(await RawSqliteFile(bad.path).isIntegral(), isFalse);
    });

    test('boş dosya 0 · olmayan dosya 0', () async {
      final dir = Directory.systemTemp.createTempSync('canteen_empty_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final empty = File(p.join(dir.path, 'empty.sqlite'))..createSync();

      expect(await RawSqliteFile(empty.path).readUserVersion(), 0);
      expect(
        await RawSqliteFile(p.join(dir.path, 'yok.sqlite')).readUserVersion(),
        0,
      );
    });
  });
}
