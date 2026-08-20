/// Ürün stok durumu — **docs/13 §7 · REQ-STOCK-011 · BR-STOCK-007**
///
/// Kritik stok koşulu üç yerde gösterilir (ürün listesi rozeti, satır ikonu,
/// stok ekranı). Kopyalandığında biri `<` diğeri `<=` olur ve fark **yalnızca
/// eşikteki üründe** görünür — yani en kolay gözden kaçan yerde. Kural bu
/// yüzden domain'de tek yerde yaşar ve sınırları burada sınanır.
/// ## Kapsanan uç durumlar (docs/26 · Faz 11 izlenebilirliği)
///
/// - **EC-PROD-011** — `minimum_stock = 0` kritik uyarısına girmez
///
library;

import 'package:canteen/core/money/money.dart';
import 'package:canteen/domain/models/product.dart';
import 'package:flutter_test/flutter_test.dart';

Product product({int stockQuantity = 0, int minimumStock = 0}) => Product(
  id: 1,
  name: 'Kola',
  description: null,
  categoryId: 1,
  brand: null,
  salesUnit: null,
  netWeightValue: null,
  netWeightUnit: null,
  purchasePrice: const Money(1000),
  salePrice: const Money(2500),
  vatRateId: null,
  stockQuantity: stockQuantity,
  minimumStock: minimumStock,
  supplierId: null,
  shelfLocation: null,
  imagePath: null,
  isFavorite: false,
  isActive: true,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  group('docs/13 §7 — kritik stok', () {
    test('SINIR: stok minimuma EŞİTKEN kritiktir', () {
      expect(
        product(stockQuantity: 5, minimumStock: 5).isCriticalStock,
        isTrue,
        reason: 'Koşul `<=`; eşiğin kendisi zaten kritiktir.',
      );
    });

    test('SINIR: minimumun bir üstü kritik DEĞİLDİR', () {
      expect(
        product(stockQuantity: 6, minimumStock: 5).isCriticalStock,
        isFalse,
      );
    });

    test('minimumun altı kritiktir', () {
      expect(
        product(stockQuantity: 1, minimumStock: 5).isCriticalStock,
        isTrue,
      );
    });

    test('REQ-STOCK-011 — minimum 0 ise ASLA kritik değildir', () {
      for (final stock in [0, -3, 100]) {
        expect(
          product(stockQuantity: stock, minimumStock: 0).isCriticalStock,
          isFalse,
          reason: 'Kullanıcı o ürün için takip istemiyor demektir.',
        );
      }
    });

    test('negatif stok, minimum takipliyse kritiktir de', () {
      final negative = product(stockQuantity: -2, minimumStock: 5);
      expect(negative.isCriticalStock, isTrue);
      expect(negative.isNegativeStock, isTrue);
    });
  });

  group('BR-STOCK-007 — negatif stok', () {
    test('SINIR: 0 negatif DEĞİLDİR', () {
      expect(product(stockQuantity: 0).isNegativeStock, isFalse);
    });

    test('SINIR: −1 negatiftir', () {
      expect(product(stockQuantity: -1).isNegativeStock, isTrue);
    });
  });
}
