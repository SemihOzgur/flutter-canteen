/// Stok repository sözleşmesi — **REQ-ARCH-004**
///
/// ## Yazma metotlarının tek çağıranı vardır
///
/// `stock_quantity` **yalnızca** `StockService` üzerinden değişir
/// (rules/02 §4); başka hiçbir kod yolu bu alana yazmaz. Aksi hâlde RSK-008
/// (sessiz stok sapması) gerçekleşir.
///
/// Bu arayüzdeki iki yazma metodu ([appendMovement] ve [writeStockQuantity])
/// **birlikte ve yalnızca** o servis tarafından, tek bir transaction içinde
/// kullanılır. İkisi ayrı ayrı çağrılırsa BR-STOCK-003 invariant'ı
/// (`stock_quantity == Σ quantity_delta`) bozulur.
///
/// Defter **okunabilirdir**: "Bu ürünün stoğu neden 12?" sorusu buradan
/// yanıtlanır (BR-STOCK-010).
library;

import '../../core/money/money.dart';
import '../../core/result/result.dart';
import '../enums/stock_movement_type.dart';
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

  /// Ürünün defterdeki hareket sayısı.
  ///
  /// BR-PROD-014 · EC-PROD-021: **kalıcı silme** kararının yarısı budur —
  /// hareketi olan ürün silinemez, çünkü defter referansı korunmalıdır.
  Future<int> countMovements(int productId);

  /// Deftere yeni bir hareket yazar ve `id`'sini döner.
  ///
  /// ⚠️ **Yalnızca `StockService` çağırır** (rules/02 §4). Transaction
  /// çağırana aittir (rules/01 §5).
  ///
  /// BR-STOCK-004: [quantityDelta] `0` olamaz — şemada `CHECK` ile de
  /// zorlanır. BR-STOCK-008: [resultingStock] her harekette yazılır.
  /// BR-STOCK-005: kayıt yazıldıktan sonra güncellenmez/silinmez; bu yüzden
  /// arayüzde `update`/`delete` yoktur.
  Future<int> appendMovement({
    required int productId,
    required StockMovementType type,
    required int quantityDelta,
    required int resultingStock,
    required int userId,
    required DateTime createdAtUtc,
    Money? unitCost,
    StockReferenceType? referenceType,
    int? referenceId,
    int? supplierId,
    String? note,
  });

  /// `products.stock_quantity` türetilmiş önbelleğini yazar (BR-STOCK-002).
  ///
  /// ⚠️ **Yalnızca `StockService` çağırır** ve daima [appendMovement] ile
  /// **aynı transaction** içindedir.
  Future<int> writeStockQuantity(int productId, int quantity);
}
