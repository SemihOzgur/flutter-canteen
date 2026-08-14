/// Veritabanı ve repository provider'ları (OD-002 — Riverpod).
///
/// ## Katman sınırı
///
/// Bu dosya `data/` içindedir. Presentation katmanı **yalnızca** provider'ları
/// tüketir; `import 'package:drift/...'` presentation altında görülürse bu bir
/// bug'dır (rules/01 §1).
///
/// Repository provider'ları **domain arayüz tipini** döndürür — tüketiciler
/// Drift implementasyonunu görmez.
///
/// ## Yaşam döngüsü
///
/// Veritabanı bağlantısı `main.dart` içinde açılır ve
/// [canteenDatabaseProvider] `ProviderScope` override'ı ile enjekte edilir.
/// Böylece bağlantı kontrolsüz global/statik bir duruma dönüşmez
/// ve kapanışta düzgün `close()` edilebilir (Windows dosya kilidi — rules/05 §6).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/sale_repository.dart';
import '../../domain/repositories/stock_repository.dart';
import '../dao/daos.dart';
import '../repositories/drift_product_repository.dart';
import '../repositories/drift_sale_repository.dart';
import '../repositories/drift_stock_repository.dart';
import 'canteen_database.dart';

/// Açık veritabanı bağlantısı.
///
/// `main.dart` bunu `overrideWithValue` ile sağlar. Override edilmezse
/// bilinçli olarak hata verir — sessizce ikinci bir bağlantı açılmaz.
final canteenDatabaseProvider = Provider<CanteenDatabase>((ref) {
  throw StateError(
    'canteenDatabaseProvider override edilmedi. Veritabanı bootstrap sırasında '
    'açılır ve ProviderScope override ile sağlanır (bkz. main.dart).',
  );
});

// --- Repository'ler (REQ-ARCH-004) ----------------------------------------

final productRepositoryProvider = Provider<ProductRepository>(
  (ref) => DriftProductRepository(ref.watch(canteenDatabaseProvider)),
);

final saleRepositoryProvider = Provider<SaleRepository>(
  (ref) => DriftSaleRepository(ref.watch(canteenDatabaseProvider)),
);

final stockRepositoryProvider = Provider<StockRepository>(
  (ref) => DriftStockRepository(ref.watch(canteenDatabaseProvider)),
);

// --- DAO'lar (interface'siz 12 tablo) --------------------------------------

final usersDaoProvider = Provider<UsersDao>(
  (ref) => UsersDao(ref.watch(canteenDatabaseProvider)),
);

final categoriesDaoProvider = Provider<CategoriesDao>(
  (ref) => CategoriesDao(ref.watch(canteenDatabaseProvider)),
);

final suppliersDaoProvider = Provider<SuppliersDao>(
  (ref) => SuppliersDao(ref.watch(canteenDatabaseProvider)),
);

final vatRatesDaoProvider = Provider<VatRatesDao>(
  (ref) => VatRatesDao(ref.watch(canteenDatabaseProvider)),
);

final productBarcodesDaoProvider = Provider<ProductBarcodesDao>(
  (ref) => ProductBarcodesDao(ref.watch(canteenDatabaseProvider)),
);

final cartsDaoProvider = Provider<CartsDao>(
  (ref) => CartsDao(ref.watch(canteenDatabaseProvider)),
);

final cartItemsDaoProvider = Provider<CartItemsDao>(
  (ref) => CartItemsDao(ref.watch(canteenDatabaseProvider)),
);

final saleItemsDaoProvider = Provider<SaleItemsDao>(
  (ref) => SaleItemsDao(ref.watch(canteenDatabaseProvider)),
);

final returnsDaoProvider = Provider<ReturnsDao>(
  (ref) => ReturnsDao(ref.watch(canteenDatabaseProvider)),
);

final returnItemsDaoProvider = Provider<ReturnItemsDao>(
  (ref) => ReturnItemsDao(ref.watch(canteenDatabaseProvider)),
);

final auditLogsDaoProvider = Provider<AuditLogsDao>(
  (ref) => AuditLogsDao(ref.watch(canteenDatabaseProvider)),
);

final appSettingsDaoProvider = Provider<AppSettingsDao>(
  (ref) => AppSettingsDao(ref.watch(canteenDatabaseProvider)),
);
