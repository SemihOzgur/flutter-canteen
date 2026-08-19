/// Aktif sepet — **docs/12 §2–§4 · BR-CART-001…005**
///
/// ## Sepet stok ve ciro tutmaz
///
/// Bu servis `stock_movements`'a, `sales`'e ve `audit_logs`'a **hiç dokunmaz**
/// (BR-CART-004 · REQ-CART-004). Sepette geçen hiçbir şey rapora girmez;
/// kalıcı iz yalnızca satış tamamlanırken oluşur (`SaleService`).
///
/// docs/18 §3'te sepet düzenlemesi için tanımlı bir audit action **yoktur**;
/// rules/00 §6 gereği uydurulmaz. (Tanımlı tek sepet action'ı `cartTakenOver`
/// olup REQ-AUTH-010'a — 🟢 Could — aittir.)
///
/// ## Her değişiklik ANINDA yazılır — REQ-CART-002
///
/// docs/12 §2.2: sepet değişikliği aynı frame'de veritabanına gider. Bu
/// yüzden burada "kaydet" metodu yoktur; her mutasyon kendi yazımını yapar ve
/// güncel sepeti geri döner. Çökme sonrası geri yükleme (REQ-CART-003) bunun
/// doğal sonucudur — ayrı bir kurtarma mekanizması gerekmez.
///
/// ## KDV
///
/// Oran çözümü **docs/08 §4**'e aittir ve tek yerde yapılır ([_resolveVatBp]):
/// ürünün oranı → yoksa varsayılan → o da yoksa `%0`. Pasif oran, ürüne
/// atanmışsa kullanılmaya devam eder (snapshot mantığı); varsayılan araması
/// ise aktiflik filtreler (BR-VAT-006 · OD-019).
library;

import '../../core/money/money.dart';
import '../../core/result/result.dart';
import '../../data/dao/daos.dart';
import '../../data/db/canteen_database.dart' show CanteenDatabase;
import '../../domain/enums/cart_status.dart';
import '../../domain/models/cart.dart';
import '../../domain/repositories/product_repository.dart';
import 'cart_failures.dart';

class CartService {
  final CanteenDatabase _db;
  final CartsDao _carts;
  final CartItemsDao _cartItems;
  final VatRatesDao _vatRates;
  final ProductRepository _products;
  final DateTime Function() _clock;

  CartService({
    required CanteenDatabase db,
    required CartsDao carts,
    required CartItemsDao cartItems,
    required VatRatesDao vatRates,
    required ProductRepository products,
    DateTime Function()? clock,
  }) : _db = db,
       _carts = carts,
       _cartItems = cartItems,
       _vatRates = vatRates,
       _products = products,
       _clock = clock ?? db.clock;

  // --- Yaşam döngüsü -------------------------------------------------------

  /// Aktif sepeti getirir; yoksa **oluşturur** — REQ-CART-001 · docs/12 §2.4.
  ///
  /// Uygulama açılışında çağrılır ve yarım kalan sepet aynen geri gelir
  /// (REQ-CART-003): sepet zaten her değişiklikte yazıldığı için "geri yükleme"
  /// ayrı bir iş değil, yalnızca okumadır.
  Future<Cart> ensureActive(int userId) async {
    final existing = await _resolveActive();
    if (existing != null) {
      // EC-CART-010 — bozulmuş satırlar açılışta bir kez temizlenir. Temizlik
      // okuma yolunda değil BURADA yapılır: `load` yan etkisiz kalmalıdır,
      // yoksa sepeti her göstermek bir yazma işlemi olurdu.
      final dropped = await _cartItems.deleteOrphanLines(existing.id);
      final cart = await _load(existing.id, existing.userId);
      return dropped == 0
          ? cart
          : Cart(
              id: cart.id,
              userId: cart.userId,
              lines: cart.lines,
              createdAt: cart.createdAt,
              updatedAt: cart.updatedAt,
              droppedLineCount: dropped,
            );
    }

    final now = _clock().toUtc();
    final id = await _carts.insertActiveCart(userId: userId, now: now);
    return Cart(
      id: id,
      userId: userId,
      lines: const [],
      createdAt: now,
      updatedAt: now,
    );
  }

  /// EC-CART-009 — bozulma sonucu birden fazla `active` sepet bulunursa
  /// **en yenisi tutulur**, diğerleri `abandoned` yapılır.
  ///
  /// `ux_carts_active` kısmi benzersiz index'i bunu normalde imkânsız kılar;
  /// bu yol index'in bulunmadığı bir yerden gelen veriye karşı savunmadır.
  /// Sessizce en yenisini seçip diğerini bırakmak, kullanıcının bir sonraki
  /// açılışta başka bir sepet görmesine yol açardı.
  Future<({int id, int userId})?> _resolveActive() async {
    final active = await _carts.listActive();
    if (active.isEmpty) return null;
    if (active.length == 1) {
      return (id: active.first.id, userId: active.first.userId);
    }

    // listActive() `updated_at` azalan sıradadır — ilki en yenisidir.
    for (final stale in active.skip(1)) {
      await _carts.updateStatus(stale.id, CartStatus.abandoned);
      // Satırlar da silinir. Terk edilmiş sepetin satırı hiçbir şeye
      // yaramaz ama `cart_items.product_id` bir yabancı anahtardır: hiç
      // satılmamış bir ürünü **kalıcı silmek** (BR-PROD-014) o referans
      // yüzünden veritabanı hatasıyla düşerdi. Kullanıcı, dokümanın izin
      // verdiği bir işlemin açıklanamayan bir hatayla reddedildiğini görürdü.
      await _cartItems.deleteOfCart(stale.id);
    }
    return (id: active.first.id, userId: active.first.userId);
  }

