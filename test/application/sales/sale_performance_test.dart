/// Satış performans eşikleri — **REQ-PERF-001/002 · docs/24 §2**
///
/// | Ölçüm | Hedef | Kabul edilemez |
/// |---|---|---|
/// | Barkod → sepet | < 100 ms | > 250 ms |
/// | Satış tamamlama (transaction) | < 50 ms | > 300 ms |
/// | Sepet işlemi (miktar) | < 50 ms | > 150 ms |
///
/// ## Neyi ölçer, neyi ölçmez
///
/// Ölçülen şey **veri yolu**dur: barkod araması + sepete yazma + sepetin
/// yeniden okunması. Ekranın boyanması dahil **değildir** — widget testinde
/// gerçek kare süresi ölçülemez ve sahte bir sayı üretmek yanıltıcı olurdu.
/// Uçtan uca süre W1–W4 (Windows, gerçek scanner) ile doğrulanır.
///
/// Veritabanı **dosya tabanlıdır**: in-memory SQLite üretimden hızlıdır ve
/// eşiği geçmesi hiçbir şey kanıtlamazdı (WAL + `synchronous=FULL` maliyeti
/// tam olarak burada görünür).
///
/// ## Neden bu test kırılgan değil
///
/// Eşik olarak **"kabul edilemez"** sınırı kullanılır, hedef değil. Hedef
/// (100 ms) bir tasarım amacıdır; CI makinesinin yüküne bağlı olarak
/// dalgalanır. `> 250 ms` ise docs/24 §2'nin *ürün kusurlu* dediği yerdir ve
/// orada dalgalanma mazeret değildir. Ölçülen süreler yine de yazdırılır.
library;

import 'dart:io';

import 'package:canteen/application/sales/cart_service.dart';
import 'package:canteen/application/sales/sale_service.dart';
import 'package:canteen/application/stock/stock_service.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, CartItem, Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/repositories/drift_product_repository.dart';
import 'package:canteen/data/repositories/drift_sale_repository.dart';
import 'package:canteen/data/repositories/drift_stock_repository.dart';
import 'package:canteen/domain/models/cart.dart';
import 'package:canteen/domain/repositories/product_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/test_database.dart';

/// docs/24 §2 — hedeflenen ürün ölçeği (REQ-PERF-008).
const int _productCount = 10000;

