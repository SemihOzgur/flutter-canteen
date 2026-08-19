/// Stok servisinin provider'ı (OD-002 — Riverpod).
///
/// Desen `application/reference/providers.dart` ile aynıdır: servis
/// **application** katmanına aittir, bu yüzden kurulum bilgisi de buradadır;
/// `data/db/providers.dart` yalnızca bağlantı, repository ve DAO'ları verir
/// (rules/01 §1 — bağımlılık yönü daima aşağı).
///
/// Tüketicileri: ürün oluşturma (REQ-PROD-007), satış (Faz 5) ve Faz 6'nın
/// stok girişi / fire / düzeltme akışları.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/providers.dart';
import '../audit/providers.dart';
import 'stock_service.dart';

/// Stok defterinin tek yazım noktası (rules/02 §4).
final stockServiceProvider = Provider<StockService>(
  (ref) => StockService(
    db: ref.watch(canteenDatabaseProvider),
    stock: ref.watch(stockRepositoryProvider),
    products: ref.watch(productRepositoryProvider),
    audit: ref.watch(auditServiceProvider),
  ),
);
