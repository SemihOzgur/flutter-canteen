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
/// ## Kapsam
///
/// | Var | Yok |
/// |---|---|
/// | `initial` (Faz 3c) | Import düzeltmesi (**Faz 10**) |
/// | `sale` (Faz 5) | Restore tabanı (**Faz 9**) |
/// | `stockEntry` · `waste` · `adjustment` (Faz 6) | Restore tabanı (**Faz 9**) |
/// | `saleCancellation` · `return` (Faz 7) | Import düzeltmesi (**Faz 10**) |
///
/// `stock_quantity`'ye yazan **başka bir yol açılmaz**; kalan üç hareket tipi
/// de buraya eklenecektir.
///
/// ## Audit
///
/// Faz 6'dan itibaren stok işlemleri denetim kaydı yazar
/// (`stockEntryCreated`, `stockWasteRecorded`, `stockAdjusted` — docs/18 §3).
///
/// `initial` ve `sale` **yazmaz** ve bu bir eksik değildir: docs/18 §3 ikisi
/// için de action tanımlamaz, `rules/00 §6` olmayanı uydurmayı yasaklar.
/// Başlangıç stoğu `productCreated`, satış hareketi `saleCompleted` kaydının
/// parçasıdır — denetim açısından ikisi de tek bir olayın içindedir.
library;

import '../../core/money/money.dart';
import '../../core/result/result.dart';
import '../../data/db/canteen_database.dart' show CanteenDatabase;
import '../../domain/enums/stock_movement_type.dart';
import '../../domain/enums/stock_reference_type.dart';
import '../../domain/models/product.dart';
import '../../domain/models/stock_movement.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/stock_repository.dart';
import '../audit/audit_actions.dart';
import '../audit/audit_service.dart';
import 'stock_failures.dart';

/// Stok girişi satırı — docs/13 §5.
class StockEntryLine {
  final int productId;

  /// Pozitif tam sayı (BR-SALE-011 · şema `CHECK`).
  final int quantity;

  /// Bu girişteki birim alış fiyatı. `null` ise ürünün mevcut fiyatı kullanılır.
  final Money? unitCost;

  /// BR-STOCK-009 · REQ-STOCK-008 — ürünün alış fiyatı da güncellensin mi?
  ///
  /// Kararı **kullanıcı** verir (docs/13 §5); servis sormaz, uygular.
  final bool updateProductPurchasePrice;

  const StockEntryLine({
    required this.productId,
    required this.quantity,
    this.unitCost,
    this.updateProductPurchasePrice = false,
  });
}

/// Tamamlanan stok girişinin özeti.
class StockEntryReceipt {
  final int lineCount;
  final int unitCount;

  /// Σ(miktar × birim alış fiyatı) — girişin toplam maliyeti.
  final Money total;

  const StockEntryReceipt({
    required this.lineCount,
    required this.unitCount,
    required this.total,
  });
}

class StockService {
  final CanteenDatabase _db;
  final StockRepository _stock;
  final ProductRepository _products;
  final AuditService? _audit;
  final DateTime Function() _clock;

  StockService({
    required CanteenDatabase db,
    required StockRepository stock,
    required ProductRepository products,
    AuditService? audit,
    DateTime Function()? clock,
  }) : _db = db,
       _stock = stock,
       _products = products,
       _audit = audit,
       _clock = clock ?? db.clock;

  // --- Okuma — ekranların TEK kapısı (rules/01 §1) ------------------------

  /// Filtrelenebilir hareket listesi — docs/13 §8.
  ///
  /// Ekranlar `data/` katmanını tanımaz; defter buradan okunur.
  Future<List<StockMovement>> movements({
    int? productId,
    StockMovementType? type,
    int? supplierId,
    int? userId,
    DateTime? fromUtc,
    DateTime? toUtc,
    int limit = 100,
    int offset = 0,
  }) => _stock.list(
    productId: productId,
    type: type,
    supplierId: supplierId,
    userId: userId,
    fromUtc: fromUtc,
    toUtc: toUtc,
    limit: limit,
    offset: offset,
  );

