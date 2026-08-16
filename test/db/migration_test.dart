/// Migration altyapısı testleri.
///
/// REQ-MIG-001 (versiyonlu) · REQ-MIG-003 (geri alma) · REQ-MIG-004 (tek
/// transaction) · REQ-MIG-005 (yeni şema reddi) · REQ-MIG-007 (veri kaybı yasak)
///
/// ## Neden sentetik migration
///
/// Faz 2 yalnızca **v1** şemasını yayınlar; çalıştırılacak gerçek bir
/// `vN → vN+1` adımı henüz yoktur. Altyapının doğru çalıştığını kanıtlamanın
/// tek dürüst yolu, sentetik adımlarla **gerçekten migration çalıştırmaktır.**
/// Aşağıdaki testler bunu yapar.
library;

import 'dart:io';

import 'package:canteen/core/errors/app_exception.dart';
import 'package:canteen/data/db/migrations/migration_plan.dart';
import 'package:canteen/data/db/migrations/migration_safety.dart';
import 'package:canteen/data/db/raw_sqlite_file.dart';
import 'package:drift/drift.dart' show Migrator;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('canteen_mig_');
    path = tempDbPath(dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// v1 şemasında bir veritabanı oluşturur ve örnek veri yazar.
  Future<({int products, int users})> createV1WithData() async {
    final db = fileDatabase(path);
    await db.customStatement('SELECT 1;');

    final userId = await insertTestUser(db);
    await insertTestProduct(db, name: 'Kola');
    await insertTestProduct(db, name: 'Ayran');
    await insertTestProduct(db, name: 'Su');

    final products = (await db.select(db.products).get()).length;
    final users = (await db.select(db.users).get()).length;
    expect(userId, greaterThan(0));

    await db.close();
    return (products: products, users: users);
  }

  /// v1 → v2: yeni nullable kolon (docs/06 §2 "Tipik değişiklik türleri").
  MigrationStep addColumnStep() => MigrationStep.sql(
    from: 1,
    to: 2,
    statements: const ['ALTER TABLE products ADD COLUMN shelf_note TEXT NULL;'],
  );

  group('REQ-MIG-001 / REQ-MIG-004 — versiyonlu, tek transaction', () {
    test(
      'sentetik v1 → v2 migration çalışır ve şema versiyonu ilerler',
      () async {
        await createV1WithData();
        expect(await RawSqliteFile(path).readUserVersion(), 1);

        final db = fileDatabase(
          path,
          schemaVersion: 2,
          supportedSchemaVersion: 2,
          migrationPlan: MigrationPlan([addColumnStep()]),
        );
        await db.customStatement('SELECT 1;');

        final columns = await tableColumns(db, 'products');
        expect(columns.keys, contains('shelf_note'));

        await db.close();
        expect(await RawSqliteFile(path).readUserVersion(), 2);
      },
    );

    test(
      'veri KORUNUR — satır sayıları ve kritik alanlar (docs/06 §6)',
      () async {
        final before = await createV1WithData();

        final db = fileDatabase(
          path,
          schemaVersion: 2,
          supportedSchemaVersion: 2,
          migrationPlan: MigrationPlan([addColumnStep()]),
        );
        await db.customStatement('SELECT 1;');

        final products = await db.select(db.products).get();
        final users = await db.select(db.users).get();

        expect(products.length, before.products);
        expect(users.length, before.users);
        expect(
          products.map((p) => p.name).toSet(),
          {'Kola', 'Ayran', 'Su'},
          reason: 'Migration sonrası kritik alan değerleri değişmemeli.',
        );
        expect(products.first.salePriceMinor, 12000);

        await db.close();
      },
    );

    test('migration sonrası foreign_key_check BOŞ (docs/06 §6)', () async {
      await createV1WithData();

      final db = fileDatabase(
        path,
        schemaVersion: 2,
        supportedSchemaVersion: 2,
        migrationPlan: MigrationPlan([addColumnStep()]),
      );
      await db.customStatement('SELECT 1;');
      final violations = await db
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      await db.close();

      expect(violations, isEmpty);
    });

    test('çok adımlı zincir v1 → v3 sırayla uygulanır', () async {
      await createV1WithData();

      final db = fileDatabase(
        path,
        schemaVersion: 3,
        supportedSchemaVersion: 3,
        migrationPlan: MigrationPlan([
          addColumnStep(),
          MigrationStep.sql(
            from: 2,
            to: 3,
            statements: const [
              'ALTER TABLE products ADD COLUMN aisle TEXT NULL;',
            ],
          ),
        ]),
      );
      await db.customStatement('SELECT 1;');

      final columns = await tableColumns(db, 'products');
      expect(columns.keys, containsAll(<String>['shelf_note', 'aisle']));

      await db.close();
      expect(await RawSqliteFile(path).readUserVersion(), 3);
    });

    test('eksik adım tespit edilir — sessizce atlanmaz', () async {
      await createV1WithData();

      final db = fileDatabase(
        path,
        schemaVersion: 3,
        supportedSchemaVersion: 3,
        // v2 → v3 adımı YOK.
        migrationPlan: MigrationPlan([addColumnStep()]),
      );

      await expectLater(
        db.customStatement('SELECT 1;'),
        throwsA(isA<StateError>()),
      );
      await db.close();
    });
  });

  group('REQ-MIG-003 — başarısız migration veriyi GERİ ALIR', () {
    test(
      'adım ortasında hata → rollback, şema v1\'de kalır, veri tam',
      () async {
        final before = await createV1WithData();

        var firstStatementRan = false;

        final db = fileDatabase(
          path,
          schemaVersion: 2,
          supportedSchemaVersion: 2,
          migrationPlan: MigrationPlan([
            MigrationStep(
              from: 1,
              to: 2,
              apply: (m, database) async {
                await database.customStatement(
                  'ALTER TABLE products ADD COLUMN shelf_note TEXT NULL;',
                );
                firstStatementRan = true;
                // 3. adımda hata — docs/06 §8 acceptance criteria.
                throw StateError('enjekte edilmiş migration hatası');
              },
            ),
          ]),
        );

        await expectLater(
          db.customStatement('SELECT 1;'),
          throwsA(isA<StateError>()),
        );
        await db.close();

        expect(
          firstStatementRan,
          isTrue,
          reason: 'Hata gerçekten adımın ortasında',
        );

        // Şema versiyonu ilerlememiş olmalı.
        expect(
          await RawSqliteFile(path).readUserVersion(),
          1,
          reason:
              'REQ-MIG-003: başarısız migration şema versiyonunu ilerletemez.',
        );

        // Veri eksiksiz ve şema v1 hâlinde olmalı.
        final reopened = fileDatabase(path);
        await reopened.customStatement('SELECT 1;');
        final products = await reopened.select(reopened.products).get();
        final columns = await tableColumns(reopened, 'products');
        await reopened.close();

        expect(products.length, before.products);
        expect(
          columns.keys,
          isNot(contains('shelf_note')),
          reason: 'Transaction geri alınmadı — DDL kalıcı olmuş!',
        );
      },
    );
  });

  group('REQ-MIG-005 — daha yeni şema REDDEDİLİR', () {
    test('user_version = 99 → SchemaVersionException', () async {
      final db = fileDatabase(path);
      await db.customStatement('SELECT 1;');
      await db.customStatement('PRAGMA user_version = 99;');
      await db.close();

      expect(await RawSqliteFile(path).readUserVersion(), 99);

      final reopened = fileDatabase(path);
      await expectLater(
        reopened.customStatement('SELECT 1;'),
        throwsA(isA<SchemaVersionException>()),
      );
      await reopened.close();
    });

    test('hata desteklenen ve bulunan versiyonu taşır', () async {
      final db = fileDatabase(path);
      await db.customStatement('SELECT 1;');
      await db.customStatement('PRAGMA user_version = 7;');
      await db.close();

      final reopened = fileDatabase(path);
      try {
        await reopened.customStatement('SELECT 1;');
        fail('SchemaVersionException bekleniyordu');
      } on SchemaVersionException catch (e) {
        expect(e.databaseVersion, 7);
        expect(e.supportedVersion, 1);
        expect(e.userMessage, contains('güncelleyin'));
        // REQ-SEC-007: teknik detay kullanıcı mesajında olmamalı.
        expect(e.userMessage, isNot(contains('user_version')));
      } finally {
        await reopened.close();
      }
    });

    test('eşit versiyon normal açılır', () async {
      final db = fileDatabase(path);
      await db.customStatement('SELECT 1;');
      await db.close();

      final reopened = fileDatabase(path);
      await reopened.customStatement('SELECT 1;');
      expect((await reopened.select(reopened.categories).get()).length, 1);
      await reopened.close();
    });
  });

  group('REQ-MIG-007 — veri kaybettiren migration YASAK', () {
    test('DROP TABLE içeren adım REDDEDİLİR', () {
      expect(
        () => MigrationStep.sql(
          from: 1,
          to: 2,
          statements: const ['DROP TABLE products;'],
        ),
        throwsA(isA<DestructiveMigrationError>()),
      );
    });

    test('DROP COLUMN içeren adım REDDEDİLİR', () {
      expect(
        () => MigrationStep.sql(
          from: 1,
          to: 2,
          statements: const ['ALTER TABLE products DROP COLUMN brand;'],
        ),
        throwsA(isA<DestructiveMigrationError>()),
      );
    });

    test('DELETE FROM içeren adım REDDEDİLİR', () {
      expect(
        () => MigrationStep.sql(
          from: 1,
          to: 2,
          statements: const ['DELETE FROM sales;'],
        ),
        throwsA(isA<DestructiveMigrationError>()),
      );
    });

    test('küçük harf / karışık yazım da yakalanır', () {
      expect(
        () => MigrationStep.sql(
          from: 1,
          to: 2,
          statements: const ['drop   table  products;'],
        ),
        throwsA(isA<DestructiveMigrationError>()),
      );
    });

    test('yorum içindeki DROP TABLE yanlış alarm ÜRETMEZ', () {
      expect(
        () => MigrationStep.sql(
          from: 1,
          to: 2,
          statements: const [
            '-- eskiden DROP TABLE products yapılırdı, artık yapılmıyor\n'
                'ALTER TABLE products ADD COLUMN note2 TEXT NULL;',
          ],
        ),
        returnsNormally,
      );
    });

    test('güvenli ADD COLUMN kabul edilir', () {
      expect(
        () => MigrationStep.sql(
          from: 1,
          to: 2,
          statements: const [
            'ALTER TABLE products ADD COLUMN note2 TEXT NULL;',
            'CREATE INDEX ix_test ON products (name);',
          ],
        ),
        returnsNormally,
      );
    });
  });

  group('MigrationStep / MigrationPlan doğrulamaları', () {
    test('bitişik olmayan adım reddedilir', () {
      expect(
        () => MigrationStep(from: 1, to: 3, apply: (m, db) async {}),
        throwsArgumentError,
      );
    });

    test('şema düşürme desteklenmez', () async {
      final plan = MigrationPlan([addColumnStep()]);
      final db = memoryDatabase();
      addTearDown(db.close);

      await expectLater(
        plan.apply(Migrator(db), db, from: 3, to: 1),
        throwsA(isA<StateError>()),
      );
    });

    test('Faz 2 planı boştur — yayınlanmış şema değişikliği yok', () {
      expect(MigrationPlan.empty.steps, isEmpty);
    });
  });
}
