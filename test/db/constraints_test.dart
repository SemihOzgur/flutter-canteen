/// Kısıt testleri — kısıtların **gerçekten reddettiğini** kanıtlar.
///
/// REQ-DB-004 (barkod UNIQUE) · REQ-DB-005 (tek aktif sepet) ·
/// REQ-DB-009 (miktar > 0) · REQ-DB-011 (ağırlık çifti) ·
/// BR-STOCK-004 (quantity_delta ≠ 0) · REQ-DB-001 (foreign_keys)
library;

import 'package:canteen/data/db/canteen_database.dart';
import 'package:canteen/domain/enums/cart_status.dart';
import 'package:canteen/domain/enums/stock_movement_type.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart' show SqliteException;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late int userId;

  setUp(() async {
    db = memoryDatabase();
    userId = await insertTestUser(db);
  });
  tearDown(() => db.close());

  Future<int> newCart(CartStatus status) => db
      .into(db.carts)
      .insert(
        CartsCompanion.insert(
          status: status,
          userId: userId,
          createdAt: testEpochUtc,
          updatedAt: testEpochUtc,
        ),
      );

  group('REQ-DB-004 — barkod GLOBAL UNIQUE (BR-PROD-005)', () {
    test('aynı barkod ikinci kez eklenemez — farklı ürünlerde bile', () async {
      final first = await insertTestProduct(db, name: 'Kola');
      final second = await insertTestProduct(db, name: 'Ayran');

      await db
          .into(db.productBarcodes)
          .insert(
            ProductBarcodesCompanion.insert(
              productId: first,
              barcode: '8690000000001',
              createdAt: testEpochUtc,
            ),
          );

      expect(
        () => db
            .into(db.productBarcodes)
            .insert(
              ProductBarcodesCompanion.insert(
                productId: second,
                barcode: '8690000000001',
                createdAt: testEpochUtc,
              ),
            ),
        throwsA(isA<SqliteException>()),
        reason: 'BR-PROD-005: barkod global benzersiz olmalı.',
      );
    });

    test('baştaki sıfırlar korunur — barkod metin olarak saklanır', () async {
      final product = await insertTestProduct(db);
      await db
          .into(db.productBarcodes)
          .insert(
            ProductBarcodesCompanion.insert(
              productId: product,
              barcode: '0001234500001',
              createdAt: testEpochUtc,
            ),
          );

      final row = await (db.select(
        db.productBarcodes,
      )..where((b) => b.productId.equals(product))).getSingle();

      expect(row.barcode, '0001234500001');
      expect(row.barcode.startsWith('000'), isTrue);
    });
  });

  group('REQ-DB-005 — tek aktif sepet (BR-CART-001)', () {
    test('ikinci active sepet REDDEDİLİR', () async {
      await newCart(CartStatus.active);

      expect(
        () => newCart(CartStatus.active),
        throwsA(isA<SqliteException>()),
        reason: 'BR-CART-001: aynı anda yalnızca bir aktif sepet olabilir.',
      );
    });

    test('birden fazla closed/abandoned sepet serbesttir', () async {
      await newCart(CartStatus.closed);
      await newCart(CartStatus.closed);
      await newCart(CartStatus.abandoned);
      await newCart(CartStatus.abandoned);

      final all = await db.select(db.carts).get();
      expect(all.length, 4);
    });

    test('aktif sepet kapatılınca yenisi açılabilir', () async {
      final first = await newCart(CartStatus.active);

      await (db.update(db.carts)..where((c) => c.id.equals(first))).write(
        const CartsCompanion(status: Value(CartStatus.closed)),
      );

      final second = await newCart(CartStatus.active);
      expect(second, isNot(first));
    });
  });

  group('REQ-DB-009 — miktar pozitif tam sayı (BR-SALE-011)', () {
    test('cart_items.quantity = 0 REDDEDİLİR', () async {
      final cart = await newCart(CartStatus.active);
      final product = await insertTestProduct(db);

      expect(
        () => db
            .into(db.cartItems)
            .insert(
              CartItemsCompanion.insert(
                cartId: cart,
                productId: product,
                quantity: 0,
                unitPriceMinor: 1000,
                addedAt: testEpochUtc,
                updatedAt: testEpochUtc,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('cart_items.quantity < 0 REDDEDİLİR', () async {
      final cart = await newCart(CartStatus.active);
      final product = await insertTestProduct(db);

      expect(
        () => db
            .into(db.cartItems)
            .insert(
              CartItemsCompanion.insert(
                cartId: cart,
                productId: product,
                quantity: -3,
                unitPriceMinor: 1000,
                addedAt: testEpochUtc,
                updatedAt: testEpochUtc,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('quantity = 1 KABUL EDİLİR', () async {
      final cart = await newCart(CartStatus.active);
      final product = await insertTestProduct(db);

      final id = await db
          .into(db.cartItems)
          .insert(
            CartItemsCompanion.insert(
              cartId: cart,
              productId: product,
              quantity: 1,
              unitPriceMinor: 1000,
              addedAt: testEpochUtc,
              updatedAt: testEpochUtc,
            ),
          );
      expect(id, greaterThan(0));
    });
  });

  group('BR-STOCK-004 — quantity_delta ≠ 0', () {
    Future<int> movement(int productId, int delta) => db
        .into(db.stockMovements)
        .insert(
          StockMovementsCompanion.insert(
            productId: productId,
            type: StockMovementType.adjustment,
            quantityDelta: delta,
            resultingStock: 10,
            note: const Value('sayım farkı'),
            userId: userId,
            createdAt: testEpochUtc,
          ),
        );

    test('quantity_delta = 0 REDDEDİLİR', () async {
      final product = await insertTestProduct(db);
      expect(() => movement(product, 0), throwsA(isA<SqliteException>()));
    });

    test('pozitif ve negatif delta KABUL EDİLİR', () async {
      final product = await insertTestProduct(db);
      expect(await movement(product, 5), greaterThan(0));
      expect(await movement(product, -5), greaterThan(0));
    });
  });

  group('REQ-DB-011 — ağırlık çifti (BR-PROD-011)', () {
    Future<int> productWithWeight(int? value, String? unit) async {
      final category = (await (db.select(
        db.categories,
      )..limit(1)).getSingle()).id;
      return db
          .into(db.products)
          .insert(
            ProductsCompanion.insert(
              name: 'Ağırlıklı ${value}_$unit',
              categoryId: category,
              salePriceMinor: 1000,
              netWeightValue: Value(value),
              netWeightUnit: Value(unit),
              createdAt: testEpochUtc,
              updatedAt: testEpochUtc,
            ),
          );
    }

    test('NULL + NULL → KABUL', () async {
      expect(await productWithWeight(null, null), greaterThan(0));
    });

    test('değer + birim → KABUL', () async {
      expect(await productWithWeight(150000, 'g'), greaterThan(0));
    });

    test('değer + NULL → RED', () async {
      expect(
        () => productWithWeight(150000, null),
        throwsA(isA<SqliteException>()),
      );
    });

    test('NULL + birim → RED', () async {
      expect(
        () => productWithWeight(null, 'g'),
        throwsA(isA<SqliteException>()),
      );
    });
  });

  group('REQ-DB-001 — foreign_keys ON', () {
    test('var olmayan kategoriye ürün eklenemez', () async {
      expect(
        () => db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                name: 'Hayalet',
                categoryId: 999999,
                salePriceMinor: 100,
                createdAt: testEpochUtc,
                updatedAt: testEpochUtc,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('foreign_key_check BOŞ döner', () async {
      await insertTestProduct(db);
      final violations = await db
          .customSelect('PRAGMA foreign_key_check;')
          .get();
      expect(violations, isEmpty);
    });
  });

  group('diğer kısıtlar — docs/05 §2', () {
    test('sale_price_minor < 0 REDDEDİLİR (satış fiyatı >= 0)', () async {
      final category = (await (db.select(
        db.categories,
      )..limit(1)).getSingle()).id;
      expect(
        () => db
            .into(db.products)
            .insert(
              ProductsCompanion.insert(
                name: 'Negatif',
                categoryId: category,
                salePriceMinor: -1,
                createdAt: testEpochUtc,
                updatedAt: testEpochUtc,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('sale_price_minor = 0 KABUL EDİLİR (ikram ürünü)', () async {
      expect(
        await insertTestProduct(db, name: 'İkram', salePriceMinor: 0),
        greaterThan(0),
      );
    });

    test('vat_rates.rate_basis_points < 0 REDDEDİLİR', () async {
      expect(
        () => db
            .into(db.vatRates)
            .insert(
              VatRatesCompanion.insert(
                name: 'Hatalı',
                rateBasisPoints: -100,
                createdAt: testEpochUtc,
                updatedAt: testEpochUtc,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('categories.name UNIQUE — pasifler dahil', () async {
      await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              name: 'İçecek',
              isActive: const Value(false),
              createdAt: testEpochUtc,
              updatedAt: testEpochUtc,
            ),
          );

      expect(
        () => db
            .into(db.categories)
            .insert(
              CategoriesCompanion.insert(
                name: 'İçecek',
                createdAt: testEpochUtc,
                updatedAt: testEpochUtc,
              ),
            ),
        throwsA(isA<SqliteException>()),
      );
    });

    test('cart_items UNIQUE(cart_id, product_id, unit_price_minor)', () async {
      final cart = await newCart(CartStatus.active);
      final product = await insertTestProduct(db);

      Future<int> add(int price) => db
          .into(db.cartItems)
          .insert(
            CartItemsCompanion.insert(
              cartId: cart,
              productId: product,
              quantity: 1,
              unitPriceMinor: price,
              addedAt: testEpochUtc,
              updatedAt: testEpochUtc,
            ),
          );

      await add(1000);
      // Farklı fiyat → ayrı satır (fiyat override senaryosu).
      expect(await add(1200), greaterThan(0));
      // Aynı fiyat → çakışma.
      expect(() => add(1000), throwsA(isA<SqliteException>()));
    });
  });
}
