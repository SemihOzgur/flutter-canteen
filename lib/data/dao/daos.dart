/// Salt DAO'lar — repository interface'i **olmayan** 12 tablo.
///
/// docs/03-architecture.md §4 · rules/01 §4:
///   Interface yalnızca Product · Sale · Stock için yazılır. Kalan tablolar
///   doğrudan DAO ile kullanılır — "diğerlerinde var, tutarlı olsun" yeterli
///   bir gerekçe değildir (rules/01 §4).
///
/// ## Kapsam sınırı — bu dosyada BULUNMAYACAKLAR
///
/// DAO'lar yalnızca **kalıcılık erişimi, eşleme ve temel sorgu** içerir.
/// Transaction orkestrasyonu, satış atomikliği, stok invariant'ı ve audit
/// yazımı **kendi fazlarına** aittir (Faz 5 / 6) ve buraya sızdırılmaz.
///
/// Tüm sorgular Drift üzerinden **parametrelidir** (REQ-SEC-006).
library;

import 'package:drift/drift.dart';

import '../../domain/enums/cart_status.dart';
import '../db/canteen_database.dart';
import '../db/tables/cart_tables.dart';
import '../db/tables/product_tables.dart';
import '../db/tables/reference_tables.dart';
import '../db/tables/return_tables.dart';
import '../db/tables/sale_tables.dart';
import '../db/tables/system_tables.dart';

part 'daos.g.dart';

// ---------------------------------------------------------------------------
// 1 — users
// ---------------------------------------------------------------------------

/// BR-AUTH-002: rol/yetki sistemi **yoktur**; `users.role` kolonu oluşturulmaz.
/// Çoklu kullanıcının tek faydası izlenebilirliktir.
@DriftAccessor(tables: [Users])
class UsersDao extends DatabaseAccessor<CanteenDatabase> with _$UsersDaoMixin {
  UsersDao(super.db);

  Future<User?> findById(int id) =>
      (select(users)..where((u) => u.id.equals(id))).getSingleOrNull();

  /// **Ham** eşleşme — çağıran normalize edilmiş adı verir.
  ///
  /// Büyük/küçük harf duyarsızlığı bir **iş kuralıdır** (REQ-AUTH-012) ve
  /// Türkçe `ı/I` katlaması gerektirir; `rules/01 §1` gereği bu karar data
  /// katmanında yaşayamaz. Tek kaynak: `AuthService.normalizeUsername`.
  Future<User?> findByUsername(String normalizedUsername) =>
      (select(users)
            ..where((u) => u.username.equals(normalizedUsername))
            ..limit(1))
          .getSingleOrNull();

  /// Yalnızca aktif kullanıcılar. Sıralama [listAll] ile aynıdır: liste
  /// ekranının aktif/pasif filtresi değiştiğinde satırların yeri değişmesin.
  Future<List<User>> listActive() =>
      (select(users)
            ..where((u) => u.isActive.equals(true))
            ..orderBy([(u) => OrderingTerm(expression: u.username)]))
          .get();

  /// **Pasifler dâhil** tüm kullanıcılar — kullanıcı yönetimi ekranı için
  /// (docs/17 §11). Kullanıcı silinmez, yalnızca pasifleşir (BR-AUTH-006);
  /// bu yüzden pasif kayıtlar da listelenebilmelidir.
  Future<List<User>> listAll() => (select(
    users,
  )..orderBy([(u) => OrderingTerm(expression: u.username)])).get();

  Future<int> insertUser(UsersCompanion user) => into(users).insert(user);

