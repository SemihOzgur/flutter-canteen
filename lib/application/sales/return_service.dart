/// Satış iptali ve iade — **docs/14 · REQ-RET-001…012**
///
/// > *"Hataların düzeltilebilmesi."* (docs/31 Faz 7)
///
/// ## İki farklı işlem — docs/14 §1
///
/// | | İptal | İade |
/// |---|---|---|
/// | Kapsam | Satışın **tamamı** | Satırların bir kısmı veya tamamı |
/// | Tekrarlanabilir | ❌ bir kez | ✅ kalan miktar kadar |
/// | Ön koşul | Hiç iade yapılmamış olmalı | Satış `cancelled` olmamalı |
///
/// Bunlar birbirinin yerine geçmez ve **birlikte kullanılamaz**: iade
/// yapılmış bir satışı iptal etmek stoğu iki kez geri eklerdi
/// (BR-RET-001 · [SaleStatusRules.canCancel]).
///
/// ## Satış kaydı SİLİNMEZ — REQ-RET-001 · BR-GEN-002
///
/// Yalnızca **durum** değişir. Satış ve satırları raporlarda görünmeye devam
/// eder; net değerler iptal ve iade düşülerek hesaplanır (docs/14 §5).
///
/// ## Her ikisi de ATOMİKTİR — REQ-RET-010
///
/// Durum + N stok hareketi + N stok güncellemesi + iade kayıtları + audit tek
/// transaction'dadır. Yarım bir iade, stoğu artmış ama `returned_quantity`'si
/// artmamış bir satır bırakırdı — ve o satır bir daha iade edilebilirdi.
library;

import '../../core/money/money.dart';
import '../../core/result/result.dart';
import '../../data/db/canteen_database.dart' show CanteenDatabase;
import '../../domain/enums/return_type.dart';
import '../../domain/enums/sale_status.dart';
import '../../domain/models/sale.dart';
import '../../domain/models/sale_return.dart';
import '../../domain/repositories/sale_repository.dart';
import '../../domain/services/sale_status_rules.dart';
import '../audit/audit_actions.dart';
import '../audit/audit_service.dart';
import '../stock/stock_service.dart';
import 'return_failures.dart';

/// Satış detayının iade/iptal için ihtiyaç duyduğu özet.
class SaleReturnState {
  final Sale sale;
  final List<SaleItem> items;
  final List<SaleReturn> returns;

  const SaleReturnState({
    required this.sale,
    required this.items,
    required this.returns,
  });

  int get totalSold => items.fold(0, (sum, i) => sum + i.quantity);
  int get totalReturned => items.fold(0, (sum, i) => sum + i.returnedQuantity);

  /// BR-RET-001 — iptal edilebilir mi?
  bool get canCancel => SaleStatusRules.canCancel(
    status: sale.status,
    totalReturned: totalReturned,
  );

  /// BR-RET-006 — iade yapılabilir mi?
  bool get canReturn => SaleStatusRules.canReturn(
    status: sale.status,
    totalSold: totalSold,
    totalReturned: totalReturned,
  );

  /// docs/14 §5 — bu satıştan iade edilmiş toplam tutar.
  Money get returnedTotal => Money.sum(returns.map((r) => r.total));
}

/// Tamamlanan iadenin özeti.
class ReturnReceipt {
  final int returnId;
  final Money total;
  final int unitCount;

  /// Yeniden hesaplanan satış durumu (REQ-RET-007).
  final SaleStatus saleStatus;

  const ReturnReceipt({
    required this.returnId,
    required this.total,
    required this.unitCount,
    required this.saleStatus,
  });
}

class _Abort implements Exception {
  final Failure failure;
  const _Abort(this.failure);
}

class ReturnService {
  final CanteenDatabase _db;
  final SaleRepository _sales;
  final StockService _stockService;
  final AuditService? _audit;
  final DateTime Function() _clock;

  ReturnService({
    required CanteenDatabase db,
    required SaleRepository sales,
    required StockService stockService,
    required DateTime Function() clock,
    AuditService? audit,
  }) : _db = db,
       _sales = sales,
       _stockService = stockService,
       _audit = audit,
       _clock = clock;

