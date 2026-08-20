/// Rapor ve dashboard sorguları — **docs/15 · docs/16 · OD-028**
///
/// `rules/01 §1` application katmanında **ham SQL detayını** yasaklar; tüm
/// aggregation buraya aittir. `rules/01 §8`: toplama **SQL tarafında** yapılır,
/// Dart'ta döngüyle toplamak yasaktır — hedef 100.000 satış satırıyla < 1 sn
/// (docs/15 §5).
///
/// ## Net değerlerin aritmetiği — OD-028
///
/// ```text
/// brüt ciro = Σ grandTotal              · completed_at aralıkta · TÜM durumlar
/// iptal     = Σ grandTotal              · cancelled_at aralıkta · cancelled
/// iade      = Σ return_items.line_total · returns.created_at aralıkta
/// ─────────────────────────────────────────────────────────────
/// net ciro  = brüt − iptal − iade
/// ```
///
/// **Brüt iptalleri İÇERİR**: içermeseydi `− iptal` terimi iptali ikinci kez
/// düşerdi. **İptal ve iade kendi tarihlerine yazılır**: orijinal satışın
/// gününden düşmek kapanmış bir günün cirosunu geriye dönük değiştirirdi
/// (docs/14 §5).
///
/// ## Kâr KDV HARİÇ matrahtan
///
/// BR-VAT-003 gereği fiyatlar KDV dahildir ve **KDV işletmenin geliri
/// değildir**. `brütKâr = matrah − maliyet` (REQ-VAT-009 · REQ-REP-013).
library;

import 'package:drift/drift.dart';

import '../db/canteen_database.dart';

/// Bir dönemin ciro/kâr özeti — tüm değerler **kuruş**.
class PeriodTotals {
  /// TÜM satışların toplamı (iptaller dâhil) — OD-028.
  final int grossRevenueMinor;

  final int cancelledMinor;
  final int returnedMinor;

  /// KDV **hariç** matrah — kâr bunun üzerinden hesaplanır.
  final int netBaseMinor;

  final int vatMinor;

  /// Satılan malın maliyeti (snapshot'lardan).
  final int costMinor;

  /// İptal ve iadelerin maliyet karşılığı — kârdan **geri eklenir**.
  final int reversedCostMinor;

  final int saleCount;
  final int unitCount;
  final int returnedUnitCount;

  const PeriodTotals({
    required this.grossRevenueMinor,
    required this.cancelledMinor,
    required this.returnedMinor,
    required this.netBaseMinor,
    required this.vatMinor,
    required this.costMinor,
    required this.reversedCostMinor,
    required this.saleCount,
    required this.unitCount,
    required this.returnedUnitCount,
  });

  static const PeriodTotals empty = PeriodTotals(
    grossRevenueMinor: 0,
    cancelledMinor: 0,
    returnedMinor: 0,
    netBaseMinor: 0,
    vatMinor: 0,
    costMinor: 0,
    reversedCostMinor: 0,
    saleCount: 0,
    unitCount: 0,
    returnedUnitCount: 0,
  );
}

/// Zaman serisi noktası — `bucket` yerel gün/saat etiketidir.
class TrendPoint {
  final String bucket;
  final int revenueMinor;
  final int saleCount;

  const TrendPoint({
    required this.bucket,
    required this.revenueMinor,
    required this.saleCount,
  });
}

/// Ürün kırılımı — "en çok satan" ve "hiç satmayan" aynı yapıyı kullanır.
class ProductBreakdown {
  final int productId;
  final String name;
  final int unitCount;
  final int revenueMinor;

  /// KDV hariç matrah − maliyet (REQ-VAT-009).
  final int profitMinor;

  const ProductBreakdown({
    required this.productId,
    required this.name,
    required this.unitCount,
    required this.revenueMinor,
    required this.profitMinor,
  });
}

/// Kategori kırılımı — docs/15 §3.6.
class CategoryBreakdown {
  final int? categoryId;
  final String name;
  final int revenueMinor;
  final int unitCount;

  const CategoryBreakdown({
    required this.categoryId,
    required this.name,
    required this.revenueMinor,
    required this.unitCount,
  });
}

class ReportingDao extends DatabaseAccessor<CanteenDatabase> {
  ReportingDao(super.db);

