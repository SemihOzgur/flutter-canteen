/// Kategori yönetimi testleri — **BR-CAT-001…005 · REQ-CAT-001/002/003/005/006**
///
/// docs/27 §4: gerçek in-memory SQLite üzerinde çalışır; mock veritabanı yoktur.
///
/// Kapsanan edge case'ler: EC-CAT-001 · EC-CAT-002 · EC-CAT-003 · EC-CAT-005 ·
/// EC-CAT-006.
///
/// ## Kapsanan requirement'lar (Faz 11 izlenebilirliği)
///
/// - **REQ-CAT-002** — `Genel` kategorisi korumalıdır
library;

import 'package:canteen/application/reference/category_failures.dart';
import 'package:canteen/application/reference/category_service.dart';
import 'package:canteen/core/result/result.dart';
// Drift, `categories` satırı için domain modeliyle aynı adlı sınıf üretir.
// Testin ilgilendiği tip DOMAIN tipidir.
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart' hide Category;
import 'package:canteen/data/db/seed.dart';
import 'package:canteen/domain/enums/sale_status.dart';
// Yalnızca `Value` gerekir; drift'in tamamı `isNull`/`isNotNull` matcher'larıyla
// çakışır.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late CategoryService service;

  /// Kategorinin veritabanındaki `icon_key` değeri.
  Future<String?> iconOf(int id) async => (await (db.select(
    db.categories,
  )..where((c) => c.id.equals(id))).getSingle()).iconKey;
  late AuditLogsDao auditLogs;
  late int userId;

  setUp(() async {
    db = memoryDatabase();
    final categories = CategoriesDao(db);
    auditLogs = AuditLogsDao(db);
    service = CategoryService(
      db: db,
      categories: categories,
      auditLogs: auditLogs,
      clock: () => testEpochUtc,
    );
    userId = await insertTestUser(db);
  });

  tearDown(() async => db.close());

  Future<int> systemCategoryId() async => (await service.systemCategory())!.id;

  Future<List<AuditLog>> auditOf(String action) async {
    final logs = await auditLogs.listRecent();
    return logs.where((log) => log.action == action).toList();
  }

  /// Satış satırı snapshot'ı üretir — EC-CAT-006 kurulumu.
  ///
  /// `sale_items.category_id_snapshot` satış anındaki kategoriyi taşır
  /// (rules/02 §3, SNAPSHOT 2/5).
  Future<void> insertSaleItemWithCategorySnapshot({
    required int categoryIdSnapshot,
    required int productId,
  }) async {
    final saleId = await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            saleNumber: '2026-000001',
            status: SaleStatus.completed,
            subtotalMinor: 10000,
            vatTotalMinor: 2000,
            grandTotalMinor: 12000,
            costTotalMinor: 8000,
            itemCount: 1,
            unitCount: 1,
            userId: userId,
            completedAt: testEpochUtc,
            createdAt: testEpochUtc,
            updatedAt: testEpochUtc,
          ),
        );

    await db
        .into(db.saleItems)
        .insert(
          SaleItemsCompanion.insert(
            saleId: saleId,
            productId: productId,
            productNameSnapshot: 'Satış Anındaki Ad',
            categoryIdSnapshot: Value(categoryIdSnapshot),
            quantity: 1,
            unitPriceMinor: 12000,
            originalUnitPriceMinor: 12000,
            purchasePriceSnapshotMinor: 8000,
            vatRateSnapshotBp: 2000,
            lineNetMinor: 10000,
            lineVatMinor: 2000,
            lineTotalMinor: 12000,
          ),
        );
  }

  group('OD-029 · REQ-CAT-008 — kategori ikonu', () {
    test('oluştururken ikon seçilebilir', () async {
      final result = await service.create(
        name: 'Soğuk İçecek',
        userId: userId,
        iconKey: 'drink',
      );

      expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
      final id = (result as Ok<int>).value;
      expect(await iconOf(id), 'drink');
    });

    test('ikon seçilmezse NULL kalır — "otomatik"', () async {
      final result = await service.create(name: 'Raf 3', userId: userId);
      final id = (result as Ok<int>).value;

      expect(
        await iconOf(id),
        isNull,
        reason: 'Varsayılan bir ikon atanırsa "otomatik" davranış kaybolur.',
      );
    });

    test('KATALOG DIŞI anahtar reddedilir — oluşturmada', () async {
      // Katalog dışı bir anahtar veritabanına girerse hiçbir ekranda ikon
      // göstermez ve kullanıcı nedenini anlayamaz.
      final result = await service.create(
        name: 'Deneme',
        userId: userId,
        iconKey: 'uydurma',
      );

      expect(result.failureOrNull, CategoryFailures.unknownIcon);
      expect(await service.list(), hasLength(1), reason: 'Yalnızca Genel.');
    });

    test('KATALOG DIŞI anahtar reddedilir — güncellemede', () async {
      final id =
          (await service.create(name: 'Deneme', userId: userId) as Ok<int>)
              .value;

      final result = await service.setIcon(id, 'uydurma');

      expect(result.failureOrNull, CategoryFailures.unknownIcon);
      expect(await iconOf(id), isNull, reason: 'Yazım yapılmamalıdır.');
    });

    test('ikon değiştirilebilir ve KALDIRILABİLİR', () async {
      final id =
          (await service.create(
                    name: 'Deneme',
                    userId: userId,
                    iconKey: 'snack',
                  )
                  as Ok<int>)
              .value;

      expect((await service.setIcon(id, 'sweet')).isErr, isFalse);
      expect(await iconOf(id), 'sweet');

      // `null` = "otomatik"e dön.
      expect((await service.setIcon(id, null)).isErr, isFalse);
      expect(await iconOf(id), isNull);
    });

    test('olmayan kategori reddedilir', () async {
      expect(
        (await service.setIcon(9999, 'drink')).failureOrNull,
        CategoryFailures.notFound,
      );
    });

    test('BR-CAT-004 — `Genel`in İKONU değiştirilebilir', () async {
      // Koruma ad, silme ve pasifleştirme içindir; ikon o listede yoktur
      // (docs/10 §1.2a).
      final general = (await service.list()).single;
      expect(general.isSystem, isTrue);

      final result = await service.setIcon(general.id, 'other');

      expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
      expect(await iconOf(general.id), 'other');
    });

    test('ikon değişikliği DENETİM İZİNE yazılmaz', () async {
      // rules/03 §9 denetlenecek mutation'ları sayar; ikon iş verisi
      // değildir ve izi gürültüyle doldurmamalıdır (docs/10 §1.2a).
      final id =
          (await service.create(name: 'Deneme', userId: userId) as Ok<int>)
              .value;
      final before = (await AuditLogsDao(db).listRecent()).length;

      await service.setIcon(id, 'drink');

      expect((await AuditLogsDao(db).listRecent()).length, before);
    });
  });

  group('Oluşturma — REQ-CAT-001 · REQ-CAT-005', () {
    test('kategori oluşturulur ve audit kaydı yazılır', () async {
      final result = await service.create(name: 'İçecek', userId: userId);
      final id = (result as Ok<int>).value;

      final created = await service.findById(id);
      expect(created!.name, 'İçecek');
      expect(created.isActive, isTrue);
      expect(created.isSystem, isFalse);

      final logs = await auditOf(CategoryService.actionCreated);
      expect(logs.single.entityType, CategoryService.auditEntityType);
      expect(logs.single.entityId, id);
      expect(logs.single.userId, userId);
    });

    test('ad boşsa reddedilir', () async {
      final result = await service.create(name: '   ');
      expect(result.failureOrNull?.code, 'category_name_required');
      // Yalnızca `Genel` kalır.
      expect((await service.list()).length, 1);
    });

    test('ad baştaki/sondaki boşluklardan arındırılır', () async {
      final result = await service.create(name: '  Atıştırmalık  ');
      final created = await service.findById((result as Ok<int>).value);
      expect(created!.name, 'Atıştırmalık');
    });

    test('REQ-CAT-005: aynı ad ikinci kez kullanılamaz', () async {
      await service.create(name: 'İçecek');
      final second = await service.create(name: 'İçecek');

      expect(second.failureOrNull?.code, 'category_name_exists');
      expect((await service.list()).where((c) => c.name == 'İçecek').length, 1);
      expect(await auditOf(CategoryService.actionCreated), hasLength(1));
    });

    test(
      'büyük/küçük harf katlaması YOKTUR — şemadaki UNIQUE(name) ne diyorsa o',
      () async {
        // docs/05 §2.2 `UNIQUE(name)` harfe duyarlıdır; katlama bir ŞEMA
        // kararı olurdu ve dokümanda yoktur (rules/00 §5.2/2).
        await service.create(name: 'İçecek');
        final other = await service.create(name: 'içecek');
        expect(other.isOk, isTrue);
      },
    );

    test('sıralama değeri yazılır ve liste sort_order ile sıralanır', () async {
      await service.create(name: 'Z-Kategori', sortOrder: 1);
      await service.create(name: 'A-Kategori', sortOrder: 5);

      final names = (await service.list()).map((c) => c.name).toList();
      // `Genel` sortOrder 0 (seed), sonra 1, sonra 5.
      expect(names, [Seed.generalCategoryName, 'Z-Kategori', 'A-Kategori']);
    });
  });

  group('EC-CAT-003 — pasif kategorinin adı yeniden kullanılamaz', () {
    test('pasifleştirilen ad yeni kategoriye verilemez', () async {
      final id = (await service.create(name: 'Şekerleme') as Ok<int>).value;
      expect((await service.deactivate(id)).isOk, isTrue);

      final again = await service.create(name: 'Şekerleme');

      expect(again.failureOrNull?.code, 'category_name_exists');
      expect(
        again.failureOrNull?.userMessage,
        contains('Pasif kategoriler de aynı adı kullanamaz'),
      );
    });

    test(
      'pasif kategorinin adı başka kategoriye rename ile de verilemez',
      () async {
        final passive =
            (await service.create(name: 'Şekerleme') as Ok<int>).value;
        await service.deactivate(passive);
        final other = (await service.create(name: 'İçecek') as Ok<int>).value;

        final result = await service.rename(other, 'Şekerleme');
        expect(result.failureOrNull?.code, 'category_name_exists');
      },
    );
  });

  group('Yeniden adlandırma — REQ-CAT-001', () {
    test('ad değişir ve audit yalnızca DEĞİŞEN alanı taşır', () async {
      final id = (await service.create(name: 'İçecek') as Ok<int>).value;

      expect(
        (await service.rename(id, 'Soğuk İçecek', userId: userId)).isOk,
        isTrue,
      );
      expect((await service.findById(id))!.name, 'Soğuk İçecek');

      final log = (await auditOf(CategoryService.actionRenamed)).single;
      expect(log.oldValue, '{"name":"İçecek"}');
      expect(log.newValue, '{"name":"Soğuk İçecek"}');
    });

    test('aynı ad verilirse veri ve audit değişmez', () async {
      final id = (await service.create(name: 'İçecek') as Ok<int>).value;
      expect((await service.rename(id, 'İçecek')).isOk, isTrue);
      expect(await auditOf(CategoryService.actionRenamed), isEmpty);
    });

    test('boş ad reddedilir', () async {
      final id = (await service.create(name: 'İçecek') as Ok<int>).value;
      expect(
        (await service.rename(id, '  ')).failureOrNull?.code,
        'category_name_required',
      );
    });

    test('olmayan kategori', () async {
      expect(
        (await service.rename(9999, 'X')).failureOrNull?.code,
        'category_not_found',
      );
    });
  });

  group('BR-CAT-003 — pasifleştirme ürünlere DOKUNMAZ', () {
    test('REQ-CAT-003: bağlı ürünler aktif ve satılabilir kalır', () async {
      final id = (await service.create(name: 'İçecek') as Ok<int>).value;
      final productIds = [
        for (var i = 0; i < 3; i++)
          await insertTestProduct(db, name: 'Ürün $i', categoryId: id),
      ];

      final before = await (db.select(
        db.products,
      )..where((p) => p.categoryId.equals(id))).get();

      expect((await service.deactivate(id, userId: userId)).isOk, isTrue);

      final after = await (db.select(
        db.products,
      )..where((p) => p.categoryId.equals(id))).get();

      expect((await service.findById(id))!.isActive, isFalse);
      expect(after, hasLength(3));
      // Satır satır karşılaştırma: hiçbir ürün alanı değişmemiştir.
      for (final product in after) {
        expect(product.isActive, isTrue);
        expect(product.categoryId, id);
      }
      expect(after.map((p) => p.toString()), before.map((p) => p.toString()));
      expect(productIds, after.map((p) => p.id).toList());
    });

    test('EC-CAT-002: içinde ürün olsa bile pasifleştirilebilir', () async {
      final id = (await service.create(name: 'İçecek') as Ok<int>).value;
      for (var i = 0; i < 5; i++) {
        await insertTestProduct(db, name: 'Ürün $i', categoryId: id);
      }

      expect(await service.productCount(id), 5);
      expect((await service.deactivate(id)).isOk, isTrue);
    });

    test('pasif kategori listeden filtrelenebilir (docs/10 §1.3)', () async {
      final id = (await service.create(name: 'İçecek') as Ok<int>).value;
      await service.deactivate(id);

      expect((await service.list()).map((c) => c.id), contains(id));
      expect(
        (await service.list(onlyActive: true)).map((c) => c.id),
        isNot(contains(id)),
      );
    });

    test('zaten pasifse audit yinelenmez', () async {
      final id = (await service.create(name: 'İçecek') as Ok<int>).value;
      await service.deactivate(id);
      await service.deactivate(id);

      expect(await auditOf(CategoryService.actionDeactivated), hasLength(1));
    });
  });

  group('EC-CAT-001 · BR-CAT-004 — `Genel` sistem kategorisi korunur', () {
    test('adı DEĞİŞTİRİLEMEZ', () async {
      final id = await systemCategoryId();
      final result = await service.rename(id, 'Başka Ad');

      expect(result.failureOrNull?.code, 'category_system_protected');
      expect((await service.findById(id))!.name, Seed.generalCategoryName);
      expect(await auditOf(CategoryService.actionRenamed), isEmpty);
    });

    test('PASİFLEŞTİRİLEMEZ', () async {
      final id = await systemCategoryId();
      final result = await service.deactivate(id);

      expect(result.failureOrNull?.code, 'category_system_protected');
      expect((await service.findById(id))!.isActive, isTrue);
      expect(await auditOf(CategoryService.actionDeactivated), isEmpty);
    });

    test('SİLİNEMEZ — hiç kullanılmamış olsa bile', () async {
      final id = await systemCategoryId();
      expect(await service.productCount(id), 0);

      final result = await service.delete(id);

      expect(result.failureOrNull?.code, 'category_system_protected');
      expect(await service.findById(id), isNotNull);
      expect(await auditOf(CategoryService.actionDeleted), isEmpty);
    });
  });

  group('EC-CAT-005 — hiç kullanılmamış kategori kalıcı silinir', () {
    test('BR-CAT-005: kayıt silinir ve audit adı taşır', () async {
      final id = (await service.create(name: 'Kırtasiye') as Ok<int>).value;

      final result = await service.delete(id, userId: userId);

      expect(result.isOk, isTrue);
      expect(await service.findById(id), isNull);

      final log = (await auditOf(CategoryService.actionDeleted)).single;
      expect(log.entityId, id);
      expect(log.metadata, '{"name":"Kırtasiye"}');
      expect(log.userId, userId);
    });

    test('silinen ad tekrar kullanılabilir — kayıt gerçekten yok', () async {
      final id = (await service.create(name: 'Kırtasiye') as Ok<int>).value;
      await service.delete(id);

      expect((await service.create(name: 'Kırtasiye')).isOk, isTrue);
    });

    test('olmayan kategori silinemez', () async {
      expect(
        (await service.delete(9999)).failureOrNull?.code,
        'category_not_found',
      );
    });
  });

  group('BR-CAT-002 — kullanımdaki kategori kalıcı SİLİNMEZ', () {
    test(
      'ürünü olan kategori silinmez; pasifleştirmeye yönlendirilir',
      () async {
        final id = (await service.create(name: 'İçecek') as Ok<int>).value;
        await insertTestProduct(db, categoryId: id);

        final result = await service.delete(id);

        expect(result.failureOrNull?.code, 'category_in_use');
        expect(
          result.failureOrNull?.userMessage,
          contains('pasife alabilirsiniz'),
        );
        expect(await service.findById(id), isNotNull);
        expect(await auditOf(CategoryService.actionDeleted), isEmpty);
      },
    );

    test('PASİF ürünü olan kategori de silinmez (docs/10 §1.2b)', () async {
      final id = (await service.create(name: 'İçecek') as Ok<int>).value;
      final productId = await insertTestProduct(db, categoryId: id);
      await (db.update(db.products)..where((p) => p.id.equals(productId)))
          .write(const ProductsCompanion(isActive: Value(false)));

      expect((await service.delete(id)).failureOrNull?.code, 'category_in_use');
    });
  });

  group('EC-CAT-006 — satış snapshot\'ında geçen kategori SİLİNMEZ', () {
    test(
      'ürünü kalmasa bile sale_items.category_id_snapshot silmeyi engeller',
      () async {
        final id = (await service.create(name: 'Şekerleme') as Ok<int>).value;

        // Ürün BAŞKA bir kategoriye bağlı: kategoriye atanmış ürün yoktur.
        final systemId = await systemCategoryId();
        final productId = await insertTestProduct(db, categoryId: systemId);

        // Ama geçmiş satış satırı bu kategorinin snapshot'ını taşıyor.
        await insertSaleItemWithCategorySnapshot(
          categoryIdSnapshot: id,
          productId: productId,
        );

        expect(await service.productCount(id), 0);

        final result = await service.delete(id);

        // Kalıcı silme SUNULMAZ — geçmiş kategori raporu bozulurdu.
        expect(result.failureOrNull?.code, 'category_in_use');
        expect(
          result.failureOrNull?.userMessage,
          contains('geçmiş satışlarda kullanılmış'),
        );
        expect(await service.findById(id), isNotNull);
        expect(await auditOf(CategoryService.actionDeleted), isEmpty);

        // Snapshot bozulmadı (rules/02 §3 — snapshot immutable).
        final item = await db.select(db.saleItems).getSingle();
        expect(item.categoryIdSnapshot, id);
      },
    );

    test('aynı kategori pasifleştirilebilir — önerilen yol budur', () async {
      final id = (await service.create(name: 'Şekerleme') as Ok<int>).value;
      final systemId = await systemCategoryId();
      final productId = await insertTestProduct(db, categoryId: systemId);
      await insertSaleItemWithCategorySnapshot(
        categoryIdSnapshot: id,
        productId: productId,
      );

      expect((await service.deactivate(id)).isOk, isTrue);
      expect((await service.findById(id))!.isActive, isFalse);
    });
  });

  group('Sıralama', () {
    test('sort_order güncellenir', () async {
      final id = (await service.create(name: 'İçecek') as Ok<int>).value;
      expect((await service.updateSortOrder(id, 7)).isOk, isTrue);
      expect((await service.findById(id))!.sortOrder, 7);
    });

    test('olmayan kategoride hata döner', () async {
      expect(
        (await service.updateSortOrder(9999, 1)).failureOrNull?.code,
        'category_not_found',
      );
    });
  });

  group('REQ-CAT-004 · OD-018 — ürünleri başka kategoriye taşıma', () {
    test('tüm ürünler taşınır ve TEK audit kaydı yazılır', () async {
      final from = (await service.create(name: 'Şekerleme') as Ok<int>).value;
      final to = (await service.create(name: 'Atıştırmalık') as Ok<int>).value;
      for (var i = 0; i < 3; i++) {
        await insertTestProduct(db, name: 'Ürün $i', categoryId: from);
      }

      final result = await service.moveProducts(
        fromCategoryId: from,
        toCategoryId: to,
        userId: userId,
      );

      expect((result as Ok<int>).value, 3);

      final moved = await (db.select(
        db.products,
      )..where((pr) => pr.categoryId.equals(to))).get();
      expect(moved, hasLength(3));
      expect(
        await (db.select(
          db.products,
        )..where((pr) => pr.categoryId.equals(from))).get(),
        isEmpty,
      );

      final logs = await auditOf(CategoryService.actionProductsMoved);
      expect(
        logs,
        hasLength(1),
        reason: 'docs/10 §1.4: ürün başına değil, TEK toplu kayıt.',
      );
      expect(logs.single.metadata, contains('"product_count":3'));
      expect(logs.single.metadata, contains('Atıştırmalık'));
    });

    test(
      'geçmiş satış snapshot\'ı DEĞİŞMEZ — BR-VAT-004 · rules/02 §3',
      () async {
        final from = (await service.create(name: 'Şekerleme') as Ok<int>).value;
        final to =
            (await service.create(name: 'Atıştırmalık') as Ok<int>).value;
        final productId = await insertTestProduct(db, categoryId: from);
        await insertSaleItemWithCategorySnapshot(
          categoryIdSnapshot: from,
          productId: productId,
        );

        await service.moveProducts(fromCategoryId: from, toCategoryId: to);

        final item = await db.select(db.saleItems).getSingle();
        expect(
          item.categoryIdSnapshot,
          from,
          reason:
              'Geçmiş kategori raporu taşımadan etkilenmemelidir — snapshot '
              'satış anındaki kategoriyi taşır.',
        );
      },
    );

    test('EC-CAT-004: hata durumunda HİÇBİR ürün taşınmaz', () async {
      final from = (await service.create(name: 'Şekerleme') as Ok<int>).value;
      await insertTestProduct(db, categoryId: from);

      // Var olmayan hedef: taşıma yazılmadan önce reddedilmelidir.
      final result = await service.moveProducts(
        fromCategoryId: from,
        toCategoryId: 9999,
      );

      expect(result.failureOrNull?.code, 'category_not_found');
      expect(
        await (db.select(
          db.products,
        )..where((pr) => pr.categoryId.equals(from))).get(),
        hasLength(1),
        reason: 'Tam rollback: ürünün kategorisi değişmemiş olmalıdır.',
      );
      expect(await auditOf(CategoryService.actionProductsMoved), isEmpty);
    });

    test('pasif kategoriye taşınamaz — docs/10 §1.3', () async {
      final from = (await service.create(name: 'Şekerleme') as Ok<int>).value;
      final to = (await service.create(name: 'Eski') as Ok<int>).value;
      await insertTestProduct(db, categoryId: from);
      await service.deactivate(to);

      final result = await service.moveProducts(
        fromCategoryId: from,
        toCategoryId: to,
      );

      expect(result.failureOrNull?.code, 'category_target_inactive');
      expect(await auditOf(CategoryService.actionProductsMoved), isEmpty);
    });

    test('kaynak ve hedef aynı olamaz', () async {
      final id = (await service.create(name: 'Şekerleme') as Ok<int>).value;

      final result = await service.moveProducts(
        fromCategoryId: id,
        toCategoryId: id,
      );

      expect(result.failureOrNull?.code, 'category_same_target');
    });

    test(
      'PASİF kaynaktan taşımaya izin verilir — docs/10 §1.3 akışı',
      () async {
        final from = (await service.create(name: 'Şekerleme') as Ok<int>).value;
        final to =
            (await service.create(name: 'Atıştırmalık') as Ok<int>).value;
        await insertTestProduct(db, categoryId: from);
        await service.deactivate(from);

        final result = await service.moveProducts(
          fromCategoryId: from,
          toCategoryId: to,
        );

        expect(
          (result as Ok<int>).value,
          1,
          reason:
              'Pasifleştirilmiş kategorinin ürünlerini toparlamak akışın ta '
              'kendisidir.',
        );
      },
    );
  });

  group('REQ-CAT-007 · EC-CAT-007 · OD-020 — yeniden aktifleştirme', () {
    test('pasif kategori yeniden aktifleştirilir ve audit yazılır', () async {
      final id = (await service.create(name: 'Şekerleme') as Ok<int>).value;
      await service.deactivate(id);
      expect((await service.findById(id))!.isActive, isFalse);

      expect((await service.activate(id, userId: userId)).isOk, isTrue);

      expect((await service.findById(id))!.isActive, isTrue);
      expect(await auditOf(CategoryService.actionActivated), hasLength(1));
    });

    test('zaten aktif kayıt audit ÜRETMEZ', () async {
      final id = (await service.create(name: 'Şekerleme') as Ok<int>).value;

      expect((await service.activate(id)).isOk, isTrue);

      expect(await auditOf(CategoryService.actionActivated), isEmpty);
    });

    test('olmayan kategori aktifleştirilemez', () async {
      expect(
        (await service.activate(9999)).failureOrNull?.code,
        'category_not_found',
      );
    });
  });
}
