/// Seed testleri — **BR-PROD-003 · BR-CAT-004**
///
/// Kurulumda `Genel` kategorisi oluşturulur; sistem kategorisidir.
/// Seed **idempotenttir**: ikinci açılışta kayıt çoğalmaz.
library;

import 'dart:io';

import 'package:canteen/data/db/canteen_database.dart';
import 'package:canteen/data/db/seed.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  group('BR-PROD-003 — Genel kategorisi', () {
    late CanteenDatabase db;

    setUp(() => db = memoryDatabase());
    tearDown(() => db.close());

    test('ilk açılışta oluşturulur', () async {
      final rows = await db.select(db.categories).get();

      expect(rows.length, 1);
      expect(rows.single.name, 'Genel');
    });

    test('is_system = true — BR-CAT-004', () async {
      final row = await db.select(db.categories).getSingle();

      expect(
        row.isSystem,
        isTrue,
        reason: 'BR-CAT-004: Genel sistem kategorisidir.',
      );
      expect(row.isActive, isTrue);
      expect(row.sortOrder, 0);
    });

    test('KDV oranı seed EDİLMEZ (rules/02 §2)', () async {
      final rates = await db.select(db.vatRates).get();
      expect(
        rates,
        isEmpty,
        reason: 'Kullanıcı kendi KDV oranlarını tanımlar.',
      );
    });

    test('kullanıcı seed EDİLMEZ — kurulum sihirbazı Faz 3', () async {
      final users = await db.select(db.users).get();
      expect(users, isEmpty);
    });

    test('tekrar çalıştırmak kayıt ÇOĞALTMAZ (idempotent)', () async {
      await Seed.apply(db, nowUtc: testEpochUtc);
      await Seed.apply(db, nowUtc: testEpochUtc);
      await Seed.apply(db, nowUtc: testEpochUtc);

      final rows = await db.select(db.categories).get();
      expect(rows.length, 1);
    });

    test('mevcut kaydı DEĞİŞTİRMEZ', () async {
      final before = await db.select(db.categories).getSingle();

      await Seed.apply(db, nowUtc: testEpochUtc.add(const Duration(days: 30)));

      final after = await db.select(db.categories).getSingle();
      expect(after.id, before.id);
      expect(after.createdAt, before.createdAt);
    });
  });

  group('kalıcılık — ikinci açılış', () {
    test('dosya yeniden açıldığında Genel hâlâ TEK kayıt', () async {
      final dir = Directory.systemTemp.createTempSync('canteen_seed_');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });

      final path = tempDbPath(dir);

      var db = fileDatabase(path);
      await db.customStatement('SELECT 1;');
      expect((await db.select(db.categories).get()).length, 1);
      final firstId = (await db.select(db.categories).getSingle()).id;
      await db.close();

      // İkinci açılış — seed tekrar çalışır ama yazmamalıdır.
      db = fileDatabase(path);
      await db.customStatement('SELECT 1;');
      final rows = await db.select(db.categories).get();
      await db.close();

      expect(rows.length, 1, reason: 'Seed duplication oluştu!');
      expect(rows.single.id, firstId);
      expect(rows.single.name, 'Genel');
    });
  });
}
