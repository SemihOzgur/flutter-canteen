/// Sepet modeli testleri — **REQ-SALE-012 · BR-VAT-003 · EC-CART-002/004 ·
/// BR-STOCK-006**
///
/// Test önceliği rules/06 §2: **VAT** 🔴 — KDV'nin fiyatın *üzerine*
/// eklenmediğini doğrulayan açık test bu dosyadadır.
library;

import 'package:canteen/core/money/money.dart';
import 'package:canteen/domain/models/cart.dart';
import 'package:flutter_test/flutter_test.dart';

CartLine line({
  int id = 1,
  int productId = 1,
  int quantity = 1,
  int unitPriceMinor = 12000,
  int? listPriceMinor,
  bool isPriceOverridden = false,
  int vatRateBp = 2000,
  int stockQuantity = 10,
  bool isProductActive = true,
}) => CartLine(
  id: id,
  productId: productId,
  productName: 'Ürün $productId',
  quantity: quantity,
  unitPrice: Money(unitPriceMinor),
  listPrice: Money(listPriceMinor ?? unitPriceMinor),
  isPriceOverridden: isPriceOverridden,
  vatRateBp: vatRateBp,
  stockQuantity: stockQuantity,
  isProductActive: isProductActive,
);

Cart cartOf(List<CartLine> lines) => Cart(
  id: 1,
  userId: 1,
  lines: lines,
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  group('BR-VAT-003 — KDV fiyatın İÇİNDEN çıkarılır', () {
    test('rules/02 §2 doğrulanmış örneği: ₺120,00 @ %20', () {
      final cart = cartOf([line(unitPriceMinor: 12000, vatRateBp: 2000)]);

      expect(cart.totals.gross, const Money(12000));
      expect(cart.totals.vat, const Money(2000));
      expect(cart.totals.net, const Money(10000));
    });

    test('REGRESYON — KDV fiyatın ÜZERİNE eklenmez', () {
      // En kritik regresyon riski (rules/06 §2). Üzerine eklenseydi toplam
      // 14400 olurdu; müşteri ₺120,00 öder, ₺144,00 değil.
      final cart = cartOf([line(unitPriceMinor: 12000, vatRateBp: 2000)]);

      expect(cart.totals.gross, const Money(12000));
      expect(
        cart.totals.gross.minor,
        isNot(14400),
        reason: 'BR-VAT-003: satış fiyatı KDV DAHİLDİR.',
      );
    });

    test('EC-SALE-017 — %0 oranda KDV yok, matrah brüte eşit', () {
      final cart = cartOf([line(unitPriceMinor: 12000, vatRateBp: 0)]);

      expect(cart.totals.vat, Money.zero);
      expect(cart.totals.net, const Money(12000));
    });

    test('farklı oranlı satırlar ayrı ayrı çıkarılır', () {
      final cart = cartOf([
        line(id: 1, productId: 1, unitPriceMinor: 12000, vatRateBp: 2000),
        line(id: 2, productId: 2, unitPriceMinor: 11000, vatRateBp: 1000),
      ]);

      // 12000 @ %20 → KDV 2000 · 11000 @ %10 → KDV 1000
      expect(cart.totals.gross, const Money(23000));
      expect(cart.totals.vat, const Money(3000));
      expect(cart.totals.net, const Money(20000));
    });
  });

  group('REQ-SALE-012 — sepet toplamı = girilen fiyatların toplamı', () {
    test('brüt toplam satır tutarlarının toplamıdır', () {
      final lines = [
        line(id: 1, productId: 1, quantity: 2, unitPriceMinor: 2500),
        line(id: 2, productId: 2, quantity: 1, unitPriceMinor: 4500),
        line(id: 3, productId: 3, quantity: 3, unitPriceMinor: 1000),
      ];
      final cart = cartOf(lines);

      expect(cart.totals.gross, Money.sum(lines.map((l) => l.lineTotal)));
      expect(cart.totals.gross, const Money(2500 * 2 + 4500 + 1000 * 3));
    });

    test('invariant: matrah + KDV == genel toplam', () {
      // rules/02 §2 — kullanıcı fişteki satırları elle toplayınca tutmalıdır.
      final cart = cartOf([
        line(id: 1, productId: 1, quantity: 3, unitPriceMinor: 3333),
        line(id: 2, productId: 2, quantity: 7, unitPriceMinor: 1777),
        line(
          id: 3,
          productId: 3,
          quantity: 1,
          unitPriceMinor: 99,
          vatRateBp: 1,
        ),
      ]);

      expect(cart.totals.net + cart.totals.vat, cart.totals.gross);
    });

    test('boş sepetin toplamı sıfırdır', () {
      final cart = cartOf([]);

      expect(cart.isEmpty, isTrue);
      expect(cart.totals.gross, Money.zero);
      expect(cart.totals.vat, Money.zero);
    });
  });

  group('sayımlar — sales.item_count / unit_count', () {
    test('itemCount satır, unitCount adet sayar', () {
      final cart = cartOf([
        line(id: 1, productId: 1, quantity: 2),
        line(id: 2, productId: 2, quantity: 5),
      ]);

      expect(cart.itemCount, 2);
      expect(cart.unitCount, 7);
    });
  });

  group('EC-CART-002 — fiyat rozeti', () {
    test('ürünün fiyatı değişmişse satır BAYAT işaretlenir', () {
      final stale = line(unitPriceMinor: 2500, listPriceMinor: 3000);

      expect(stale.isPriceStale, isTrue);
      expect(
        stale.unitPrice,
        const Money(2500),
        reason: 'REQ-CART-007: sepetteki fiyat KORUNUR.',
      );
    });

    test('kullanıcının değiştirdiği fiyat bayat SAYILMAZ', () {
      // docs/12 §4 — bilinçli bir tercihtir; "fiyat güncellendi" rozeti
      // göstermek kullanıcıya yanlış bilgi verirdi.
      final overridden = line(
        unitPriceMinor: 2000,
        listPriceMinor: 2500,
        isPriceOverridden: true,
      );

      expect(overridden.isPriceStale, isFalse);
    });

    test('fiyat aynıysa rozet yok', () {
      expect(
        line(unitPriceMinor: 2500, listPriceMinor: 2500).isPriceStale,
        isFalse,
      );
    });
  });

  group('BR-STOCK-006 — negatif stok işaretlenir, engellenmez', () {
    test('stok 0 ve altı tükenmiş sayılır', () {
      expect(line(stockQuantity: 0).isOutOfStock, isTrue);
      expect(line(stockQuantity: -3).isOutOfStock, isTrue);
      expect(line(stockQuantity: 1).isOutOfStock, isFalse);
    });

    test('tükenmiş satırlar ayrıca listelenir ama sepette KALIR', () {
      final cart = cartOf([
        line(id: 1, productId: 1, stockQuantity: 5),
        line(id: 2, productId: 2, stockQuantity: 0),
        line(id: 3, productId: 3, stockQuantity: -2),
      ]);

      expect(cart.outOfStockLines.map((l) => l.id), [2, 3]);
      expect(
        cart.lines,
        hasLength(3),
        reason: 'BR-STOCK-006: satış engellenmez, yalnızca uyarılır.',
      );
    });
  });

  test('BR-SALE-011 — sıfır miktarlı satır hesaplanamaz', () {
    // Şema `CHECK(quantity > 0)` uygular; domain de aynı invariant'ı korur.
    expect(() => line(quantity: 0).breakdown, throwsArgumentError);
  });
}
