/// Stok defterinin **tek yazım noktası** — BR-STOCK-001…004 · docs/13
///
/// ## Bu dosya neden ŞİMDİ var
///
/// `rules/02 §4`: *"`stock_quantity` **yalnızca** `StockService` üzerinden
/// değişir. Başka hiçbir kod yolu bu alana yazmaz."* Aksi hâlde RSK-008
/// (sessiz stok sapması) gerçekleşir.
///
/// REQ-PROD-007 · BR-STOCK-003 ürün oluştururken başlangıç stoğunun
/// **doğrudan `stock_quantity`'ye yazılmasını yasaklar**; değer bir `initial`
/// stok hareketi üretmek zorundadır. Faz 3c'de ürün oluşturma geldiği için
/// deftere ilk satırı yazacak bir yer gerekti — ve o yer, yukarıdaki kural
/// gereği, başka hiçbir sınıf olamazdı.
///
/// ## Kapsam — bilinçli olarak MİNİMAL
///
/// | Var | Yok (**Faz 6**) |
/// |---|---|
/// | `initial` hareketi | Stok girişi (`stockEntry`) |
/// | | Fire (`waste`) |
/// | | Düzeltme / sayım (`adjustment`) |
/// | | Satış / iptal / iade hareketleri (Faz 5, 7) |
/// | | Import düzeltmesi (Faz 10), restore tabanı (Faz 9) |
///
/// Bu sınıf Faz 6'nın genişleteceği **dikiş noktasıdır**: kalan sekiz hareket
/// tipi buraya eklenecek, `stock_quantity`'ye yazan başka bir yol
/// **açılmayacaktır**. Bugünden fazlasını yazmak `rules/06 §5`'in yasakladığı
/// "sonraki fazın işini öne almak" olurdu.
///
/// ## Audit
///
/// Bu servis audit kaydı **yazmaz.** docs/18 §3 stok için üç action tanımlar
/// (`stockEntryCreated`, `stockWasteRecorded`, `stockAdjusted`) — `initial`
/// için tanımlı bir action **yoktur** ve `rules/00 §6` olmayanı uydurmayı
/// yasaklar. Başlangıç stoğu `productCreated` kaydının metadata'sında yaşar
/// (`ProductService`), çünkü denetim açısından tek bir olayın parçasıdır.
library;

import '../../core/money/money.dart';
import '../../core/result/result.dart';
import '../../data/db/canteen_database.dart' show CanteenDatabase;
import '../../domain/enums/stock_movement_type.dart';
import '../../domain/repositories/stock_repository.dart';
import 'stock_failures.dart';

class StockService {
  final CanteenDatabase _db;
  final StockRepository _stock;
  final DateTime Function() _clock;

  StockService({
    required CanteenDatabase db,
    required StockRepository stock,
    DateTime Function()? clock,
  }) : _db = db,
       _stock = stock,
       _clock = clock ?? db.clock;

  /// Ürün oluşturulurken girilen başlangıç stoğunu deftere yazar —
  /// **REQ-PROD-007 · BR-STOCK-003 · docs/13 §2.**
  ///
  /// ```text
  /// Tek transaction:
  ///   stock_movements          type=initial, delta=+N, resulting_stock=N
  ///   products.stock_quantity  N
  /// ```
  ///
  /// | Kural | Davranış |
  /// |---|---|
  /// | BR-STOCK-004 — `quantity_delta` asla `0` olamaz | [quantity] `0` ise **hiç hareket yazılmaz** |
  /// | docs/13 §2 — `initial` yönü `+` | Negatif miktar reddedilir |
  /// | docs/13 §2 — ürün başına en fazla bir kez | Defterde hareket varsa reddedilir |
  /// | BR-STOCK-008 | `resulting_stock` her harekette yazılır |
  /// | BR-STOCK-002 | Önbellek defterle **aynı transaction** içinde güncellenir |
  ///
  /// Dönen değer hareket sonrası stoktur (hareket yazılmadıysa `0`).
  ///
  /// [unitCost] docs/13 §2'de `initial` için **opsiyoneldir**; çağıran ürünün
  /// alış fiyatını verir — o an bilinen maliyet budur ve sonradan
  /// türetilemez.
  ///
  /// Transaction **burada** açılır (rules/01 §5). Çağıran zaten bir
  /// transaction içindeyse drift bunu savepoint olarak iç içe çalıştırır;
  /// böylece ürün + barkod + hareket + audit bütünlüğü her iki durumda da
  /// korunur.
  Future<Result<int>> recordInitialStock({
    required int productId,
    required int quantity,
    required int userId,
    Money? unitCost,
  }) async {
    if (quantity < 0) return const Err(StockFailures.negativeInitialStock);

    // BR-STOCK-004: delta `0` olamaz. Başlangıç stoğu 0 olan ürün defterde
    // satır açmaz — "hareket yok" ile "0 hareketi var" aynı şey değildir.
    if (quantity == 0) return const Ok(0);

    final now = _clock().toUtc();

    return _db.transaction(() async {
      if (await _stock.countMovements(productId) > 0) {
        return const Err<int>(StockFailures.alreadyInitialized);
      }

      // Defter boş olduğu için hareket sonrası stok = miktarın kendisidir.
      // Invariant açıkça korunur: stock_quantity == Σ quantity_delta.
      await _stock.appendMovement(
        productId: productId,
        type: StockMovementType.initial,
        quantityDelta: quantity,
        resultingStock: quantity,
        userId: userId,
        createdAtUtc: now,
        unitCost: unitCost,
      );
      await _stock.writeStockQuantity(productId, quantity);

      return Ok<int>(quantity);
    });
  }
}