  /// Sepeti satırlarıyla birlikte okur.
  Future<Cart> load(int cartId, int userId) => _load(cartId, userId);

  Future<Cart> _load(int cartId, int userId) async {
    final header = await _carts.findById(cartId);
    final rows = await _cartItems.rowsOfCart(cartId);
    final defaultBp = await _defaultVatBp();

    final lines = rows
        .map(
          (row) => CartLine(
            id: row.id,
            productId: row.productId,
            productName: row.productName,
            quantity: row.quantity,
            unitPrice: Money(row.unitPriceMinor),
            listPrice: Money(row.listPriceMinor),
            isPriceOverridden: row.isPriceOverridden,
            vatRateBp: row.productVatRateBp ?? defaultBp,
            stockQuantity: row.stockQuantity,
            isProductActive: row.isProductActive,
          ),
        )
        .toList();

    final now = _clock().toUtc();
    return Cart(
      id: cartId,
      userId: header?.userId ?? userId,
      lines: lines,
      createdAt: header?.createdAt ?? now,
      updatedAt: header?.updatedAt ?? now,
      // EC-CART-010 — join dışında kalan satırlar; `rowsOfCart` ürünü olmayan
      // satırı hiç döndürmez, bu yüzden sayı ham sayımla karşılaştırılır.
      droppedLineCount: await _cartItems.countOfCart(cartId) - lines.length,
    );
  }

  // --- Satır işlemleri -----------------------------------------------------

  /// Ürünü sepete ekler — **REQ-CART-006 · REQ-BARC-005 · docs/12 §3.**
  ///
  /// Aynı ürün **aynı birim fiyatla** eklenirse yeni satır açılmaz, miktar
  /// artar. Fiyatı değiştirilmiş bir satır varken ürün normal fiyatla
  /// eklenirse ayrı satır oluşur (EC-CART-004) — kullanıcı iki farklı fiyatı
  /// bilinçli olarak uygulamış demektir.
  ///
  /// BR-STOCK-006: stok yetersizse **eklemeyi engellemez.** Uyarı kararı
  /// çağırana aittir; dönen sepette ilgili satır [CartLine.isOutOfStock] ile
  /// işaretlidir.
  ///
  /// [unitPrice] verilmezse ürünün güncel liste fiyatı kullanılır.
  Future<Result<Cart>> addProduct({
    required int cartId,
    required int productId,
    int quantity = 1,
    Money? unitPrice,
  }) async {
    if (quantity <= 0) return const Err(CartFailures.negativeQuantity);

    final found = await _products.findById(productId);
    // EC-CART-010 — ürün yoksa satır oluşturulmaz; sepetin kalanı korunur.
    if (found.isErr) return const Err(CartFailures.productNotFound);
    final product = found.valueOrNull!;

    final price = unitPrice ?? product.salePrice;
    if (price.isNegative) return const Err(CartFailures.negativePrice);

    final now = _clock().toUtc();

    return _db.transaction(() async {
      final existing = await _cartItems.findLine(
        cartId: cartId,
        productId: productId,
        unitPriceMinor: price.minor,
      );

      if (existing == null) {
        await _cartItems.insertItem(
          cartId: cartId,
          productId: productId,
          quantity: quantity,
          unitPriceMinor: price.minor,
          now: now,
          // Liste fiyatından farklı bir fiyatla ekleniyorsa satır baştan
          // "fiyatı değiştirilmiş"tir; aksi hâlde EC-CART-002 rozetiyle
          // karışırdı (bkz. CartLine.isPriceStale).
          isPriceOverridden: price != product.salePrice,
        );
      } else {
        await _cartItems.updateQuantity(
          existing.id,
          existing.quantity + quantity,
        );
      }

      await _carts.touch(cartId);
      return Ok(await _load(cartId, product.id));
    });
  }

  /// Satır miktarını **mutlak** olarak ayarlar.
  ///
  /// EC-CART-003: `0` satırı siler. Onay sorma kararı UI'ya aittir; servis
  /// isteneni yapar.
  Future<Result<Cart>> setQuantity({
    required int cartId,
    required int lineId,
    required int quantity,
  }) async {
    if (quantity < 0) return const Err(CartFailures.negativeQuantity);
    if (quantity == 0) return removeLine(cartId: cartId, lineId: lineId);

    return _db.transaction(() async {
      final line = await _cartItems.findById(lineId);
      if (line == null || line.cartId != cartId) {
        return const Err<Cart>(CartFailures.lineNotFound);
      }
      await _cartItems.updateQuantity(lineId, quantity);
      await _carts.touch(cartId);
      return Ok(await _load(cartId, line.cartId));
    });
  }

