/// Satış tamamlama — **BR-SALE-005 · docs/12 §6 · REQ-SALE-001…009**
///
/// ## Tek iş: yarım satış oluşmasın
///
/// docs/12 §6.2'deki altı adım **tek transaction**'dır. Herhangi bir adımda
/// hata → tam rollback; hiçbir `sales`, `sale_items` veya `stock_movements`
/// kaydı kalmaz ve **sepet olduğu gibi korunur** (EC-SALE-002 · REQ-SALE-001).
/// Elektrik kesintisi normal bir senaryodur (rules/03 §10), istisna değil.
///
/// ```text
/// BEGIN
///   1. Satış numarası üret (sayaç aynı transaction içinde artar)
///   2. sales satırı
///   3. Her sepet satırı için:
///        sale_items  (BEŞ snapshot alanı + KDV çıkarımı)
///        stock_movements (type=sale, delta=-qty, resulting_stock)
///        products.stock_quantity
///   4. Aktif sepeti kapat (status=closed)
///   5. Yeni boş aktif sepet
///   6. audit_logs (saleCompleted)
/// COMMIT
/// ```
///
/// ## Transaction içinde ne YOKTUR
///
/// Dosya I/O, ağ çağrısı, UI beklemesi (rules/01 §5). Hedef süre < 50 ms
/// (REQ-SALE-009). Ürünler satır satır **taze** okunur — EC-SALE-005 satış
/// anındaki değerin kullanılmasını şart koşar — ama okuma da veritabanından
/// ve indeksten gelir.
///
/// ## KDV fiyatın İÇİNDEN çıkarılır — BR-VAT-003
///
/// Sepetin brüt toplamı müşteriden alınan tutardır; üzerine hiçbir ek
/// yapılmaz (REQ-SALE-012). Hesap `domain/services/vat_calculator`'a aittir;
/// burada ikinci bir formül yoktur (rules/01 §2).
library;

import 'dart:convert';

import '../../core/logging/app_logger.dart';
import '../../core/money/money.dart';
import '../../core/result/result.dart';
import '../../data/dao/daos.dart';
import '../../data/db/canteen_database.dart' show CanteenDatabase;
import '../../domain/enums/cart_status.dart';
import '../../domain/enums/sale_status.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/sale.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/sale_repository.dart';
import '../../domain/services/sale_number.dart';
import '../../domain/services/vat_calculator.dart';
import '../stock/stock_service.dart';
import 'cart_service.dart';
import 'sale_failures.dart';

/// Tamamlanan satışın çağırana dönen özeti — docs/12 §6.3.
class SaleReceipt {
  final int saleId;

  /// `YYYY-NNNNNN` (REQ-SALE-005).
  final String saleNumber;

  /// KDV **dahil** — müşteriden alınan tutar.
  final Money grandTotal;

  final Money? change;

  /// Satış sonrası açılan **yeni boş** aktif sepet (REQ-SALE-006).
  final Cart newCart;

  const SaleReceipt({
    required this.saleId,
    required this.saleNumber,
    required this.grandTotal,
    required this.change,
    required this.newCart,
  });
}

/// Yazma başladıktan sonra reddedilen durumlar için — transaction'ı geri alır.
class _Abort implements Exception {
  final Failure failure;
  const _Abort(this.failure);
}

class SaleService {
  /// docs/18 §2 — `entity_type`.
  static const String auditEntityType = 'sale';

  /// docs/18 §3.
  static const String actionCompleted = 'saleCompleted';

  /// docs/18 §3 — satış sırasında fiyat değiştirildi (BR-SALE-004).
  static const String actionPriceOverridden = 'salePriceOverridden';

  final CanteenDatabase _db;
  final CartService _cartService;
  final CartsDao _carts;
  final VatRatesDao _vatRates;
  final AppSettingsDao _appSettings;
  final AuditLogsDao _auditLogs;
  final ProductRepository _products;
  final SaleRepository _sales;
  final StockService _stockService;
  final AppLogger? _logger;
  final DateTime Function() _clock;

  /// REQ-SALE-008 — tamamlama sürerken ikinci istek reddedilir.
  bool _inProgress = false;

