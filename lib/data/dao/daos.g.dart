// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'daos.dart';

// ignore_for_file: type=lint
mixin _$UsersDaoMixin on DatabaseAccessor<CanteenDatabase> {
  $UsersTable get users => attachedDatabase.users;
  UsersDaoManager get managers => UsersDaoManager(this);
}

class UsersDaoManager {
  final _$UsersDaoMixin _db;
  UsersDaoManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
}

mixin _$CategoriesDaoMixin on DatabaseAccessor<CanteenDatabase> {
  $CategoriesTable get categories => attachedDatabase.categories;
  $VatRatesTable get vatRates => attachedDatabase.vatRates;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $ProductsTable get products => attachedDatabase.products;
  $UsersTable get users => attachedDatabase.users;
  $SalesTable get sales => attachedDatabase.sales;
  $SaleItemsTable get saleItems => attachedDatabase.saleItems;
  CategoriesDaoManager get managers => CategoriesDaoManager(this);
}

class CategoriesDaoManager {
  final _$CategoriesDaoMixin _db;
  CategoriesDaoManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$VatRatesTableTableManager get vatRates =>
      $$VatRatesTableTableManager(_db.attachedDatabase, _db.vatRates);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db.attachedDatabase, _db.suppliers);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db.attachedDatabase, _db.sales);
  $$SaleItemsTableTableManager get saleItems =>
      $$SaleItemsTableTableManager(_db.attachedDatabase, _db.saleItems);
}

mixin _$SuppliersDaoMixin on DatabaseAccessor<CanteenDatabase> {
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $CategoriesTable get categories => attachedDatabase.categories;
  $VatRatesTable get vatRates => attachedDatabase.vatRates;
  $ProductsTable get products => attachedDatabase.products;
  SuppliersDaoManager get managers => SuppliersDaoManager(this);
}

class SuppliersDaoManager {
  final _$SuppliersDaoMixin _db;
  SuppliersDaoManager(this._db);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db.attachedDatabase, _db.suppliers);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$VatRatesTableTableManager get vatRates =>
      $$VatRatesTableTableManager(_db.attachedDatabase, _db.vatRates);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
}

mixin _$VatRatesDaoMixin on DatabaseAccessor<CanteenDatabase> {
  $VatRatesTable get vatRates => attachedDatabase.vatRates;
  $CategoriesTable get categories => attachedDatabase.categories;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $ProductsTable get products => attachedDatabase.products;
  VatRatesDaoManager get managers => VatRatesDaoManager(this);
}

class VatRatesDaoManager {
  final _$VatRatesDaoMixin _db;
  VatRatesDaoManager(this._db);
  $$VatRatesTableTableManager get vatRates =>
      $$VatRatesTableTableManager(_db.attachedDatabase, _db.vatRates);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db.attachedDatabase, _db.suppliers);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
}

mixin _$ProductBarcodesDaoMixin on DatabaseAccessor<CanteenDatabase> {
  $CategoriesTable get categories => attachedDatabase.categories;
  $VatRatesTable get vatRates => attachedDatabase.vatRates;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $ProductsTable get products => attachedDatabase.products;
  $ProductBarcodesTable get productBarcodes => attachedDatabase.productBarcodes;
  ProductBarcodesDaoManager get managers => ProductBarcodesDaoManager(this);
}

class ProductBarcodesDaoManager {
  final _$ProductBarcodesDaoMixin _db;
  ProductBarcodesDaoManager(this._db);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$VatRatesTableTableManager get vatRates =>
      $$VatRatesTableTableManager(_db.attachedDatabase, _db.vatRates);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db.attachedDatabase, _db.suppliers);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$ProductBarcodesTableTableManager get productBarcodes =>
      $$ProductBarcodesTableTableManager(
        _db.attachedDatabase,
        _db.productBarcodes,
      );
}

mixin _$CartsDaoMixin on DatabaseAccessor<CanteenDatabase> {
  $UsersTable get users => attachedDatabase.users;
  $CartsTable get carts => attachedDatabase.carts;
  CartsDaoManager get managers => CartsDaoManager(this);
}

class CartsDaoManager {
  final _$CartsDaoMixin _db;
  CartsDaoManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$CartsTableTableManager get carts =>
      $$CartsTableTableManager(_db.attachedDatabase, _db.carts);
}

mixin _$CartItemsDaoMixin on DatabaseAccessor<CanteenDatabase> {
  $UsersTable get users => attachedDatabase.users;
  $CartsTable get carts => attachedDatabase.carts;
  $CategoriesTable get categories => attachedDatabase.categories;
  $VatRatesTable get vatRates => attachedDatabase.vatRates;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $ProductsTable get products => attachedDatabase.products;
  $CartItemsTable get cartItems => attachedDatabase.cartItems;
  CartItemsDaoManager get managers => CartItemsDaoManager(this);
}

