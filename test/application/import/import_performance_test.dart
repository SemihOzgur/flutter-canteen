/// İçe aktarma performansı — **docs/31 Faz 8 çıkış kriteri · REQ-IMEX-015**
///
/// > *"1.000 satırlık dosya < 10 sn"*
///
/// Veritabanı **dosya tabanlıdır**: in-memory SQLite üretimden hızlıdır ve
/// eşiği geçmesi hiçbir şey kanıtlamazdı — WAL + `synchronous=FULL` maliyeti
/// tam olarak burada görünür (rules/03 §1).
library;

import 'dart:io';

import 'package:canteen/application/audit/audit_service.dart';
import 'package:canteen/application/import/product_import_service.dart';
import 'package:canteen/application/product/product_service.dart';
import 'package:canteen/application/stock/stock_service.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide
        Cart,
        CartItem,
        Category,
        Product,
        Sale,
        SaleItem,
        StockMovement,
        Supplier;
import 'package:canteen/data/files/product_image_store.dart';
import 'package:canteen/data/repositories/drift_product_repository.dart';
import 'package:canteen/data/repositories/drift_stock_repository.dart';
import 'package:canteen/domain/services/product_import_rules.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/test_database.dart';

void main() {
  late Directory dir;
  late CanteenDatabase db;
  late TempAppPaths temp;
  late ProductImportService service;
  late int userId;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('canteen_import_perf_');
    db = fileDatabase(p.join(dir.path, 'canteen.sqlite'));
    temp = await TempAppPaths.create();
    final products = DriftProductRepository(db);
    final stock = DriftStockRepository(db);
    final audit = AuditService(
      auditLogs: AuditLogsDao(db),
      clock: () => testEpochUtc,
    );
    service = ProductImportService(
      db: db,
      products: ProductService(
        db: db,
        products: products,
        stock: stock,
        stockService: StockService(
          db: db,
          stock: stock,
          products: products,
          audit: audit,
          clock: () => testEpochUtc,
        ),
        categories: CategoriesDao(db),
        saleItems: SaleItemsDao(db),
        auditLogs: AuditLogsDao(db),
        appSettings: AppSettingsDao(db),
        images: ProductImageStore(paths: temp.paths),
        clock: () => testEpochUtc,
      ),
      productRepo: products,
      categories: CategoriesDao(db),
      suppliers: SuppliersDao(db),
      vatRates: VatRatesDao(db),
      audit: audit,
      clock: () => testEpochUtc,
    );
    userId = await insertTestUser(db);
  });

  tearDown(() async {
    await db.close();
    temp.dispose();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test(
    'docs/31 — 1.000 satırlık import < 10 sn',
    () async {
      const header =
          'Ürün adı;Satış fiyatı (KDV dahil);Alış fiyatı;'
          'Kategori;Barkod;Başlangıç stoğu;Tedarikçi';
      final buffer = StringBuffer(header);
      for (var i = 0; i < 1000; i++) {
        // Gerçekçi dosya: 20 kategori, 5 tedarikçi, her satırda barkod ve stok.
        buffer.write(
          '\nÜrün $i;${10 + i % 90},50;${5 + i % 40},00;'
          'Kategori ${i % 20};869${i.toString().padLeft(10, '0')};'
          '${i % 200};Tedarikçi ${i % 5}',
        );
      }

      final watch = Stopwatch()..start();
      final preview = await service.preview(
        contents: buffer.toString(),
        mapping: ProductImportRules.autoMap(header.split(';')),
        policy: DuplicateBarcodePolicy.skip,
      );
      final previewMs = watch.elapsedMilliseconds;
      expect(preview.isErr, isFalse, reason: '${preview.failureOrNull}');
      expect(preview.valueOrNull!.createCount, 1000);

      final result = await service.apply(
        preview: preview.valueOrNull!,
        userId: userId,
        confirmed: true,
      );
      watch.stop();
      expect(result.isErr, isFalse, reason: '${result.failureOrNull}');

      // ignore: avoid_print
      print(
        'Import 1.000 satır: önizleme $previewMs ms · '
        'toplam ${watch.elapsedMilliseconds} ms',
      );
      expect(result.valueOrNull!.created, 1000);
      expect(result.valueOrNull!.newCategories, 20);
      expect(result.valueOrNull!.newSuppliers, 5);
      expect(
        watch.elapsedMilliseconds,
        lessThan(10000),
        reason: 'docs/31 Faz 10 çıkış kriteri.',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
