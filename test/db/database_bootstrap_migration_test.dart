/// `DatabaseBootstrap` **üretim yolunda** migration — OD-029 · REQ-MIG-001
///
/// ## Bu dosya neden var
///
/// `migration_v2_test.dart` v1 → v2 adımını doğruluyordu ama veritabanını
/// `CanteenDatabase` üzerinden **doğrudan** kuruyordu. Uygulama ise
/// `DatabaseBootstrap`'ten geçer ve orada plan varsayılanı `MigrationPlan.empty`
/// kalmıştı: şema versiyonu 2'ye çıkmış, plan boş kalmıştı ve uygulama
/// gerçek bir v1 veritabanıyla açılırken
///
/// > `Bad state: Migration adımı bulunamadı: v1 → v2.`
///
/// ile düşüyordu. Testler yeşildi çünkü hiçbiri **kullanıcının izlediği
/// yolu** izlemiyordu.
///
/// Buradaki testler `DatabaseBootstrap.open()` dışında bir giriş noktası
/// kullanmaz — kusurun tekrar etmesi ancak bu yolun bozulmasıyla mümkün olur.
///
/// ## Kapsanan requirement'lar (Faz 11 izlenebilirliği)
///
/// - **REQ-MIG-001** — versiyonlu migration adımı üretim yolunda çalışır
/// - **REQ-MIG-002** — migration veri kaybetmez
library;

import 'dart:io';