  /// BR-AUTH-006 — en az bir aktif kullanıcı bulunmalıdır.
  Future<int> countActive() async {
    final count = users.id.count();
    final row =
        await (selectOnly(users)
              ..addColumns([count])
              ..where(users.isActive.equals(true)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// EC-AUTH-008 / REQ-AUTH-002 — hiç kullanıcı yoksa kurulum sihirbazı açılır.
  /// Pasif kullanıcılar da sayılır: pasif bir kullanıcı varken sistem "yeni
  /// kurulum" değildir.
  Future<int> countAll() async {
    final count = users.id.count();
    final row = await (selectOnly(users)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  /// Başarılı giriş sonrası son giriş zamanı (docs/04 §3.1).
  ///
  /// [at] UTC'ye çevrilerek yazılır (rules/03 §1 — tüm zaman alanları UTC).
  Future<int> touchLastLogin(int id, DateTime at) =>
      (update(users)..where((u) => u.id.equals(id))).write(
        UsersCompanion(
          lastLoginAt: Value(at.toUtc()),
          updatedAt: Value(_now()),
        ),
      );

  /// Parola değişikliği — **yalnızca** hash ve salt yazılır.
  ///
  /// BR-SEC-001: düz metin parola hiçbir kolona yazılmaz; bu metot düz metni
  /// hiç görmez.
  Future<int> updatePassword(
    int id, {
    required String passwordHash,
    required String passwordSalt,
  }) => (update(users)..where((u) => u.id.equals(id))).write(
    UsersCompanion(
      passwordHash: Value(passwordHash),
      passwordSalt: Value(passwordSalt),
      updatedAt: Value(_now()),
    ),
  );

  /// BR-AUTH-006 — kullanıcı **silinmez**, yalnızca pasifleştirilir.
  ///
  /// "Son aktif kullanıcı" kontrolü bir iş kuralıdır ve application
  /// katmanındadır (rules/01 §1 — DAO iş kararı içermez).
  Future<int> setActive(int id, bool isActive) =>
      (update(users)..where((u) => u.id.equals(id))).write(
        UsersCompanion(isActive: Value(isActive), updatedAt: Value(_now())),
      );

  Future<int> updateDisplayName(int id, String displayName) =>
      (update(users)..where((u) => u.id.equals(id))).write(
        UsersCompanion(
          displayName: Value(displayName),
          updatedAt: Value(_now()),
        ),
      );

  DateTime _now() => attachedDatabase.clock().toUtc();
}

// ---------------------------------------------------------------------------
// 2 — categories
// ---------------------------------------------------------------------------

/// `products` ve `sale_items` bu accessor'a **kullanım sayımı** için dâhildir.
///
/// BR-CAT-005 · REQ-CAT-006: bir kategori ancak hiçbir ürüne atanmamışsa **ve**
/// hiçbir satış satırı snapshot'ında geçmiyorsa kalıcı silinebilir. İki sayım
/// da burada, SQL tarafında yapılır (rules/01 §8 — aggregation Dart'ta değil).
/// **Karar** DAO'ya ait değildir: sayıları yorumlayan ve silme/pasifleştirme
/// arasında seçim yapan `CategoryService`'tir (rules/01 §1).
@DriftAccessor(tables: [Categories, Products, SaleItems])
class CategoriesDao extends DatabaseAccessor<CanteenDatabase>
    with _$CategoriesDaoMixin {
  CategoriesDao(super.db);

  Future<Category?> findById(int id) =>
      (select(categories)..where((c) => c.id.equals(id))).getSingleOrNull();

  /// **Ham** eşleşme — `ux_categories_name` ne diyorsa o.
  ///
  /// Büyük/küçük harf katlaması **yapılmaz**: benzersizlik kısıtı şemada
  /// `UNIQUE(name)`'dir (docs/05 §2.2) ve katlama bir şema kararı olurdu.
  Future<Category?> findByName(String name) =>
      (select(categories)
            ..where((c) => c.name.equals(name))
            ..limit(1))
          .getSingleOrNull();

  Future<List<Category>> listActive() =>
      (select(categories)
            ..where((c) => c.isActive.equals(true))
            ..orderBy([
              (c) => OrderingTerm(expression: c.sortOrder),
              (c) => OrderingTerm(expression: c.name),
            ]))
          .get();

  /// **Pasifler dâhil** tüm kategoriler — yönetim ekranı için.
  ///
  /// Sıralama [listActive] ile aynıdır: aktif/pasif filtresi değiştiğinde
  /// satırların yeri değişmesin.
  Future<List<Category>> listAll() =>
      (select(categories)..orderBy([
            (c) => OrderingTerm(expression: c.sortOrder),
            (c) => OrderingTerm(expression: c.name),
          ]))
          .get();

  /// BR-CAT-004 — `Genel` sistem kategorisi.
  Future<Category?> findSystemCategory() =>
      (select(categories)
            ..where((c) => c.isSystem.equals(true))
            ..limit(1))
          .getSingleOrNull();

  /// Yeni kategori. `isSystem` **yazılmaz**: sistem kategorisi yalnızca
  /// seed tarafından oluşturulur (BR-CAT-004 · `data/db/seed.dart`).
  Future<int> insertCategory({
    required String name,
    required int sortOrder,
    required DateTime now,
  }) => into(categories).insert(
    CategoriesCompanion.insert(
      name: name,
      sortOrder: Value(sortOrder),
      createdAt: now,
      updatedAt: now,
    ),
  );

  Future<int> updateName(int id, String name) =>
      (update(categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(name: Value(name), updatedAt: Value(_now())),
      );

  Future<int> updateSortOrder(int id, int sortOrder) =>
      (update(categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(
          sortOrder: Value(sortOrder),
          updatedAt: Value(_now()),
        ),
      );

  /// BR-CAT-003 — pasifleştirme **yalnızca bu satıra** dokunur; bağlı ürünler
  /// değişmez. Sistem kategorisi koruması bir iş kuralıdır ve
  /// `CategoryService`'tedir (rules/01 §1).
  Future<int> setActive(int id, bool isActive) =>
      (update(categories)..where((c) => c.id.equals(id))).write(
        CategoriesCompanion(
          isActive: Value(isActive),
          updatedAt: Value(_now()),
        ),
      );

  /// BR-CAT-005 — **koşulsuz** siler. Koşul kontrolü çağırana aittir ve
  /// silmeyle aynı transaction içinde yapılmalıdır (`CategoryService.delete`).
  Future<int> deleteById(int id) =>
      (delete(categories)..where((c) => c.id.equals(id))).go();

  Future<int> countAll() async {
    final count = categories.id.count();
    final row = await (selectOnly(categories)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  /// Bu kategoriye atanmış ürün sayısı — **pasif ürünler dâhil**
  /// (docs/10 §1.2b: "aktif veya pasif").
  Future<int> countProducts(int categoryId) async {
    final count = products.id.count();
    final row =
        await (selectOnly(products)
              ..addColumns([count])
              ..where(products.categoryId.equals(categoryId)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// Bu kategorinin geçtiği satış satırı snapshot'ı sayısı — EC-CAT-006.
  ///
  /// `sale_items.category_id_snapshot` satış anındaki kategoriyi taşır
  /// (rules/02 §3). Kategori satılmış bir satırda geçiyorsa kalıcı silme
  /// geçmiş kategori raporunu bozar.
  Future<int> countSaleItemSnapshots(int categoryId) async {
    final count = saleItems.id.count();
    final row =
        await (selectOnly(saleItems)
              ..addColumns([count])
              ..where(saleItems.categoryIdSnapshot.equals(categoryId)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// Bir kategorideki **tüm** ürünleri hedef kategoriye taşır — docs/10 §1.4.
  ///
  /// Tek `UPDATE` ifadesidir; ürün başına döngü yoktur. Değişen satır sayısını
  /// döndürür (audit metadata'sındaki ürün sayısı budur).
  ///
  /// ⚠️ Transaction **çağıran serviste** açılır (rules/01 §5).
  Future<int> moveProductsTo({
    required int fromCategoryId,
    required int toCategoryId,
  }) => (update(products)..where((p) => p.categoryId.equals(fromCategoryId)))
      .write(
        ProductsCompanion(
          categoryId: Value(toCategoryId),
          updatedAt: Value(_now()),
        ),
      );

  DateTime _now() => attachedDatabase.clock().toUtc();
}

// ---------------------------------------------------------------------------
// 3 — suppliers
// ---------------------------------------------------------------------------

/// BR-SUP-002 · REQ-SUP-002: tedarikçi **silinmez.**
///
/// Bu DAO bu yüzden `deleteById` **sunmaz** — kural bir runtime kontrolü değil,
/// var olmayan bir metottur. Aynı koruma `SupplierService`'te de geçerlidir.
@DriftAccessor(tables: [Suppliers, Products])
class SuppliersDao extends DatabaseAccessor<CanteenDatabase>
    with _$SuppliersDaoMixin {
  SuppliersDao(super.db);

  Future<Supplier?> findById(int id) =>
      (select(suppliers)..where((s) => s.id.equals(id))).getSingleOrNull();

  Future<List<Supplier>> listActive() =>
      (select(suppliers)
            ..where((s) => s.isActive.equals(true))
            ..orderBy([(s) => OrderingTerm(expression: s.name)]))
          .get();

  /// **Pasifler dâhil** — tedarikçi silinmediği için yönetim ekranı pasif
  /// kayıtları da görebilmelidir.
  Future<List<Supplier>> listAll() => (select(
    suppliers,
  )..orderBy([(s) => OrderingTerm(expression: s.name)])).get();

  /// Yalnızca [name] zorunludur (REQ-SUP-001).
  Future<int> insertSupplier({
    required String name,
    required DateTime now,
    String? contactName,
    String? phone,
    String? email,
    String? address,
    String? note,
  }) => into(suppliers).insert(
    SuppliersCompanion.insert(
      name: name,
      contactName: Value(contactName),
      phone: Value(phone),
      email: Value(email),
      address: Value(address),
      note: Value(note),
      createdAt: now,
      updatedAt: now,
    ),
  );

  /// Tüm alanlar güncellenebilir (docs/10 §2.1). Opsiyonel alanlar `null`
  /// verilerek **temizlenebilir**; bu yüzden `Value(...)` koşulsuz yazılır.
  Future<int> updateSupplier(
    int id, {
    required String name,
    String? contactName,
    String? phone,
    String? email,
    String? address,
    String? note,
  }) => (update(suppliers)..where((s) => s.id.equals(id))).write(
    SuppliersCompanion(
      name: Value(name),
      contactName: Value(contactName),
      phone: Value(phone),
      email: Value(email),
      address: Value(address),
      note: Value(note),
      updatedAt: Value(_now()),
    ),
  );

  /// EC-SUP-001 — pasifleştirme **yalnızca bu satıra** dokunur; bağlı ürünlerin
  /// `supplier_id` bağı kopmaz (docs/10 §2.3).
  Future<int> setActive(int id, bool isActive) =>
      (update(suppliers)..where((s) => s.id.equals(id))).write(
        SuppliersCompanion(isActive: Value(isActive), updatedAt: Value(_now())),
      );

  /// Bu tedarikçiye bağlı ürün sayısı — pasif ürünler dâhil.
  Future<int> countProducts(int supplierId) async {
    final count = products.id.count();
    final row =
        await (selectOnly(products)
              ..addColumns([count])
              ..where(products.supplierId.equals(supplierId)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  DateTime _now() => attachedDatabase.clock().toUtc();
}

// ---------------------------------------------------------------------------
// 4 — vat_rates
// ---------------------------------------------------------------------------

/// BR-VAT-001: oranlar yönetilebilir; **mevzuata bağlı oranlar koda gömülmez
/// ve seed edilmez** (rules/02 §2). Kurulumda yalnızca nötr `%0 — KDV Yok`
/// oluşturulur (docs/08 §3 · OD-017).
///
/// docs/08 §4: oran kaydı **silinemez** — geçmiş ürün ilişkileri korunur.
/// Bu DAO bu yüzden `deleteById` **sunmaz.**
///
/// `products` kullanım sayımı içindir: docs/08 §4 oran değiştirilirken
/// "bu oran `N` üründe kullanılıyor" bilgisini ve `vatRateChanged` audit
/// metadata'sını (docs/18 §3) gerektirir.
@DriftAccessor(tables: [VatRates, Products])
class VatRatesDao extends DatabaseAccessor<CanteenDatabase>
    with _$VatRatesDaoMixin {
  VatRatesDao(super.db);

  Future<VatRate?> findById(int id) =>
      (select(vatRates)..where((v) => v.id.equals(id))).getSingleOrNull();

  Future<List<VatRate>> listActive() =>
      (select(vatRates)
            ..where((v) => v.isActive.equals(true))
            ..orderBy([(v) => OrderingTerm(expression: v.rateBasisPoints)]))
          .get();

  /// **Pasifler dâhil** — oran silinmediği için yönetim ekranı pasif kayıtları
  /// da görebilmelidir.
  Future<List<VatRate>> listAll() => (select(
    vatRates,
  )..orderBy([(v) => OrderingTerm(expression: v.rateBasisPoints)])).get();

  /// docs/08 §4 — ürüne oran atanmamışsa kullanılan oran.
  ///
  /// Pasif oran varsayılan sayılmaz: pasifleştirilmiş bir varsayılan, "varsayılan
  /// oran yok" durumudur ve KDV `%0` kabul edilir (docs/08 §4 tablosu).
  Future<VatRate?> findDefault() =>
      (select(vatRates)
            ..where((v) => v.isDefault.equals(true) & v.isActive.equals(true))
            ..limit(1))
          .getSingleOrNull();

  Future<int> insertVatRate({
    required String name,
    required int rateBasisPoints,
    required DateTime now,
    bool isDefault = false,
  }) => into(vatRates).insert(
    VatRatesCompanion.insert(
      name: name,
      rateBasisPoints: rateBasisPoints,
      isDefault: Value(isDefault),
      createdAt: now,
      updatedAt: now,
    ),
  );

  Future<int> updateVatRate(int id, {String? name, int? rateBasisPoints}) =>
      (update(vatRates)..where((v) => v.id.equals(id))).write(
        VatRatesCompanion(
          name: name == null ? const Value.absent() : Value(name),
          rateBasisPoints: rateBasisPoints == null
              ? const Value.absent()
              : Value(rateBasisPoints),
          updatedAt: Value(_now()),
        ),
      );

  Future<int> setActive(int id, bool isActive) =>
      (update(vatRates)..where((v) => v.id.equals(id))).write(
        VatRatesCompanion(isActive: Value(isActive), updatedAt: Value(_now())),
      );

  /// docs/04 §3.4 — `isDefault` yalnızca **bir** kayıtta `true` olabilir.
  ///
  /// Bu metot tek başına invariant'ı sağlamaz; [clearDefault] ile birlikte ve
  /// **aynı transaction** içinde çağrılmalıdır (`VatRateService.setDefault`).
  Future<int> setDefault(int id, bool isDefault) =>
      (update(vatRates)..where((v) => v.id.equals(id))).write(
        VatRatesCompanion(
          isDefault: Value(isDefault),
          updatedAt: Value(_now()),
        ),
      );

  /// Tüm kayıtlarda `is_default = 0`. [exceptId] verilirse o satır atlanır.
  Future<int> clearDefault({int? exceptId}) {
    final statement = update(vatRates)
      ..where(
        (v) => exceptId == null
            ? v.isDefault.equals(true)
            : v.isDefault.equals(true) & v.id.equals(exceptId).not(),
      );
    return statement.write(
      VatRatesCompanion(
        isDefault: const Value(false),
        updatedAt: Value(_now()),
      ),
    );
  }

  Future<int> countAll() async {
    final count = vatRates.id.count();
    final row = await (selectOnly(vatRates)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }

  /// Aktif ve **sıfırdan farklı** oran sayısı — BR-VAT-005 · OD-017.
  ///
  /// Kurulumda nötr `%0` oranı seed edildiği için (docs/08 §3) `countAll`
  /// artık "kullanıcı KDV takip ediyor mu" sorusuna cevap veremez; bu sayım
  /// verir. Karar `VatRateService.isVatDisabled` içindedir — bu DAO yalnızca
  /// sorgular (rules/01 §1).
  Future<int> countActiveTaxable() async {
    final count = vatRates.id.count();
    final row =
        await (selectOnly(vatRates)
              ..addColumns([count])
              ..where(
                vatRates.isActive.equals(true) &
                    vatRates.rateBasisPoints.isBiggerThanValue(0),
              ))
            .getSingle();
    return row.read(count) ?? 0;
  }

  /// Bu oranı **doğrudan** kullanan ürün sayısı (`products.vat_rate_id`).
  ///
  /// `vat_rate_id IS NULL` olan ürünler varsayılan oranı kullanır (docs/08 §4);
  /// onlar bu sayıma girmez — sayı "oran değişirse hangi ürünlerin oranı
  /// değişir" sorusuna değil, "kaç ürün bu kayda bağlı" sorusuna cevaptır.
  Future<int> countProducts(int vatRateId) async {
    final count = products.id.count();
    final row =
        await (selectOnly(products)
              ..addColumns([count])
              ..where(products.vatRateId.equals(vatRateId)))
            .getSingle();
    return row.read(count) ?? 0;
  }

  DateTime _now() => attachedDatabase.clock().toUtc();
}

// ---------------------------------------------------------------------------
// 5 — product_barcodes
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [ProductBarcodes])
class ProductBarcodesDao extends DatabaseAccessor<CanteenDatabase>
    with _$ProductBarcodesDaoMixin {
  ProductBarcodesDao(super.db);

  /// Barkodlar **metin** olarak saklanır; baştaki sıfırlar korunur.
  Future<ProductBarcode?> findByBarcode(String barcode) =>
      (select(productBarcodes)
            ..where((b) => b.barcode.equals(barcode))
            ..limit(1))
          .getSingleOrNull();

  Future<List<ProductBarcode>> listOfProduct(int productId) => (select(
    productBarcodes,
  )..where((b) => b.productId.equals(productId))).get();

  Future<int> insertBarcode(ProductBarcodesCompanion barcode) =>
      into(productBarcodes).insert(barcode);

  Future<int> deleteById(int id) =>
      (delete(productBarcodes)..where((b) => b.id.equals(id))).go();
}

// ---------------------------------------------------------------------------
// 6 — carts
// ---------------------------------------------------------------------------

/// BR-CART-001 — aynı anda tek aktif sepet. Kısıt `ux_carts_active` ile
/// **veritabanı seviyesinde** korunur.
@DriftAccessor(tables: [Carts])
class CartsDao extends DatabaseAccessor<CanteenDatabase> with _$CartsDaoMixin {
  CartsDao(super.db);

  Future<Cart?> findActive() =>
      (select(carts)
            ..where((c) => c.status.equalsValue(CartStatus.active))
            ..limit(1))
          .getSingleOrNull();

  Future<Cart?> findById(int id) =>
      (select(carts)..where((c) => c.id.equals(id))).getSingleOrNull();

  Future<int> insertCart(CartsCompanion cart) => into(carts).insert(cart);

  Future<int> updateStatus(int id, CartStatus status) =>
      (update(carts)..where((c) => c.id.equals(id))).write(
        CartsCompanion(status: Value(status), updatedAt: Value(_now())),
      );

  DateTime _now() => attachedDatabase.clock().toUtc();
}

// ---------------------------------------------------------------------------
// 7 — cart_items
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [CartItems])
class CartItemsDao extends DatabaseAccessor<CanteenDatabase>
    with _$CartItemsDaoMixin {
  CartItemsDao(super.db);

  Future<List<CartItem>> listOfCart(int cartId) =>
      (select(cartItems)..where((i) => i.cartId.equals(cartId))).get();

  Future<int> insertItem(CartItemsCompanion item) =>
      into(cartItems).insert(item);

  Future<int> deleteById(int id) =>
      (delete(cartItems)..where((i) => i.id.equals(id))).go();

  Future<int> deleteOfCart(int cartId) =>
      (delete(cartItems)..where((i) => i.cartId.equals(cartId))).go();
}

// ---------------------------------------------------------------------------
// 8 — sale_items
// ---------------------------------------------------------------------------

/// SaleItem satırları **immutable**'dır (rules/02 §3): snapshot alanları
/// yazıldıktan sonra değiştirilmez. Bu DAO update metodu **sunmaz.**
@DriftAccessor(tables: [SaleItems])
class SaleItemsDao extends DatabaseAccessor<CanteenDatabase>
    with _$SaleItemsDaoMixin {
  SaleItemsDao(super.db);

  Future<List<SaleItem>> listOfSale(int saleId) =>
      (select(saleItems)..where((i) => i.saleId.equals(saleId))).get();

  Future<List<SaleItem>> listOfProduct(int productId, {int limit = 100}) =>
      (select(saleItems)
            ..where((i) => i.productId.equals(productId))
            ..limit(limit))
          .get();

  /// Bu ürünün geçtiği satış satırı sayısı.
  ///
  /// BR-PROD-014 · EC-PROD-020: **kalıcı silme** kararının diğer yarısıdır —
  /// satılmış ürün silinemez, çünkü snapshot'lar anlamsızlaşır ve raporlar
  /// bozulur. Sayım SQL tarafındadır (rules/01 §8).
  ///
  /// İptal edilmiş satışların satırları da sayılır: iptal, satış kaydını
  /// **silmez** (BR-GEN-002) ve satır ürüne referans vermeye devam eder.
  Future<int> countOfProduct(int productId) async {
    final total = saleItems.id.count();
    final row =
        await (selectOnly(saleItems)
              ..addColumns([total])
              ..where(saleItems.productId.equals(productId)))
            .getSingle();
    return row.read(total) ?? 0;
  }

  Future<int> insertItem(SaleItemsCompanion item) =>
      into(saleItems).insert(item);
}

// ---------------------------------------------------------------------------
// 9 — returns
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [Returns])
class ReturnsDao extends DatabaseAccessor<CanteenDatabase>
    with _$ReturnsDaoMixin {
  ReturnsDao(super.db);

  Future<Return?> findById(int id) =>
      (select(returns)..where((r) => r.id.equals(id))).getSingleOrNull();

  Future<List<Return>> listOfSale(int saleId) =>
      (select(returns)..where((r) => r.saleId.equals(saleId))).get();

  Future<int> insertReturn(ReturnsCompanion value) =>
      into(returns).insert(value);
}

// ---------------------------------------------------------------------------
// 10 — return_items
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [ReturnItems])
class ReturnItemsDao extends DatabaseAccessor<CanteenDatabase>
    with _$ReturnItemsDaoMixin {
  ReturnItemsDao(super.db);

  Future<List<ReturnItem>> listOfReturn(int returnId) =>
      (select(returnItems)..where((i) => i.returnId.equals(returnId))).get();

  Future<int> insertItem(ReturnItemsCompanion item) =>
      into(returnItems).insert(item);
}

// ---------------------------------------------------------------------------
// 11 — audit_logs
// ---------------------------------------------------------------------------

/// rules/03 §9 · rules/04 §8:
///   Audit kayıtları **düzenlenemez ve silinemez.** Bu DAO update/delete
///   metodu **sunmaz.**
///   **Parola, recovery code, hash ve salt ASLA yazılmaz.**
@DriftAccessor(tables: [AuditLogs])
class AuditLogsDao extends DatabaseAccessor<CanteenDatabase>
    with _$AuditLogsDaoMixin {
  AuditLogsDao(super.db);

  Future<int> insertLog(AuditLogsCompanion log) => into(auditLogs).insert(log);

  /// Alan bazlı kayıt — çağıranın Drift `Value`/companion tiplerine ihtiyacı
  /// olmasın diye vardır (rules/01 §1: Drift ayrıntısı `data/` içinde kalır).
  ///
  /// [oldValue] / [newValue] / [metadata] **hazır JSON metnidir**; bu DAO
  /// serileştirme yapmaz. ⚠️ Parola, recovery code, hash ve salt bu alanların
  /// hiçbirine yazılmaz (REQ-AUDIT-004 · rules/04 §8).
  Future<int> record({
    required DateTime createdAt,
    required String action,
    required String entityType,
    int? userId,
    int? entityId,
    String? oldValue,
    String? newValue,
    String? metadata,
  }) {
    return insertLog(
      AuditLogsCompanion.insert(
        createdAt: createdAt,
        action: action,
        entityType: entityType,
        userId: Value(userId),
        entityId: Value(entityId),
        oldValue: Value(oldValue),
        newValue: Value(newValue),
        metadata: Value(metadata),
      ),
    );
  }

  Future<List<AuditLog>> listRecent({int limit = 100, int offset = 0}) =>
      (select(auditLogs)
            ..orderBy([
              (a) => OrderingTerm(
                expression: a.createdAt,
                mode: OrderingMode.desc,
              ),
            ])
            ..limit(limit, offset: offset))
          .get();

  Future<List<AuditLog>> listOfEntity(String entityType, int entityId) =>
      (select(auditLogs)..where(
            (a) =>
                a.entityType.equals(entityType) & a.entityId.equals(entityId),
          ))
          .get();
}

// ---------------------------------------------------------------------------
// 12 — app_settings
// ---------------------------------------------------------------------------

/// ⚠️ BR-SEC-001 / REQ-DB-010: bu tabloya **düz metin parola veya recovery code
/// yazılmaz.** Yalnızca salt'lı SHA-256 hash'leri saklanır (Faz 3).
@DriftAccessor(tables: [AppSettings])
class AppSettingsDao extends DatabaseAccessor<CanteenDatabase>
    with _$AppSettingsDaoMixin {
  AppSettingsDao(super.db);

  Future<String?> read(String key) async {
    final row =
        await (select(appSettings)
              ..where((s) => s.key.equals(key))
              ..limit(1))
            .getSingleOrNull();
    return row?.value;
  }

  Future<void> write(String key, String value) async {
    await into(appSettings).insertOnConflictUpdate(
      AppSettingsCompanion.insert(
        key: key,
        value: value,
        updatedAt: attachedDatabase.clock().toUtc(),
      ),
    );
  }

  Future<int> remove(String key) =>
      (delete(appSettings)..where((s) => s.key.equals(key))).go();
}