  /// docs/15 §2 · docs/16 — dönem özeti.
  ///
  /// Üç ayrı zaman ekseni tek sorguda toplanır (OD-028): satışlar
  /// `completed_at`, iptaller `cancelled_at`, iadeler `returns.created_at`
  /// üzerinden filtrelenir. Alt sorgular birbirinden bağımsızdır; JOIN ile
  /// birleştirmek satır çoğaltır ve toplamları şişirirdi.
  Future<PeriodTotals> periodTotals({
    required int fromMillis,
    required int toMillis,
  }) async {
    final row = await customSelect(
      '''
SELECT
  (SELECT COALESCE(SUM(grand_total_minor), 0) FROM sales
    WHERE completed_at >= ?1 AND completed_at < ?2)              AS gross,
  (SELECT COUNT(*) FROM sales
    WHERE completed_at >= ?1 AND completed_at < ?2)              AS sale_count,
  (SELECT COALESCE(SUM(unit_count), 0) FROM sales
    WHERE completed_at >= ?1 AND completed_at < ?2)              AS unit_count,
  (SELECT COALESCE(SUM(subtotal_minor), 0) FROM sales
    WHERE completed_at >= ?1 AND completed_at < ?2)              AS net_base,
  (SELECT COALESCE(SUM(vat_total_minor), 0) FROM sales
    WHERE completed_at >= ?1 AND completed_at < ?2)              AS vat,
  (SELECT COALESCE(SUM(cost_total_minor), 0) FROM sales
    WHERE completed_at >= ?1 AND completed_at < ?2)              AS cost,
  (SELECT COALESCE(SUM(grand_total_minor), 0) FROM sales
    WHERE status = 'cancelled'
      AND cancelled_at >= ?1 AND cancelled_at < ?2)              AS cancelled,
  (SELECT COALESCE(SUM(ri.line_total_minor), 0)
     FROM return_items ri JOIN returns r ON r.id = ri.return_id
    WHERE r.created_at >= ?1 AND r.created_at < ?2)              AS returned,
  (SELECT COALESCE(SUM(ri.quantity), 0)
     FROM return_items ri JOIN returns r ON r.id = ri.return_id
    WHERE r.created_at >= ?1 AND r.created_at < ?2)              AS returned_units,
  (SELECT COALESCE(SUM(si.purchase_price_snapshot_minor * si.quantity), 0)
     FROM sale_items si JOIN sales s ON s.id = si.sale_id
    WHERE s.status = 'cancelled'
      AND s.cancelled_at >= ?1 AND s.cancelled_at < ?2)          AS cancelled_cost,
  (SELECT COALESCE(SUM(si.purchase_price_snapshot_minor * ri.quantity), 0)
     FROM return_items ri
     JOIN returns r  ON r.id = ri.return_id
     JOIN sale_items si ON si.id = ri.sale_item_id
    WHERE r.created_at >= ?1 AND r.created_at < ?2)              AS returned_cost
''',
      variables: [Variable.withInt(fromMillis), Variable.withInt(toMillis)],
      readsFrom: {sales, saleItems, returns, returnItems},
    ).getSingle();

    return PeriodTotals(
      grossRevenueMinor: row.read<int>('gross'),
      cancelledMinor: row.read<int>('cancelled'),
      returnedMinor: row.read<int>('returned'),
      netBaseMinor: row.read<int>('net_base'),
      vatMinor: row.read<int>('vat'),
      costMinor: row.read<int>('cost'),
      reversedCostMinor:
          row.read<int>('cancelled_cost') + row.read<int>('returned_cost'),
      saleCount: row.read<int>('sale_count'),
      unitCount: row.read<int>('unit_count'),
      returnedUnitCount: row.read<int>('returned_units'),
    );
  }

  /// docs/15 §3.2 — ciro trendi.
  ///
  /// [format] SQLite `strftime` biçimidir (`'%Y-%m-%d'`, `'%H'` …). Gruplama
  /// **yerel saate** göre yapılır (BR-GEN-004): `unixepoch`'a `localtime`
  /// eklenir, aksi hâlde gün sınırları UTC'ye kayar ve kullanıcının "bugün"ü
  /// yanlış olurdu.
  Future<List<TrendPoint>> revenueTrend({
    required int fromMillis,
    required int toMillis,
    required String format,
  }) async {
    final rows = await customSelect(
      "SELECT strftime(?3, completed_at / 1000, 'unixepoch', 'localtime') "
      '         AS bucket, '
      '       COALESCE(SUM(grand_total_minor), 0) AS revenue, '
      '       COUNT(*) AS sale_count '
      'FROM sales '
      "WHERE status != 'cancelled' "
      '  AND completed_at >= ?1 AND completed_at < ?2 '
      'GROUP BY bucket ORDER BY bucket',
      variables: [
        Variable.withInt(fromMillis),
        Variable.withInt(toMillis),
        Variable.withString(format),
      ],
      readsFrom: {sales},
    ).get();

    return [
      for (final row in rows)
        TrendPoint(
          bucket: row.read<String>('bucket'),
          revenueMinor: row.read<int>('revenue'),
          saleCount: row.read<int>('sale_count'),
        ),
    ];
  }

