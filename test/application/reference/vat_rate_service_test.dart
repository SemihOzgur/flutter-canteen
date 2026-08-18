/// KDV oranı yönetimi testleri — **BR-VAT-001/004/005 · REQ-VAT-001/002**
///
/// docs/27 §4: gerçek in-memory SQLite.
///
/// Kritik invariant: `is_default` **yalnızca bir kayıtta** `true` olabilir
/// (docs/04 §3.4).
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

  group('BR-VAT-001 · REQ-VAT-002 — hiçbir oran SEED EDİLMEZ', () {
    test('temiz kurulumda vat_rates tablosu BOŞTUR', () async {
      expect(await vatRates.countAll(), 0);
      expect(await service.list(), isEmpty);
      expect(await service.defaultRate(), isNull);
      expect(await service.isVatDisabled(), isTrue);
    });

    test('okuma çağrıları kendiliğinden oran ÜRETMEZ', () async {
      await service.list();
      await service.defaultRate();
      await service.isVatDisabled();

      expect(await vatRates.countAll(), 0);
    });

    test('seed kaynağında KDV oranı yazan bir satır YOK', () {
      // Koda gömülü oran yasağı (BR-VAT-001) kaynak seviyesinde de korunur.
      final seed = File('lib/data/db/seed.dart').readAsStringSync();
      expect(seed.toLowerCase(), isNot(contains('vatrate')));
      expect(seed.toLowerCase(), isNot(contains('vat_rate')));
      expect(seed, isNot(contains('basisPoint')));
    });

    test('BR-VAT-005: oran yokken KDV hesabı sıfırdır', () async {
      // Varsayılan oran yoksa KDV `%0` kabul edilir (docs/08 §4).
      expect(await service.defaultRate(), isNull);

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
      final result = await service.create(name: ' ', rateBasisPoints: 2000);
      expect(result.failureOrNull?.code, 'vat_rate_name_required');
      expect(await vatRates.countAll(), 0);
    });

    test('negatif oran reddedilir (CHECK(rate_basis_points >= 0))', () async {
      final result = await service.create(name: 'Hatalı', rateBasisPoints: -1);
      expect(result.failureOrNull?.code, 'vat_rate_invalid');
      expect(await vatRates.countAll(), 0);
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
      expect(await rawDefaultIds(), [first, second]);

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
      expect(await rawDefaultIds(), isEmpty);
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
}
