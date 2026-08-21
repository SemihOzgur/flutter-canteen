/// Migration snapshot ve kurtarma testleri.
///
/// REQ-MIG-002 (doğrulanmış snapshot) · REQ-MIG-003 (geri alma) ·
/// REQ-MIG-006 (yarım migration kurtarması)
///
/// docs/06 §3.
///
/// **Kapsam notu:** Kullanıcıya "geri yükleyelim mi?" diye soran diyalog Faz 3+
/// kapsamındadır (onaylanmış karar). Buradaki testler **mekanizmayı** doğrular:
/// tespit, snapshot, doğrulama, geri yükleme ve yarım şemayla açılmama.
/// ## Kapsanan uç durumlar (docs/26 · Faz 11 izlenebilirliği)
///
/// - **EC-SYS-004** — DB dosyası bozuk (`integrity_check` fail)
/// - **EC-SYS-005** — migration yarım kalmış
///
library;

import 'dart:io';

import 'package:canteen/core/errors/app_exception.dart';
import 'package:canteen/data/db/app_setting_keys.dart';
import 'package:canteen/data/db/database_bootstrap.dart';
import 'package:canteen/data/db/migrations/migration_coordinator.dart';
import 'package:canteen/data/db/migrations/migration_plan.dart';
import 'package:canteen/data/db/raw_sqlite_file.dart';
import 'package:canteen/data/db/schema_version.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/test_database.dart';