  /// docs/13 §7 — kritik stok (REQ-STOCK-011: `minimum_stock = 0` hariç).
  Future<List<Product>> criticalStock({int limit = 100}) =>
      _products.listCriticalStock(limit: limit);

  /// docs/13 §7 · BR-STOCK-007 — negatif stok gizlenmez.
  Future<List<Product>> negativeStock({int limit = 100}) =>
      _products.listNegativeStock(limit: limit);

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

  /// Satılan miktarı deftere düşer — **docs/12 §6.2 adım 3c–3d · docs/13 §2.**
  ///
  /// ```text
  ///   stock_movements          type=sale, delta=-N, reference=(sale, saleId)
  ///   products.stock_quantity  önceki − N
  /// ```
  ///
  /// | Kural | Davranış |
  /// |---|---|
  /// | **BR-STOCK-006** — negatif stok satışı engellemez | Stok yetersizse **yine de** yazılır; sonuç negatif olabilir |
  /// | BR-STOCK-010 | `reference_type=sale` + `reference_id` zorunlu taşınır |
  /// | docs/13 §2 — `sale` için `unit_cost` ❌ | Birim maliyet yazılmaz; maliyet snapshot'ı `sale_items`'tadır |
  /// | BR-STOCK-008 | `resulting_stock` her harekette yazılır |
  ///
  /// ⚠️ **Transaction AÇMAZ.** Çağıran (`SaleService`) satışın tamamını tek
  /// transaction'da tutar (BR-SALE-005); burada ikinci bir sınır açmak
  /// EC-SALE-002'nin istediği tam rollback'i belirsizleştirirdi.
  ///
  /// Önbellek her çağrıda **yeniden okunur**: aynı ürün sepette iki ayrı
  /// satırda olabilir (EC-CART-004) ve ikinci satırın `resulting_stock`'u
  /// birincisini görmek zorundadır.
  Future<Result<int>> recordSale({
    required int productId,
    required int quantity,
    required int saleId,
    required int userId,
    required DateTime nowUtc,
  }) async {
    // BR-STOCK-004: delta `0` olamaz. Sepet satırı zaten pozitiftir
    // (BR-SALE-011 · şema CHECK); bu savunma çağıranı değil veriyi korur.
    if (quantity <= 0) return const Err(StockFailures.nonPositiveSaleQuantity);

    final before = await _stock.readStockQuantity(productId);
    final resulting = before - quantity;

    await _stock.appendMovement(
      productId: productId,
      type: StockMovementType.sale,
      quantityDelta: -quantity,
      resultingStock: resulting,
      userId: userId,
      createdAtUtc: nowUtc,
      referenceType: StockReferenceType.sale,
      referenceId: saleId,
    );
    await _stock.writeStockQuantity(productId, resulting);

    return Ok<int>(resulting);
  }

  /// Satış iptalinin stok geri yazımı — **docs/14 §3 · REQ-RET-002/006.**
  ///
  /// ```text
  ///   stock_movements  type=saleCancellation, delta=+N, reference=(sale, id)
  /// ```
  ///
  /// Orijinal `sale` hareketi **silinmez** (BR-STOCK-005): defter yalnızca
  /// ileri yazılır ve "bu ürünün stoğu neden 12?" sorusu iptalden sonra da
  /// yanıtlanabilir kalır.
  ///
  /// ⚠️ Transaction AÇMAZ — çağıran (`ReturnService`) satışın tamamını tek
  /// transaction'da tutar (REQ-RET-010).
  Future<Result<int>> recordSaleCancellation({
    required int productId,
    required int quantity,
    required int saleId,
    required int userId,
    required DateTime nowUtc,
  }) => _recordPositiveReference(
    productId: productId,
    quantity: quantity,
    type: StockMovementType.saleCancellation,
    referenceType: StockReferenceType.sale,
    referenceId: saleId,
    userId: userId,
    nowUtc: nowUtc,
  );

