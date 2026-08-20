/// KDV oranı yönetimi testleri — **BR-VAT-001/004/005 · REQ-VAT-001/002**
///
/// docs/27 §4: gerçek in-memory SQLite.
///
/// Kritik invariant: `is_default` **yalnızca bir kayıtta** `true` olabilir
/// (docs/04 §3.4).
///
/// ## Kapsanan requirement'lar (Faz 11 izlenebilirliği)
///
/// - **REQ-VAT-010** — pasif oran varsayılan yapılamaz
library;

import 'dart:io';

import 'package:canteen/application/reference/vat_rate_service.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/result/result.dart';
// Drift, `vat_rates` satırı için domain modeliyle aynı adlı sınıf üretir.
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart' hide VatRate;
import 'package:canteen/domain/services/vat_calculator.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late VatRateService service;
  late VatRatesDao vatRates;
  late AuditLogsDao auditLogs;
  late int userId;

  /// Kurulumda seed edilen `%0 — KDV Yok` oranı (OD-017) — testlerin çoğu
  /// artık boş bir tabloyla değil, bu tek kayıtla başlar.
  late int neutralRateId;

  setUp(() async {
    db = memoryDatabase();
    vatRates = VatRatesDao(db);
    auditLogs = AuditLogsDao(db);
    service = VatRateService(
      db: db,
      vatRates: vatRates,
      auditLogs: auditLogs,
      clock: () => testEpochUtc,
    );
    userId = await insertTestUser(db);
    neutralRateId = (await vatRates.listAll()).single.id;
  });

  tearDown(() async => db.close());

  Future<List<AuditLog>> auditOf(String action) async {
    final logs = await auditLogs.listRecent();
    return logs.where((log) => log.action == action).toList();
  }

  /// Veritabanındaki **ham** varsayılan sayısı — `findDefault` aktiflik filtresi
  /// uyguladığı için invariant'ı gizleyebilirdi.
  Future<List<int>> rawDefaultIds() async {
    final rows = await (db.select(
      db.vatRates,
    )..where((v) => v.isDefault.equals(true))).get();
    return rows.map((r) => r.id).toList();
  }

  group('BR-VAT-001 · REQ-VAT-002 · OD-017 — yalnızca nötr %0 seed edilir', () {
    test('temiz kurulumda tek bir %0 oranı vardır ve varsayılandır', () async {
      expect(await vatRates.countAll(), 1);

      final only = (await service.list()).single;
      expect(only.rateBasisPoints, 0);
      expect(only.isDefault, isTrue);
      expect(only.isActive, isTrue);
      expect((await service.defaultRate())?.id, only.id);
    });

    test('BR-VAT-005: kullanıcı oran tanımlamadıkça KDV KAPALIDIR', () async {
      expect(
        await service.isVatDisabled(),
        isTrue,
        reason: 'Tek oran %0 ise KDV alanları gizlenir (docs/08 §3).',
      );

      await service.create(name: 'Standart', rateBasisPoints: 2000);

      expect(
        await service.isVatDisabled(),
        isFalse,
        reason: 'Kullanıcı gerçek bir oran tanımlayınca KDV açılır.',
      );
    });

    test('okuma çağrıları kendiliğinden oran ÜRETMEZ', () async {
      await service.list();
      await service.defaultRate();
      await service.isVatDisabled();

      expect(await vatRates.countAll(), 1);
    });

    test('seed MEVZUATA BAĞLI hiçbir oran yazmaz (BR-VAT-001)', () {
      // BR-VAT-001'in koruduğu şey %20/%10/%1 gibi mevzuat değerlerinin koda
      // yazılmasıdır. Kaynak seviyesinde korunur: seed.dart'taki her
      // `rateBasisPoints` literali SIFIR olmalıdır.
      final seed = File('lib/data/db/seed.dart').readAsStringSync();
      final literals = RegExp(
        r'rateBasisPoints:\s*(-?\d+)',
      ).allMatches(seed).map((m) => m.group(1)).toList();

      expect(literals, isNotEmpty, reason: 'OD-017: %0 oranı seed edilir.');
      expect(
        literals,
        everyElement('0'),
        reason: 'Sıfırdan farklı bir oran seed edilemez.',
      );
    });

    test('BR-VAT-005: %0 varsayılanıyla KDV hesabı sıfırdır', () async {
      expect((await service.defaultRate())!.rateBasisPoints, 0);

      final breakdown = VatCalculator.fromGross(
        gross: const Money(12000),
        vatRateBp: 0,
      );
      expect(breakdown.vat.minor, 0);
      expect(breakdown.net.minor, 12000);
    });
  });

  group('Oluşturma — REQ-VAT-001', () {
    test('oran basis point olarak kaydedilir ve audit yazılır', () async {
      final id =
          (await service.create(
                    name: 'Standart',
                    rateBasisPoints: 2000,
                    userId: userId,
                  )
                  as Ok<int>)
              .value;

      final created = await service.findById(id);
      expect(created!.name, 'Standart');
      expect(created.rateBasisPoints, 2000); // %20
      expect(created.isDefault, isFalse);
      expect(created.isActive, isTrue);

      final log = (await auditOf(VatRateService.actionCreated)).single;
      expect(log.entityType, VatRateService.auditEntityType);
      expect(log.entityId, id);
      expect(log.newValue, contains('"rate_basis_points":2000'));
    });

    test('ad boşsa reddedilir', () async {
      final before = await vatRates.countAll();
      final result = await service.create(name: ' ', rateBasisPoints: 2000);
      expect(result.failureOrNull?.code, 'vat_rate_name_required');
      expect(await vatRates.countAll(), before, reason: 'Yeni kayıt yok.');
    });

    test('negatif oran reddedilir (CHECK(rate_basis_points >= 0))', () async {
      final before = await vatRates.countAll();
      final result = await service.create(name: 'Hatalı', rateBasisPoints: -1);
      expect(result.failureOrNull?.code, 'vat_rate_invalid');
      expect(await vatRates.countAll(), before, reason: 'Yeni kayıt yok.');
    });

    test('%0 oranı geçerlidir (BR-VAT-005 — "KDV Yok")', () async {
      final result = await service.create(name: 'KDV Yok', rateBasisPoints: 0);
      expect(result.isOk, isTrue);
      expect(
        (await service.findById((result as Ok<int>).value))!.rateBasisPoints,
        0,
      );
    });

    test(
      'parseRate metin girdisini bp\'ye çevirir (tek implementasyon)',
      () async {
        final parsed = VatRateService.parseRate('%0,5');
        expect((parsed as Ok<int>).value, 50);

        final id =
            (await service.create(name: 'Yarım', rateBasisPoints: parsed.value)
                    as Ok<int>)
                .value;
        expect((await service.findById(id))!.rateBasisPoints, 50);

        expect(
          VatRateService.parseRate('abc').failureOrNull?.code,
          'vat_rate_invalid',
        );
      },
    );
  });

  group('docs/04 §3.4 — VARSAYILAN yalnızca BİR kayıtta true olabilir', () {
    test('yeni varsayılan atanınca eskisi temizlenir', () async {
      final first =
          (await service.create(name: 'Standart', rateBasisPoints: 2000)
                  as Ok<int>)
              .value;
      final second =
          (await service.create(name: 'İndirimli', rateBasisPoints: 1000)
                  as Ok<int>)
              .value;

      expect((await service.setDefault(first, userId: userId)).isOk, isTrue);
      expect(await rawDefaultIds(), [first]);

      expect((await service.setDefault(second, userId: userId)).isOk, isTrue);

      // İKİ KAYIT AYNI ANDA DEFAULT OLAMAZ.
      expect(await rawDefaultIds(), [second]);
      expect((await service.findById(first))!.isDefault, isFalse);
      expect((await service.defaultRate())!.id, second);
    });

    test('create(isDefault: true) da invariant\'ı korur', () async {
      final first =
          (await service.create(
                    name: 'Standart',
                    rateBasisPoints: 2000,
                    isDefault: true,
                  )
                  as Ok<int>)
              .value;
      final second =
          (await service.create(
                    name: 'İndirimli',
                    rateBasisPoints: 1000,
                    isDefault: true,
                  )
                  as Ok<int>)
              .value;

      expect(await rawDefaultIds(), [second]);
      expect((await service.findById(first))!.isDefault, isFalse);
    });

    test('bozulmuş veri (iki varsayılan) setDefault ile onarılır', () async {
      final first =
          (await service.create(name: 'Standart', rateBasisPoints: 2000)
                  as Ok<int>)
              .value;
      final second =
          (await service.create(name: 'İndirimli', rateBasisPoints: 1000)
                  as Ok<int>)
              .value;

      // Servis dışından bozulma (örn. eski bir sürüm veya elle müdahale).
      await db
          .update(db.vatRates)
          .write(const VatRatesCompanion(isDefault: Value(true)));
      expect(await rawDefaultIds(), [neutralRateId, first, second]);

      expect((await service.setDefault(second)).isOk, isTrue);
      expect(await rawDefaultIds(), [second]);
    });

    test('pasif oran varsayılan YAPILAMAZ — sessiz KDV kaybı olurdu', () async {
      final id =
          (await service.create(name: 'Eski Oran', rateBasisPoints: 800)
                  as Ok<int>)
              .value;
      await service.deactivate(id);

      final result = await service.setDefault(id);

      expect(result.failureOrNull?.code, 'vat_rate_inactive_default');
      expect(await rawDefaultIds(), [
        neutralRateId,
      ], reason: 'Varsayılan devredilmemiş olmalıdır.');
    });

    test('olmayan oran varsayılan yapılamaz', () async {
      expect(
        (await service.setDefault(9999)).failureOrNull?.code,
        'vat_rate_not_found',
      );
    });
  });

  group('Güncelleme — BR-VAT-004 · docs/08 §4', () {
    test('vatRateChanged eski/yeni oranı ve ürün sayısını taşır', () async {
      final id =
          (await service.create(name: 'Standart', rateBasisPoints: 1800)
                  as Ok<int>)
              .value;

      // Bu orana bağlı iki ürün.
      for (var i = 0; i < 2; i++) {
        final productId = await insertTestProduct(db, name: 'Ürün $i');
        await (db.update(db.products)..where((p) => p.id.equals(productId)))
            .write(ProductsCompanion(vatRateId: Value(id)));
      }

      expect(
        (await service.update(id, rateBasisPoints: 2000, userId: userId)).isOk,
        isTrue,
      );
      expect((await service.findById(id))!.rateBasisPoints, 2000);

      final log = (await auditOf(VatRateService.actionChanged)).single;
      expect(log.oldValue, '{"rate_basis_points":1800}');
      expect(log.newValue, '{"rate_basis_points":2000}');
      expect(log.metadata, '{"affected_product_count":2}');
    });

    test('ad değişikliği de vatRateChanged olarak kaydedilir', () async {
      final id =
          (await service.create(name: 'Standart', rateBasisPoints: 2000)
                  as Ok<int>)
              .value;

      expect((await service.update(id, name: 'Genel Oran')).isOk, isTrue);

      final log = (await auditOf(VatRateService.actionChanged)).single;
      expect(log.oldValue, '{"name":"Standart"}');
      expect(log.newValue, '{"name":"Genel Oran"}');
    });

    test('değişiklik yoksa audit yazılmaz', () async {
      final id =
          (await service.create(name: 'Standart', rateBasisPoints: 2000)
                  as Ok<int>)
              .value;

      expect(
        (await service.update(
          id,
          name: 'Standart',
          rateBasisPoints: 2000,
        )).isOk,
        isTrue,
      );
      expect(await auditOf(VatRateService.actionChanged), isEmpty);
    });

    test('boş ad ve negatif oran reddedilir', () async {
      final id =
          (await service.create(name: 'Standart', rateBasisPoints: 2000)
                  as Ok<int>)
              .value;

      expect(
        (await service.update(id, name: ' ')).failureOrNull?.code,
        'vat_rate_name_required',
      );
      expect(
        (await service.update(id, rateBasisPoints: -5)).failureOrNull?.code,
        'vat_rate_invalid',
      );
      expect((await service.findById(id))!.rateBasisPoints, 2000);
    });

    test('olmayan oran güncellenemez', () async {
      expect(
        (await service.update(9999, rateBasisPoints: 100)).failureOrNull?.code,
        'vat_rate_not_found',
      );
    });
  });

  group('Pasifleştirme — docs/08 §4 (silme YOK)', () {
    test('oran pasifleşir, ürün bağı korunur', () async {
      final id =
          (await service.create(name: 'Standart', rateBasisPoints: 2000)
                  as Ok<int>)
              .value;
      final productId = await insertTestProduct(db);
      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(ProductsCompanion(vatRateId: Value(id)));

      expect((await service.deactivate(id, userId: userId)).isOk, isTrue);

      expect((await service.findById(id))!.isActive, isFalse);
      final product = await (db.select(
        db.products,
      )..where((p) => p.id.equals(productId))).getSingle();
      expect(product.vatRateId, id);
      expect(product.isActive, isTrue);

      final log = (await auditOf(VatRateService.actionDeactivated)).single;
      expect(log.metadata, contains('"rate_basis_points":2000'));
    });

    test(
      'varsayılan oran pasifleşirse "varsayılan yok" durumuna düşülür',
      () async {
        final id =
            (await service.create(
                      name: 'Standart',
                      rateBasisPoints: 2000,
                      isDefault: true,
                    )
                    as Ok<int>)
                .value;

        expect((await service.defaultRate())!.id, id);
        expect((await service.deactivate(id)).isOk, isTrue);

        // docs/08 §4: varsayılan oran yoksa KDV %0 kabul edilir.
        expect(await service.defaultRate(), isNull);
      },
    );

    test('zaten pasifse audit yinelenmez', () async {
      final id =
          (await service.create(name: 'Standart', rateBasisPoints: 2000)
                  as Ok<int>)
              .value;
      await service.deactivate(id);
      await service.deactivate(id);

      expect(await auditOf(VatRateService.actionDeactivated), hasLength(1));
    });

    test('pasif oran listeden filtrelenebilir', () async {
      final id =
          (await service.create(name: 'Standart', rateBasisPoints: 2000)
                  as Ok<int>)
              .value;
      await service.deactivate(id);

      expect((await service.list()).map((v) => v.id), contains(id));
      expect(
        (await service.list(onlyActive: true)).map((v) => v.id),
        isNot(contains(id)),
      );
    });
  });

  group('docs/08 §4 — KDV oranı SİLİNEMEZ', () {
    const forbidden = ['delete', 'deleteById', 'remove', 'purge'];

    bool declaresMember(String source, String member) => RegExp(
      r'^\s*(?!///)[\w<>,\s\?]*\b' + member + r'\s*\(',
      multiLine: true,
    ).hasMatch(source);

    test('VatRateService silme metodu SUNMAZ', () {
      final source = File(
        'lib/application/reference/vat_rate_service.dart',
      ).readAsStringSync();
      for (final member in forbidden) {
        expect(
          declaresMember(source, member),
          isFalse,
          reason: 'docs/08 §4: oran kaydı silinemez — "$member" olmamalı.',
        );
      }
      // Pozitif kontrol: tarama gerçekten bildirim bulabiliyor.
      expect(declaresMember(source, 'deactivate'), isTrue);
    });

    test('VatRatesDao silme metodu SUNMAZ ve kodda DELETE yolu yok', () {
      final source = File('lib/data/dao/daos.dart').readAsStringSync();
      final start = source.indexOf('class VatRatesDao');
      final end = source.indexOf('class ProductBarcodesDao');
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));

      final daoSource = source.substring(start, end);
      for (final member in forbidden) {
        expect(declaresMember(daoSource, member), isFalse);
      }
      expect(declaresMember(daoSource, 'setActive'), isTrue);

      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.readAsStringSync().contains('delete(vatRates)')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty, reason: 'docs/08 §4 ihlali: $offenders');
    });
  });

  group('REQ-VAT-011 · OD-020 — yeniden aktifleştirme', () {
    test('pasif oran yeniden aktifleştirilir ve audit yazılır', () async {
      final id =
          (await service.create(name: 'Standart', rateBasisPoints: 2000)
                  as Ok<int>)
              .value;
      await service.deactivate(id);

      expect((await service.activate(id, userId: userId)).isOk, isTrue);

      expect((await service.findById(id))!.isActive, isTrue);
      expect(await auditOf(VatRateService.actionActivated), hasLength(1));
    });

    test(
      'varsayılan bayrağı taşıyan oran aktifleşince invariant korunur',
      () async {
        // Seed edilen %0 varsayılandır. Yeni bir oranı varsayılan yapıp
        // pasifleştirirsek bayrak onda kalır (EC-VAT-002).
        final id =
            (await service.create(
                      name: 'Standart',
                      rateBasisPoints: 2000,
                      isDefault: true,
                    )
                    as Ok<int>)
                .value;
        await service.deactivate(id);

        await service.activate(id);

        expect(
          await rawDefaultIds(),
          [id],
          reason: 'docs/04 §3.4: aynı anda yalnızca bir varsayılan.',
        );
      },
    );

    test('zaten aktif kayıt audit ÜRETMEZ', () async {
      final id =
          (await service.create(name: 'Standart', rateBasisPoints: 2000)
                  as Ok<int>)
              .value;

      expect((await service.activate(id)).isOk, isTrue);

      expect(await auditOf(VatRateService.actionActivated), isEmpty);
    });
  });

  group('EC-VAT-002 / EC-VAT-003 — varsayılan ve silinemezlik', () {
    test(
      'EC-VAT-002: varsayılan oran pasifleştirilince bayrak KORUNUR',
      () async {
        final neutral = (await service.list()).single;
        expect(neutral.isDefault, isTrue);

        await service.deactivate(neutral.id);

        expect(
          await rawDefaultIds(),
          [neutral.id],
          reason: 'docs/08 §4: is_default bayrağına dokunulmaz.',
        );
        expect(
          await service.defaultRate(),
          isNull,
          reason: 'Arama aktiflik filtreler → sonuç "varsayılan yok" → %0.',
        );
      },
    );

    test('EC-VAT-003: %0 oranı SİLİNEMEZ — silme yolu yok', () {
      // docs/08 §4: hiçbir KDV oranı silinemez. Kural runtime kontrolü değil,
      // metodun var olmamasıdır.
      final source = File(
        'lib/application/reference/vat_rate_service.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('Future<Result<void>> delete')));
      expect(source, isNot(contains('delete(vatRates)')));
    });
  });
}