void main() {
  late TempAppPaths temp;
  late FakeClock clock;

  setUp(() async {
    temp = await TempAppPaths.create();
    clock = FakeClock(testEpochUtc);
  });

  tearDown(() => temp.dispose());

  MigrationCoordinator makeCoordinator() => MigrationCoordinator(
    databaseFilePath: temp.paths.databaseFile,
    autoBackupsDirPath: temp.paths.autoBackupsDir,
    clock: clock.fn,
  );

  /// v1 veritabanı + örnek veri.
  Future<int> seedV1() async {
    final db = fileDatabase(temp.paths.databaseFile, clock: clock.fn);
    await db.customStatement('SELECT 1;');
    await insertTestUser(db);
    await insertTestProduct(db, name: 'Kola');
    await insertTestProduct(db, name: 'Ayran');
    final count = (await db.select(db.products).get()).length;
    await db.close();
    return count;
  }

  group('REQ-MIG-002 — pre-migration snapshot', () {
    test('VACUUM INTO ile snapshot alınır ve doğrulanır', () async {
      await seedV1();

      final db = fileDatabase(temp.paths.databaseFile, clock: clock.fn);
      await db.customStatement('SELECT 1;');
      final coordinator = makeCoordinator();

      final snapshot = await coordinator.createSnapshot(db, fromVersion: 1);
      await db.close();

      expect(snapshot.existsSync(), isTrue);
      expect(snapshot.lengthSync(), greaterThan(0));
      expect(
        p.basename(snapshot.path),
        startsWith('premigration_v1_'),
        reason: 'docs/06 §3 adım 2 adlandırması',
      );
      expect(
        p.dirname(snapshot.path),
        temp.paths.autoBackupsDir,
        reason: 'backups/auto/ altına yazılmalı',
      );
      expect(await coordinator.verifySnapshot(snapshot), isTrue);
    });

    test('snapshot verinin TAM kopyasıdır', () async {
      final expected = await seedV1();

      final db = fileDatabase(temp.paths.databaseFile, clock: clock.fn);
      await db.customStatement('SELECT 1;');
      final snapshot = await makeCoordinator().createSnapshot(
        db,
        fromVersion: 1,
      );
      await db.close();

      final copy = fileDatabase(snapshot.path, clock: clock.fn);
      await copy.customStatement('SELECT 1;');
      final products = await copy.select(copy.products).get();
      await copy.close();

      expect(products.length, expected);
      expect(products.map((p) => p.name), containsAll(['Kola', 'Ayran']));
    });

    test('boş / bozuk snapshot doğrulamayı GEÇEMEZ', () async {
      final bogus = File(p.join(temp.paths.autoBackupsDir, 'bos.sqlite'))
        ..createSync(recursive: true);

      expect(await makeCoordinator().verifySnapshot(bogus), isFalse);

      bogus.writeAsStringSync('bu bir sqlite dosyası değil');
      expect(await makeCoordinator().verifySnapshot(bogus), isFalse);
    });

    test('var olmayan snapshot doğrulamayı GEÇEMEZ', () async {
      final missing = File(p.join(temp.paths.autoBackupsDir, 'yok.sqlite'));
      expect(await makeCoordinator().verifySnapshot(missing), isFalse);
    });

    test('yalnızca son 5 snapshot tutulur — docs/06 §4', () async {
      await seedV1();
      final coordinator = makeCoordinator();

      for (var i = 0; i < 8; i++) {
        final db = fileDatabase(temp.paths.databaseFile, clock: clock.fn);
        await db.customStatement('SELECT 1;');
        await coordinator.createSnapshot(db, fromVersion: 1);
        await db.close();
        clock.advance(const Duration(seconds: 5));
      }

      await coordinator.pruneSnapshots();

      final remaining = Directory(temp.paths.autoBackupsDir)
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).startsWith('premigration_'))
          .length;

      expect(remaining, 5);
    });
  });

  group('REQ-MIG-006 — yarım kalmış migration', () {
    Future<void> writeStaleFlag() async {
      final db = fileDatabase(temp.paths.databaseFile, clock: clock.fn);
      await db.customStatement('SELECT 1;');
      await makeCoordinator().writeFlag(
        db,
        MigrationFlag(from: 1, to: 2, startedAt: clock.now()),
      );
      await db.close();
    }

    test('bayrak duruyorsa uygulama AÇILMAZ', () async {
      await seedV1();
      await writeStaleFlag();

      await expectLater(
        DatabaseBootstrap(paths: temp.paths, clock: clock.fn).open(),
        throwsA(isA<MigrationRecoveryRequiredException>()),
      );
    });

    test('hata, kurtarma için gereken bilgiyi taşır', () async {
      await seedV1();

      final db = fileDatabase(temp.paths.databaseFile, clock: clock.fn);
      await db.customStatement('SELECT 1;');
      final snapshot = await makeCoordinator().createSnapshot(
        db,
        fromVersion: 1,
      );
      await makeCoordinator().writeFlag(
        db,
        MigrationFlag(from: 1, to: 2, startedAt: clock.now()),
      );
      await db.close();

      try {
        await DatabaseBootstrap(paths: temp.paths, clock: clock.fn).open();
        fail('MigrationRecoveryRequiredException bekleniyordu');
      } on MigrationRecoveryRequiredException catch (e) {
        expect(e.fromVersion, 1);
        expect(e.toVersion, 2);
        expect(e.snapshotPath, snapshot.path);
        expect(e.userMessage, contains('yarım'));
        // REQ-SEC-007 — teknik detay kullanıcı mesajında değil.
        expect(e.userMessage, isNot(contains('migration_in_progress')));
        expect(e.technicalDetail, contains('migration_in_progress'));
      }
    });

    test('bayrak temizlenince normal açılır', () async {
      await seedV1();
      await writeStaleFlag();

      final db = fileDatabase(temp.paths.databaseFile, clock: clock.fn);
      await db.customStatement('SELECT 1;');
      await makeCoordinator().clearFlag(db);
      await db.close();

      final result = await DatabaseBootstrap(
        paths: temp.paths,
        clock: clock.fn,
      ).open();
      addTearDown(result.database.close);

      expect(result.kind, DatabaseOpenKind.opened);
    });

    test('bozuk bayrak JSON\'ı uygulamayı çökertmez', () async {
      await seedV1();

      final db = fileDatabase(temp.paths.databaseFile, clock: clock.fn);
      await db.customStatement('SELECT 1;');
      await db.customStatement(
        'INSERT INTO app_settings (key, value, updated_at) VALUES (?, ?, ?);',
        [
          AppSettingKeys.migrationInProgress,
          'bu-json-degil{{{',
          clock.now().millisecondsSinceEpoch,
        ],
      );
      await db.close();

      // Bozuk bayrak → parse null → kurtarma tetiklenmez, açılış sürer.
      final result = await DatabaseBootstrap(
        paths: temp.paths,
        clock: clock.fn,
      ).open();
      addTearDown(result.database.close);
      expect(result.kind, DatabaseOpenKind.opened);
    });
  });

  group('REQ-MIG-003 — snapshot\'tan geri yükleme', () {
    test('mevcut veritabanı SİLİNMEZ, .corrupt_ olarak taşınır', () async {
      await seedV1();

      final db = fileDatabase(temp.paths.databaseFile, clock: clock.fn);
      await db.customStatement('SELECT 1;');
      final snapshot = await makeCoordinator().createSnapshot(
        db,
        fromVersion: 1,
      );
      // Snapshot sonrası veri değişir — geri yükleme bunu geri almalı.
      await insertTestProduct(db, name: 'SonradanEklenen');
      await db.close();

      clock.advance(const Duration(minutes: 1));
      await makeCoordinator().restoreFromSnapshot(snapshot);

      // Eski dosya korunmuş olmalı.
      final corrupt = Directory(temp.paths.dataDir)
          .listSync()
          .whereType<File>()
          .where((f) => p.basename(f.path).contains('.corrupt_'))
          .toList();
      expect(
        corrupt,
        hasLength(1),
        reason: 'docs/06 §3: mevcut veritabanı silinmez, TAŞINIR.',
      );

      // Geri yüklenen veri snapshot anındaki hâlde olmalı.
      final restored = fileDatabase(temp.paths.databaseFile, clock: clock.fn);
      await restored.customStatement('SELECT 1;');
      final names = (await restored.select(restored.products).get())
          .map((p) => p.name)
          .toList();
      await restored.close();

      expect(names, containsAll(['Kola', 'Ayran']));
      expect(names, isNot(contains('SonradanEklenen')));
    });

    test('doğrulanamayan snapshot geri YÜKLENMEZ', () async {
      await seedV1();
      final bogus = File(p.join(temp.paths.autoBackupsDir, 'bozuk.sqlite'))
        ..writeAsStringSync('bozuk');

      await expectLater(
        makeCoordinator().restoreFromSnapshot(bogus),
        throwsA(isA<MigrationException>()),
      );

      // Mevcut veritabanı dokunulmamış olmalı.
      expect(File(temp.paths.databaseFile).existsSync(), isTrue);
      expect(await RawSqliteFile(temp.paths.databaseFile).isIntegral(), isTrue);
    });

    test('geri yükleme sonrası WAL yan dosyaları temizlenir', () async {
      await seedV1();

      final db = fileDatabase(temp.paths.databaseFile, clock: clock.fn);
      await db.customStatement('SELECT 1;');
      final snapshot = await makeCoordinator().createSnapshot(
        db,
        fromVersion: 1,
      );
      await db.close();

      clock.advance(const Duration(minutes: 1));
      await makeCoordinator().restoreFromSnapshot(snapshot);

      expect(File('${temp.paths.databaseFile}-wal').existsSync(), isFalse);
      expect(File('${temp.paths.databaseFile}-shm').existsSync(), isFalse);
    });
  });

  group('tam migration protokolü — docs/06 §3', () {
    test('snapshot → migration → bayrak temizliği sırayla işler', () async {
      final before = await seedV1();

      final plan = MigrationPlan([
        // Sentetik adım MEVCUT versiyonun üstüne kurulur; sabit `1 → 2`
        // yazılsaydı şema yükseltilince bu test migration yolunu değil,
        // normal açılışı ölçmeye başlardı.
        MigrationStep.sql(
          from: kSupportedSchemaVersion,
          to: kSupportedSchemaVersion + 1,
          statements: const [
            'ALTER TABLE products ADD COLUMN shelf_note TEXT NULL;',
          ],
        ),
      ]);

      final result = await DatabaseBootstrap(
        paths: temp.paths,
        clock: clock.fn,
        migrationPlan: plan,
        supportedSchemaVersion: kSupportedSchemaVersion + 1,
      ).open();
      addTearDown(result.database.close);

      expect(result.kind, DatabaseOpenKind.migrated);
      expect(result.snapshot, isNotNull);
      expect(result.snapshot!.existsSync(), isTrue);

      // Veri korunmuş.
      final products = await result.database
          .select(result.database.products)
          .get();
      expect(products.length, before);

      // Bayrak temizlenmiş — REQ-MIG-006 tekrar tetiklenmemeli.
      final flag = await makeCoordinator().readFlag(result.database);
      expect(flag, isNull);

      // Şema ilerlemiş.
      final columns = await tableColumns(result.database, 'products');
      expect(columns.keys, contains('shelf_note'));
    });

    test(
      'migration BAŞARISIZ olursa bayrak KALIR ve kurtarma tetiklenir',
      () async {
        await seedV1();

        final failingPlan = MigrationPlan([
          MigrationStep(
            from: kSupportedSchemaVersion,
            to: kSupportedSchemaVersion + 1,
            apply: (m, database) async {
              throw StateError('enjekte edilmiş hata');
            },
          ),
        ]);

        await expectLater(
          DatabaseBootstrap(
            paths: temp.paths,
            clock: clock.fn,
            migrationPlan: failingPlan,
            supportedSchemaVersion: kSupportedSchemaVersion + 1,
          ).open(),
          throwsA(isA<StateError>()),
        );

        // Şema versiyonu ilerlememiş.
        expect(
          await RawSqliteFile(temp.paths.databaseFile).readUserVersion(),
          kSupportedSchemaVersion,
        );

        // Sonraki açılış kurtarma ister — yarım şemayla çalışılmaz.
        await expectLater(
          DatabaseBootstrap(
            paths: temp.paths,
            clock: clock.fn,
            migrationPlan: failingPlan,
            supportedSchemaVersion: kSupportedSchemaVersion + 1,
          ).open(),
          throwsA(isA<MigrationRecoveryRequiredException>()),
        );
      },
    );
  });
}
