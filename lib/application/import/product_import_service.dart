/// Ürün içe aktarma — **docs/20 §3–§6 · BR-DATA-005 · BR-IMEX-001/002**
///
/// ```text
/// Dosya seç → Ayrıştır → Eşleştir → DOĞRULA → ÖNİZLE → ONAY → Uygula
/// ```
///
/// **Önizleme atlanamaz** (REQ-IMEX-007): [preview] hiçbir şey yazmaz,
/// [apply] ise yalnızca kullanıcının gördüğü önizlemeyi uygular.
///
/// ## All-or-nothing — BR-DATA-005 · REQ-IMEX-008
///
/// Uygulama tek transaction'dır. Hatalı satırlar (🔴) transaction'a **hiç
/// dâhil edilmez**; bu "kısmi import" değildir — kullanıcının önizlemede
/// gördüğü ve onayladığı kapsamdır (docs/20 §6).
///
/// ## Satış ve stok hareketi import EDİLEMEZ — REQ-IMEX-012
///
/// Bu servis yalnızca ürün, kategori, tedarikçi ve **başlangıç stoğu**
/// yazar. Stok değişimi doğrudan yazılmaz; `StockService` üzerinden hareket
/// oluşturur (REQ-IMEX-011). Satış ve satış satırı için bir yol **yoktur ve
/// eklenmeyecektir** — denetim izinin temeli budur (docs/20 §1).
library;

import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../core/result/result.dart';
import '../../data/dao/daos.dart';
import '../../data/db/canteen_database.dart' show CanteenDatabase;
import '../../data/files/csv_parser.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/services/product_import_rules.dart';
import '../audit/audit_actions.dart';
import '../audit/audit_service.dart';
import '../product/product_draft.dart';
import '../product/product_service.dart';
import 'import_failures.dart';

/// Doğrulanmış tek satır.
class ImportRow {
  /// Dosyadaki gerçek satır numarası (başlık 1'dir) — REQ-IMEX-005.
  final int lineNumber;

  final String name;
  final Money salePrice;
  final Money purchasePrice;
  final String? category;
  final List<String> barcodes;
  final String? brand;
  final String? supplier;
  final int initialStock;
  final int minimumStock;
  final String? shelfLocation;
  final String? description;
  final int? netWeightValue;
  final String? netWeightUnit;
  final List<ImportIssue> issues;

  /// `true` ise satır mevcut bir ürünü **günceller** (BR-IMEX-001).
  final int? updatesProductId;

  const ImportRow({
    required this.lineNumber,
    required this.name,
    required this.salePrice,
    required this.purchasePrice,
    required this.category,
    required this.barcodes,
    required this.brand,
    required this.supplier,
    required this.initialStock,
    required this.minimumStock,
    required this.shelfLocation,
    required this.description,
    required this.netWeightValue,
    required this.netWeightUnit,
    required this.issues,
    required this.updatesProductId,
  });

  /// 🔴 bulgusu olan satır **alınmaz**.
  bool get isRejected => issues.any((issue) => issue.isBlocking);
  bool get hasWarnings => issues.any((issue) => !issue.isBlocking);
}

/// docs/20 §5 — önizleme.
class ImportPreview {
  final List<ImportRow> rows;
  final String separator;

  /// Oluşturulacak yeni kategori ve tedarikçi adları.
  final Set<String> newCategories;
  final Set<String> newSuppliers;

  const ImportPreview({
    required this.rows,
    required this.separator,
    required this.newCategories,
    required this.newSuppliers,
  });

  Iterable<ImportRow> get accepted => rows.where((row) => !row.isRejected);
  Iterable<ImportRow> get rejected => rows.where((row) => row.isRejected);

  int get createCount =>
      accepted.where((row) => row.updatesProductId == null).length;
  int get updateCount =>
      accepted.where((row) => row.updatesProductId != null).length;
  int get warningCount => accepted.where((row) => row.hasWarnings).length;
  int get rejectedCount => rejected.length;

