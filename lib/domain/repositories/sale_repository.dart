/// Satış repository sözleşmesi — **REQ-ARCH-004**
///
/// ## Neden `create` yok
///
/// Satış oluşturma **atomik bir transaction**'dır (BR-SALE-005): sale +
/// saleItems + stockMovements + stock + cart + audit. Transaction sınırları
/// yalnızca application katmanında açılır (rules/01 §5) ve bu akış **Faz 5**
/// kapsamındadır. Faz 2 yalnızca okuma tarafını kurar.
library;

import '../../core/result/result.dart';
import '../models/sale.dart';

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
}