  /// İadenin stok geri yazımı — **docs/14 §4 · REQ-RET-006.**
  ///
  /// ```text
  ///   stock_movements  type=return, delta=+N, reference=(return, returnId)
  /// ```
  ///
  /// Referans **iadeye** verilir, satışa değil: aynı satıştan birden fazla
  /// kısmi iade yapılabilir (docs/14 §1) ve hangi hareketin hangi iadeye ait
  /// olduğu ayırt edilebilmelidir.
  Future<Result<int>> recordReturn({
    required int productId,
    required int quantity,
    required int returnId,
    required int userId,
    required DateTime nowUtc,
  }) => _recordPositiveReference(
    productId: productId,
    quantity: quantity,
    type: StockMovementType.returnedToStock,
    referenceType: StockReferenceType.returnOperation,
    referenceId: returnId,
    userId: userId,
    nowUtc: nowUtc,
  );

  /// İptal ve iadenin ortak gövdesi: pozitif yönlü, referanslı hareket.
  ///
  /// docs/13 §2 — ikisi de `unit_cost` taşımaz: maliyet zaten
  /// `sale_items.purchase_price_snapshot_minor`'dadır ve oradan türetilir.
  Future<Result<int>> _recordPositiveReference({
    required int productId,
    required int quantity,
    required StockMovementType type,
    required StockReferenceType referenceType,
    required int referenceId,
    required int userId,
    required DateTime nowUtc,
  }) async {
    // BR-STOCK-004 — delta `0` olamaz.
    if (quantity <= 0) return const Err(StockFailures.nonPositiveSaleQuantity);

    // Önbellek her çağrıda yeniden okunur: aynı ürün satışta iki satırda
    // olabilir ve ikinci hareketin `resulting_stock`'u birincisini görmelidir.
    final before = await _stock.readStockQuantity(productId);
    final resulting = before + quantity;

    await _stock.appendMovement(
      productId: productId,
      type: type,
      quantityDelta: quantity,
      resultingStock: resulting,
      userId: userId,
      createdAtUtc: nowUtc,
      referenceType: referenceType,
      referenceId: referenceId,
    );
    await _stock.writeStockQuantity(productId, resulting);

    return Ok<int>(resulting);
  }

  // --- Faz 6: stok girişi, fire, düzeltme ---------------------------------

