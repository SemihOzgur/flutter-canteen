/// Stok servisinin provider'ı (OD-002 — Riverpod).
///
/// Desen `application/reference/providers.dart` ile aynıdır: servis
/// **application** katmanına aittir, bu yüzden kurulum bilgisi de buradadır;
/// `data/db/providers.dart` yalnızca bağlantı, repository ve DAO'ları verir
/// (rules/01 §1 — bağımlılık yönü daima aşağı).
///
/// Faz 6 stok ekranları bu provider'ı **genişleterek** kullanacaktır; bugün
/// tek tüketicisi ürün oluşturma akışıdır (REQ-PROD-007).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/providers.dart';
import 'stock_service.dart';

/// Stok defterinin tek yazım noktası (rules/02 §4).
final stockServiceProvider = Provider<StockService>(
  (ref) => StockService(
    db: ref.watch(canteenDatabaseProvider),
    stock: ref.watch(stockRepositoryProvider),
  ),
);
