/// Tedarikçi yönetimi testleri — **BR-SUP-001/002 · REQ-SUP-001/002/004**
///
/// docs/27 §4: gerçek in-memory SQLite. Kapsanan edge case: EC-SUP-001.
library;

import 'dart:io';

import 'package:canteen/application/reference/supplier_service.dart';
import 'package:canteen/core/result/result.dart';
// Drift, `suppliers` satırı için domain modeliyle aynı adlı sınıf üretir.
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart' hide Supplier;
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late SupplierService service;
  late AuditLogsDao auditLogs;
  late int userId;

  setUp(() async {
    db = memoryDatabase();
    auditLogs = AuditLogsDao(db);
    service = SupplierService(
      db: db,
      suppliers: SuppliersDao(db),
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

  group('REQ-SUP-001 — yalnızca ad zorunlu', () {
    test('tedarikçi tek alanla oluşturulur', () async {
      final result = await service.create(
        name: 'Yerel Toptancı',
        userId: userId,
      );
      final id = (result as Ok<int>).value;

      final created = await service.findById(id);
      expect(created!.name, 'Yerel Toptancı');
      expect(created.contactName, isNull);
      expect(created.phone, isNull);
      expect(created.email, isNull);
      expect(created.address, isNull);
      expect(created.note, isNull);
      expect(created.isActive, isTrue);

      final log = (await auditOf(SupplierService.actionCreated)).single;
      expect(log.entityType, SupplierService.auditEntityType);
      expect(log.entityId, id);
      expect(log.userId, userId);
    });

    test('opsiyonel alanlar birlikte kaydedilir', () async {
      final id =
          (await service.create(
                    name: 'Toptancı',
                    contactName: 'Ayşe Yılmaz',
                    phone: '0212 000 00 00',
                    email: 'ayse@example.com',
                    address: 'Merkez Mah.',
                    note: 'Salı günleri gelir',
                  )
                  as Ok<int>)
              .value;

      final created = await service.findById(id);
      expect(created!.contactName, 'Ayşe Yılmaz');
      expect(created.phone, '0212 000 00 00');
      expect(created.email, 'ayse@example.com');
      expect(created.address, 'Merkez Mah.');
      expect(created.note, 'Salı günleri gelir');
    });

    test('boş metin alanları null olarak kaydedilir', () async {
      final id =
          (await service.create(name: 'Toptancı', phone: '   ', note: '')
                  as Ok<int>)
              .value;

      final created = await service.findById(id);
      expect(created!.phone, isNull);
      expect(created.note, isNull);
    });

    test('ad boşsa reddedilir', () async {
      final result = await service.create(name: '  ');
      expect(result.failureOrNull?.code, 'supplier_name_required');
      expect(await service.list(), isEmpty);
    });

    test('aynı ad iki kez kullanılabilir — şemada UNIQUE kısıtı yok', () async {
      // docs/05 §2.3: `suppliers` tablosunda ad üzerinde benzersizlik yoktur.
      expect((await service.create(name: 'Toptancı')).isOk, isTrue);
      expect((await service.create(name: 'Toptancı')).isOk, isTrue);
      expect(await service.list(), hasLength(2));
    });
  });

  group('Güncelleme — docs/10 §2.1 "tüm alanlar"', () {
    test('audit YALNIZCA değişen alanları taşır (docs/18 §2)', () async {
      final id =
          (await service.create(
                    name: 'Toptancı',
                    phone: '0212 000 00 00',
                    note: 'eski not',
                  )
                  as Ok<int>)
              .value;

      final result = await service.update(
        id,
        name: 'Toptancı',
        phone: '0212 111 11 11',
        note: 'eski not',
        userId: userId,
      );

      expect(result.isOk, isTrue);
      expect((await service.findById(id))!.phone, '0212 111 11 11');

      final log = (await auditOf(SupplierService.actionUpdated)).single;
      expect(log.oldValue, '{"phone":"0212 000 00 00"}');
      expect(log.newValue, '{"phone":"0212 111 11 11"}');
    });

    test('opsiyonel alan null verilerek temizlenir', () async {
      final id =
          (await service.create(name: 'Toptancı', note: 'not') as Ok<int>)
              .value;

      expect((await service.update(id, name: 'Toptancı')).isOk, isTrue);
      expect((await service.findById(id))!.note, isNull);
    });

    test('hiçbir alan değişmediyse audit yazılmaz', () async {
      final id = (await service.create(name: 'Toptancı') as Ok<int>).value;
      expect((await service.update(id, name: 'Toptancı')).isOk, isTrue);
      expect(await auditOf(SupplierService.actionUpdated), isEmpty);
    });

    test('boş ad reddedilir', () async {
      final id = (await service.create(name: 'Toptancı') as Ok<int>).value;
      expect(
        (await service.update(id, name: ' ')).failureOrNull?.code,
        'supplier_name_required',
      );
    });

    test('olmayan tedarikçi', () async {
      expect(
        (await service.update(9999, name: 'X')).failureOrNull?.code,
        'supplier_not_found',
      );
    });
  });

  group('EC-SUP-001 — pasifleştirme bağlı ürünleri ETKİLEMEZ', () {
    test('ürünlerin supplier_id bağı ve durumu korunur', () async {
      final id = (await service.create(name: 'Toptancı') as Ok<int>).value;

      final productIds = [
        for (var i = 0; i < 3; i++)
          await insertTestProduct(db, name: 'Ürün $i'),
      ];
      for (final productId in productIds) {
        await (db.update(db.products)..where((p) => p.id.equals(productId)))
            .write(ProductsCompanion(supplierId: Value(id)));
      }

      final before = await (db.select(
        db.products,
      )..where((p) => p.supplierId.equals(id))).get();
      expect(before, hasLength(3));

      expect(await service.productCount(id), 3);
      expect((await service.deactivate(id, userId: userId)).isOk, isTrue);

      final after = await (db.select(
        db.products,
      )..where((p) => p.supplierId.equals(id))).get();

      expect((await service.findById(id))!.isActive, isFalse);
      expect(after, hasLength(3));
      for (final product in after) {
        expect(product.isActive, isTrue);
        expect(product.supplierId, id);
      }
      expect(after.map((p) => p.toString()), before.map((p) => p.toString()));

      final log = (await auditOf(SupplierService.actionDeactivated)).single;
      expect(log.entityId, id);
    });

    test('pasif tedarikçi listeden filtrelenebilir', () async {
      final id = (await service.create(name: 'Toptancı') as Ok<int>).value;
      await service.deactivate(id);

      expect((await service.list()).map((s) => s.id), contains(id));
      expect(
        (await service.list(onlyActive: true)).map((s) => s.id),
        isNot(contains(id)),
      );
    });

    test('zaten pasifse audit yinelenmez', () async {
      final id = (await service.create(name: 'Toptancı') as Ok<int>).value;
      await service.deactivate(id);
      await service.deactivate(id);

      expect(await auditOf(SupplierService.actionDeactivated), hasLength(1));
    });
  });

  group('BR-SUP-002 · REQ-SUP-002 — tedarikçi SİLİNEMEZ', () {
    /// Kural bir runtime kontrolü değil, **var olmayan bir metottur**: bir
    /// silme çağrısı derlenmemelidir. Bu yüzden doğrulama yapısaldır —
    /// kaynak dosyalar taranır ve silme anlamına gelebilecek bir üye
    /// bulunmadığı gösterilir. `dart:mirrors` Flutter'da yoktur; kaynak
    /// taraması aynı soruyu deterministik olarak yanıtlar.
    ///
    /// Aynı yaklaşımın örneği: `test/application/auth/secret_leak_scan_test.dart`.
    const forbidden = ['delete', 'deleteById', 'remove', 'purge', 'destroy'];

    String readSource(String path) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: '$path bulunamadı.');
      return file.readAsStringSync();
    }

    /// `Future<...> delete(` gibi bir **bildirim** arar; yorum satırlarındaki
    /// geçişleri saymaz.
    bool declaresMember(String source, String member) => RegExp(
      r'^\s*(?!///)[\w<>,\s\?]*\b' + member + r'\s*\(',
      multiLine: true,
    ).hasMatch(source);

    void expectNoDeclaration(String source, String member, String where) {
      expect(
        declaresMember(source, member),
        isFalse,
        reason: 'BR-SUP-002: $where içinde "$member" bildirimi olmamalı.',
      );
    }

    /// Pozitif kontrol: taramanın gerçekten bildirim bulabildiğini kanıtlar.
    /// Aksi hâlde bozuk bir regex "silme metodu yok" diye sessizce geçerdi.
    void expectDeclaration(String source, String member, String where) {
      expect(
        declaresMember(source, member),
        isTrue,
        reason: 'Tarama bozuk: $where içinde "$member" bulunmalıydı.',
      );
    }

    test('SupplierService silme metodu SUNMAZ', () {
      final source = readSource(
        'lib/application/reference/supplier_service.dart',
      );
      for (final member in forbidden) {
        expectNoDeclaration(source, member, 'SupplierService');
      }
      // Pasifleştirme yolu ise mevcut olmalıdır (aynı zamanda pozitif kontrol).
      expectDeclaration(source, 'deactivate', 'SupplierService');
    });

    test('SuppliersDao silme metodu SUNMAZ', () {
      final source = readSource('lib/data/dao/daos.dart');
      final start = source.indexOf('class SuppliersDao');
      final end = source.indexOf('class VatRatesDao');
      expect(start, greaterThan(0));
      expect(end, greaterThan(start));

      final daoSource = source.substring(start, end);
      for (final member in forbidden) {
        expectNoDeclaration(daoSource, member, 'SuppliersDao');
      }
      expectDeclaration(daoSource, 'setActive', 'SuppliersDao');
    });

    test('Tedarikçi tablosuna DELETE yazan başka bir kod yolu yok', () {
      // `delete(suppliers)` Drift'te tek silme yoludur; kaynak ağacında hiç
      // bulunmamalıdır.
      final offenders = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.readAsStringSync().contains('delete(suppliers)')) {
          offenders.add(entity.path);
        }
      }
      expect(offenders, isEmpty, reason: 'BR-SUP-002 ihlali: $offenders');
    });
  });
}
