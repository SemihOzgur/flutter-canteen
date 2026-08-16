/// PARA REGRESYON KORUMASI — **REQ-DB-002 · BR-FIN-001**
///
/// rules/02 §1: "Floating point ile para hesabı YASAKTIR."
///
/// Bu dosyanın tek amacı, ileride birinin bir parasal kolonu `RealColumn`
/// yapmasını **derhal yakalamaktır.** Şemaya sızan tek bir REAL kolon, sessiz
/// kuruş kayıplarına yol açar.
library;

import 'package:canteen/core/money/money.dart';
import 'package:canteen/data/db/canteen_database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  late CanteenDatabase db;

  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  const allTables = <String>[
    'users',
    'categories',
    'suppliers',
    'vat_rates',
    'products',
    'product_barcodes',
    'carts',
    'cart_items',
    'sales',
    'sale_items',
    'returns',
    'return_items',
    'stock_movements',
    'audit_logs',
    'app_settings',
  ];

  test('HİÇBİR tabloda REAL/FLOAT/DOUBLE kolon yok', () async {
    final offenders = <String>[];

    for (final table in allTables) {
      final columns = await tableColumns(db, table);
      columns.forEach((name, type) {
        if (type.contains('REAL') ||
            type.contains('FLOAT') ||
            type.contains('DOUBLE') ||
            type.contains('NUMERIC') ||
            type.contains('DECIMAL')) {
          offenders.add('$table.$name ($type)');
        }
      });
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'BR-FIN-001 İHLALİ: ondalık kolon bulundu → ${offenders.join(", ")}',
    );
  });

  test('tüm *_minor kolonları INTEGER', () async {
    final minorColumns = <String>[];

    for (final table in allTables) {
      final columns = await tableColumns(db, table);
      columns.forEach((name, type) {
        if (name.endsWith('_minor')) {
          minorColumns.add('$table.$name');
          expect(
            type,
            'INTEGER',
            reason: 'BR-FIN-001 İHLALİ: $table.$name tipi $type',
          );
        }
      });
    }

    // Beklenen parasal alan sayısı — yeni bir para alanı eklenirse bu test
    // güncellenmeli ve bilinçli olarak gözden geçirilmelidir.
    //   products 2 · cart_items 1 · sales 7 · sale_items 6 · returns 1 ·
    //   return_items 2 · stock_movements 1  = 20
    expect(
      minorColumns.length,
      20,
      reason: 'Parasal alan sayısı değişti: ${minorColumns.join(", ")}',
    );
  });

  test('basis point oranı INTEGER (BR-FIN-002)', () async {
    expect(
      (await tableColumns(db, 'vat_rates'))['rate_basis_points'],
      'INTEGER',
    );
    expect(
      (await tableColumns(db, 'sale_items'))['vat_rate_snapshot_bp'],
      'INTEGER',
    );
  });

  test('miktar kolonları INTEGER (BR-SALE-011)', () async {
    expect((await tableColumns(db, 'cart_items'))['quantity'], 'INTEGER');
    expect((await tableColumns(db, 'sale_items'))['quantity'], 'INTEGER');
    expect((await tableColumns(db, 'return_items'))['quantity'], 'INTEGER');
    expect(
      (await tableColumns(db, 'stock_movements'))['quantity_delta'],
      'INTEGER',
    );
  });

  test('Money değeri kuruş olarak kayıpsız gidip gelir', () async {
    // ₺1.234.567,89 — büyük tutarda da kuruş kaybı olmamalı.
    const price = Money(123456789);
    final id = await insertTestProduct(
      db,
      name: 'Pahalı',
      salePriceMinor: price.minor,
      purchasePriceMinor: 1,
    );

    final row = await (db.select(
      db.products,
    )..where((p) => p.id.equals(id))).getSingle();

    expect(Money(row.salePriceMinor), price);
    expect(row.salePriceMinor, 123456789);
    expect(row.purchasePriceMinor, 1, reason: '1 kuruş kaybolmamalı');
  });

  test('negatif stok saklanabilir (BR-STOCK-006)', () async {
    final id = await insertTestProduct(db);
    await (db.update(db.products)..where((p) => p.id.equals(id))).write(
      const ProductsCompanion(stockQuantity: Value(-3)),
    );

    final row = await (db.select(
      db.products,
    )..where((p) => p.id.equals(id))).getSingle();

    expect(
      row.stockQuantity,
      -3,
      reason: 'BR-STOCK-006: negatif stok geçerli bir durumdur.',
    );
  });
}
