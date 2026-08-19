/// Seed testleri — **BR-PROD-003 · BR-CAT-004**
///
/// Kurulumda `Genel` kategorisi oluşturulur; sistem kategorisidir.
/// Seed **idempotenttir**: ikinci açılışta kayıt çoğalmaz.
library;

import 'dart:io';

import 'package:drift/drift.dart' show Value;

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

    test('nötr %0 oranı seed EDİLİR ve varsayılan olur (OD-017)', () async {
      final rates = await db.select(db.vatRates).get();

      expect(rates, hasLength(1), reason: 'docs/08 §3: tek bir oran.');
      expect(rates.single.name, Seed.neutralVatRateName);
      expect(
        rates.single.rateBasisPoints,
        0,
        reason: 'BR-VAT-005: kullanıcı tanımlamadıkça KDV yoktur.',
      );
      expect(
        rates.single.isDefault,
        isTrue,
        reason: 'docs/08 §3: oran varsayılan olur.',
      );
      expect(rates.single.isActive, isTrue);
    });

    test('mevzuata bağlı HİÇBİR oran seed edilmez (BR-VAT-001)', () async {
      final rates = await db.select(db.vatRates).get();

      // BR-VAT-001'in koruduğu şey budur: %20/%10/%1 gibi mevzuata bağlı bir
      // değerin koda yazılması. %0 nötr elemandır, vergi varsayımı değildir.
      expect(
        rates.map((r) => r.rateBasisPoints),
        everyElement(0),
        reason: 'Sıfırdan farklı bir oran seed edilmiş olamaz.',
      );
    });

    test(
      'kullanıcı oranı düzenlerse seed onu GERİ GETİRMEZ (OD-017)',
      () async {
        // Ad değiştirilebilir (OD-017). Seed adla arasaydı burada ikinci bir
        // %0 oranı oluşur ve varsayılan sessizce devredilirdi.
        await (db.update(db.vatRates)
              ..where((v) => v.rateBasisPoints.equals(0)))
            .write(const VatRatesCompanion(name: Value('KDV Yok')));

        await Seed.apply(db, nowUtc: testEpochUtc);

        final rates = await db.select(db.vatRates).get();
        expect(rates, hasLength(1), reason: 'İkinci oran oluşmamalıdır.');
        expect(rates.single.name, 'KDV Yok', reason: 'Ad korunmalıdır.');
      },
    );

    test('kullanıcının kendi oranları varken seed KAYIT EKLEMEZ', () async {
      await db.delete(db.vatRates).go();
      await db
          .into(db.vatRates)
          .insert(
            VatRatesCompanion.insert(
              name: 'Standart',
              rateBasisPoints: 2000,
              isDefault: const Value(true),
              createdAt: testEpochUtc,
              updatedAt: testEpochUtc,
            ),
          );

      await Seed.apply(db, nowUtc: testEpochUtc);

      final rates = await db.select(db.vatRates).get();
      expect(rates, hasLength(1));
      expect(rates.single.name, 'Standart');
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