import 'package:canteen/core/errors/app_exception.dart';
import 'package:canteen/data/db/database_bootstrap.dart';
import 'package:canteen/data/db/migrations/migration_coordinator.dart';
import 'package:canteen/data/db/migrations/migration_plan.dart';
import 'package:canteen/data/db/raw_sqlite_file.dart';
import 'package:canteen/data/db/schema_version.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  late TempAppPaths temp;

  setUp(() async => temp = await TempAppPaths.create());
  tearDown(() => temp.dispose());

  /// Gerçek **v1** şemasında bir veritabanı bırakır.
  ///
  /// Drift'in `onCreate`'i güncel tabloları kurar; sürümü 1 yazmak tek
  /// başına v1 şeması üretmez, bu yüzden v2'de eklenen kolon düşürülür.
  Future<({int categories, int products})> seedRealV1() async {
    final db = fileDatabase(temp.paths.databaseFile, supportedSchemaVersion: 1);
    await db.customStatement('SELECT 1;');

    await insertTestUser(db);
    await db.customStatement(
      "INSERT INTO categories (name, sort_order, is_system, is_active, "
      "created_at, updated_at) VALUES ('İçecekler', 1, 0, 1, 0, 0)",
    );
    await insertTestProduct(db, name: 'Kola');
    await insertTestProduct(db, name: 'Ayran');

    final categories = (await db.select(db.categories).get()).length;
    final products = (await db.select(db.products).get()).length;

    await db.customStatement('ALTER TABLE categories DROP COLUMN icon_key');
    await db.close();

    return (categories: categories, products: products);
  }

  test('v1 veritabanı DatabaseBootstrap ile açılınca MIGRATE EDİLİR', () async {
    // Bu, kullanıcının gördüğü hatanın birebir senaryosudur.
    final before = await seedRealV1();
    expect(await RawSqliteFile(temp.paths.databaseFile).readUserVersion(), 1);

    final result = await DatabaseBootstrap(paths: temp.paths).open();
    addTearDown(result.database.close);

    expect(
      result.kind,
      DatabaseOpenKind.migrated,
      reason: 'Açılış migration yolundan geçmelidir.',
    );
    expect(
      await RawSqliteFile(temp.paths.databaseFile).readUserVersion(),
      kSupportedSchemaVersion,
    );

    // REQ-MIG-002 — veri aynen durur.
    final db = result.database;
    expect((await db.select(db.categories).get()).length, before.categories);
    expect((await db.select(db.products).get()).length, before.products);
  });

  test('migrate edilen veritabanı KULLANILABİLİR durumda açılır', () async {
    // Şema yükseldi ama uygulama yeni kolonu okuyamıyorsa migration yarım
    // sayılır.
    await seedRealV1();

    final result = await DatabaseBootstrap(paths: temp.paths).open();
    addTearDown(result.database.close);
    final db = result.database;

    final rows = await db.select(db.categories).get();
    expect(rows, isNotEmpty);
    for (final row in rows) {
      expect(row.iconKey, isNull);
    }
  });

  test('yeni kurulum migration YOLUNA GİRMEZ', () async {
    // Boş dizinde `onCreate` çalışır; migration'ın orada işi yoktur.
    final result = await DatabaseBootstrap(paths: temp.paths).open();
    addTearDown(result.database.close);

    expect(result.kind, DatabaseOpenKind.created);
    expect(
      await RawSqliteFile(temp.paths.databaseFile).readUserVersion(),
      kSupportedSchemaVersion,
    );
  });

  test('ikinci açılış migration TEKRARLAMAZ', () async {
    await seedRealV1();

    final first = await DatabaseBootstrap(paths: temp.paths).open();
    await first.database.close();

    final second = await DatabaseBootstrap(paths: temp.paths).open();
    addTearDown(second.database.close);

    expect(
      second.kind,
      DatabaseOpenKind.opened,
      reason: 'Adım yeniden çalışsaydı "duplicate column" ile düşerdi.',
    );
  });

  test(
    'REQ-MIG-006 — snapshot geri yüklenince migration YENİDEN denenir',
    () async {
      // docs/06 §3 adım 3: "Kullanıcı onaylarsa snapshot geri yüklenir ve
      // migration yeniden denenir." Ekranın gösterdiği düğmenin ARKASINDAKİ
      // mekanizma budur.
      final before = await seedRealV1();

      // Yarım kalmış migration üret: snapshot al, bayrağı yaz.
      final probe = fileDatabase(
        temp.paths.databaseFile,
        supportedSchemaVersion: 1,
      );
      final coordinator = MigrationCoordinator(
        databaseFilePath: temp.paths.databaseFile,
        autoBackupsDirPath: temp.paths.autoBackupsDir,
      );
      final snapshot = await coordinator.createSnapshot(probe, fromVersion: 1);
      await coordinator.writeFlag(
        probe,
        MigrationFlag(from: 1, to: 2, startedAt: DateTime.utc(2026)),
      );
      await probe.close();

      // Açılış kurtarma ister ve snapshot'ı GÖSTERİR.
      try {
        await DatabaseBootstrap(paths: temp.paths).open();
        fail('MigrationRecoveryRequiredException bekleniyordu');
      } on MigrationRecoveryRequiredException catch (e) {
        expect(e.snapshotPath, isNotNull);
        expect(e.fromVersion, 1);
        expect(e.toVersion, 2);
      }

      // Kullanıcı onaylar → geri yükle → yeniden aç.
      await coordinator.restoreFromSnapshot(snapshot);

      final result = await DatabaseBootstrap(paths: temp.paths).open();
      addTearDown(result.database.close);

      expect(
        result.kind,
        DatabaseOpenKind.migrated,
        reason:
            'Geri yüklenen kopya bayrağı TAŞIMAZ; migration temiz zeminde '
            'yeniden çalışır (snapshot adım 2, bayrak adım 4).',
      );

      final db = result.database;
      expect((await db.select(db.categories).get()).length, before.categories);
      expect((await db.select(db.products).get()).length, before.products);
    },
  );

  test(
    'plan eksikse veritabanına DOKUNULMAZ — bayrak ve snapshot oluşmaz',
    () async {
      // Kullanıcının yaşadığı asıl zarar buydu: eksik adım bayrak
      // yazıldıktan SONRA fark ediliyordu ve uygulama, hiçbir şeyin
      // değişmediği bir veritabanı için "yarım kaldı" diyerek bir daha
      // açılmıyordu.
      await seedRealV1();

      await expectLater(
        DatabaseBootstrap(
          paths: temp.paths,
          migrationPlan: MigrationPlan.empty,
        ).open(),
        throwsA(isA<MigrationException>()),
      );

      // Bayrak yazılmamış olmalı: sonraki açılış kurtarma İSTEMEZ.
      final result = await DatabaseBootstrap(paths: temp.paths).open();
      addTearDown(result.database.close);
      expect(result.kind, DatabaseOpenKind.migrated);

      // Snapshot da alınmamış olmalı — boşuna yedek üretilmez.
      final snapshots = Directory(temp.paths.autoBackupsDir).existsSync()
          ? Directory(
              temp.paths.autoBackupsDir,
            ).listSync().where((e) => e.path.contains('premigration')).length
          : 0;
      expect(
        snapshots,
        1,
        reason:
            'Yalnızca GERÇEKTEN çalışan migration snapshot almalıdır; '
            'başarısız plan kontrolü dosya bırakmaz.',
      );
    },
  );

  test('plan, DESTEKLENEN her versiyona kadar eksiksizdir', () async {
    // Eksik adım `StateError` atar ve kullanıcı bunu veritabanı açılırken
    // görür — kullanıcının gördüğü hata tam olarak buydu.
    await seedRealV1();

    await expectLater(DatabaseBootstrap(paths: temp.paths).open(), completes);
  });
}
