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

  Future<User?> findByUsername(String username) =>
      (select(users)
            ..where((u) => u.username.equals(username.toLowerCase()))
            ..limit(1))
          .getSingleOrNull();

  Future<List<User>> listActive() =>
      (select(users)..where((u) => u.isActive.equals(true))).get();

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

@DriftAccessor(tables: [Categories])
class CategoriesDao extends DatabaseAccessor<CanteenDatabase>
    with _$CategoriesDaoMixin {
  CategoriesDao(super.db);

  Future<Category?> findById(int id) =>
      (select(categories)..where((c) => c.id.equals(id))).getSingleOrNull();

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

  /// BR-CAT-004 — `Genel` sistem kategorisi.
  Future<Category?> findSystemCategory() =>
      (select(categories)
            ..where((c) => c.isSystem.equals(true))
            ..limit(1))
          .getSingleOrNull();

  Future<int> insertCategory(CategoriesCompanion category) =>
      into(categories).insert(category);

  Future<int> countAll() async {
    final count = categories.id.count();
    final row = await (selectOnly(categories)..addColumns([count])).getSingle();
    return row.read(count) ?? 0;
  }
}

// ---------------------------------------------------------------------------
// 3 — suppliers
// ---------------------------------------------------------------------------

@DriftAccessor(tables: [Suppliers])
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

  Future<int> insertSupplier(SuppliersCompanion supplier) =>
      into(suppliers).insert(supplier);
}

// ---------------------------------------------------------------------------
// 4 — vat_rates
// ---------------------------------------------------------------------------

/// BR-VAT-001: oranlar yönetilebilir; **koda gömülmez** (rules/02 §2).
/// Kurulumda oran **seed edilmez.**
@DriftAccessor(tables: [VatRates])
class VatRatesDao extends DatabaseAccessor<CanteenDatabase>
    with _$VatRatesDaoMixin {
  VatRatesDao(super.db);

  Future<VatRate?> findById(int id) =>
      (select(vatRates)..where((v) => v.id.equals(id))).getSingleOrNull();

  Future<List<VatRate>> listActive() =>
      (select(vatRates)..where((v) => v.isActive.equals(true))).get();

  Future<VatRate?> findDefault() =>
      (select(vatRates)
            ..where((v) => v.isDefault.equals(true) & v.isActive.equals(true))
            ..limit(1))
          .getSingleOrNull();

  Future<int> insertVatRate(VatRatesCompanion rate) =>
      into(vatRates).insert(rate);
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
