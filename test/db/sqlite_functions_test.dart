/// Uygulama tanımlı SQL fonksiyonu testleri — **REQ-PROD-010 · docs/09 §6**
///
/// `canteen_fold` şema değişikliği yapmadan Türkçe duyarsız aramayı mümkün
/// kılar (şema FİNAL — rules/03 §1). Bu dosya fonksiyonun **hangi
/// bağlantılarda** var olduğunu doğrular.
library;

import 'dart:io';

import 'package:canteen/data/db/canteen_database.dart';
import 'package:canteen/data/db/database_bootstrap.dart';
import 'package:canteen/data/db/database_opener.dart';
import 'package:canteen/domain/services/turkish_text.dart';
import 'package:drift/drift.dart'
    show QueryExecutor, QueryExecutorUser, OpeningDetails, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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

void main() {
  test('in-memory bağlantıda kayıtlıdır', () async {
    final db = CanteenDatabase(openDatabaseInMemory(), schemaVersion: 1);
    addTearDown(db.close);

    final row = await db
        .customSelect("SELECT ${SqliteFunctions.fold}('IŞIL Çğü') AS folded")
        .getSingle();

    expect(row.data['folded'], 'isil cgu');
  });

  test('Dart ve SQLite tarafı AYNI katlamayı üretir', () async {
    final db = CanteenDatabase(openDatabaseInMemory(), schemaVersion: 1);
    addTearDown(db.close);

    const samples = [
      'Şeftali Suyu',
      'IŞIL',
      'İstanbul',
      'Ayçiçek Yağı',
      'Beyaz Peynir 500 g',
      '8691234567890',
    ];

    for (final sample in samples) {
      final row = await db
          .customSelect(
            'SELECT ${SqliteFunctions.fold}(?) AS folded',
            variables: [Variable<String>(sample)],
          )
          .getSingle();
      expect(
        row.data['folded'],
        TurkishText.fold(sample),
        reason: 'Sorgunun iki yakası aynı kuralı kullanmalıdır: $sample',
      );
    }
  });

  test('NULL girdi NULL döner', () async {
    final db = CanteenDatabase(openDatabaseInMemory(), schemaVersion: 1);
    addTearDown(db.close);

    final row = await db
        .customSelect('SELECT ${SqliteFunctions.fold}(NULL) AS folded')
        .getSingle();
    expect(row.data['folded'], isNull);
  });

  test('üretim bağlantısında (DatabaseBootstrap) kayıtlıdır', () async {
    final temp = await TempAppPaths.create();
    addTearDown(temp.dispose);

    final result = await DatabaseBootstrap(paths: temp.paths).open();
    addTearDown(result.database.close);

    final row = await result.database
        .customSelect("SELECT ${SqliteFunctions.fold}('ÖĞÜN') AS folded")
        .getSingle();
    expect(row.data['folded'], 'ogun');
  });

  test('TANI bağlantısı PRAGMA-only kalır — fonksiyon YOKTUR', () async {
    // `buildDiagnosticSetup` snapshot doğrulaması için kullanılır ve
    // doğruladığı dosyaya hiçbir şey eklememelidir (bkz. database_opener.dart).
    final dir = Directory.systemTemp.createTempSync('canteen_fn_diag_');
    addTearDown(() => dir.deleteSync(recursive: true));

    final path = '${dir.path}/diag.sqlite';
    final executor = NativeDatabase(
      File(path),
      enableMigrations: false,
      setup: buildDiagnosticSetup(),
    );
    addTearDown(executor.close);
    await executor.ensureOpen(_InertExecutorUser());

    await expectLater(
      executor.runSelect("SELECT ${SqliteFunctions.fold}('x');", const []),
      throwsA(anything),
      reason: 'Tanı bağlantısı yalnızca PRAGMA çalıştırır.',
    );
  });
}
