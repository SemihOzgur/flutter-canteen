/// ZAMAN REGRESYON KORUMASI — **REQ-DB-003 · BR-GEN-004**
///
/// docs/05 §5: "Tüm zaman alanları UTC unix-**millisecond** tam sayıdır."
///
/// ## Neden bu test kritik
///
/// Drift'in `DateTimeColumn` **varsayılanı** zamanı unix **saniye** (veya ISO
/// metin) olarak saklar. Varsayılan kullanılsaydı milisaniye bileşeni sessizce
/// kaybolur ve REQ-DB-003 ihlal edilirdi — üstelik hiçbir hata vermeden.
///
/// Bu dosya, milisaniye hassasiyetinin **gerçekten korunduğunu** kanıtlar.
library;

import 'package:canteen/data/db/canteen_database.dart';
import 'package:canteen/data/db/converters.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  late CanteenDatabase db;

  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  const allTables = <String>[
    'users',
    'categories',
    'suppliers',
    'vat_rates',
    'products',
    'product_barcodes',
    'carts',
    'cart_items',
    'sales',
    'sale_items',
    'returns',
    'return_items',
    'stock_movements',
    'audit_logs',
    'app_settings',
  ];

  test('tüm zaman kolonları INTEGER — TEXT/REAL değil', () async {
    const timeSuffixes = ['_at', 'created_at', 'updated_at'];

    for (final table in allTables) {
      final columns = await tableColumns(db, table);
      columns.forEach((name, type) {
        if (timeSuffixes.any(name.endsWith)) {
          expect(
            type,
            'INTEGER',
            reason:
                'REQ-DB-003 İHLALİ: $table.$name tipi $type — unix-ms INTEGER olmalı.',
          );
        }
      });
    }
  });

  test('678 ms hassasiyeti kaybolmadan geri gelir', () async {
    final moment = DateTime.utc(2026, 8, 14, 1, 23, 45, 678);
    expect(moment.millisecond, 678);

    final id = await insertTestUser(db);
    await (db.update(db.users)..where((u) => u.id.equals(id))).write(
      UsersCompanion(lastLoginAt: Value(moment)),
    );

    final row = await (db.select(
      db.users,
    )..where((u) => u.id.equals(id))).getSingle();

    expect(
      row.lastLoginAt!.millisecond,
      678,
      reason:
          'Milisaniye kayboldu — Drift saniye hassasiyetine düşmüş olabilir!',
    );
    expect(row.lastLoginAt, moment);
    expect(row.lastLoginAt!.isUtc, isTrue, reason: 'BR-GEN-004: UTC okunmalı.');
  });

  test('ham saklanan değer unix-MİLİSANİYE tam sayısıdır', () async {
    final moment = DateTime.utc(2026, 8, 14, 1, 23, 45, 678);
    final id = await insertTestUser(db);

    await (db.update(db.users)..where((u) => u.id.equals(id))).write(
      UsersCompanion(lastLoginAt: Value(moment)),
    );

    final raw = await db
        .customSelect(
          'SELECT last_login_at AS v FROM users WHERE id = ?;',
          variables: [Variable<int>(id)],
        )
        .getSingle();

    final stored = raw.data['v'] as int;
    expect(stored, moment.millisecondsSinceEpoch);
    expect(
      stored,
      isNot(moment.millisecondsSinceEpoch ~/ 1000),
      reason: 'Saniye olarak saklanmış — REQ-DB-003 İHLALİ!',
    );
    // 2026 için ms değeri ~1.7e12; saniye olsaydı ~1.7e9 olurdu.
    expect(stored, greaterThan(1000000000000));
  });

  test('yerel saatli DateTime UTC olarak saklanır (BR-GEN-004)', () async {
    final local = DateTime(2026, 8, 14, 10, 30, 15, 250);
    final id = await insertTestUser(db);

    await (db.update(db.users)..where((u) => u.id.equals(id))).write(
      UsersCompanion(lastLoginAt: Value(local)),
    );

    final row = await (db.select(
      db.users,
    )..where((u) => u.id.equals(id))).getSingle();

    expect(row.lastLoginAt!.isUtc, isTrue);
    expect(
      row.lastLoginAt!.millisecondsSinceEpoch,
      local.millisecondsSinceEpoch,
      reason: 'Aynı an olmalı; yalnızca gösterim zaman dilimi farklı.',
    );
    expect(row.lastLoginAt!.millisecond, 250);
  });

  test('dönüştürücü ileri/geri tutarlı — sınır değerler', () {
    const converter = UtcMillisConverter();

    for (final moment in [
      DateTime.utc(1970),
      DateTime.utc(2026, 8, 14, 1, 23, 45, 1),
      DateTime.utc(2026, 8, 14, 1, 23, 45, 999),
      DateTime.utc(2099, 12, 31, 23, 59, 59, 999),
    ]) {
      final sql = converter.toSql(moment);
      final back = converter.fromSql(sql);
      expect(back, moment);
      expect(back.isUtc, isTrue);
      expect(back.millisecond, moment.millisecond);
    }
  });

  test('milisaniye çözünürlüğü ayırt edilebilir', () async {
    final a = DateTime.utc(2026, 8, 14, 1, 23, 45, 100);
    final b = DateTime.utc(2026, 8, 14, 1, 23, 45, 900);

    final first = await insertTestUser(db, username: 'a');
    final second = await insertTestUser(db, username: 'b');

    await (db.update(db.users)..where((u) => u.id.equals(first))).write(
      UsersCompanion(lastLoginAt: Value(a)),
    );
    await (db.update(db.users)..where((u) => u.id.equals(second))).write(
      UsersCompanion(lastLoginAt: Value(b)),
    );

    final rows = await db.select(db.users).get();
    final stamps = rows
        .where((r) => r.lastLoginAt != null)
        .map((r) => r.lastLoginAt!.millisecondsSinceEpoch)
        .toSet();

    expect(
      stamps.length,
      2,
      reason: 'Saniye saklansaydı iki değer aynı olurdu.',
    );
  });
}