void main() {
  late Directory dir;
  late CanteenDatabase db;
  late ProductRepository products;
  late CartService cartService;
  late SaleService saleService;
  late int userId;
  late Cart cart;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('canteen_perf_');
    db = fileDatabase(p.join(dir.path, 'canteen.sqlite'));
    products = DriftProductRepository(db);
    cartService = CartService(
      db: db,
      carts: CartsDao(db),
      cartItems: CartItemsDao(db),
      vatRates: VatRatesDao(db),
      products: products,
      clock: () => testEpochUtc,
    );
    saleService = SaleService(
      db: db,
      cartService: cartService,
      carts: CartsDao(db),
      vatRates: VatRatesDao(db),
      appSettings: AppSettingsDao(db),
      auditLogs: AuditLogsDao(db),
      products: products,
      sales: DriftSaleRepository(db),
      stockService: StockService(
        db: db,
        stock: DriftStockRepository(db),
        products: DriftProductRepository(db),
        clock: () => testEpochUtc,
      ),
      clock: () => testEpochUtc,
    );
    userId = await insertTestUser(db);

    // 10.000 ürün + barkod. Seed toplu yazılır: ölçülen şey **arama**dır,
    // ekleme değil.
    final categoryId = (await (db.select(
      db.categories,
    )..limit(1)).getSingle()).id;
    final epoch = testEpochUtc.millisecondsSinceEpoch;
    await db.transaction(() async {
      await db.customStatement(
        'INSERT INTO products '
        '(name, category_id, sale_price_minor, purchase_price_minor, '
        ' stock_quantity, minimum_stock, is_favorite, is_active, '
        ' created_at, updated_at) '
        'WITH RECURSIVE seq(n) AS ('
        '  SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < $_productCount'
        ') '
        "SELECT 'Ürün ' || n, $categoryId, 1000 + n, 500, 100, 0, 0, 1, "
        '$epoch, $epoch FROM seq',
      );
      await db.customStatement(
        'INSERT INTO product_barcodes (product_id, barcode, is_primary, '
        ' created_at) '
        "SELECT id, '869' || printf('%010d', id), 1, $epoch FROM products",
      );
    });

    cart = await cartService.ensureActive(userId);
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// [body]'yi [runs] kez çalıştırır, **en kötü** süreyi döner.
  ///
  /// Ortalama değil en kötü: kasadaki kullanıcı ortalamayı değil, takılan
  /// okumayı hisseder.
  Future<Duration> worstOf(int runs, Future<void> Function(int i) body) async {
    var worst = Duration.zero;
    for (var i = 0; i < runs; i++) {
      final watch = Stopwatch()..start();
      await body(i);
      watch.stop();
      if (watch.elapsed > worst) worst = watch.elapsed;
    }
    return worst;
  }

  test('REQ-PERF-001 — barkod → sepet, 10.000 ürün içinde', () async {
    // 50 ardışık okutma (docs/27 §8 W1 ile aynı sayı).
    final worst = await worstOf(50, (i) async {
      final barcode = '869${(i + 1).toString().padLeft(10, '0')}';
      final found = await products.findByBarcode(barcode);
      expect(found.isOk, isTrue, reason: 'Barkod bulunamadı: $barcode');
      final added = await cartService.addProduct(
        cartId: cart.id,
        productId: found.valueOrNull!.id,
      );
      expect(added.isErr, isFalse);
    });

    // ignore: avoid_print
    print('REQ-PERF-001 barkod → sepet (en kötü): ${worst.inMilliseconds} ms');
    expect(
      worst.inMilliseconds,
      lessThan(250),
      reason:
          'docs/24 §2: > 250 ms **kabul edilemez**. Hedef < 100 ms; bu eşiğin '
          'aşılması `product_barcodes(barcode)` UNIQUE index\'inin '
          'kullanılmadığını gösterir.',
    );
  });

  test('REQ-PERF-002 — satış tamamlama transaction\'ı', () async {
    // Gerçekçi bir kantin fişi: 10 satır.
    for (var i = 0; i < 10; i++) {
      final found = await products.findByBarcode(
        '869${(i + 1).toString().padLeft(10, '0')}',
      );
      await cartService.addProduct(
        cartId: cart.id,
        productId: found.valueOrNull!.id,
        quantity: 2,
      );
    }

    final watch = Stopwatch()..start();
    final result = await saleService.complete(cartId: cart.id, userId: userId);
    watch.stop();
    expect(result.isErr, isFalse, reason: '${result.failureOrNull}');

    // ignore: avoid_print
    print('REQ-PERF-002 satış tamamlama: ${watch.elapsedMilliseconds} ms');
    expect(
      watch.elapsedMilliseconds,
      lessThan(300),
      reason: 'docs/24 §2: > 300 ms kabul edilemez (hedef < 50 ms).',
    );
  });

  test('docs/24 §2 — sepet miktar işlemi', () async {
    final found = await products.findByBarcode('8690000000001');
    final added = await cartService.addProduct(
      cartId: cart.id,
      productId: found.valueOrNull!.id,
    );
    final lineId = added.valueOrNull!.lines.single.id;

    final worst = await worstOf(30, (_) async {
      final result = await cartService.changeQuantity(
        cartId: cart.id,
        lineId: lineId,
        by: 1,
      );
      expect(result.isErr, isFalse);
    });

    // ignore: avoid_print
    print('sepet miktar işlemi (en kötü): ${worst.inMilliseconds} ms');
    expect(
      worst.inMilliseconds,
      lessThan(150),
      reason: 'docs/24 §2: > 150 ms kabul edilemez (hedef < 50 ms).',
    );
  });

  test('EC-CART-005 — 200 satırlık sepet okunabilir kalır', () async {
    for (var i = 0; i < 200; i++) {
      final found = await products.findByBarcode(
        '869${(i + 1).toString().padLeft(10, '0')}',
      );
      await cartService.addProduct(
        cartId: cart.id,
        productId: found.valueOrNull!.id,
      );
    }

    final watch = Stopwatch()..start();
    final loaded = await cartService.load(cart.id, userId);
    watch.stop();

    expect(loaded.lines, hasLength(200));
    // ignore: avoid_print
    print('200 satırlık sepet yüklenmesi: ${watch.elapsedMilliseconds} ms');
    expect(
      watch.elapsedMilliseconds,
      lessThan(150),
      reason:
          'Satır başına ürün sorgusu yapılsaydı (N+1) burası 200 sorgu '
          'olurdu; `rowsOfCart` tek join\'dir.',
    );
  });
}
