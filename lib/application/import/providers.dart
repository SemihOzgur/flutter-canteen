/// İçe aktarma servislerinin provider'ları (OD-002 — Riverpod).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/providers.dart';
import '../audit/providers.dart';
import '../product/providers.dart';
import 'data_export_service.dart';
import 'product_import_service.dart';

/// docs/20 — ürün içe aktarma. **Kilit dışındadır** (rules/04 §4): import bir
/// veri girişi işidir, finansal rapor değildir.
final productImportServiceProvider = Provider<ProductImportService>(
  (ref) => ProductImportService(
    db: ref.watch(canteenDatabaseProvider),
    products: ref.watch(productServiceProvider),
    productRepo: ref.watch(productRepositoryProvider),
    categories: ref.watch(categoriesDaoProvider),
    suppliers: ref.watch(suppliersDaoProvider),
    vatRates: ref.watch(vatRatesDaoProvider),
    audit: ref.watch(auditServiceProvider),
    clock: ref.watch(canteenDatabaseProvider).clock,
  ),
);

/// docs/20 §8 — ürün/kategori/tedarikçi dışa aktarma. **Kilit dışındadır**
/// (rules/04 §4): kullanıcı bu listeleri zaten ekranda görebiliyor.
final dataExportServiceProvider = Provider<DataExportService>(
  (ref) => DataExportService(
    products: ref.watch(productRepositoryProvider),
    categories: ref.watch(categoriesDaoProvider),
    suppliers: ref.watch(suppliersDaoProvider),
    audit: ref.watch(auditServiceProvider),
    clock: ref.watch(canteenDatabaseProvider).clock,
  ),
);
