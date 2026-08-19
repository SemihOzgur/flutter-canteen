/// Ürün arama ve sayfalama testleri —
/// **REQ-PROD-010 · REQ-PERF-006 · docs/09 §6**
///
/// Arama Türkçe karakter ve büyük/küçük harf duyarsızdır; sonuçlar satış
/// adedine göre sıralanır ve en fazla 50 satır döner.
library;

import 'package:canteen/application/product/product_draft.dart';
import 'package:canteen/application/product/product_service.dart';
import 'package:canteen/application/stock/stock_service.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart' hide Category, Product;
import 'package:canteen/data/repositories/drift_product_repository.dart';
import 'package:canteen/data/repositories/drift_stock_repository.dart';
import 'package:canteen/domain/enums/sale_status.dart';
import 'package:canteen/domain/services/product_rules.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late ProductService service;
  late int userId;

  setUp(() async {
    db = memoryDatabase();
    final stock = DriftStockRepository(db);
    service = ProductService(
      db: db,
      products: DriftProductRepository(db),
      stock: stock,
      stockService: StockService(
        db: db,
        stock: stock,
        clock: () => testEpochUtc,
      ),
      categories: CategoriesDao(db),
      saleItems: SaleItemsDao(db),
      auditLogs: AuditLogsDao(db),
      clock: () => testEpochUtc,
    );
    userId = await insertTestUser(db);
  });

  tearDown(() async => db.close());

  Future<int> create(String name, {String? brand, int? categoryId}) async {
    final result = await service.create(
      ProductDraft(
        name: name,
        brand: brand,
        categoryId: categoryId,
        salePrice: const Money(1000),
      ),
      userId: userId,
    );
    return (result as Ok<ProductSaveOutcome>).value.productId;
  }

  /// Ürüne satış geçmişi ekler — sıralama ölçütü budur (docs/09 §6).
  Future<void> sell(
    int productId, {
    required int quantity,
    SaleStatus status = SaleStatus.completed,
    int returnedQuantity = 0,
    String saleNumber = '2026-000001',
  }) async {
    final saleId = await db
        .into(db.sales)
        .insert(
          SalesCompanion.insert(
            saleNumber: saleNumber,
            status: status,
            subtotalMinor: 1000,
            vatTotalMinor: 0,
            grandTotalMinor: 1000,
            costTotalMinor: 0,
            itemCount: 1,
            unitCount: quantity,
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
            productNameSnapshot: 'snapshot',
            quantity: quantity,
            unitPriceMinor: 1000,
            originalUnitPriceMinor: 1000,
            purchasePriceSnapshotMinor: 0,
            vatRateSnapshotBp: 0,
            lineNetMinor: 1000,
            lineVatMinor: 0,
            lineTotalMinor: 1000,
            returnedQuantity: Value(returnedQuantity),
          ),
        );
  }

  Future<List<String>> search(String query, {int? limit}) async {
    final results = limit == null
        ? await service.search(query)
        : await service.search(query, limit: limit);
    return results.map((p) => p.name).toList();
  }

  // -------------------------------------------------------------------------
  group('REQ-PROD-010 — Türkçe karakter duyarsız', () {
    test('ı/i · ş/s · ğ/g · ü/u · ö/o · ç/c', () async {
      await create('Süt');
      await create('Şeftali Suyu');
      await create('Ayçiçek Yağı');
      await create('Çılbır');

      expect(await search('sut'), ['Süt']);
      expect(await search('seftali'), ['Şeftali Suyu']);
      expect(await search('yagi'), ['Ayçiçek Yağı']);
      expect(await search('cilbir'), ['Çılbır']);
    });

    test('ters yön: Türkçe yazılan sorgu düz metni bulur', () async {
      await create('Sut Kutusu');
      expect(await search('süt'), ['Sut Kutusu']);
    });

    test('büyük/küçük harf duyarsız — IŞIL tuzağı', () async {
      await create('Işıl Gofret');
      expect(await search('ISIL'), ['Işıl Gofret']);
      expect(await search('isil'), ['Işıl Gofret']);
      expect(await search('ışıl'), ['Işıl Gofret']);
    });

    test('kelime ortasında da eşleşir (contains)', () async {
      await create('Beyaz Peynir 500 g');
      expect(await search('peynir'), ['Beyaz Peynir 500 g']);
    });
  });

  group('docs/09 §6 — kapsam ve sıralama', () {
    test('markada da aranır; ad eşleşmeleri ÖNCE gelir', () async {
      await create('Gazoz', brand: 'Ülker');
      await create('Ülker Çikolata', brand: 'Başka');

      expect(await search('ulker'), ['Ülker Çikolata', 'Gazoz']);
    });

    test('sonuçlar satış adedine göre sıralanır', () async {
      final az = await create('Kola Az Satan');
      final cok = await create('Kola Çok Satan');

      await sell(az, quantity: 2, saleNumber: '2026-000001');
      await sell(cok, quantity: 40, saleNumber: '2026-000002');

      expect(await search('kola'), ['Kola Çok Satan', 'Kola Az Satan']);
    });

    test('İPTAL edilmiş satış ürünü öne taşımaz', () async {
      final cancelled = await create('Kola A');
      final real = await create('Kola B');

      await sell(
        cancelled,
        quantity: 99,
        status: SaleStatus.cancelled,
        saleNumber: '2026-000001',
      );
      await sell(real, quantity: 1, saleNumber: '2026-000002');

      expect(await search('kola'), ['Kola B', 'Kola A']);
    });

    test('iade edilen adetler sıralamadan düşülür', () async {
      final returned = await create('Kola A');
      final kept = await create('Kola B');

      await sell(
        returned,
        quantity: 10,
        returnedQuantity: 10,
        saleNumber: '2026-000001',
      );
      await sell(kept, quantity: 3, saleNumber: '2026-000002');

      expect(await search('kola'), ['Kola B', 'Kola A']);
    });

    test('satışı olmayan ürünler ada göre sıralanır', () async {
      await create('Kola C');
      await create('Kola A');
      await create('Kola B');

      expect(await search('kola'), ['Kola A', 'Kola B', 'Kola C']);
    });

    test('pasif ürünler aramada görünmez (docs/09 §4)', () async {
      final id = await create('Kola Eski');
      await create('Kola Yeni');
      await service.deactivate(id, userId: userId);

      expect(await search('kola'), ['Kola Yeni']);
    });

    test('varsayılan sınır 50 sonuçtur', () async {
      for (var i = 0; i < 60; i++) {
        await create('Ürün ${i.toString().padLeft(2, '0')}');
      }

      expect(await search('ürün'), hasLength(ProductRules.searchResultLimit));
      expect(await search('ürün', limit: 3), hasLength(3));
    });

    test(
      'boş sorgu boş liste döner (kategori/favori listesi gösterilir)',
      () async {
        await create('Kola');
        expect(await search(''), isEmpty);
        expect(await search('   '), isEmpty);
      },
    );

    test('LIKE joker karakterleri kaçışlanır', () async {
      await create('Kola');
      await create('%100 Meyve Suyu');

      // Tek başına `%` bütün kataloğu döndürmemeli.
      expect(await search('%'), ['%100 Meyve Suyu']);
      expect(await search('_'), isEmpty);
      expect(await search('%100'), ['%100 Meyve Suyu']);
    });

    test('eşleşme yoksa boş liste', () async {
      await create('Kola');
      expect(await search('bulunmayan'), isEmpty);
    });
  });

  group('REQ-PERF-006 — sayfalama', () {
    test('list limit/offset uygular ve ada göre sıralar', () async {
      for (var i = 0; i < 5; i++) {
        await create('P$i');
      }

      expect((await service.list(limit: 2)).map((p) => p.name), ['P0', 'P1']);
      expect((await service.list(limit: 2, offset: 2)).map((p) => p.name), [
        'P2',
        'P3',
      ]);
      expect(await service.list(limit: 2, offset: 4), hasLength(1));
      expect(await service.list(limit: 2, offset: 10), isEmpty);
    });

    test('count sayfa göstergesini besler', () async {
      for (var i = 0; i < 7; i++) {
        await create('P$i');
      }
      expect(await service.count(), 7);
      expect(await service.list(limit: 3), hasLength(3));
    });

    test('pasifler varsayılan olarak gizlidir', () async {
      final id = await create('Eski');
      await create('Yeni');
      await service.deactivate(id, userId: userId);

      expect(await service.count(), 1);
      expect(await service.count(includeInactive: true), 2);
    });

    test('kategori filtresi', () async {
      final other = await CategoriesDao(
        db,
      ).insertCategory(name: 'İçecek', sortOrder: 1, now: testEpochUtc);
      await create('Genel Ürün');
      await create('İçecek Ürün', categoryId: other);

      expect((await service.list(categoryId: other)).map((p) => p.name), [
        'İçecek Ürün',
      ]);
      expect(await service.count(categoryId: other), 1);
    });
  });

  test('barkod ile bulma — normalize edilerek aranır', () async {
    final id = await create('Kola');
    await service.addBarcode(id, '0123456789012', userId: userId);

    expect((await service.findByBarcode(' 0123456789012 '))!.id, id);
    expect(await service.findByBarcode('123456789012'), isNull);
    expect(await service.findByBarcode(''), isNull);
  });
}