  bool get hasAnything => accepted.isNotEmpty;
}

/// docs/20 §6 — sonuç raporu.
class ImportResult {
  final int created;
  final int updated;
  final int skipped;
  final int newCategories;
  final int newSuppliers;

  const ImportResult({
    required this.created,
    required this.updated,
    required this.skipped,
    required this.newCategories,
    required this.newSuppliers,
  });
}

class _Abort implements Exception {
  final Failure failure;
  const _Abort(this.failure);
}

class ProductImportService {
  final CanteenDatabase _db;
  final ProductService _products;
  final ProductRepository _productRepo;
  final CategoriesDao _categories;
  final SuppliersDao _suppliers;
  final VatRatesDao _vatRates;
  final AuditService? _audit;
  final DateTime Function() _clock;

  ProductImportService({
    required CanteenDatabase db,
    required ProductService products,
    required ProductRepository productRepo,
    required CategoriesDao categories,
    required SuppliersDao suppliers,
    required VatRatesDao vatRates,
    required DateTime Function() clock,
    AuditService? audit,
  }) : _db = db,
       _products = products,
       _productRepo = productRepo,
       _categories = categories,
       _suppliers = suppliers,
       _vatRates = vatRates,
       _audit = audit,
       _clock = clock;

  /// docs/20 §5 — **hiçbir şey yazmaz.**
  Future<Result<ImportPreview>> preview({
    required String contents,
    required Map<int, ImportField> mapping,
    required DuplicateBarcodePolicy policy,
  }) async {
    if (policy == DuplicateBarcodePolicy.cancel) {
      return const Err(ImportFailures.cancelledByPolicy);
    }

    final parsed = CsvParser.parse(contents);
    if (parsed == null) return const Err(ImportFailures.fileUnreadable);
    if (parsed.rows.isEmpty) return const Err(ImportFailures.emptyFile);

    final missing = ProductImportRules.missingRequired(mapping);
    if (missing.isNotEmpty) {
      return const Err(ImportFailures.missingRequiredColumns);
    }

    // BR-IMEX-002 — dosya içi tekrarlar ÖNCE bulunur: bir satırın geçerliliği
    // dosyanın tamamına bağlıdır.
    final barcodesPerRow = [
      for (final row in parsed.rows)
        ProductImportRules.splitBarcodes(
          _cell(row, mapping, ImportField.barcode),
        ),
    ];
    final duplicatesInFile = ProductImportRules.findDuplicatesInFile(
      barcodesPerRow,
    );

    // Mevcut barkodlar tek seferde okunur; satır başına sorgu 1.000 satırda
    // 1.000 sorgu ederdi (rules/01 §8).
    final existing = <String, int>{};
    for (final barcode in barcodesPerRow.expand((row) => row).toSet()) {
      final found = await _productRepo.findByBarcode(barcode);
      if (found.isOk) existing[barcode] = found.valueOrNull!.id;
    }

    final knownVatRates = {
      for (final rate in await _vatRates.listAll()) rate.rateBasisPoints,
    };
    final existingCategories = {
      for (final category in await _categories.listAll())
        category.name.toLowerCase(),
    };
    final existingSuppliers = {
      for (final supplier in await _suppliers.listAll())
        supplier.name.toLowerCase(),
    };

    final rows = <ImportRow>[];
    final newCategories = <String>{};
    final newSuppliers = <String>{};

    for (var i = 0; i < parsed.rows.length; i++) {
      final raw = parsed.rows[i];
      final name = _cell(raw, mapping, ImportField.name);
      final rawSalePrice = _cell(raw, mapping, ImportField.salePrice);
      final rawPurchase = _cell(raw, mapping, ImportField.purchasePrice);
      final rawStock = _cell(raw, mapping, ImportField.initialStock);
      final rawVat = _cell(raw, mapping, ImportField.vatRate);
      final weightValue = _cell(raw, mapping, ImportField.netWeightValue);
      final weightUnit = _cell(raw, mapping, ImportField.netWeightUnit);
      final category = _cell(raw, mapping, ImportField.category);
      final supplier = _cell(raw, mapping, ImportField.supplier);
      final barcodes = barcodesPerRow[i];

      final salePrice = MoneyParser.tryParse(rawSalePrice);
      final purchasePrice = MoneyParser.tryParse(rawPurchase);
      final stock = _parseQuantity(rawStock);

      final issues = ProductImportRules.validate(
        name: name,
        rawSalePrice: rawSalePrice,
        salePriceMinor: salePrice?.minor,
        purchasePriceMinor: purchasePrice?.minor,
        rawPurchasePrice: rawPurchase,
        barcodes: barcodes,
        existingBarcodes: existing.keys.toSet(),
        duplicateInFile: duplicatesInFile,
        rawInitialStock: rawStock,
        initialStock: stock,
        netWeightValue: weightValue,
        netWeightUnit: weightUnit,
        vatRateKnown: _vatKnown(rawVat, knownVatRates),
        rawVatRate: rawVat,
        policy: policy,
      );

      final row = ImportRow(
        lineNumber: ParsedCsv.lineNumberOf(i),
        name: name.length > ProductImportRules.maxNameLength
            ? name.substring(0, ProductImportRules.maxNameLength)
            : name,
        salePrice: salePrice ?? Money.zero,
        // BR-PROD-002 — okunamayan alış fiyatı `0`'dır, asla `null`.
        purchasePrice: purchasePrice ?? Money.zero,
        category: category.isEmpty ? null : category,
        barcodes: barcodes,
        brand: _nullIfEmpty(_cell(raw, mapping, ImportField.brand)),
        supplier: supplier.isEmpty ? null : supplier,
        initialStock: stock ?? 0,
        minimumStock:
            _parseQuantity(_cell(raw, mapping, ImportField.minimumStock)) ?? 0,
        shelfLocation: _nullIfEmpty(
          _cell(raw, mapping, ImportField.shelfLocation),
        ),
        description: _nullIfEmpty(_cell(raw, mapping, ImportField.description)),
        // BR-PROD-011 — biri eksikse İKİSİ de boşaltılır.
        netWeightValue: weightValue.isNotEmpty && weightUnit.isNotEmpty
            ? _parseQuantity(weightValue)
            : null,
        netWeightUnit: weightValue.isNotEmpty && weightUnit.isNotEmpty
            ? weightUnit
            : null,
        issues: issues,
        updatesProductId: policy == DuplicateBarcodePolicy.updateExisting
            ? barcodes
                  .map((barcode) => existing[barcode])
                  .firstWhere((id) => id != null, orElse: () => null)
            : null,
      );
      rows.add(row);

      if (!row.isRejected) {
        if (category.isNotEmpty &&
            !existingCategories.contains(category.toLowerCase())) {
          newCategories.add(category);
        }
        if (supplier.isNotEmpty &&
            !existingSuppliers.contains(supplier.toLowerCase())) {
          newSuppliers.add(supplier);
        }
      }
    }

    return Ok(
      ImportPreview(
        rows: rows,
        separator: parsed.separator,
        newCategories: newCategories,
        newSuppliers: newSuppliers,
      ),
    );
  }

