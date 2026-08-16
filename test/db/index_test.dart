/// Index testleri — **REQ-DB-006**
///
/// docs/05 §3: "🔴 kritik index'lerin tamamı ilk sürümde mevcuttur."
///
/// Bu dosya index'in **var olduğunu** doğrulamakla yetinmez; kritik sorguların
/// `EXPLAIN QUERY PLAN` çıktısında o index'i **gerçekten kullandığını** kanıtlar.
/// Var olan ama kullanılmayan bir index performans hedefini karşılamaz.
library;

import 'package:canteen/data/db/canteen_database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  late CanteenDatabase db;

  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  /// docs/05 §3 — 17 index.
  const documentedIndexes = <String>[
    'ux_barcode',
    'ix_barcode_product',
    'ix_products_active_name',
    'ix_products_category',
    'ix_products_supplier',
    'ix_products_favorite',
    'ix_products_lowstock',
    'ix_sales_completed_at',
    'ix_sales_status_date',
    'ix_sale_items_sale',
    'ix_sale_items_product',
    'ix_movements_product_date',
    'ix_movements_date',
    'ix_movements_reference',
    'ix_audit_date',
    'ix_audit_entity',
    'ux_carts_active',
  ];

  /// docs/05 §3'te 🔴 Kritik işaretli olanlar.
  const criticalIndexes = <String>[
    'ux_barcode',
    'ix_products_active_name',
    'ix_sales_completed_at',
    'ix_sale_items_sale',
    'ix_sale_items_product',
    'ix_movements_product_date',
    'ux_carts_active',
  ];

  test('docs/05 §3\'teki 17 index\'in tamamı mevcut', () async {
    final actual = await indexNames(db);
    for (final index in documentedIndexes) {
      expect(actual, contains(index), reason: 'Eksik index: $index');
    }
  });

  test('🔴 kritik index\'ler mevcut — REQ-DB-006', () async {
    final actual = await indexNames(db);
    expect(actual, containsAll(criticalIndexes));
  });

  group('EXPLAIN QUERY PLAN — index GERÇEKTEN kullanılıyor', () {
    test('barkod lookup → ux_barcode (satış hızının tamamı)', () async {
      final plan = await queryPlan(
        db,
        "SELECT * FROM product_barcodes WHERE barcode = '8690000000001'",
      );
      expect(
        plan,
        contains('ux_barcode'),
        reason: 'Barkod araması index kullanmıyor — satış hedefi tutmaz.',
      );
    });

    test('aktif ürün listeleme → ix_products_active_name', () async {
      final plan = await queryPlan(
        db,
        'SELECT * FROM products WHERE is_active = 1 ORDER BY name',
      );
      expect(plan, contains('ix_products_active_name'));
    });

    test('tarih aralıklı satış raporu → ix_sales_completed_at', () async {
      final plan = await queryPlan(
        db,
        'SELECT * FROM sales WHERE completed_at >= 100 AND completed_at < 200',
      );
      expect(
        plan,
        anyOf(
          contains('ix_sales_completed_at'),
          contains('ix_sales_status_date'),
        ),
        reason: 'Tüm dashboard/rapor sorguları bu index\'e bağlı.',
      );
    });

    test('satış detayı → ix_sale_items_sale', () async {
      final plan = await queryPlan(
        db,
        'SELECT * FROM sale_items WHERE sale_id = 1',
      );
      expect(plan, contains('ix_sale_items_sale'));
    });

    test('ürün bazlı satış raporu → ix_sale_items_product', () async {
      final plan = await queryPlan(
        db,
        'SELECT * FROM sale_items WHERE product_id = 1',
      );
      expect(plan, contains('ix_sale_items_product'));
    });

    test('ürün stok geçmişi → ix_movements_product_date', () async {
      final plan = await queryPlan(
        db,
        'SELECT * FROM stock_movements WHERE product_id = 1 '
        'ORDER BY created_at DESC',
      );
      expect(plan, contains('ix_movements_product_date'));
    });

    test('aktif sepet arama → ux_carts_active', () async {
      final plan = await queryPlan(
        db,
        "SELECT * FROM carts WHERE status = 'active'",
      );
      expect(plan, contains('ux_carts_active'));
    });

    test('satışa bağlı stok hareketleri → ix_movements_reference', () async {
      final plan = await queryPlan(
        db,
        "SELECT * FROM stock_movements WHERE reference_type = 'sale' "
        'AND reference_id = 1',
      );
      expect(plan, contains('ix_movements_reference'));
    });

    test('kategori bazlı listeleme → ix_products_category', () async {
      final plan = await queryPlan(
        db,
        'SELECT * FROM products WHERE category_id = 1 AND is_active = 1',
      );
      expect(plan, contains('ix_products_category'));
    });

    test('favoriler → kısmi index ix_products_favorite', () async {
      final plan = await queryPlan(
        db,
        'SELECT * FROM products WHERE is_favorite = 1',
      );
      expect(plan, contains('ix_products_favorite'));
    });

    test('audit entity geçmişi → ix_audit_entity', () async {
      final plan = await queryPlan(
        db,
        "SELECT * FROM audit_logs WHERE entity_type = 'product' AND entity_id = 1",
      );
      expect(plan, contains('ix_audit_entity'));
    });
  });

  test('ux_carts_active KISMİ index\'tir (WHERE içerir)', () async {
    final row = await db
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE name = 'ux_carts_active';",
        )
        .getSingle();

    final sql = (row.data['sql'] as String).toLowerCase();
    expect(sql, contains('unique'));
    expect(
      sql,
      contains('where'),
      reason: 'Kısmi olmayan unique index tüm sepetleri tekilleştirirdi.',
    );
    expect(sql, contains("status = 'active'"));
  });
}
