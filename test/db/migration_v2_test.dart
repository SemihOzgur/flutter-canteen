/// v1 → v2 migration — **OD-029 · REQ-MIG-001/004 · docs/27 §6.4**
///
/// Bugüne kadarki migration testleri **sentetik** adımlarla altyapıyı
/// doğruladı. Bu, uygulamanın gerçekten yayınladığı ilk adımdır:
/// `categories.icon_key` (OD-029).
///
/// ## Neden gerçek bir v1 veritabanı kuruyoruz
///
/// Drift'in `onCreate`'i **güncel** tablo tanımlarını kullanır; şema
/// versiyonunu 1'e sabitlemek `icon_key`'i olmayan bir tablo üretmez,
/// yalnızca `user_version`'ı 1 yazar. Böyle bir veritabanında migration
/// çalışsa da `ALTER TABLE` "duplicate column" ile patlardı ve test hiçbir
/// şey kanıtlamazdı. Bu yüzden kolon **düşürülerek** gerçek v1 şeması
/// üretilir.
///
/// ## Kapsanan requirement'lar (Faz 11 izlenebilirliği)
///
/// - **REQ-CAT-008** — kategori ikonu alanı
/// - **REQ-MIG-001** — versiyonlu migration adımı
/// - **REQ-MIG-002** — migration veri kaybetmez
library;

import 'dart:io';

import 'package:canteen/data/db/canteen_database.dart'
    hide Category, Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/db/raw_sqlite_file.dart';
import 'package:canteen/data/db/schema_version.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  late Directory dir;
  late String path;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('canteen_mig_v2_');
    path = tempDbPath(dir);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// Gerçek **v1** şemasında bir veritabanı üretir ve örnek veri yazar.
  Future<({int categories, int products, String firstCategory})>
  createRealV1() async {
    final db = fileDatabase(path, schemaVersion: 1);
    await db.customStatement('SELECT 1;');

    await insertTestUser(db);
    final generalId = (await (db.select(
      db.categories,
    )..limit(1)).getSingle()).id;
    await db.customStatement(
      "INSERT INTO categories (name, sort_order, is_system, is_active, "
      "created_at, updated_at) VALUES ('İçecekler', 1, 0, 1, 0, 0)",
    );
    await insertTestProduct(db, name: 'Kola', categoryId: generalId);
    await insertTestProduct(db, name: 'Ayran', categoryId: generalId);

    final categories = (await db.select(db.categories).get()).length;
    final products = (await db.select(db.products).get()).length;
    final first = (await (db.select(db.categories)..limit(1)).getSingle()).name;

    // v1'de bu kolon YOKTUR. Drift onCreate'i güncel tanımı kurduğu için
    // düşürerek gerçek v1 şemasına iniyoruz.
    await db.customStatement('ALTER TABLE categories DROP COLUMN icon_key');
    await db.close();

    return (categories: categories, products: products, firstCategory: first);
  }

  Future<List<String>> columnsOfCategories(CanteenDatabase db) async {
    final rows = await db.customSelect('PRAGMA table_info(categories)').get();
    return rows.map((row) => row.read<String>('name')).toList();
  }

  test('kurulan v1 şemasında icon_key GERÇEKTEN yoktur', () async {
    await createRealV1();

    final db = fileDatabase(path, schemaVersion: 1);
    addTearDown(db.close);
    expect(await columnsOfCategories(db), isNot(contains('icon_key')));
  });

  test('v1 → v2: icon_key eklenir, VERİ AYNEN KALIR', () async {
    final before = await createRealV1();
    expect(await RawSqliteFile(path).readUserVersion(), 1);

    // Uygulamanın gerçek planıyla açılır — sentetik adım YOK.
    final db = fileDatabase(path);
    addTearDown(db.close);
    await db.customStatement('SELECT 1;');

    expect(
      await RawSqliteFile(path).readUserVersion(),
      kSupportedSchemaVersion,
    );
    expect(await columnsOfCategories(db), contains('icon_key'));

    // REQ-MIG-002 — hiçbir satır kaybolmaz, hiçbir değer değişmez.
    expect((await db.select(db.categories).get()).length, before.categories);
    expect((await db.select(db.products).get()).length, before.products);
    expect(
      (await (db.select(db.categories)..limit(1)).getSingle()).name,
      before.firstCategory,
    );
  });

  test('eklenen kolon NULL başlar — kimse ikon kazanmış görünmez', () async {
    // Varsayılan bir değer verilseydi, kullanıcı seçmediği hâlde tüm
    // kategoriler aynı ikonu kazanır ve "otomatik" davranış kaybolurdu.
    await createRealV1();

    final db = fileDatabase(path);
    addTearDown(db.close);
    await db.customStatement('SELECT 1;');

    final rows = await db.select(db.categories).get();
    expect(rows, isNotEmpty);
    for (final row in rows) {
      expect(row.iconKey, isNull, reason: '${row.name} ikon kazanmış.');
    }
  });

  test('migration sonrası foreign_key_check BOŞTUR', () async {
    await createRealV1();

    final db = fileDatabase(path);
    addTearDown(db.close);
    await db.customStatement('SELECT 1;');

    final violations = await db.customSelect('PRAGMA foreign_key_check').get();
    expect(violations, isEmpty);
  });

  test('v2 veritabanı ikinci açılışta TEKRAR migrate edilmez', () async {
    // Adım yeniden çalışsaydı "duplicate column name" ile patlardı.
    await createRealV1();

    final first = fileDatabase(path);
    await first.customStatement('SELECT 1;');
    await first.close();

    final second = fileDatabase(path);
    addTearDown(second.close);
    await expectLater(second.customStatement('SELECT 1;'), completes);
    expect(await columnsOfCategories(second), contains('icon_key'));
  });
}