  /// Mal kabul — **docs/13 §5 · REQ-STOCK-007/008 · BR-STOCK-009.**
  ///
  /// ```text
  /// BEGIN
  ///   Her satır için:
  ///     stock_movements  type=stockEntry, delta=+N, unit_cost, supplier
  ///     products.stock_quantity
  ///     (onaylandıysa) products.purchase_price_minor + productCostChanged
  ///   audit_logs (stockEntryCreated)
  /// COMMIT
  /// ```
  ///
  /// **REQ-STOCK-007 — kısmi giriş oluşmaz.** 15 satırlık bir girişin
  /// 10.'sunda hata çıkarsa hiçbir hareket yazılmaz ve hiçbir ürünün stoğu
  /// değişmez; ekrandaki veriler çağıranda durur, kullanıcı düzeltip tekrar
  /// dener (docs/13 §10).
  ///
  /// Aynı ürün birden fazla satırda olabilir (farklı alış fiyatıyla girilmiş
  /// olabilir); her satır kendi hareketini yazar ve `resulting_stock`
  /// zincirlenir.
  Future<Result<StockEntryReceipt>> recordEntry({
    required List<StockEntryLine> lines,
    required int userId,
    int? supplierId,
    String? documentNumber,
    String? note,
  }) async {
    if (lines.isEmpty) return const Err(StockFailures.emptyEntry);
    for (final line in lines) {
      if (line.quantity <= 0) {
        return const Err(StockFailures.entryQuantityInvalid);
      }
      if (line.unitCost != null && line.unitCost!.isNegative) {
        return const Err(StockFailures.negativePurchasePrice);
      }
    }

    final now = _clock().toUtc();

    try {
      return Ok(
        await _db.transaction(() async {
          var unitCount = 0;
          var totalMinor = 0;

          for (final line in lines) {
            final found = await _products.findById(line.productId);
            if (found.isErr) throw const _Abort(StockFailures.productNotFound);
            final product = found.valueOrNull!;

            // docs/13 §5 — ürünün mevcut alış fiyatı önerilir; kullanıcı
            // değiştirmediyse o kullanılır.
            final unitCost = line.unitCost ?? product.purchasePrice;

            final before = await _stock.readStockQuantity(line.productId);
            final resulting = before + line.quantity;

            await _stock.appendMovement(
              productId: line.productId,
              type: StockMovementType.stockEntry,
              quantityDelta: line.quantity,
              resultingStock: resulting,
              userId: userId,
              createdAtUtc: now,
              unitCost: unitCost,
              supplierId: supplierId,
              note: documentNumber,
            );
            await _stock.writeStockQuantity(line.productId, resulting);

            // BR-STOCK-009 · REQ-STOCK-008 — kararı kullanıcı vermiştir.
            if (line.updateProductPurchasePrice &&
                unitCost != product.purchasePrice) {
              await _products.updatePurchasePrice(line.productId, unitCost);
              await _audit?.record(
                action: AuditActions.productCostChanged,
                entityType: AuditEntities.product,
                entityId: line.productId,
                userId: userId,
                at: now,
                oldValue: {'purchase_price_minor': product.purchasePrice.minor},
                newValue: {'purchase_price_minor': unitCost.minor},
                // docs/18 §3 — `productCostChanged` metadata'sı **kaynağı**
                // taşır; elle yapılan değişiklikten ayırt edilebilmelidir.
                metadata: const {'source': 'stockEntry'},
              );
            }

            unitCount += line.quantity;
            totalMinor += unitCost.minor * line.quantity;
          }

          await _audit?.record(
            action: AuditActions.stockEntryCreated,
            entityType: AuditEntities.stock,
            userId: userId,
            at: now,
            // docs/18 §3 — tedarikçi, satır sayısı, toplam tutar.
            metadata: {
              'supplier_id': supplierId,
              'line_count': lines.length,
              'unit_count': unitCount,
              'total_minor': totalMinor,
              'document_number': ?documentNumber,
              'note': ?note,
            },
          );

          return StockEntryReceipt(
            lineCount: lines.length,
            unitCount: unitCount,
            total: Money(totalMinor),
          );
        }),
      );
    } on _Abort catch (abort) {
      return Err(abort.failure);
    }
  }