  /// Satışın iade/iptal durumunu okur — ekran düğmeleri buna göre açılır.
  Future<Result<SaleReturnState>> stateOf(int saleId) async {
    final sale = await _sales.findById(saleId);
    if (sale.isErr) return const Err(ReturnFailures.saleNotFound);
    return Ok(
      SaleReturnState(
        sale: sale.valueOrNull!,
        items: await _sales.itemsOf(saleId),
        returns: await _sales.returnsOf(saleId),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // İPTAL — docs/14 §3
  // -------------------------------------------------------------------------

  /// Satışın tamamını iptal eder — **REQ-RET-002/006/010/012.**
  ///
  /// ```text
  /// BEGIN
  ///   sales.status = cancelled, cancelled_at = now, note += sebep
  ///   Her sale_item için:
  ///     stock_movements  type=saleCancellation, delta=+quantity
  ///     products.stock_quantity += quantity
  ///   audit_logs: saleCancelled
  /// COMMIT
  /// ```
  ///
  /// [reason] **zorunludur**: docs/18 §3 `saleCancelled` metadata'sında sebebi
  /// şart koşar ve "bu satış neden iptal edildi?" sorusu denetim izinden
  /// yanıtlanabilmelidir.
  Future<Result<void>> cancelSale({
    required int saleId,
    required int userId,
    required String reason,
  }) async {
    final trimmed = reason.trim();
    if (trimmed.isEmpty) return const Err(ReturnFailures.reasonRequired);

    final state = await stateOf(saleId);
    if (state.isErr) return Err(state.failureOrNull!);
    final sale = state.valueOrNull!;

    // BR-RET-006 · BR-RET-001 — iki ayrı sebep, iki ayrı mesaj.
    if (sale.sale.status == SaleStatus.cancelled) {
      return const Err(ReturnFailures.alreadyCancelled);
    }
    if (!sale.canCancel) return const Err(ReturnFailures.cancelAfterReturn);

    final now = _clock().toUtc();

    try {
      await _db.transaction(() async {
        await _sales.updateStatus(
          saleId,
          status: SaleStatus.cancelled,
          cancelledAtUtc: now,
          note: _appendNote(sale.sale.note, trimmed),
        );

        for (final item in sale.items) {
          final moved = await _stockService.recordSaleCancellation(
            productId: item.productId,
            quantity: item.quantity,
            saleId: saleId,
            userId: userId,
            nowUtc: now,
          );
          if (moved.isErr) throw _Abort(moved.failureOrNull!);
        }

        await _audit?.record(
          action: AuditActions.saleCancelled,
          entityType: AuditEntities.sale,
          entityId: saleId,
          userId: userId,
          at: now,
          oldValue: {'status': sale.sale.status.wire},
          newValue: {'status': SaleStatus.cancelled.wire},
          // docs/18 §3 — fiş no, tutar, **sebep**.
          metadata: {
            'sale_number': sale.sale.saleNumber,
            'grand_total_minor': sale.sale.grandTotal.minor,
            'reason': trimmed,
          },
        );
      });
      return const Ok(null);
    } on _Abort catch (abort) {
      return Err(abort.failure);
    }
  }

  // -------------------------------------------------------------------------
  // İADE — docs/14 §4
  // -------------------------------------------------------------------------

  /// Kısmi veya tam iade oluşturur — **REQ-RET-003/004/005/006/007/010/012.**
  ///
  /// ```text
  /// BEGIN
  ///   returns satırı (type = tam mı kısmi mi)
  ///   Her iade satırı için:
  ///     return_items (unit_price = sale_item SNAPSHOT'ı)
  ///     sale_items.returned_quantity += miktar
  ///     stock_movements  type=return, delta=+miktar, reference=(return, id)
  ///     products.stock_quantity += miktar
  ///   sales.status yeniden HESAPLANIR
  ///   audit_logs: saleReturned
  /// COMMIT
  /// ```
  ///
  /// **Fiyat çağırandan alınmaz** (BR-RET-005): `sale_items` snapshot'ından
  /// okunur. Ekrana bırakılsaydı güncel fiyat gönderilebilir ve müşteri ₺25'e
  /// aldığı ürün için ₺30 geri alabilirdi.
  Future<Result<ReturnReceipt>> createReturn({
    required int saleId,
    required int userId,
    required List<ReturnLineRequest> lines,
    String? reason,
  }) async {
    final state = await stateOf(saleId);
    if (state.isErr) return Err(state.failureOrNull!);
    final sale = state.valueOrNull!;

    if (sale.sale.status == SaleStatus.cancelled) {
      return const Err(ReturnFailures.returnFromCancelled);
    }

    // --- Doğrulama — docs/14 §4 --------------------------------------------
    final byId = {for (final item in sale.items) item.id: item};
    final requested = <int, int>{};
    for (final line in lines) {
      if (line.quantity <= 0) continue;
      final item = byId[line.saleItemId];
      if (item == null) return const Err(ReturnFailures.lineNotInSale);

      // BR-RET-003 — bir satırın toplam iadesi satılan miktarı aşamaz.
      // Aynı satır listede iki kez geçebilir; toplamı kontrol edilir.
      final total = (requested[line.saleItemId] ?? 0) + line.quantity;
      if (total > item.remainingQuantity) {
        return const Err(ReturnFailures.exceedsRemaining);
      }
      requested[line.saleItemId] = total;
    }
    if (requested.isEmpty) return const Err(ReturnFailures.nothingToReturn);

    final now = _clock().toUtc();
    final unitCount = requested.values.fold(0, (sum, q) => sum + q);

    // BR-RET-005 — tutar **orijinal snapshot fiyattan**.
    var totalMinor = 0;
    for (final entry in requested.entries) {
      totalMinor += byId[entry.key]!.unitPrice.minor * entry.value;
    }

    // docs/14 §2 — bu iadeden SONRAKİ durum.
    final nextStatus = SaleStatusRules.fromReturnedQuantities(
      totalSold: sale.totalSold,
      totalReturned: sale.totalReturned + unitCount,
    );

    try {
      return Ok(
        await _db.transaction(() async {
          final returnId = await _sales.insertReturn(
            NewReturn(
              saleId: saleId,
              // docs/14 §4 — bu **tek iadenin** kapsamı: satışın tamamı bu
              // iadeyle kapanıyorsa `full`, değilse `partial`.
              type: nextStatus == SaleStatus.returned
                  ? ReturnType.full
                  : ReturnType.partial,
              total: Money(totalMinor),
              reason: reason?.trim().isEmpty ?? true ? null : reason!.trim(),
              userId: userId,
              createdAtUtc: now,
            ),
          );

          for (final entry in requested.entries) {
            final item = byId[entry.key]!;
            final quantity = entry.value;
            final lineTotal = item.unitPrice * quantity;

            await _sales.insertReturnItem(
              returnId,
              NewReturnItem(
                saleItemId: item.id,
                quantity: quantity,
                unitPrice: item.unitPrice,
                lineTotal: lineTotal,
              ),
            );
            await _sales.incrementReturnedQuantity(item.id, quantity);

            final moved = await _stockService.recordReturn(
              productId: item.productId,
              quantity: quantity,
              returnId: returnId,
              userId: userId,
              nowUtc: now,
            );
            if (moved.isErr) throw _Abort(moved.failureOrNull!);
          }

          // REQ-RET-007 — durum HESAPLANIR, elle atanmaz.
          await _sales.updateStatus(saleId, status: nextStatus);

          await _audit?.record(
            action: AuditActions.saleReturned,
            entityType: AuditEntities.sale,
            entityId: saleId,
            userId: userId,
            at: now,
            oldValue: {'status': sale.sale.status.wire},
            newValue: {'status': nextStatus.wire},
            // docs/18 §3 — fiş no, iade tutarı, satır sayısı, **sebep**.
            metadata: {
              'sale_number': sale.sale.saleNumber,
              'return_id': returnId,
              'total_minor': totalMinor,
              'line_count': requested.length,
              'unit_count': unitCount,
              'reason': ?reason?.trim(),
            },
          );

          return ReturnReceipt(
            returnId: returnId,
            total: Money(totalMinor),
            unitCount: unitCount,
            saleStatus: nextStatus,
          );
        }),
      );
    } on _Abort catch (abort) {
      return Err(abort.failure);
    }
  }

  /// İptal sebebini nota ekler — mevcut not **korunur**.
  static String _appendNote(String? existing, String reason) {
    final suffix = 'İptal sebebi: $reason';
    if (existing == null || existing.trim().isEmpty) return suffix;
    return '$existing\n$suffix';
  }
}