  SaleService({
    required CanteenDatabase db,
    required CartService cartService,
    required CartsDao carts,
    required VatRatesDao vatRates,
    required AppSettingsDao appSettings,
    required AuditLogsDao auditLogs,
    required ProductRepository products,
    required SaleRepository sales,
    required StockService stockService,
    AppLogger? logger,
    DateTime Function()? clock,
  }) : _db = db,
       _cartService = cartService,
       _carts = carts,
       _vatRates = vatRates,
       _appSettings = appSettings,
       _auditLogs = auditLogs,
       _products = products,
       _sales = sales,
       _stockService = stockService,
       _logger = logger,
       _clock = clock ?? db.clock;

  /// Aktif sepeti satışa çevirir — **docs/12 §6.**
  ///
  /// [cashReceived] **opsiyoneldir** (BR-SALE-007 · REQ-SALE-007): verilmezse
  /// `cash_received_minor` ve `change_minor` `NULL` kaydedilir. Verilirse
  /// toplamdan az olamaz (BR-SALE-008 · EC-SALE-009); EC-SALE-010 gereği
  /// büyük tutarlar reddedilmez, para üstü hesaplanır.
  ///
  /// Stok yetersizliği satışı **engellemez** (BR-STOCK-006 · REQ-STOCK-005):
  /// uyarı ve "Devam Et" kararı UI'ya aittir, servis satar ve stok negatife
  /// düşer.
  Future<Result<SaleReceipt>> complete({
    required int cartId,
    required int userId,
    Money? cashReceived,
    String? note,
  }) async {
    // REQ-SALE-008 · EC-SALE-008 — çift gönderim tek satış üretir.
    if (_inProgress) return const Err(SaleFailures.alreadyInProgress);
    _inProgress = true;
    try {
      return await _complete(
        cartId: cartId,
        userId: userId,
        cashReceived: cashReceived,
        note: note,
      );
    } finally {
      _inProgress = false;
    }
  }