class CartItemsDaoManager {
  final _$CartItemsDaoMixin _db;
  CartItemsDaoManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$CartsTableTableManager get carts =>
      $$CartsTableTableManager(_db.attachedDatabase, _db.carts);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$VatRatesTableTableManager get vatRates =>
      $$VatRatesTableTableManager(_db.attachedDatabase, _db.vatRates);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db.attachedDatabase, _db.suppliers);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$CartItemsTableTableManager get cartItems =>
      $$CartItemsTableTableManager(_db.attachedDatabase, _db.cartItems);
}

mixin _$SaleItemsDaoMixin on DatabaseAccessor<CanteenDatabase> {
  $UsersTable get users => attachedDatabase.users;
  $SalesTable get sales => attachedDatabase.sales;
  $CategoriesTable get categories => attachedDatabase.categories;
  $VatRatesTable get vatRates => attachedDatabase.vatRates;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $ProductsTable get products => attachedDatabase.products;
  $SaleItemsTable get saleItems => attachedDatabase.saleItems;
  SaleItemsDaoManager get managers => SaleItemsDaoManager(this);
}

class SaleItemsDaoManager {
  final _$SaleItemsDaoMixin _db;
  SaleItemsDaoManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db.attachedDatabase, _db.sales);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$VatRatesTableTableManager get vatRates =>
      $$VatRatesTableTableManager(_db.attachedDatabase, _db.vatRates);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db.attachedDatabase, _db.suppliers);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$SaleItemsTableTableManager get saleItems =>
      $$SaleItemsTableTableManager(_db.attachedDatabase, _db.saleItems);
}

mixin _$ReturnsDaoMixin on DatabaseAccessor<CanteenDatabase> {
  $UsersTable get users => attachedDatabase.users;
  $SalesTable get sales => attachedDatabase.sales;
  $ReturnsTable get returns => attachedDatabase.returns;
  ReturnsDaoManager get managers => ReturnsDaoManager(this);
}

class ReturnsDaoManager {
  final _$ReturnsDaoMixin _db;
  ReturnsDaoManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db.attachedDatabase, _db.sales);
  $$ReturnsTableTableManager get returns =>
      $$ReturnsTableTableManager(_db.attachedDatabase, _db.returns);
}

mixin _$ReturnItemsDaoMixin on DatabaseAccessor<CanteenDatabase> {
  $UsersTable get users => attachedDatabase.users;
  $SalesTable get sales => attachedDatabase.sales;
  $ReturnsTable get returns => attachedDatabase.returns;
  $CategoriesTable get categories => attachedDatabase.categories;
  $VatRatesTable get vatRates => attachedDatabase.vatRates;
  $SuppliersTable get suppliers => attachedDatabase.suppliers;
  $ProductsTable get products => attachedDatabase.products;
  $SaleItemsTable get saleItems => attachedDatabase.saleItems;
  $ReturnItemsTable get returnItems => attachedDatabase.returnItems;
  ReturnItemsDaoManager get managers => ReturnItemsDaoManager(this);
}

class ReturnItemsDaoManager {
  final _$ReturnItemsDaoMixin _db;
  ReturnItemsDaoManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$SalesTableTableManager get sales =>
      $$SalesTableTableManager(_db.attachedDatabase, _db.sales);
  $$ReturnsTableTableManager get returns =>
      $$ReturnsTableTableManager(_db.attachedDatabase, _db.returns);
  $$CategoriesTableTableManager get categories =>
      $$CategoriesTableTableManager(_db.attachedDatabase, _db.categories);
  $$VatRatesTableTableManager get vatRates =>
      $$VatRatesTableTableManager(_db.attachedDatabase, _db.vatRates);
  $$SuppliersTableTableManager get suppliers =>
      $$SuppliersTableTableManager(_db.attachedDatabase, _db.suppliers);
  $$ProductsTableTableManager get products =>
      $$ProductsTableTableManager(_db.attachedDatabase, _db.products);
  $$SaleItemsTableTableManager get saleItems =>
      $$SaleItemsTableTableManager(_db.attachedDatabase, _db.saleItems);
  $$ReturnItemsTableTableManager get returnItems =>
      $$ReturnItemsTableTableManager(_db.attachedDatabase, _db.returnItems);
}

mixin _$AuditLogsDaoMixin on DatabaseAccessor<CanteenDatabase> {
  $UsersTable get users => attachedDatabase.users;
  $AuditLogsTable get auditLogs => attachedDatabase.auditLogs;
  AuditLogsDaoManager get managers => AuditLogsDaoManager(this);
}

class AuditLogsDaoManager {
  final _$AuditLogsDaoMixin _db;
  AuditLogsDaoManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$AuditLogsTableTableManager get auditLogs =>
      $$AuditLogsTableTableManager(_db.attachedDatabase, _db.auditLogs);
}

mixin _$AppSettingsDaoMixin on DatabaseAccessor<CanteenDatabase> {
  $AppSettingsTable get appSettings => attachedDatabase.appSettings;
  AppSettingsDaoManager get managers => AppSettingsDaoManager(this);
}

class AppSettingsDaoManager {
  final _$AppSettingsDaoMixin _db;
  AppSettingsDaoManager(this._db);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db.attachedDatabase, _db.appSettings);
}
