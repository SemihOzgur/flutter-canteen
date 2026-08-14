/// Stok repository sözleşmesi — **REQ-ARCH-004**
///
/// ## Neden yazma metodu yok
///
/// `stock_quantity` **yalnızca** `StockService` üzerinden değişir
/// (rules/02 §4); başka hiçbir kod yolu bu alana yazmaz. Aksi hâlde RSK-008
/// (sessiz stok sapması) gerçekleşir. `StockService` **Faz 6** kapsamındadır.
///
/// Faz 2 defteri **okunabilir** kılar: "Bu ürünün stoğu neden 12?" sorusunun
/// defterden yanıtlanabilmesi (BR-STOCK-010) buradan başlar.
library;

import '../../core/result/result.dart';
import '../enums/stock_reference_type.dart';
import '../models/stock_movement.dart';

abstract interface class StockRepository {
  Future<Result<StockMovement>> findById(int id);

  /// Ürün stok geçmişi — `ix_movements_product_date` kullanır (docs/05 §3).
  Future<List<StockMovement>> movementsOf(
    int productId, {
    int limit = 100,
    int offset = 0,
  });

  /// Defter toplamı — BR-STOCK-002 tutarlılık invariant'ının ölçüm noktası:
  /// `products.stock_quantity == Σ quantity_delta`.
  ///
  /// Toplama **SQL tarafında** yapılır; Dart'ta döngüyle toplanmaz
  /// (rules/01 §8).
  Future<int> sumQuantityDelta(int productId);

  /// Bir satışa/iadeye bağlı hareketler — `ix_movements_reference`.
  Future<List<StockMovement>> findByReference({
    required StockReferenceType referenceType,
    required int referenceId,
  });
}
