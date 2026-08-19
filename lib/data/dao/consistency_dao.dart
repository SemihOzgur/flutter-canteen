/// Tutarlılık denetimi sorguları — **docs/24 §3.3.**
///
/// ## Neden ayrı bir DAO
///
/// `rules/01 §1` application katmanında **ham SQL detayını** yasaklar.
/// Denetimlerin tamamı aggregation sorgusudur ve `rules/01 §8` gereği
/// toplama SQL tarafında yapılır — dolayısıyla sorgular buraya, *kararlar*
/// `application/maintenance/consistency_service.dart` içine aittir.
///
/// Bu DAO **hiçbir iş kararı vermez**: sapmanın düzeltilebilir olup olmadığına,
/// kullanıcıya nasıl gösterileceğine veya audit'e ne yazılacağına burada karar
/// verilmez.
library;

import 'package:drift/drift.dart';

import '../db/canteen_database.dart';

/// Türetilmiş bir alanın kaynağından saptığı tek bir kayıt.
class DriftRow {
  final int id;
  final String label;

  /// Kaynaktan hesaplanan — **doğru** kabul edilen değer.
  final String expected;

  /// Türetilmiş alanda **bulunan** değer.
  final String actual;

  const DriftRow({
    required this.id,
    required this.label,
    required this.expected,
    required this.actual,
  });
}

class ConsistencyDao extends DatabaseAccessor<CanteenDatabase> {
  ConsistencyDao(super.db);

  // `@DriftAccessor` mixin'i yerine doğrudan erişim: bu DAO hiçbir tabloya
  // yazmaz, yalnızca okur ve `daos.g.dart` part'ına yeni bir accessor eklemeyi
  // gerektirmez.
  $ProductsTable get products => attachedDatabase.products;
  $SalesTable get sales => attachedDatabase.sales;
  $SaleItemsTable get saleItems => attachedDatabase.saleItems;
  $ReturnItemsTable get returnItems => attachedDatabase.returnItems;
  $StockMovementsTable get stockMovements => attachedDatabase.stockMovements;

  /// `products.stock_quantity` = Σ `stock_movements.quantity_delta`
  ///
  /// `LEFT JOIN`: hiç hareketi olmayan ürün de denetlenir — defter toplamı
  /// `0`'dır ve önbellek `0` değilse bu bir sapmadır.
  Future<List<DriftRow>> stockQuantityDrift() async {
    final rows = await customSelect(
      'SELECT p.id AS id, p.name AS label, p.stock_quantity AS actual, '
      '       COALESCE(SUM(m.quantity_delta), 0) AS expected '
      'FROM products p '
      'LEFT JOIN stock_movements m ON m.product_id = p.id '
      'GROUP BY p.id '
      'HAVING p.stock_quantity != COALESCE(SUM(m.quantity_delta), 0)',
      readsFrom: {products, stockMovements},
    ).get();
    return rows.map(_toDrift).toList();
  }

  /// `sales.grand_total_minor` = Σ `sale_items.line_total_minor`
  Future<List<DriftRow>> saleTotalDrift() async {
    final rows = await customSelect(
      'SELECT s.id AS id, s.sale_number AS label, '
      '       s.grand_total_minor AS actual, '
      '       COALESCE(SUM(i.line_total_minor), 0) AS expected '
      'FROM sales s '
      'LEFT JOIN sale_items i ON i.sale_id = s.id '
      'GROUP BY s.id '
      'HAVING s.grand_total_minor != COALESCE(SUM(i.line_total_minor), 0)',
      readsFrom: {sales, saleItems},
    ).get();
    return rows.map(_toDrift).toList();
  }

  /// `sales.item_count` / `unit_count` satırlarla tutarlı
  Future<List<DriftRow>> saleCountDrift() async {
    final rows = await customSelect(
      'SELECT s.id AS id, s.sale_number AS label, '
      '       s.item_count AS item_count, s.unit_count AS unit_count, '
      '       COUNT(i.id) AS real_items, '
      '       COALESCE(SUM(i.quantity), 0) AS real_units '
      'FROM sales s '
      'LEFT JOIN sale_items i ON i.sale_id = s.id '
      'GROUP BY s.id '
      'HAVING s.item_count != COUNT(i.id) '
      '    OR s.unit_count != COALESCE(SUM(i.quantity), 0)',
      readsFrom: {sales, saleItems},
    ).get();

    return [
      for (final row in rows)
        DriftRow(
          id: row.read<int>('id'),
          label: row.read<String>('label'),
          expected:
              '${row.read<int>('real_items')} satır / '
              '${row.read<int>('real_units')} adet',
          actual:
              '${row.read<int>('item_count')} satır / '
              '${row.read<int>('unit_count')} adet',
        ),
    ];
  }

  /// `sale_items.returned_quantity` = Σ `return_items.quantity`
  ///
  /// İade **Faz 7**'dedir; bugün her satır `0 = 0` verir. Denetimin şimdiden
  /// var olması bilinçlidir: sonradan eklenen bir kontrol, aradaki sapmaları
  /// hiç görmemiş olurdu.
  Future<List<DriftRow>> returnedQuantityDrift() async {
    final rows = await customSelect(
      'SELECT i.id AS id, i.product_name_snapshot AS label, '
      '       i.returned_quantity AS actual, '
      '       COALESCE(SUM(r.quantity), 0) AS expected '
      'FROM sale_items i '
      'LEFT JOIN return_items r ON r.sale_item_id = i.id '
      'GROUP BY i.id '
      'HAVING i.returned_quantity != COALESCE(SUM(r.quantity), 0)',
      readsFrom: {saleItems, returnItems},
    ).get();
    return rows.map(_toDrift).toList();
  }

  /// `PRAGMA foreign_key_check` — boş dönmelidir (rules/03 §3).
  Future<List<String>> foreignKeyViolations() async {
    final rows = await customSelect('PRAGMA foreign_key_check').get();
    return rows.map((row) => row.data.toString()).toList();
  }

  /// `PRAGMA integrity_check` — `ok` dönmelidir.
  Future<String> integrityCheck() async {
    final rows = await customSelect('PRAGMA integrity_check').get();
    if (rows.isEmpty) return 'sonuç yok';
    return rows.first.data.values.first.toString();
  }

  /// Görseli olan ürünler — `(id, ad, göreli yol)`.
  Future<List<({int id, String name, String imagePath})>>
  productsWithImages() async {
    final rows =
        await (selectOnly(products)
              ..addColumns([products.id, products.name, products.imagePath])
              ..where(products.imagePath.isNotNull()))
            .get();
    return [
      for (final row in rows)
        (
          id: row.read(products.id)!,
          name: row.read(products.name)!,
          imagePath: row.read(products.imagePath)!,
        ),
    ];
  }

  Future<int> countProducts() async {
    final total = products.id.count();
    final row = await (selectOnly(products)..addColumns([total])).getSingle();
    return row.read(total) ?? 0;
  }

  Future<int> countSales() async {
    final total = sales.id.count();
    final row = await (selectOnly(sales)..addColumns([total])).getSingle();
    return row.read(total) ?? 0;
  }

  static DriftRow _toDrift(QueryRow row) => DriftRow(
    id: row.read<int>('id'),
    label: row.read<String>('label'),
    expected: '${row.read<int>('expected')}',
    actual: '${row.read<int>('actual')}',
  );
}
