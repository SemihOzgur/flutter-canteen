/// Favori testleri — **REQ-PROD-009 · BR-PROD-008 · docs/09 §5**
///
/// | Test | Kural |
/// |---|---|
/// | `products.is_favorite` değişir | BR-PROD-008 |
/// | **Ayrı `favorites` tablosu YOKTUR** | rules/02 §11.5 · docs/04 §1 |
/// | 30 üstü favoride uyarı **servisten** gelir | docs/09 §5 · rules/05 §8 |
library;

import 'dart:io';

import 'package:canteen/application/product/product_draft.dart';
import 'package:canteen/application/product/product_service.dart';
import 'package:canteen/application/stock/stock_service.dart';
import 'package:canteen/core/paths/app_paths.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart' hide Product;
import 'package:canteen/data/repositories/drift_product_repository.dart';
import 'package:canteen/data/repositories/drift_stock_repository.dart';
import 'package:canteen/data/files/product_image_store.dart';
import 'package:canteen/domain/services/product_rules.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late ProductService service;
  late int userId;
  late Directory imageRoot;

  setUp(() async {
    // Görsel deposu gerçek bir dizin ister; testler kullanıcı veri dizinine
    // DOKUNMAZ (BR-DATA-001).
    imageRoot = Directory.systemTemp.createTempSync('canteen_fav_');
    db = memoryDatabase();
    final stock = DriftStockRepository(db);
    service = ProductService(
      db: db,
      products: DriftProductRepository(db),
      stock: stock,
      stockService: StockService(
        db: db,
        stock: stock,
        products: DriftProductRepository(db),
        clock: () => testEpochUtc,
      ),
      categories: CategoriesDao(db),
      saleItems: SaleItemsDao(db),
      auditLogs: AuditLogsDao(db),
      appSettings: AppSettingsDao(db),
      images: ProductImageStore(paths: AppPaths(rootPath: imageRoot.path)),
      clock: () => testEpochUtc,
    );
    userId = await insertTestUser(db);
  });

  tearDown(() async {
    await db.close();
    if (imageRoot.existsSync()) imageRoot.deleteSync(recursive: true);
  });

  Future<int> create(String name) async {
    final result = await service.create(
      ProductDraft(name: name, salePrice: const Money(1000)),
      userId: userId,
    );
    return (result as Ok<ProductSaveOutcome>).value.productId;
  }

  test('favori eklenir ve çıkarılır — REQ-PROD-009', () async {
    final id = await create('Tost');
    expect((await service.findById(id))!.isFavorite, isFalse);

    expect((await service.setFavorite(id, isFavorite: true)).isOk, isTrue);
    expect((await service.findById(id))!.isFavorite, isTrue);

    expect((await service.setFavorite(id, isFavorite: false)).isOk, isTrue);
    expect((await service.findById(id))!.isFavorite, isFalse);
  });

  test('ayrı bir favori TABLOSU oluşmaz — rules/02 §11.5', () async {
    final id = await create('Çay');
    await service.setFavorite(id, isFavorite: true);

    final tables = await db
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'table' "
          "AND name LIKE '%favorite%'",
        )
        .get();

    expect(
      tables,
      isEmpty,
      reason:
          'docs/04 §1: Favorite ayrı entity DEĞİLDİR; '
          '`products.is_favorite` yeterlidir.',
    );
  });

  test('olmayan ürün favoriye alınamaz', () async {
    expect(
      (await service.setFavorite(9999, isFavorite: true)).failureOrNull?.code,
      'product_not_found',
    );
  });

  test('docs/09 §5 — eşiği aşınca uyarı SERVİSTEN gelir', () async {
    final threshold = ProductRules.favoriteWarningThreshold;

    List<Object?> warnings = const [];
    for (var i = 0; i <= threshold; i++) {
      final id = await create('Ürün $i');
      final result = await service.setFavorite(id, isFavorite: true);
      warnings = (result as Ok<List<Object?>>).value;
    }

    expect(
      warnings,
      isNotEmpty,
      reason:
          'rules/05 §8: eşik UI\'da değil serviste değerlendirilir; '
          'ekran yalnızca gösterir.',
    );
  });

  test('aynı değer tekrar yazılırsa updated_at DEĞİŞMEZ', () async {
    final id = await create('Poğaça');
    await service.setFavorite(id, isFavorite: true);
    final first = (await service.findById(id))!.updatedAt;

    await service.setFavorite(id, isFavorite: true);

    expect((await service.findById(id))!.updatedAt, first);
  });
}
