/// Ürün servisinin provider'ları (OD-002 — Riverpod).
///
/// Desen `application/reference/providers.dart` ile aynıdır.
///
/// ## Neden liste provider'ı yok
///
/// Kategori/tedarikçi/KDV ekranları var olduğu için onların liste
/// provider'ları da vardır. Ürün ekranları **Faz 3d ve sonrasına** aittir;
/// bugün tüketicisi olmayan bir `FutureProvider` ölü kod olurdu (rules/07).
/// Ayrıca ürün listesi **sayfalıdır** (REQ-PERF-006): parametresiz bir liste
/// provider'ı "tüm kayıtları belleğe alma" alışkanlığını davet ederdi
/// (rules/01 §8).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/providers.dart';
import '../../data/files/providers.dart';
import '../auth/providers.dart' show appLoggerProvider;
import '../stock/providers.dart';
import 'product_service.dart';

/// Ürün yönetimi (docs/09).
final productServiceProvider = Provider<ProductService>(
  (ref) => ProductService(
    db: ref.watch(canteenDatabaseProvider),
    products: ref.watch(productRepositoryProvider),
    stock: ref.watch(stockRepositoryProvider),
    stockService: ref.watch(stockServiceProvider),
    categories: ref.watch(categoriesDaoProvider),
    saleItems: ref.watch(saleItemsDaoProvider),
    auditLogs: ref.watch(auditLogsDaoProvider),
    appSettings: ref.watch(appSettingsDaoProvider),
    images: ref.watch(productImageStoreProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);