  /// docs/20 §6 — **tek transaction**, tam rollback.
  ///
  /// [confirmed] REQ-IMEX-007'nin kod karşılığıdır: çağıran, kullanıcının
  /// önizlemeyi onayladığını **açıkça** bildirmek zorundadır.
  Future<Result<ImportResult>> apply({
    required ImportPreview preview,
    required int userId,
    required bool confirmed,
  }) async {
    if (!confirmed) return const Err(ImportFailures.notConfirmed);
    if (!preview.hasAnything) {
      return const Err(ImportFailures.nothingToImport);
    }

    final now = _clock().toUtc();

    try {
      return Ok(
        await _db.transaction(() async {
          final categoryIds = <String, int>{};
          for (final category in await _categories.listAll()) {
            categoryIds[category.name.toLowerCase()] = category.id;
          }
          final supplierIds = <String, int>{};
          for (final supplier in await _suppliers.listAll()) {
            supplierIds[supplier.name.toLowerCase()] = supplier.id;
          }

          var createdCategories = 0;
          for (final name in preview.newCategories) {
            categoryIds[name.toLowerCase()] = await _categories.insertCategory(
              name: name,
              sortOrder: 0,
              now: now,
            );
            createdCategories++;
          }
          var createdSuppliers = 0;
          for (final name in preview.newSuppliers) {
            supplierIds[name.toLowerCase()] = await _suppliers.insertSupplier(
              name: name,
              now: now,
            );
            createdSuppliers++;
          }

          var created = 0;
          var updated = 0;
          for (final row in preview.accepted) {
            final draft = ProductDraft(
              name: row.name,
              salePrice: row.salePrice,
              purchasePrice: row.purchasePrice,
              categoryId: row.category == null
                  ? null
                  : categoryIds[row.category!.toLowerCase()],
              supplierId: row.supplier == null
                  ? null
                  : supplierIds[row.supplier!.toLowerCase()],
              brand: row.brand,
              minimumStock: row.minimumStock,
              shelfLocation: row.shelfLocation,
              description: row.description,
              netWeightValue: row.netWeightValue,
              netWeightUnit: row.netWeightUnit,
            );

            if (row.updatesProductId != null) {
              // docs/20 §4.1 — güncellemede **stok import edilmez**: stok
              // yalnızca hareketle değişir.
              final result = await _products.update(
                row.updatesProductId!,
                draft,
                userId: userId,
              );
              if (result.isErr) throw _Abort(result.failureOrNull!);
              updated++;
            } else {
              final result = await _products.create(
                draft,
                userId: userId,
                barcodes: row.barcodes,
                // REQ-IMEX-011 — stok DOĞRUDAN yazılmaz; `StockService`
                // üzerinden hareket oluşturur.
                initialStock: row.initialStock,
                creationPath: ProductCreationPath.import,
              );
              if (result.isErr) throw _Abort(result.failureOrNull!);
              created++;
            }
          }

          await _audit?.record(
            action: AuditActions.dataImported,
            entityType: AuditEntities.system,
            userId: userId,
            at: now,
            // docs/18 §3 — eklenen/güncellenen/atlanan satır sayıları.
            metadata: {
              'created': created,
              'updated': updated,
              'skipped': preview.rejectedCount,
              'new_categories': createdCategories,
              'new_suppliers': createdSuppliers,
            },
          );

          return ImportResult(
            created: created,
            updated: updated,
            skipped: preview.rejectedCount,
            newCategories: createdCategories,
            newSuppliers: createdSuppliers,
          );
        }),
      );
    } on _Abort catch (abort) {
      return Err(abort.failure);
    }
  }

  static String _cell(
    List<String> row,
    Map<int, ImportField> mapping,
    ImportField field,
  ) {
    for (final entry in mapping.entries) {
      if (entry.value != field) continue;
      // Eksik hücre boş sayılır: kısa satırlar dosyalarda olağandır.
      return entry.key < row.length ? row[entry.key].trim() : '';
    }
    return '';
  }

  /// BR-SALE-011 — miktar tam sayıdır; ondalık **yuvarlanır**.
  static int? _parseQuantity(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    final asInt = int.tryParse(text);
    if (asInt != null) return asInt;
    final asDouble = double.tryParse(text.replaceAll(',', '.'));
    return asDouble?.round();
  }

  /// KDV oranı yüzde olarak gelir (`20` → 2000 bp).
  static bool _vatKnown(String raw, Set<int> knownBasisPoints) {
    final text = raw.trim();
    if (text.isEmpty) return true;
    final percent = double.tryParse(text.replaceAll(',', '.'));
    if (percent == null) return false;
    return knownBasisPoints.contains((percent * 100).round());
  }

  static String? _nullIfEmpty(String value) =>
      value.trim().isEmpty ? null : value.trim();
}