  /// Fire — **docs/13 §6 · REQ-STOCK-009.**
  ///
  /// Yön **yalnızca negatiftir** ve **sebep zorunludur** (BR-STOCK-010).
  /// Fire kantinlerde gerçek bir maliyet kalemidir (bozulan süt, bayatlayan
  /// poğaça); `unit_cost` bu yüzden yazılır — kâr raporu fireyi gider olarak
  /// gösterir ve maliyet sonradan türetilemez.
  ///
  /// ⚠️ docs/13 §2 `waste` için `unit_cost` sütununu ❌ işaretler. Buradaki
  /// yazım o tabloyla çelişmez: tablo *kullanıcının girdiği* bir maliyeti
  /// kasteder; §6 ise fire tutarının `qty × unitCost` ile raporlanmasını
  /// **şart koşar**. Değer kullanıcıdan değil, ürünün o anki alış fiyatından
  /// gelir (bkz. OD-025).
  Future<Result<int>> recordWaste({
    required int productId,
    required int quantity,
    required String reason,
    required int userId,
  }) async {
    if (quantity <= 0) return const Err(StockFailures.wasteMustBePositive);
    final trimmed = reason.trim();
    if (trimmed.isEmpty) return const Err(StockFailures.reasonRequired);

    final now = _clock().toUtc();

    try {
      return Ok(
        await _db.transaction(() async {
          final found = await _products.findById(productId);
          if (found.isErr) throw const _Abort(StockFailures.productNotFound);
          final product = found.valueOrNull!;

          final before = await _stock.readStockQuantity(productId);
          final resulting = before - quantity;

          await _stock.appendMovement(
            productId: productId,
            type: StockMovementType.waste,
            quantityDelta: -quantity,
            resultingStock: resulting,
            userId: userId,
            createdAtUtc: now,
            unitCost: product.purchasePrice,
            note: trimmed,
          );
          await _stock.writeStockQuantity(productId, resulting);

          await _audit?.record(
            action: AuditActions.stockWasteRecorded,
            entityType: AuditEntities.stock,
            entityId: productId,
            userId: userId,
            at: now,
            // docs/18 §3 — ürün, miktar, **sebep**.
            metadata: {
              'product_id': productId,
              'quantity': quantity,
              'reason': trimmed,
              'unit_cost_minor': product.purchasePrice.minor,
            },
          );

          return resulting;
        }),
      );
    } on _Abort catch (abort) {
      return Err(abort.failure);
    }
  }

  /// Sayım düzeltmesi — **docs/13 §6 · REQ-DATA-007.**
  ///
  /// Çağıran **hedeflenen stoğu** verir, farkı değil: kullanıcı sayım sonucunu
  /// bilir, deltayı değil. Fark servis tarafından hesaplanır ve deftere delta
  /// olarak yazılır.
  ///
  /// Yön ± olabilir; **sebep zorunludur** (BR-STOCK-010).
  Future<Result<int>> recordAdjustment({
    required int productId,
    required int newQuantity,
    required String reason,
    required int userId,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) return const Err(StockFailures.reasonRequired);

    final now = _clock().toUtc();

    try {
      return Ok(
        await _db.transaction(() async {
          final exists = await _products.findById(productId);
          if (exists.isErr) throw const _Abort(StockFailures.productNotFound);

          final before = await _stock.readStockQuantity(productId);
          final delta = newQuantity - before;
          // BR-STOCK-004 — `0` hareketi yazılamaz.
          if (delta == 0) {
            throw const _Abort(StockFailures.adjustmentNoChange);
          }

          await _stock.appendMovement(
            productId: productId,
            type: StockMovementType.adjustment,
            quantityDelta: delta,
            resultingStock: newQuantity,
            userId: userId,
            createdAtUtc: now,
            note: trimmed,
          );
          await _stock.writeStockQuantity(productId, newQuantity);

          await _audit?.record(
            action: AuditActions.stockAdjusted,
            entityType: AuditEntities.stock,
            entityId: productId,
            userId: userId,
            at: now,
            // docs/18 §3 — ürün, eski/yeni stok, **sebep**.
            oldValue: {'stock_quantity': before},
            newValue: {'stock_quantity': newQuantity},
            metadata: {'product_id': productId, 'reason': trimmed},
          );

          return newQuantity;
        }),
      );
    } on _Abort catch (abort) {
      return Err(abort.failure);
    }
  }

