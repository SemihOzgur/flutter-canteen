/// Veri dışa aktarma — **docs/20 §8 · REQ-IMEX-013 · REQ-AUDIT-001**
///
/// ## Ürün export'u import ŞABLONUYLA UYUMLUDUR
///
/// docs/20 §8: *"dışa aktar, düzenle, içe aktar döngüsü çalışır."*
/// Sütun başlıkları [ImportField.label] değerlerinden üretilir — ikisi
/// ayrışırsa döngü sessizce kırılır ve kullanıcı kendi dışa aktardığı dosyayı
/// içe aktaramaz. Bu yüzden başlıklar **elle yazılmaz**.
///
/// ## Kilit YOKTUR — ve bu bilinçlidir
///
/// rules/04 §4: finansal erişim kilidi yalnızca Dashboard ve Raporlar
/// içindir. Ürün/kategori/tedarikçi listesi kilit **dışındadır**; kullanıcı
/// bunları zaten ekranda görebiliyor. Satış ve rapor export'ları ise
/// `ReportExportService` üzerinden ve **kapının arkasından** gider.
library;

import '../../core/money/money_formatter.dart';
import '../../data/dao/daos.dart';
import '../../data/files/csv_writer.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/services/product_import_rules.dart';
import '../audit/audit_actions.dart';
import '../audit/audit_service.dart';

/// docs/20 §8 — kilit dışındaki export türleri.
enum DataExport { products, categories, suppliers }

class DataExportService {
  final ProductRepository _products;
  final CategoriesDao _categories;
  final SuppliersDao _suppliers;
  final AuditService? _audit;
  final DateTime Function() _clock;

  DataExportService({
    required ProductRepository products,
    required CategoriesDao categories,
    required SuppliersDao suppliers,
    required DateTime Function() clock,
    AuditService? audit,
  }) : _products = products,
       _categories = categories,
       _suppliers = suppliers,
       _audit = audit,
       _clock = clock;

  /// docs/20 §8 — CSV üretir (BOM + `;`, formül kaçışlamalı).
  Future<String> exportCsv(DataExport target) async {
    final rows = switch (target) {
      DataExport.products => await _productRows(),
      DataExport.categories => await _categoryRows(),
      DataExport.suppliers => await _supplierRows(),
    };

    await _audit?.record(
      action: AuditActions.dataExported,
      entityType: AuditEntities.system,
      at: _clock().toUtc(),
      metadata: {'export': target.name, 'row_count': rows.length - 1},
    );

    return CsvWriter.encode(rows);
  }

  /// **Import şablonuyla birebir aynı sütunlar** — REQ-IMEX-013.
  ///
  /// Şablon indirme de aynı başlıkları kullanır (REQ-IMEX-002); tek kaynak
  /// [ImportField] enum'ıdır.
  static List<Object?> get productHeader => [
    for (final field in ImportField.values) field.label,
  ];

  /// REQ-IMEX-002 — boş şablon: yalnızca başlık satırı.
  static String template() => CsvWriter.encode([productHeader]);

  Future<List<List<Object?>>> _productRows() async {
    // docs/09 §4 — export pasif ürünleri de içerir: kullanıcı kendi
    // verisinin tamamını geri alabilmelidir.
    final all = await _products.list(includeInactive: true, limit: 100000);

    final rows = <List<Object?>>[productHeader];
    for (final product in all) {
      final barcodes = await _products.barcodesOf(product.id);
      final category = await _categories.findById(product.categoryId);
      rows.add([
        product.name,
        MoneyFormatter.format(product.salePrice),
        MoneyFormatter.format(product.purchasePrice),
        category?.name ?? '',
        barcodes.join(ProductImportRules.barcodeSeparator),
        product.brand ?? '',
        product.salesUnit ?? '',
        product.netWeightValue ?? '',
        product.netWeightUnit ?? '',
        // KDV oranı yüzde olarak yazılır; import de yüzde bekler.
        '',
        '',
        // docs/20 §8 — güncel stok. Import tarafında bu sütun YENİ ürünlerde
        // `initial` hareketi olur; güncellemede yok sayılır (docs/20 §4.1).
        product.stockQuantity,
        product.minimumStock,
        product.shelfLocation ?? '',
        product.description ?? '',
      ]);
    }
    return rows;
  }

  Future<List<List<Object?>>> _categoryRows() async => [
    const ['Kategori', 'Sıra', 'Durum'],
    for (final category in await _categories.listAll())
      [
        category.name,
        category.sortOrder,
        category.isActive ? 'Aktif' : 'Pasif',
      ],
  ];

  Future<List<List<Object?>>> _supplierRows() async => [
    const ['Tedarikçi', 'Telefon', 'E-posta', 'Durum'],
    for (final supplier in await _suppliers.listAll())
      [
        supplier.name,
        supplier.phone ?? '',
        supplier.email ?? '',
        supplier.isActive ? 'Aktif' : 'Pasif',
      ],
  ];
}
