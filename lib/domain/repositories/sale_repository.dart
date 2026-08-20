/// Satış repository sözleşmesi — **REQ-ARCH-004**
///
/// ## Yazma metotlarının tek çağıranı vardır
///
/// Satış oluşturma **atomik bir transaction**'dır (BR-SALE-005): sale +
/// saleItems + stockMovements + stock + cart + audit. Transaction sınırları
/// yalnızca application katmanında açılır (rules/01 §5), dolayısıyla
/// [insertSale] ve [insertItem] **yalnızca `SaleService`** tarafından ve
/// **tek bir transaction içinde** çağrılır. Ayrı ayrı çağrılırlarsa başlıksız
/// satır ya da satırsız satış oluşur — yani BR-SALE-005 ihlal edilir.
///
/// `update`/`delete` **yoktur ve eklenmeyecektir**: satış kayıtları silinmez
/// (BR-GEN-002 · BR-SALE-006), snapshot alanları immutable'dır (rules/02 §3);
/// iptal ve iade yalnızca **durum** değiştirir ve Faz 7 kapsamındadır.
library;

import '../../core/result/result.dart';
import '../enums/sale_status.dart';
import '../models/sale.dart';
import '../models/sale_return.dart';

abstract interface class SaleRepository {
  Future<Result<Sale>> findById(int id);

  Future<Result<Sale>> findByNumber(String saleNumber);

  /// Tarih aralıklı listeleme — `ix_sales_completed_at` kullanır (docs/05 §3).
  ///
  /// Sınırlar **UTC**'dir; yerel gün sınırına çevirme çağıranın işidir
  /// (BR-GEN-004).
  Future<List<Sale>> listCompletedBetween({
    required DateTime fromUtc,
    required DateTime toUtc,
    int limit = 100,
    int offset = 0,
  });

  /// Satış satırları — 5 snapshot alanıyla birlikte (BR-SALE-001).
  Future<List<SaleItem>> itemsOf(int saleId);

  /// Satış başlığını yazar ve `id`'sini döner.
  ///
  /// ⚠️ **Yalnızca `SaleService` çağırır.** Transaction çağırana aittir
  /// (rules/01 §5). `sale_number` şemada `UNIQUE`'tir; çakışma bir hata
  /// değil, **satışın hiç oluşmaması** demektir (REQ-SALE-005).
  Future<int> insertSale(NewSale sale);

  /// Satış satırını **beş snapshot alanıyla** yazar (BR-SALE-001) ve `id`'sini
  /// döner.
  ///
  /// ⚠️ **Yalnızca `SaleService` çağırır**, [insertSale] ile aynı transaction
  /// içinde.
  Future<int> insertItem(int saleId, NewSaleItem item);

  // --- Faz 7: iptal ve iade ------------------------------------------------

  /// Satış **durumunu** değiştirir — docs/14 §2.
  ///
  /// Satış kaydı hiçbir koşulda **silinmez** (BR-GEN-002 · REQ-RET-001);
  /// bu yüzden arayüzde `delete` yoktur ve olmayacaktır.
  ///
  /// ⚠️ Yalnızca `ReturnService` çağırır ve durumu **elle atamaz**:
  /// `SaleStatusRules` üzerinden hesaplar (REQ-RET-007).
  Future<int> updateStatus(
    int saleId, {
    required SaleStatus status,
    DateTime? cancelledAtUtc,
    String? note,
  });

  /// İade başlığını yazar ve `id`'sini döner.
  Future<int> insertReturn(NewReturn value);

  /// İade satırını yazar — fiyat **orijinal snapshot'tır** (BR-RET-005).
  Future<int> insertReturnItem(int returnId, NewReturnItem item);

  /// `sale_items.returned_quantity`'yi [by] kadar artırır (denormalize alan,
  /// rules/03 §2 — kaynağıyla **aynı transaction** içinde güncellenir).
  ///
  /// Şemadaki `CHECK(returned_quantity <= quantity)` son güvencedir.
  Future<int> incrementReturnedQuantity(int saleItemId, int by);

  /// Bir satışın iadeleri — satış detayında gösterilir.
  Future<List<SaleReturn>> returnsOf(int saleId);

  /// Bir iadenin satırları.
  Future<List<SaleReturnItem>> returnItemsOf(int returnId);
}
