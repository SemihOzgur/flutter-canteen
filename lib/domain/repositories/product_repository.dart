/// Ürün repository sözleşmesi — **REQ-ARCH-004**
///
/// docs/03-architecture.md §4 · rules/01 §4: interface yalnızca Product, Sale ve
/// Stock için yazılır. Diğer tablolar doğrudan DAO ile kullanılır.
///
/// Bu dosya `domain/` içindedir ve **hiçbir Drift/Flutter/dart:io bağımlılığı
/// taşımaz** (rules/01 §1).
///
/// ## Faz 2 kapsam sınırı
///
/// Burada **kalıcılık** işlemleri vardır; iş akışı orkestrasyonu yoktur.
/// `stock_quantity` bu arayüzden yazılamaz — tek yazım noktası `StockService`
/// olacaktır (rules/02 §4, Faz 6).
library;

import '../../core/result/result.dart';
import '../models/product.dart';

abstract interface class ProductRepository {
  Future<Result<Product>> findById(int id);

  /// Barkod lookup — satış hızının tamamı buna bağlıdır (docs/05 §3, 🔴).
  ///
  /// Bulunamazsa `Failure('product_not_found')` döner; bu **beklenen** bir
  /// sonuçtur (bilinmeyen barkod akışı, rules/02 §10) ve exception fırlatmaz.
  Future<Result<Product>> findByBarcode(String barcode);

  /// Ad araması — yalnızca aktif ürünler, SQL tarafında sıralı ve sayfalı
  /// (docs/05 §3.1).
  Future<List<Product>> searchByName(String query, {int limit = 50});

  Future<List<Product>> listActive({int limit = 100, int offset = 0});

  /// Ürünü kaydeder ve yeni `id`'yi döner.
  Future<Result<int>> create(NewProduct product);

  Future<Result<void>> update(Product product);

  /// BR-PROD-005 — barkod global benzersizdir.
  /// Çakışma → `Failure('barcode_exists')`.
  Future<Result<int>> addBarcode({
    required int productId,
    required String barcode,
    bool isPrimary = false,
  });

  Future<List<String>> barcodesOf(int productId);
}
