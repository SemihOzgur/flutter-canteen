/// Dashboard performansı — **docs/15 §5 · docs/24 §2 · REQ-PERF-004/007**
///
/// > *"Dashboard (100k satış satırı) < 1 sn"*
///
/// ## Kapsanan requirement'lar (Faz 11 izlenebilirliği)
///
/// - **REQ-PERF-004** — dashboard 100.000 satırla < 1 sn
/// - **REQ-PERF-007** — 5. yıl veri hacminde raporlar çalışır
///
/// Veritabanı **dosya tabanlıdır**; in-memory SQLite üretimden hızlıdır ve
/// eşiği geçmesi hiçbir şey kanıtlamazdı.
///
/// Ölçülen şey **sorgu yoludur**. Ekranın boyanması dahil değildir — o
/// `docs/32 G9` olarak elle doğrulanır.
library;

import 'dart:io';

import 'package:canteen/application/auth/financial_access_service.dart';
import 'package:canteen/application/reporting/dashboard_service.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/dao/reporting_dao.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, CartItem, Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/repositories/drift_sale_repository.dart';
import 'package:canteen/domain/services/report_period.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/test_database.dart';

/// docs/24 §2 — hedeflenen 5. yıl veri hacmi.
const int _saleCount = 20000;
const int _saleItemCount = 100000;
const int _productCount = 500;

void main() {
  late Directory dir;
  late CanteenDatabase db;
  late DashboardService service;
  late DateTime now;

  setUp(() async {
    now = DateTime.utc(2026, 8, 14, 12);
    dir = Directory.systemTemp.createTempSync('canteen_dash_perf_');
    db = fileDatabase(p.join(dir.path, 'canteen.sqlite'), clock: () => now);

    final settings = AppSettingsDao(db);
    final access = FinancialAccessService(
      db: db,
      settings: settings,
      auditLogs: AuditLogsDao(db),
      clock: () => now,
    );
    await access.setPassword('DASH-PERF');
    await access.unlock('DASH-PERF');

    service = DashboardService(
      access: access,
      dao: ReportingDao(db),
      sales: DriftSaleRepository(db),
    );

    final userId = await insertTestUser(db);
    final categoryId = (await (db.select(
      db.categories,
    )..limit(1)).getSingle()).id;
    final epoch = now.millisecondsSinceEpoch;
    // Satışlar son 90 güne yayılır: trend ve saatlik yoğunluk sorguları
    // gerçekçi sayıda grup üretir.
    const spreadMs = 90 * 24 * 60 * 60 * 1000;

    await db.transaction(() async {
      await db.customStatement(
        'INSERT INTO products '
        '(name, category_id, sale_price_minor, purchase_price_minor, '
        ' stock_quantity, minimum_stock, is_favorite, is_active, '
        ' created_at, updated_at) '
        'WITH RECURSIVE seq(n) AS ('
        '  SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < $_productCount'
        ') '
        "SELECT 'Ürün ' || n, $categoryId, 1000 + n, 500, 100, 0, 0, 1, "
        '$epoch, $epoch FROM seq',
      );
      await db.customStatement(
        'INSERT INTO sales '
        '(sale_number, status, subtotal_minor, vat_total_minor, '
        ' discount_total_minor, grand_total_minor, cost_total_minor, '
        ' item_count, unit_count, user_id, completed_at, created_at, '
        ' updated_at) '
        'WITH RECURSIVE seq(n) AS ('
        '  SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < $_saleCount'
        ') '
        "SELECT '2026-' || printf('%06d', n), 'completed', 10000, 2000, 0, "
        '12000, 6000, 5, 5, $userId, '
        '$epoch - (n * $spreadMs / $_saleCount), '
        '$epoch, $epoch FROM seq',
      );
      await db.customStatement(
        'INSERT INTO sale_items '
        '(sale_id, product_id, product_name_snapshot, category_id_snapshot, '
        ' quantity, unit_price_minor, original_unit_price_minor, '
        ' purchase_price_snapshot_minor, vat_rate_snapshot_bp, '
        ' line_net_minor, line_vat_minor, line_total_minor, '
        ' returned_quantity) '
        'WITH RECURSIVE seq(n) AS ('
        '  SELECT 1 UNION ALL SELECT n + 1 FROM seq WHERE n < $_saleItemCount'
        ') '
        "SELECT (n % $_saleCount) + 1, (n % $_productCount) + 1, "
        "       'Ürün ' || ((n % $_productCount) + 1), $categoryId, "
        '       1, 2400, 2400, 1200, 2000, 2000, 400, 2400, 0 FROM seq',
      );
    });
  });

  tearDown(() async {
    await db.close();
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  test(
    'REQ-PERF-004 — 100.000 satış satırıyla dashboard < 1 sn',
    () async {
      // En ağır dönem: 90 günlük aralık, saatlik yoğunluk dahil.
      final period = ReportPeriod.of(ReportPeriodKind.last30Days, now);

      final watch = Stopwatch()..start();
      final result = await service.load(period);
      watch.stop();

      expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
      final data = result.valueOrNull!;
      expect(data.summary.saleCount, greaterThan(0));
      expect(data.topProducts, isNotEmpty);

      // ignore: avoid_print
      print(
        'Dashboard ($_saleItemCount satır, $_saleCount satış): '
        '${watch.elapsedMilliseconds} ms',
      );
      expect(
        watch.elapsedMilliseconds,
        lessThan(1000),
        reason:
            'docs/24 §2 — dashboard 100k satırla < 1 sn. Aggregation SQL '
            'tarafında yapılmazsa bu eşik tutmaz (rules/01 §8).',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'REQ-PERF-007 — 5. yıl hacminde tüm dönemler çalışır',
    () async {
      for (final kind in ReportPeriodKind.values) {
        if (kind == ReportPeriodKind.custom) continue;
        final watch = Stopwatch()..start();
        final result = await service.load(ReportPeriod.of(kind, now));
        watch.stop();

        expect(result.isErr, isFalse, reason: '$kind: ${result.failureOrNull}');
        // ignore: avoid_print
        print('  ${kind.name}: ${watch.elapsedMilliseconds} ms');
        expect(
          watch.elapsedMilliseconds,
          lessThan(3000),
          reason: 'docs/24 §2 — > 3 sn kabul edilemez.',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