  Future<Result<SaleReceipt>> _complete({
    required int cartId,
    required int userId,
    Money? cashReceived,
    String? note,
  }) async {
    // --- Ön kontroller — docs/12 §6.1 --------------------------------------
    final cart = await _cartService.load(cartId, userId);
    if (cart.isEmpty) return const Err(SaleFailures.emptyCart);

    // EC-CART-010 — sepette gösterilemeyen satır varsa satış YAPILMAZ.
    //
    // Bu bir para güvenliğidir: üç satırlık sepetin bir satırı bozulmuşsa
    // kalan ikisini satmak müşteriden eksik tahsilat demektir ve kimse fark
    // etmez. Bozulmayı kullanıcı görmeli, sepeti düzeltmelidir.
    if (cart.hasDroppedLines) return const Err(SaleFailures.productMissing);

    final totals = cart.totals;
    if (cashReceived != null) {
      if (cashReceived.isNegative) return const Err(SaleFailures.negativeCash);
      if (cashReceived < totals.gross) {
        return const Err(SaleFailures.insufficientCash);
      }
    }

    final now = _clock().toUtc();
    final change = cashReceived == null ? null : cashReceived - totals.gross;

    try {
      return Ok(
        await _db.transaction(() async {
          // 1 — Satış numarası (sayaç aynı transaction içinde artar).
          final saleNumber = await _nextSaleNumber(now);

          // 3a — Satırların snapshot'ları ÖNCE hazırlanır: `sales` başlığındaki
          // toplamlar satırlardan türer ve ikisi tutmak zorundadır
          // (rules/02 §2 — subtotal + vatTotal == grandTotal).
          final items = await _buildItems(cart);
          final lineBreakdowns = items.map(
            (item) => VatBreakdown(
              gross: item.lineTotal,
              vat: item.lineVat,
              net: item.lineNet,
            ),
          );
          final saleTotals = VatCalculator.aggregate(lineBreakdowns);
          final costTotal = Money.sum(
            items.map((i) => i.purchasePriceSnapshot * i.quantity),
          );

          // 2 — sales satırı.
          final saleId = await _sales.insertSale(
            NewSale(
              saleNumber: saleNumber,
              status: SaleStatus.completed,
              subtotal: saleTotals.net,
              vatTotal: saleTotals.vat,
              grandTotal: saleTotals.gross,
              costTotal: costTotal,
              cashReceived: cashReceived,
              change: change,
              itemCount: items.length,
              unitCount: items.fold(0, (sum, i) => sum + i.quantity),
              userId: userId,
              note: note,
              completedAtUtc: now,
            ),
          );

          // 3b–3d — satır + stok hareketi + stok önbelleği.
          for (final item in items) {
            await _sales.insertItem(saleId, item);

            final moved = await _stockService.recordSale(
              productId: item.productId,
              quantity: item.quantity,
              saleId: saleId,
              userId: userId,
              nowUtc: now,
            );
            if (moved.isErr) throw _Abort(moved.failureOrNull!);

            // BR-SALE-004 — fiyat override'ı denetim izine yazılır.
            if (item.isPriceOverridden) {
              await _writeAudit(
                action: actionPriceOverridden,
                now: now,
                userId: userId,
                entityId: saleId,
                metadata: {
                  'product_id': item.productId,
                  'sale_number': saleNumber,
                  'list_price_minor': item.originalUnitPrice.minor,
                  'applied_price_minor': item.unitPrice.minor,
                },
              );
            }
          }

          // 4 — aktif sepet kapatılır. 5 — yeni boş sepet.
          //
          // Sıra zorunludur: `ux_carts_active` aynı anda iki aktif sepete izin
          // vermez, dolayısıyla yeni sepet ancak eskisi kapandıktan sonra
          // açılabilir.
          await _carts.updateStatus(cartId, CartStatus.closed);
          final newCartId = await _carts.insertActiveCart(
            userId: userId,
            now: now,
          );

          // 6 — audit.
          await _writeAudit(
            action: actionCompleted,
            now: now,
            userId: userId,
            entityId: saleId,
            // docs/18 §3 — fiş no, toplam, satır sayısı.
            newValue: {
              'sale_number': saleNumber,
              'grand_total_minor': saleTotals.gross.minor,
              'item_count': items.length,
            },
          );

          return SaleReceipt(
            saleId: saleId,
            saleNumber: saleNumber,
            grandTotal: saleTotals.gross,
            change: change,
            newCart: Cart(
              id: newCartId,
              userId: userId,
              lines: const [],
              createdAt: now,
              updatedAt: now,
            ),
          );
        }),
      );
    } on _Abort catch (abort) {
      return Err(abort.failure);
    }
  }

  // --- Satır snapshot'ları — BR-SALE-001 ----------------------------------