  /// docs/15 §3.4 — en çok satan ürünler.
  ///
  /// Snapshot alanları kullanılır; `products`'a **JOIN yapılmaz** (rules/02 §3):
  /// ürün adı sonradan değişse de geçmiş rapor aynı sonucu verir.
  ///
  /// İade edilen miktarlar **düşülür** (BR-RET-007 — raporlar nettir).
  Future<List<ProductBreakdown>> topProducts({
    required int fromMillis,
    required int toMillis,
    int limit = 10,
  }) async {
    final rows = await customSelect(
      '''
SELECT si.product_id                                       AS product_id,
       si.product_name_snapshot                            AS name,
       SUM(si.quantity - si.returned_quantity)             AS units,
       SUM(si.line_total_minor
           - CAST(si.line_total_minor AS REAL) * si.returned_quantity
             / si.quantity)                                AS revenue,
       SUM(si.line_net_minor
           - CAST(si.line_net_minor AS REAL) * si.returned_quantity
             / si.quantity
           - si.purchase_price_snapshot_minor
             * (si.quantity - si.returned_quantity))       AS profit
FROM sale_items si
JOIN sales s ON s.id = si.sale_id
WHERE s.status != 'cancelled'
  AND s.completed_at >= ?1 AND s.completed_at < ?2
GROUP BY si.product_id, si.product_name_snapshot
HAVING units > 0
ORDER BY units DESC
LIMIT ?3
''',
      variables: [
        Variable.withInt(fromMillis),
        Variable.withInt(toMillis),
        Variable.withInt(limit),
      ],
      readsFrom: {sales, saleItems},
    ).get();

    return rows.map(_toBreakdown).toList();
  }

  /// docs/15 §3.6 — kategori dağılımı.
  ///
  /// `category_id_snapshot` kullanılır (BR-SALE-001): ürün sonradan başka
  /// kategoriye taşınsa da geçmiş kategori raporu **değişmez**.
  Future<List<CategoryBreakdown>> categoryBreakdown({
    required int fromMillis,
    required int toMillis,
  }) async {
    final rows = await customSelect(
      '''
SELECT si.category_id_snapshot                   AS category_id,
       COALESCE(c.name, 'Kategorisiz')           AS name,
       SUM(si.line_total_minor)                  AS revenue,
       SUM(si.quantity - si.returned_quantity)   AS units
FROM sale_items si
JOIN sales s ON s.id = si.sale_id
LEFT JOIN categories c ON c.id = si.category_id_snapshot
WHERE s.status != 'cancelled'
  AND s.completed_at >= ?1 AND s.completed_at < ?2
GROUP BY si.category_id_snapshot, name
ORDER BY revenue DESC
''',
      variables: [Variable.withInt(fromMillis), Variable.withInt(toMillis)],
      readsFrom: {sales, saleItems, categories},
    ).get();

    return [
      for (final row in rows)
        CategoryBreakdown(
          categoryId: row.read<int?>('category_id'),
          name: row.read<String>('name'),
          revenueMinor: row.read<int>('revenue'),
          unitCount: row.read<int>('units'),
        ),
    ];
  }

  /// docs/15 §3.3 — saatlik yoğunluk (0–23, yerel saat).
  Future<List<TrendPoint>> hourlyDensity({
    required int fromMillis,
    required int toMillis,
  }) => revenueTrend(fromMillis: fromMillis, toMillis: toMillis, format: '%H');

  /// docs/15 §3.7 — kritik stok sayısı (**anlık**, tarih aralığından bağımsız).
  Future<int> criticalStockCount() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM products '
      'WHERE is_active = 1 AND minimum_stock > 0 '
      '  AND stock_quantity <= minimum_stock',
      readsFrom: {products},
    ).getSingle();
    return row.read<int>('c');
  }

  /// docs/15 §3.1 — negatif stok sayısı (**anlık**).
  Future<int> negativeStockCount() async {
    final row = await customSelect(
      'SELECT COUNT(*) AS c FROM products WHERE stock_quantity < 0',
      readsFrom: {products},
    ).getSingle();
    return row.read<int>('c');
  }

  /// docs/16 R10 — fire maliyeti (kâr raporunda **gider**).
  Future<int> wasteCostMinor({
    required int fromMillis,
    required int toMillis,
  }) async {
    final row = await customSelect(
      "SELECT COALESCE(SUM(-quantity_delta * COALESCE(unit_cost_minor, 0)), 0) "
      '         AS cost '
      'FROM stock_movements '
      "WHERE type = 'waste' AND created_at >= ?1 AND created_at < ?2",
      variables: [Variable.withInt(fromMillis), Variable.withInt(toMillis)],
      readsFrom: {stockMovements},
    ).getSingle();
    return row.read<int>('cost');
  }

  $ProductsTable get products => attachedDatabase.products;
  $SalesTable get sales => attachedDatabase.sales;
  $SaleItemsTable get saleItems => attachedDatabase.saleItems;
  $ReturnsTable get returns => attachedDatabase.returns;
  $ReturnItemsTable get returnItems => attachedDatabase.returnItems;
  $CategoriesTable get categories => attachedDatabase.categories;
  $StockMovementsTable get stockMovements => attachedDatabase.stockMovements;

  static ProductBreakdown _toBreakdown(QueryRow row) => ProductBreakdown(
    productId: row.read<int>('product_id'),
    name: row.read<String>('name'),
    unitCount: row.read<int>('units'),
    // Oransal iade düşümü kesirli çıkabilir; kuruş **tam sayıdır**
    // (BR-FIN-001) ve yuvarlama burada yapılır.
    revenueMinor: row.read<double>('revenue').round(),
    profitMinor: row.read<double>('profit').round(),
  );
}