  /// Miktarı [by] kadar değiştirir; sonuç `0` veya altına inerse satır silinir
  /// (EC-CART-003).
  Future<Result<Cart>> changeQuantity({
    required int cartId,
    required int lineId,
    required int by,
  }) async {
    final line = await _cartItems.findById(lineId);
    if (line == null || line.cartId != cartId) {
      return const Err(CartFailures.lineNotFound);
    }
    final next = line.quantity + by;
    return setQuantity(
      cartId: cartId,
      lineId: lineId,
      quantity: next < 0 ? 0 : next,
    );
  }

  Future<Result<Cart>> removeLine({
    required int cartId,
    required int lineId,
  }) async {
    return _db.transaction(() async {
      final line = await _cartItems.findById(lineId);
      if (line == null || line.cartId != cartId) {
        return const Err<Cart>(CartFailures.lineNotFound);
      }
      await _cartItems.deleteById(lineId);
      await _carts.touch(cartId);
      return Ok(await _load(cartId, line.cartId));
    });
  }

  /// Satır fiyatını değiştirir — **docs/12 §4 · REQ-CART-005.**
  ///
  /// | Kural | |
  /// |---|---|
  /// | BR-SALE-003 — `Product.salePrice` **değişmez** | Bu servis `products`'a yazmaz |
  /// | EC-SALE-006 — `0` fiyat | ✅ İzin verilir (ikram) |
  /// | EC-SALE-007 — negatif fiyat | ❌ Reddedilir |
  ///
  /// Audit kaydı **burada yazılmaz**: docs/18 §3'teki `salePriceOverridden`
  /// bir *satış* olayıdır ve satır satılana kadar kalıcı bir iş olayı yoktur.
  /// Sepette on kez fiyat denemesi yapmak on denetim satırı üretmemelidir;
  /// kayıt satış tamamlanırken `SaleService` tarafından yazılır (BR-SALE-004).
  ///
  /// Yeni fiyat başka bir satırınkiyle çakışırsa (aynı ürün, aynı fiyat) iki
  /// satır **birleştirilir** — şemadaki `UNIQUE(cart_id, product_id,
  /// unit_price_minor)` aksi hâlde yazımı reddederdi.
  Future<Result<Cart>> overridePrice({
    required int cartId,
    required int lineId,
    required Money unitPrice,
  }) async {
    if (unitPrice.isNegative) return const Err(CartFailures.negativePrice);

    return _db.transaction(() async {
      final line = await _cartItems.findById(lineId);
      if (line == null || line.cartId != cartId) {
        return const Err<Cart>(CartFailures.lineNotFound);
      }

      final found = await _products.findById(line.productId);
      if (found.isErr) return const Err<Cart>(CartFailures.productNotFound);
      final product = found.valueOrNull!;

      final twin = await _cartItems.findLine(
        cartId: cartId,
        productId: line.productId,
        unitPriceMinor: unitPrice.minor,
      );

      if (twin != null && twin.id != lineId) {
        await _cartItems.updateQuantity(twin.id, twin.quantity + line.quantity);
        await _cartItems.deleteById(lineId);
      } else {
        await _cartItems.updatePrice(
          lineId,
          unitPriceMinor: unitPrice.minor,
          // Liste fiyatına geri dönmek override'ı **kaldırır**: satır artık
          // ürünün fiyatını izliyor demektir.
          isPriceOverridden: unitPrice != product.salePrice,
        );
      }

      await _carts.touch(cartId);
      return Ok(await _load(cartId, line.cartId));
    });
  }

  /// Sepeti boşaltır — satır silinir, sepet **kaydı** durur.
  ///
  /// Sepet kaydının kendisi `closed` yapılmaz: kullanıcı sepeti temizlemekle
  /// satış yapmış olmaz ve BR-CART-001 gereği ortada hâlâ bir aktif sepet
  /// bulunmalıdır.
  Future<Cart> clear({required int cartId, required int userId}) async {
    return _db.transaction(() async {
      await _cartItems.deleteOfCart(cartId);
      await _carts.touch(cartId);
      return _load(cartId, userId);
    });
  }

  // --- KDV oranı çözümü — docs/08 §4 --------------------------------------

  /// Varsayılan oranın basis point değeri; varsayılan yoksa `0`.
  ///
  /// docs/08 §4: *"Varsayılan oran yok → `%0` kabul edilir."* Arama aktiflik
  /// filtreler (`findDefault`), çünkü pasifleştirilmiş bir varsayılan
  /// "varsayılan yok" durumudur (BR-VAT-006 · OD-019).
  Future<int> _defaultVatBp() async =>
      (await _vatRates.findDefault())?.rateBasisPoints ?? 0;
}
