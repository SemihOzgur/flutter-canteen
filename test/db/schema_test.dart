/// Şema testleri — docs/05-database-architecture.md §2
///
/// REQ-DB-002 (para tam sayı) · REQ-DB-003 (zaman INTEGER) ·
/// REQ-DB-010 (düz metin parola yok) · REQ-DB-011 (ağırlık çifti)
///
/// Bu dosya şemayı **dokümana karşı** doğrular; "kod çalıştı" testi değildir.
library;

import 'package:canteen/data/db/canteen_database.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  late CanteenDatabase db;

  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  /// docs/05 §2 — "Toplam 15 tablo".
  const expectedTables = <String>[
    'app_settings',
    'audit_logs',
    'cart_items',
    'carts',
    'categories',
    'product_barcodes',
    'products',
    'return_items',
    'returns',
    'sale_items',
    'sales',
    'stock_movements',
    'suppliers',
    'users',
    'vat_rates',
  ];

  group('15 tablo — docs/05 §2', () {
    test('tam olarak 15 tablo oluşur, adları dokümanla birebir', () async {
      final names = await tableNames(db);

      expect(names.length, 15, reason: 'Şema FİNAL: 15 tablo olmalıdır.');
      expect(names, expectedTables);
    });
  });

  group('kolon adları ve tipleri — docs/05 §2', () {
    test('users — REQ-DB-010: düz metin parola alanı YOK', () async {
      final columns = await tableColumns(db, 'users');

      expect(
        columns.keys,
        containsAll(<String>['password_hash', 'password_salt']),
      );

      // Yasak alan adları — BR-SEC-001.
      const forbidden = <String>[
        'password',
        'plain_password',
        'password_plain',
        'recovery_code',
        'pin',
        'secret',
      ];
      for (final name in forbidden) {
        expect(
          columns.containsKey(name),
          isFalse,
          reason: 'BR-SEC-001 İHLALİ: users.$name düz metin sır alanı!',
        );
      }
    });

    test('hiçbir tabloda düz metin sır kolonu yok — REQ-DB-010', () async {
      for (final table in expectedTables) {
        final columns = await tableColumns(db, table);
        for (final column in columns.keys) {
          final isHashed = column.endsWith('_hash') || column.endsWith('_salt');
          final looksSecret =
              column == 'password' ||
              column == 'recovery_code' ||
              column.contains('plain');
          expect(
            looksSecret && !isHashed,
            isFalse,
            reason: 'REQ-DB-010 İHLALİ: $table.$column',
          );
        }
      }
    });

    test('products — docs/05 §2.5 kolonları eksiksiz', () async {
      final columns = await tableColumns(db, 'products');

      expect(columns.keys, <String>[
        'id',
        'name',
        'description',
        'category_id',
        'brand',
        'sales_unit',
        'net_weight_value',
        'net_weight_unit',
        'purchase_price_minor',
        'sale_price_minor',
        'vat_rate_id',
        'stock_quantity',
        'minimum_stock',
        'supplier_id',
        'shelf_location',
        'image_path',
        'is_favorite',
        'is_active',
        'created_at',
        'updated_at',
      ]);
    });

    test('sale_items — BR-SALE-001 beş snapshot alanı mevcut', () async {
      final columns = await tableColumns(db, 'sale_items');

      // rules/02 §3 — beş snapshot alanı.
      expect(
        columns.keys,
        containsAll(<String>[
          'product_name_snapshot',
          'unit_price_minor',
          'purchase_price_snapshot_minor',
          'vat_rate_snapshot_bp',
          'category_id_snapshot',
        ]),
      );
      // Ek snapshot alanları.
      expect(
        columns.keys,
        containsAll(<String>['original_unit_price_minor', 'barcode_snapshot']),
      );
    });

    test('sales — docs/05 §2.8 kolonları eksiksiz', () async {
      final columns = await tableColumns(db, 'sales');
      expect(
        columns.keys,
        containsAll(<String>[
          'sale_number',
          'status',
          'subtotal_minor',
          'vat_total_minor',
          'discount_total_minor',
          'grand_total_minor',
          'cost_total_minor',
          'cash_received_minor',
          'change_minor',
          'item_count',
          'unit_count',
          'completed_at',
          'cancelled_at',
        ]),
      );
    });

    test('stock_movements — docs/05 §2.10 kolonları eksiksiz', () async {
      final columns = await tableColumns(db, 'stock_movements');
      expect(columns.keys, <String>[
        'id',
        'product_id',
        'type',
        'quantity_delta',
        'resulting_stock',
        'unit_cost_minor',
        'reference_type',
        'reference_id',
        'supplier_id',
        'note',
        'user_id',
        'created_at',
      ]);
    });

    test('app_settings — key TEXT PRIMARY KEY', () async {
      final columns = await tableColumns(db, 'app_settings');
      expect(columns, {
        'key': 'TEXT',
        'value': 'TEXT',
        'updated_at': 'INTEGER',
      });
    });
  });

  group('enum kolonları TEXT olarak saklanır', () {
    test(
      'carts.status · sales.status · returns.type · movements.type',
      () async {
        expect((await tableColumns(db, 'carts'))['status'], 'TEXT');
        expect((await tableColumns(db, 'sales'))['status'], 'TEXT');
        expect((await tableColumns(db, 'returns'))['type'], 'TEXT');
        expect((await tableColumns(db, 'stock_movements'))['type'], 'TEXT');
        expect(
          (await tableColumns(db, 'stock_movements'))['reference_type'],
          'TEXT',
          reason:
              'Drift varsayılanı INTEGER index olurdu — docs/05 TEXT diyor.',
        );
      },
    );
  });

  test('şema versiyonu 1 — docs/06 §1', () async {
    final row = await db.customSelect('PRAGMA user_version;').getSingle();
    expect(row.data['user_version'], 1);
  });
}