  /// Tutarlılık sapmasını kapatır — **REQ-DATA-007 · rules/03 §2 · OD-026.**
  ///
  /// [recordAdjustment]'tan **kritik farkı:** delta önbellekten değil,
  /// **defterden** hesaplanır.
  ///
  /// ```text
  /// Sapma:  defter = 10,  önbellek = 99
  ///
  /// recordAdjustment(newQuantity: 10)      ❌ delta = 10 − 99 = −89
  ///     → defter 10 + (−89) = −79,  önbellek 10   → HÂLÂ AYRI
  ///
  /// repairFromLedger(physicalQuantity: 10) ✅ delta = 10 − 10 = 0
  ///     → hareket yazılmaz, önbellek defterden tazelenir → TUTAR
  /// ```
  ///
  /// Normal düzeltmede önbellekten hesaplamak **doğrudur**: mevcut sapma
  /// korunur ve görünür kalır (rules/03 §2). Ama sapmayı *kapatan* işlem tam
  /// olarak bunu yapmamalıdır, yoksa düzeltme sapmayı yeniden üretir.
  ///
  /// [physicalQuantity] kullanıcının **onayladığı gerçek** miktardır. Sapma
  /// iki şeyden biri olabilir ve hangisi olduğunu yalnızca kullanıcı bilir:
  /// önbellek bozulmuştur (rafta defterin dediği kadar var) veya bir hareket
  /// yazılamamıştır (rafta önbelleğin dediği kadar var). Bu yüzden servis
  /// kendi başına bir taraf seçmez.
  ///
  /// - `physicalQuantity == defter` → hareket **yazılmaz**, yalnızca önbellek
  ///   tazelenir. Olmayan bir stok olayı uydurmak denetim izini bozardı.
  /// - Aksi hâlde farkı kapatan bir `adjustment` hareketi yazılır.
  Future<Result<int>> repairFromLedger({
    required int productId,
    required int physicalQuantity,
    required String reason,
    required int userId,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) return const Err(StockFailures.reasonRequired);

    final now = _clock().toUtc();

    try {
      return Ok(
        await _db.transaction(() async {
          final exists = await _products.findById(productId);
          if (exists.isErr) throw const _Abort(StockFailures.productNotFound);

          final cached = await _stock.readStockQuantity(productId);
          final ledger = await _stock.sumQuantityDelta(productId);
          final delta = physicalQuantity - ledger;

          if (delta != 0) {
            await _stock.appendMovement(
              productId: productId,
              type: StockMovementType.adjustment,
              quantityDelta: delta,
              resultingStock: physicalQuantity,
              userId: userId,
              createdAtUtc: now,
              note: trimmed,
            );
          }
          await _stock.writeStockQuantity(productId, physicalQuantity);

          await _audit?.record(
            action: AuditActions.stockAdjusted,
            entityType: AuditEntities.stock,
            entityId: productId,
            userId: userId,
            at: now,
            oldValue: {'stock_quantity': cached},
            newValue: {'stock_quantity': physicalQuantity},
            metadata: {
              'product_id': productId,
              'reason': trimmed,
              // Sapmanın kapatıldığı elle yapılan sayımdan ayırt edilebilmeli.
              'source': 'consistencyRepair',
              'ledger_before': ledger,
              'movement_written': delta != 0,
            },
          );

          return physicalQuantity;
        }),
      );
    } on _Abort catch (abort) {
      return Err(abort.failure);
    }
  }

  /// Yanlış girilen bir hareketin **ters kaydını** oluşturur —
  /// **REQ-STOCK-003 · docs/13 §10.**
  ///
  /// > *"Düzenle veya Sil seçeneği bulunmaz. Ters kayıt oluştur seçeneği
  /// > bulunur. Orijinal hareket olduğu gibi durur."*
  ///
  /// Ters kayıt bir `adjustment`'tır: defter yalnızca ileri yazılır
  /// (BR-STOCK-005) ve düzeltme ters yönde **yeni** bir hareketle yapılır.
  Future<Result<int>> reverseMovement({
    required int movementId,
    required String reason,
    required int userId,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) return const Err(StockFailures.reasonRequired);

    final found = await _stock.findById(movementId);
    if (found.isErr) return const Err(StockFailures.movementNotFound);
    final original = found.valueOrNull!;

    final before = await _stock.readStockQuantity(original.productId);
    return recordAdjustment(
      productId: original.productId,
      newQuantity: before - original.quantityDelta,
      reason: trimmed,
      userId: userId,
    );
  }
}

/// Yazma başladıktan sonra reddedilen durumlar için — transaction'ı geri alır.
class _Abort implements Exception {
  final Failure failure;
  const _Abort(this.failure);
}
