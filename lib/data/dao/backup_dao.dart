/// Yedekleme sorguları — **docs/19 §2–§5.**
///
/// `rules/01 §1` application katmanında **ham SQL detayını** yasaklar:
/// `VACUUM INTO`, `integrity_check` ve `counts` sorguları buraya aittir.
/// `BackupService` neyin yedekleneceğine ve neyin geçerli sayılacağına karar
/// verir; **nasıl sorgulanacağına** değil.
library;

import 'package:drift/drift.dart';

import '../db/canteen_database.dart';
import '../db/raw_sqlite_file.dart';

class BackupDao extends DatabaseAccessor<CanteenDatabase> {
  BackupDao(super.db);

  $ProductsTable get products => attachedDatabase.products;
  $SalesTable get sales => attachedDatabase.sales;

  /// docs/19 §3 adım 3 — **uygulamayı durdurmadan** tutarlı kopya.
  ///
  /// `VACUUM INTO` WAL'daki tamamlanmış işlemleri de içerir (REQ-BKUP-003),
  /// bir transaction içinde çalıştırılamaz ve hedef dosya **var olmamalıdır**.
  ///
  /// Yol **parametrelidir**; SQL'e gömülmez (REQ-SEC-006).
  Future<void> snapshotInto(String targetPath) =>
      customStatement('VACUUM INTO ?;', [targetPath]);

  /// docs/19 §2 — `metadata.counts`.
  ///
  /// Tek sorguda toplanır: sekiz ayrı `COUNT(*)` yerine tek geçiş
  /// (rules/01 §8).
  Future<Map<String, int>> tableCounts() async {
    final row = await customSelect(
      'SELECT '
      ' (SELECT COUNT(*) FROM products)        AS products, '
      ' (SELECT COUNT(*) FROM categories)      AS categories, '
      ' (SELECT COUNT(*) FROM suppliers)       AS suppliers, '
      ' (SELECT COUNT(*) FROM sales)           AS sales, '
      ' (SELECT COUNT(*) FROM sale_items)      AS sale_items, '
      ' (SELECT COUNT(*) FROM stock_movements) AS stock_movements, '
      ' (SELECT COUNT(*) FROM audit_logs)      AS audit_logs',
    ).getSingle();

    return {
      'products': row.read<int>('products'),
      'categories': row.read<int>('categories'),
      'suppliers': row.read<int>('suppliers'),
      'sales': row.read<int>('sales'),
      'saleItems': row.read<int>('sale_items'),
      'stockMovements': row.read<int>('stock_movements'),
      'auditLogs': row.read<int>('audit_logs'),
    };
  }

  /// docs/19 §3 adım 4 — yalnızca **DB'de referansı olan** görseller.
  ///
  /// Orphan dosyalar yedeğe girmez: yedeği gereksiz büyütür ve bir sonraki
  /// restore'da geri gelirlerdi (docs/19 §5 — orphan taraması).
  Future<List<String>> referencedImagePaths() async {
    final rows =
        await (selectOnly(products)
              ..addColumns([products.imagePath])
              ..where(products.imagePath.isNotNull()))
            .get();
    return [for (final row in rows) ?row.read(products.imagePath)];
  }

  /// docs/19 §5 · REQ-BKUP-015 — satış numarası sayacı düzeltmesi.
  ///
  /// Geri yüklenen veritabanındaki en yüksek numara okunur; aksi hâlde sayaç
  /// eski değerinde kalır ve **numara çakışması** olur.
  Future<String?> maxSaleNumber() async {
    final row = await customSelect(
      'SELECT MAX(sale_number) AS max_number FROM sales',
    ).getSingle();
    return row.read<String?>('max_number');
  }

  /// docs/19 §4 adım 7 · adım 15 — `PRAGMA integrity_check`.
  ///
  /// Ayrı bir dosyayı, açık bağlantıya dokunmadan denetler.
  static Future<bool> isFileIntegral(String path) =>
      RawSqliteFile(path).isIntegral();
}
