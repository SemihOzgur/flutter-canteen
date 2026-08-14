/// SQLite yapılandırma testleri — **REQ-DB-001 · REQ-DATA-002**
///
/// docs/05 §1 · rules/03 §1.
///
/// WAL yalnızca **dosya tabanlı** veritabanında doğrulanabilir: in-memory
/// veritabanları `journal_mode = memory` kullanır. Bu yüzden yapılandırma
/// testleri gerçek bir dosya üzerinde çalışır.
library;

import 'dart:io';

import 'package:canteen/data/db/canteen_database.dart';
import 'package:canteen/data/db/database_opener.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
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
}
