/// Aktif sepet testleri — **BR-CART-001…005 · REQ-CART-001…009 ·
/// docs/12 §2–§4**
///
/// docs/27 §4: gerçek in-memory SQLite üzerinde çalışır; mock veritabanı yoktur.
library;

import 'package:canteen/application/sales/cart_failures.dart';
import 'package:canteen/application/sales/cart_service.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, CartItem, Product;
import 'package:canteen/data/repositories/drift_product_repository.dart';
import 'package:canteen/domain/enums/cart_status.dart';
import 'package:canteen/domain/models/cart.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late CartService service;
  late int userId;
  late Cart cart;

  CartService buildService() => CartService(
    db: db,
    carts: CartsDao(db),
    cartItems: CartItemsDao(db),
    vatRates: VatRatesDao(db),
    products: DriftProductRepository(db),
    clock: () => testEpochUtc,
  );

  setUp(() async {
    db = memoryDatabase();
    service = buildService();
    userId = await insertTestUser(db);
    cart = await service.ensureActive(userId);
  });

  tearDown(() async => db.close());

  Future<int> vatRate(int bp, {bool isDefault = false}) async {
    if (isDefault) {
      await db
          .update(db.vatRates)
          .write(const VatRatesCompanion(isDefault: Value(false)));
    }
    return VatRatesDao(db).insertVatRate(
      name: 'oran-$bp',
      rateBasisPoints: bp,
      isDefault: isDefault,
      now: testEpochUtc,
    );
  }

  Future<int> product({
    String name = 'Kola',
    int salePriceMinor = 2500,
    int purchasePriceMinor = 1500,
    int? vatRateId,
    int stockQuantity = 10,
  }) async {
    final id = await insertTestProduct(
      db,
      name: name,
      salePriceMinor: salePriceMinor,
      purchasePriceMinor: purchasePriceMinor,
    );
    await (db.update(db.products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(
        vatRateId: Value(vatRateId),
        stockQuantity: Value(stockQuantity),
      ),
    );
    return id;
  }

  Cart ok(Result<Cart> result) {
    expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
    return result.valueOrNull!;
  }

  Future<Cart> add(int productId, {int quantity = 1, Money? unitPrice}) async =>
      ok(
        await service.addProduct(
          cartId: cart.id,
          productId: productId,
          quantity: quantity,
          unitPrice: unitPrice,
        ),
      );

  group('REQ-CART-001 — tek aktif sepet', () {
    test('ensureActive iki kez çağrılınca AYNI sepeti döner', () async {
      final again = await service.ensureActive(userId);

      expect(again.id, cart.id);
      expect(await CartsDao(db).listActive(), hasLength(1));
    });

    test('EC-CART-009 — iki aktif sepet varsa en YENİSİ tutulur', () async {
      // Kısmi benzersiz index bunu normalde imkânsız kılar; bozulmuş bir
      // yedekten gelen veriyi taklit etmek için index atlanarak yazılır.
      await db.customStatement('DROP INDEX ux_carts_active');
      final intruder = await CartsDao(db).insertActiveCart(
        userId: userId,
        now: testEpochUtc.add(const Duration(minutes: 5)),
      );

      final resolved = await service.ensureActive(userId);

      expect(resolved.id, intruder, reason: 'En yenisi tutulur.');
      expect(
        (await CartsDao(db).findById(cart.id))!.status,
        CartStatus.abandoned,
      );
    });
  });

  group('REQ-CART-006 · EC-CART-004 — satır birleştirme', () {
    test('aynı ürün aynı fiyatla MİKTARI artırır', () async {
      final id = await product();

      await add(id);
      final after = await add(id, quantity: 2);

      expect(after.lines, hasLength(1));
      expect(after.lines.single.quantity, 3);
    });

    test('aynı ürün FARKLI fiyatla ayrı satır açar', () async {
      final id = await product();

      await add(id);
      final after = await add(id, unitPrice: const Money(2000));

      expect(after.lines, hasLength(2));
      expect(after.lines.map((l) => l.unitPrice.minor), [2500, 2000]);
      expect(
        after.lines.last.isPriceOverridden,
        isTrue,
        reason:
            'Liste fiyatından farklı eklenen satır baştan "değiştirilmiş"tir; '
            'aksi hâlde EC-CART-002 rozetiyle karışırdı.',
      );
    });

    test('farklı ürünler ekleniş sırasında durur', () async {
      final a = await product(name: 'Kola');
      final b = await product(name: 'Su', salePriceMinor: 1000);

      await add(a);
      final after = await add(b);

      expect(after.lines.map((l) => l.productName), ['Kola', 'Su']);
    });
  });

  group('REQ-CART-002/003 — anında kalıcı, çökme sonrası geri gelir', () {
    test('yeni servis örneği sepeti aynen geri yükler', () async {
      final id = await product();
      await add(id, quantity: 3);

      // Uygulama öldürülüp yeniden açılmış gibi: yeni servis, aynı veritabanı.
      final restored = await buildService().ensureActive(userId);

      expect(restored.id, cart.id);
      expect(restored.lines.single.quantity, 3);
      expect(restored.totals.gross, const Money(7500));
    });

    test('REQ-CART-004 — sepet stok hareketi veya satış ÜRETMEZ', () async {
      final id = await product(stockQuantity: 10);
      await add(id, quantity: 4);

      expect(await db.select(db.stockMovements).get(), isEmpty);
      expect(await db.select(db.sales).get(), isEmpty);
      final row = await (db.select(
        db.products,
      )..where((p) => p.id.equals(id))).getSingle();
      expect(row.stockQuantity, 10, reason: 'Sepet stok REZERVE ETMEZ.');
    });
  });

  group('miktar — BR-SALE-011 · EC-CART-003', () {
    test('setQuantity(0) satırı SİLER', () async {
      final added = await add(await product());

      final after = ok(
        await service.setQuantity(
          cartId: cart.id,
          lineId: added.lines.single.id,
          quantity: 0,
        ),
      );

      expect(after.lines, isEmpty);
    });

    test('negatif miktar reddedilir', () async {
      final added = await add(await product());

      final result = await service.setQuantity(
        cartId: cart.id,
        lineId: added.lines.single.id,
        quantity: -1,
      );

      expect(result.failureOrNull, CartFailures.negativeQuantity);
    });

    test('changeQuantity(-1) son adette satırı siler', () async {
      final added = await add(await product());

      final after = ok(
        await service.changeQuantity(
          cartId: cart.id,
          lineId: added.lines.single.id,
          by: -1,
        ),
      );

      expect(after.lines, isEmpty);
    });

    test('changeQuantity(+2) miktarı artırır', () async {
      final added = await add(await product());

      final after = ok(
        await service.changeQuantity(
          cartId: cart.id,
          lineId: added.lines.single.id,
          by: 2,
        ),
      );

      expect(after.lines.single.quantity, 3);
    });
  });

  group('REQ-CART-005 · docs/12 §4 — satır fiyatı', () {
    test('fiyat değişir, ÜRÜNÜN fiyatı DEĞİŞMEZ (BR-SALE-003)', () async {
      final id = await product(salePriceMinor: 2500);
      final added = await add(id);

      final after = ok(
        await service.overridePrice(
          cartId: cart.id,
          lineId: added.lines.single.id,
          unitPrice: const Money(2000),
        ),
      );

      expect(after.lines.single.unitPrice, const Money(2000));
      expect(after.lines.single.isPriceOverridden, isTrue);
      final row = await (db.select(
        db.products,
      )..where((p) => p.id.equals(id))).getSingle();
      expect(row.salePriceMinor, 2500, reason: 'BR-SALE-003');
    });

    test('EC-SALE-006 — fiyat 0 (ikram) KABUL EDİLİR', () async {
      final added = await add(await product());

      final after = ok(
        await service.overridePrice(
          cartId: cart.id,
          lineId: added.lines.single.id,
          unitPrice: Money.zero,
        ),
      );

      expect(after.totals.gross, Money.zero);
    });

    test('EC-SALE-007 — negatif fiyat REDDEDİLİR', () async {
      final added = await add(await product());

      final result = await service.overridePrice(
        cartId: cart.id,
        lineId: added.lines.single.id,
        unitPrice: const Money(-1),
      );

      expect(result.failureOrNull, CartFailures.negativePrice);
    });

    test('liste fiyatına dönmek override bayrağını KALDIRIR', () async {
      final id = await product(salePriceMinor: 2500);
      final added = await add(id, unitPrice: const Money(2000));

      final after = ok(
        await service.overridePrice(
          cartId: cart.id,
          lineId: added.lines.single.id,
          unitPrice: const Money(2500),
        ),
      );

      expect(after.lines.single.isPriceOverridden, isFalse);
    });

    test('fiyat başka satırınkiyle çakışırsa satırlar BİRLEŞİR', () async {
      // Şemadaki UNIQUE(cart_id, product_id, unit_price_minor) aksi hâlde
      // yazımı reddeder ve kullanıcı sebebini anlamadığı bir hata görürdü.
      final id = await product(salePriceMinor: 2500);
      await add(id, quantity: 2);
      final two = await add(id, quantity: 3, unitPrice: const Money(2000));
      expect(two.lines, hasLength(2));

      final after = ok(
        await service.overridePrice(
          cartId: cart.id,
          lineId: two.lines.last.id,
          unitPrice: const Money(2500),
        ),
      );

      expect(after.lines, hasLength(1));
      expect(after.lines.single.quantity, 5);
    });
  });

  group('docs/08 §4 — KDV oranı çözümü', () {
    test('ürünün kendi oranı kullanılır', () async {
      final rate = await vatRate(2000);
      final after = await add(
        await product(salePriceMinor: 12000, vatRateId: rate),
      );

      expect(after.lines.single.vatRateBp, 2000);
      expect(after.totals.vat, const Money(2000));
    });

    test('oran atanmamışsa VARSAYILAN oran kullanılır', () async {
      await vatRate(1000, isDefault: true);
      final after = await add(await product(salePriceMinor: 11000));

      expect(after.lines.single.vatRateBp, 1000);
      expect(after.totals.vat, const Money(1000));
    });

    test('PASİF oran ürüne atanmışsa yine de kullanılır', () async {
      // docs/08 §4: "Ürünün oranı pasifleştirilmiş → satışta o oran
      // kullanılmaya devam eder — snapshot mantığı gereği doğru davranıştır."
      final rate = await vatRate(2000);
      await VatRatesDao(db).setActive(rate, false);

      final after = await add(
        await product(salePriceMinor: 12000, vatRateId: rate),
      );

      expect(after.lines.single.vatRateBp, 2000);
    });

    test('varsayılan PASİFSE %0 kabul edilir', () async {
      // BR-VAT-006 · OD-019 — arama aktiflik filtreler; pasifleşmiş varsayılan
      // "varsayılan yok" demektir.
      final seeded = await VatRatesDao(db).findDefault();
      await VatRatesDao(db).setActive(seeded!.id, false);

      final after = await add(await product(salePriceMinor: 12000));

      expect(after.lines.single.vatRateBp, 0);
      expect(after.totals.vat, Money.zero);
    });
  });

  test('EC-CART-010 — olmayan ürün eklenemez, sepet bozulmaz', () async {
    await add(await product());

    final result = await service.addProduct(cartId: cart.id, productId: 9999);

    expect(result.failureOrNull, CartFailures.productNotFound);
    expect((await service.load(cart.id, userId)).lines, hasLength(1));
  });

  test('docs/12 §2.4 — pasifleşen ürün sepette KALIR, işaretlenir', () async {
    final id = await product();
    await add(id);
    await DriftProductRepository(db).setActive(id, false);

    final after = await service.load(cart.id, userId);

    expect(after.lines, hasLength(1));
    expect(after.lines.single.isProductActive, isFalse);
  });

  test('clear sepeti boşaltır ama AKTİF sepet kalır', () async {
    await add(await product());

    final after = await service.clear(cartId: cart.id, userId: userId);

    expect(after.lines, isEmpty);
    expect(
      (await CartsDao(db).findById(cart.id))!.status,
      CartStatus.active,
      reason: 'BR-CART-001: ortada hep bir aktif sepet bulunmalıdır.',
    );
  });
}