  /// Sepet satırlarını **beş snapshot alanıyla** satış satırlarına çevirir.
  ///
  /// Ürünler burada **taze** okunur: EC-SALE-005 satış anındaki değerin
  /// kullanılmasını, EC-SALE-016 ise satır KDV oranının satış anındaki oran
  /// olmasını şart koşar. Sepetteki gösterim değerleri kullanılmaz — sepet
  /// dakikalarca açık durmuş olabilir.
  ///
  /// Uygulanan fiyat (`unitPrice`) **sepetten** gelir: kullanıcı bu satışa
  /// özel bir fiyat uygulamış olabilir (docs/12 §4) ve ürünün fiyatı sepet
  /// dururken değişmişse sepetteki fiyat korunur (REQ-CART-007).
  Future<List<NewSaleItem>> _buildItems(Cart cart) async {
    // Aynı oranı paylaşan satırlar için tekrar sorgu yapılmasın — transaction
    // < 50 ms hedefindedir (REQ-SALE-009).
    final rateCache = <int, int>{};
    int? defaultBp;

    final items = <NewSaleItem>[];
    for (final line in cart.lines) {
      final found = await _products.findById(line.productId);
      if (found.isErr) throw const _Abort(SaleFailures.productMissing);
      final product = found.valueOrNull!;

      // docs/08 §4 — ürünün oranı; yoksa varsayılan; o da yoksa %0.
      // Ürüne atanmış oran **pasif olsa da** kullanılır: snapshot mantığı
      // gereği doğru davranış budur.
      final int vatBp;
      if (product.vatRateId != null) {
        vatBp = rateCache[product.vatRateId!] ??=
            (await _vatRates.findById(product.vatRateId!))?.rateBasisPoints ??
            0;
      } else {
        defaultBp ??= (await _vatRates.findDefault())?.rateBasisPoints ?? 0;
        vatBp = defaultBp;
      }

      // BR-VAT-003 — KDV brüt tutarın İÇİNDEN çıkarılır.
      final breakdown = VatCalculator.forLine(
        unitPrice: line.unitPrice,
        quantity: line.quantity,
        vatRateBp: vatBp,
      );

      final barcodes = await _products.barcodesOf(product.id);

      items.add(
        NewSaleItem(
          productId: product.id,
          // 1/5 — ad.
          productNameSnapshot: product.name,
          // docs/04 §3.9 · **OD-022** — ürünün **birincil** barkodu.
          //
          // "Okutulan barkod" hedefinden vazgeçildi: `cart_items` okutulan
          // barkodu taşımaz (docs/05 §2.7) ve sepetin çökme sonrası aynen
          // geri gelmesi gerekir (REQ-CART-003). Alan yalnızca raporlama
          // amaçlıdır; hiçbir para, stok, KDV veya durum hesabına girmez.
          //
          // `barcodesOf` sırası sözleşmenin parçasıdır (birincil başta);
          // sırasız bir sonuç aynı ürünün satışlarında rastgele snapshot
          // üretirdi.
          barcodeSnapshot: barcodes.isEmpty ? null : barcodes.first,
          // 2/5 — kategori.
          categoryIdSnapshot: product.categoryId,
          quantity: line.quantity,
          // 3/5 — uygulanan birim fiyat (KDV dahil).
          unitPrice: line.unitPrice,
          // BR-SALE-004 — o andaki liste fiyatı.
          originalUnitPrice: product.salePrice,
          // 4/5 — alış fiyatı (REQ-FIN-008 kâr hesabının maliyet tarafı).
          purchasePriceSnapshot: product.purchasePrice,
          // 5/5 — KDV oranı (REQ-VAT-003).
          vatRateSnapshotBp: vatBp,
          lineNet: breakdown.net,
          lineVat: breakdown.vat,
          lineTotal: breakdown.gross,
        ),
      );
    }
    return items;
  }

  // --- Satış numarası — docs/12 §6.4 --------------------------------------

  /// Sayacı **aynı transaction içinde** artırır ve numarayı biçimlendirir.
  ///
  /// Sayaç yıl başına ayrı bir anahtarda tutulur; yıl değişince yenisi
  /// kendiliğinden `1`'den başlar (EC-SALE-011). Benzersizliğin son güvencesi
  /// `ux_sales_number`'dır: çakışma satışı **oluşturmaz**, rollback eder.
  ///
  /// Restore sonrası sayaç düzeltmesi (EC-SALE-012 · REQ-BKUP-015) **Faz 9**
  /// kapsamındadır; restore o faza kadar zaten mevcut değildir.
  Future<String> _nextSaleNumber(DateTime nowUtc) async {
    final year = SaleNumber.yearOf(nowUtc);
    final key = SaleNumber.counterKey(year);
    final current = int.tryParse(await _appSettings.read(key) ?? '') ?? 0;
    final next = current + 1;
    await _appSettings.write(key, '$next');
    return SaleNumber.format(year: year, sequence: next);
  }

  // --- Audit ---------------------------------------------------------------

  /// REQ-AUDIT-007 — yazım hatası ana işlemi **başarısız kılmaz.**
  Future<void> _writeAudit({
    required String action,
    required DateTime now,
    required int entityId,
    int? userId,
    Map<String, Object?>? newValue,
    Map<String, Object?>? metadata,
  }) async {
    try {
      await _auditLogs.record(
        createdAt: now,
        action: action,
        entityType: auditEntityType,
        userId: userId,
        entityId: entityId,
        newValue: newValue == null ? null : jsonEncode(newValue),
        metadata: metadata == null ? null : jsonEncode(metadata),
      );
    } on Object catch (error, stackTrace) {
      _logger?.error(
        'Denetim kaydı yazılamadı ($action).',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }
}
