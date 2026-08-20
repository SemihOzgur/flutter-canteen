/// Satış servislerinin provider'ları (OD-002 — Riverpod).
///
/// Desen `application/stock/providers.dart` ile aynıdır: servis **application**
/// katmanına aittir, kurulum bilgisi de buradadır; `data/db/providers.dart`
/// yalnızca bağlantı, repository ve DAO'ları verir (rules/01 §1).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/providers.dart';
import '../auth/providers.dart' show appLoggerProvider;
import '../audit/providers.dart';
import '../stock/providers.dart';
import 'cart_service.dart';
import 'return_service.dart';
import 'sale_service.dart';

/// Aktif sepet — BR-CART-001.
final cartServiceProvider = Provider<CartService>(
  (ref) => CartService(
    db: ref.watch(canteenDatabaseProvider),
    carts: ref.watch(cartsDaoProvider),
    cartItems: ref.watch(cartItemsDaoProvider),
    vatRates: ref.watch(vatRatesDaoProvider),
    products: ref.watch(productRepositoryProvider),
  ),
);

/// Satış tamamlama — BR-SALE-005 (atomik).
final saleServiceProvider = Provider<SaleService>(
  (ref) => SaleService(
    db: ref.watch(canteenDatabaseProvider),
    cartService: ref.watch(cartServiceProvider),
    carts: ref.watch(cartsDaoProvider),
    vatRates: ref.watch(vatRatesDaoProvider),
    appSettings: ref.watch(appSettingsDaoProvider),
    auditLogs: ref.watch(auditLogsDaoProvider),
    products: ref.watch(productRepositoryProvider),
    sales: ref.watch(saleRepositoryProvider),
    stockService: ref.watch(stockServiceProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

/// docs/14 — satış iptali ve iade. İkisi de **atomiktir** (REQ-RET-010).
final returnServiceProvider = Provider<ReturnService>(
  (ref) => ReturnService(
    db: ref.watch(canteenDatabaseProvider),
    sales: ref.watch(saleRepositoryProvider),
    stockService: ref.watch(stockServiceProvider),
    audit: ref.watch(auditServiceProvider),
    clock: ref.watch(canteenDatabaseProvider).clock,
  ),
);
