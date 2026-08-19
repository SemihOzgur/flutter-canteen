/// Ürün ve stok provider wiring testleri — **rules/01 §1 · OD-002**
///
/// Servis testleri bağımlılıkları elle enjekte eder; yanlış kurulmuş bir
/// provider grafiği onlardan geçer. Bu dosya yalnızca **kurulumu** doğrular.
///
/// Desen: `test/application/reference/providers_test.dart`.
library;

import 'package:canteen/application/product/product_draft.dart';
import 'package:canteen/application/product/product_service.dart';
import 'package:canteen/application/product/providers.dart';
import 'package:canteen/application/stock/providers.dart';
import 'package:canteen/application/stock/stock_service.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Category, Product, Sale, SaleItem, StockMovement, Supplier, VatRate;
import 'package:canteen/data/db/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;

  ProviderContainer newContainer() {
    final container = ProviderContainer(
      overrides: [canteenDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  test('servisler çözülür ve tek örnektir', () {
    final container = newContainer();

    expect(container.read(productServiceProvider), isA<ProductService>());
    expect(container.read(stockServiceProvider), isA<StockService>());
    expect(
      identical(
        container.read(productServiceProvider),
        container.read(productServiceProvider),
      ),
      isTrue,
    );
  });

  test('provider grafiği gerçekten aynı veritabanına yazar', () async {
    final container = newContainer();
    final userId = await insertTestUser(db);

    final created = await container
        .read(productServiceProvider)
        .create(
          const ProductDraft(name: 'Kola', salePrice: Money(12000)),
          userId: userId,
          initialStock: 4,
        );

    expect(created.isOk, isTrue);
    final id = (created as Ok<ProductSaveOutcome>).value.productId;

    // Ürün ve stok hareketi aynı bağlantıdan okunabilmelidir.
    final row = await (db.select(
      db.products,
    )..where((p) => p.id.equals(id))).getSingle();
    expect(row.name, 'Kola');
    expect(row.stockQuantity, 4);

    final movements = await (db.select(
      db.stockMovements,
    )..where((m) => m.productId.equals(id))).get();
    expect(movements, hasLength(1));
  });
}
