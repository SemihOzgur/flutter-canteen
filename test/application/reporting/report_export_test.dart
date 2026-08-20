/// Rapor dışa aktarma — **docs/16 §2 · REQ-IMEX-014 · REQ-SEC-005 ·
/// BR-AUTH-012 · docs/18 §3**
///
/// En kritik iddia: **dışa aktarma kilidin etrafından dolaşamaz.** "Dışa
/// aktar" düğmesi, ekranda gizlenmiş bir raporu dosyaya yazmanın yolu
/// olmamalıdır.
library;

import 'package:canteen/application/audit/audit_actions.dart';
import 'package:canteen/application/audit/audit_service.dart';
import 'package:canteen/application/auth/financial_access_service.dart';
import 'package:canteen/application/reporting/dashboard_service.dart';
import 'package:canteen/application/reporting/report_export_service.dart';
import 'package:canteen/application/sales/cart_service.dart';
import 'package:canteen/application/sales/sale_service.dart';
import 'package:canteen/application/stock/stock_service.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/dao/reporting_dao.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, CartItem, Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/files/csv_writer.dart';
import 'package:canteen/data/repositories/drift_product_repository.dart';
import 'package:canteen/data/repositories/drift_sale_repository.dart';
import 'package:canteen/data/repositories/drift_stock_repository.dart';
import 'package:canteen/domain/services/report_period.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late DateTime now;
  late FinancialAccessService access;
  late ReportExportService service;
  late CartService cartService;
  late SaleService saleService;
  late int userId;

  const dashboardPassword = 'DASH-EXPORT-7K3';

  setUp(() async {
    now = DateTime.utc(2026, 8, 14, 12);
    db = memoryDatabase(clock: () => now);
    final settings = AppSettingsDao(db);
    access = FinancialAccessService(
      db: db,
      settings: settings,
      auditLogs: AuditLogsDao(db),
      clock: () => now,
    );
    final products = DriftProductRepository(db);
    final audit = AuditService(auditLogs: AuditLogsDao(db), clock: () => now);
    final dashboard = DashboardService(
      access: access,
      dao: ReportingDao(db),
      sales: DriftSaleRepository(db),
    );
    service = ReportExportService(
      dashboard: dashboard,
      audit: audit,
      clock: () => now,
    );
    cartService = CartService(
      db: db,
      carts: CartsDao(db),
      cartItems: CartItemsDao(db),
      vatRates: VatRatesDao(db),
      products: products,
      clock: () => now,
    );
    saleService = SaleService(
      db: db,
      cartService: cartService,
      carts: CartsDao(db),
      vatRates: VatRatesDao(db),
      appSettings: settings,
      auditLogs: AuditLogsDao(db),
      products: products,
      sales: DriftSaleRepository(db),
      stockService: StockService(
        db: db,
        stock: DriftStockRepository(db),
        products: products,
        audit: audit,
        clock: () => now,
      ),
      clock: () => now,
    );
    userId = await insertTestUser(db);
  });

  tearDown(() => db.close());

  Future<void> unlock() async {
    await access.setPassword(dashboardPassword);
    await access.unlock(dashboardPassword);
  }

  Future<int> product({String name = 'Kola', int salePriceMinor = 2500}) async {
    final id = await insertTestProduct(
      db,
      name: name,
      salePriceMinor: salePriceMinor,
    );
    await (db.update(db.products)..where((p) => p.id.equals(id))).write(
      const ProductsCompanion(stockQuantity: Value(100)),
    );
    return id;
  }

  Future<void> sell(int productId, {int quantity = 1}) async {
    final cart = await cartService.ensureActive(userId);
    await cartService.addProduct(
      cartId: cart.id,
      productId: productId,
      quantity: quantity,
    );
    await saleService.complete(cartId: cart.id, userId: userId);
  }

  ReportPeriod today() => ReportPeriod.of(ReportPeriodKind.today, now);

  Future<List<AuditLog>> logs() => AuditLogsDao(db).listRecent();

  group('BR-AUTH-012 — kilit dışa aktarmayı da kapsar', () {
    test('kilit kapalıyken dışa aktarma REDDEDİLİR', () async {
      await sell(await product());

      final result = await service.exportCsv(
        report: ExportableReport.productSales,
        period: today(),
      );

      expect(result.isErr, isTrue);
    });

    test('kilit kapalıyken audit kaydı BİLE yazılmaz', () async {
      await sell(await product());

      await service.exportCsv(
        report: ExportableReport.productSales,
        period: today(),
      );

      expect(
        (await logs()).where((l) => l.action == AuditActions.dataExported),
        isEmpty,
        reason:
            '"Dışa aktarıldı" kaydı, aktarılmamış bir rapor için '
            'yazılmamalıdır.',
      );
    });

    test('kilit açıkken çalışır', () async {
      await sell(await product());
      await unlock();

      final result = await service.exportCsv(
        report: ExportableReport.productSales,
        period: today(),
      );

      expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
    });
  });

  group('rules/03 §7 — CSV biçimi', () {
    test('BOM ile başlar ve `;` ile ayrılır', () async {
      await sell(await product(name: 'Kola'));
      await unlock();

      final csv = (await service.exportCsv(
        report: ExportableReport.productSales,
        period: today(),
      )).valueOrNull!;

      expect(csv.codeUnitAt(0), 0xFEFF);
      expect(csv, contains('Ürün;Adet;'));
    });

    test('başlık satırı ve veri satırları', () async {
      final id = await product(name: 'Kola', salePriceMinor: 2500);
      await sell(id, quantity: 3);
      await unlock();

      final csv = (await service.exportCsv(
        report: ExportableReport.productSales,
        period: today(),
      )).valueOrNull!;
      final lines = csv.trim().split('\r\n');

      expect(lines, hasLength(2));
      expect(lines.first, contains('Ürün'));
      expect(lines.last, contains('Kola'));
      expect(lines.last, contains('3'));
    });

    test('REQ-SEC-005 — ürün adındaki formül KAÇIŞLANIR', () async {
      // Ürün adı KULLANICI GİRDİSİDİR; rapor onu başka bir makineye taşır.
      final id = await product(name: "=cmd|'/c calc'!A1");
      await sell(id);
      await unlock();

      final csv = (await service.exportCsv(
        report: ExportableReport.productSales,
        period: today(),
      )).valueOrNull!;

      expect(csv, contains("'=cmd"));
      expect(
        csv.split('\r\n').any((line) => line.startsWith('=')),
        isFalse,
        reason: 'Hiçbir hücre formül önekiyle BAŞLAMAMALIDIR.',
      );
    });

    test('kategori raporu da üretilir', () async {
      await sell(await product());
      await unlock();

      final csv = (await service.exportCsv(
        report: ExportableReport.categorySales,
        period: today(),
      )).valueOrNull!;

      expect(csv, contains('Kategori;Adet;'));
    });

    test('veri yokken yalnızca başlık satırı döner', () async {
      await unlock();

      final csv = (await service.exportCsv(
        report: ExportableReport.productSales,
        period: today(),
      )).valueOrNull!;

      expect(csv.trim().split('\r\n'), hasLength(1));
    });
  });

  group('docs/18 §3 — dataExported', () {
    test('rapor türü, aralık ve satır sayısı yazılır', () async {
      final id = await product();
      await sell(id, quantity: 2);
      await unlock();

      await service.exportCsv(
        report: ExportableReport.productSales,
        period: today(),
      );

      final log = (await logs()).firstWhere(
        (l) => l.action == AuditActions.dataExported,
      );
      expect(log.entityType, AuditEntities.system);
      expect(log.metadata, contains('productSales'));
      expect(
        log.metadata,
        contains('"row_count":1'),
        reason: 'Başlık satırı sayılmaz.',
      );
    });
  });

  test('docs/16 §2 — dışa aktarma SAYFAYLA sınırlı değildir', () async {
    // Ekran 50 satır gösterir; dışa aktarma filtrelenmiş TÜM sonucu kapsar.
    for (var i = 0; i < 60; i++) {
      await sell(await product(name: 'Ürün $i'));
    }
    await unlock();

    final csv = (await service.exportCsv(
      report: ExportableReport.productSales,
      period: today(),
    )).valueOrNull!;

    expect(csv.trim().split('\r\n'), hasLength(61));
  });

  test('CsvWriter ayırıcısı ile rapor çıktısı AYNI', () {
    // İkisi ayrışırsa Türkçe Excel tek sütun açar ve kimse fark etmez.
    expect(CsvWriter.separator, ';');
  });
}
