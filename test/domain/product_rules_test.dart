/// Ürün alan kuralları testleri — **docs/09 §1 · BR-PROD-011 · REQ-PROD-012**
library;

import 'package:canteen/core/money/money.dart';
import 'package:canteen/domain/services/product_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BR-PROD-011 · EC-PROD-018 — ağırlık çifti', () {
    test('ikisi de dolu → geçerli', () {
      expect(ProductRules.isWeightPairValid(150000, 'g'), isTrue);
    });

    test('ikisi de boş → geçerli', () {
      expect(ProductRules.isWeightPairValid(null, null), isTrue);
    });

    test('yalnızca değer → geçersiz', () {
      expect(ProductRules.isWeightPairValid(150000, null), isFalse);
    });

    test('yalnızca birim → geçersiz', () {
      expect(ProductRules.isWeightPairValid(null, 'g'), isFalse);
    });
  });

  group('REQ-PROD-012 — %50 fiyat değişikliği', () {
    test('değişiklik yoksa uyarı yok', () {
      expect(
        ProductRules.isSignificantPriceChange(
          const Money(2500),
          const Money(2500),
        ),
        isFalse,
      );
    });

    test('tam %50 sınırın altındadır — uyarı yok', () {
      expect(
        ProductRules.isSignificantPriceChange(
          const Money(2000),
          const Money(3000),
        ),
        isFalse,
      );
    });

    test('%50\'nin bir kuruş üstü uyarır', () {
      expect(
        ProductRules.isSignificantPriceChange(
          const Money(2000),
          const Money(3001),
        ),
        isTrue,
      );
    });

    test('kuruş/lira karışması yakalanır: ₺25 → ₺2.500', () {
      expect(
        ProductRules.isSignificantPriceChange(
          const Money(2500),
          const Money(250000),
        ),
        isTrue,
      );
    });

    test('düşüş yönü de uyarır', () {
      expect(
        ProductRules.isSignificantPriceChange(
          const Money(10000),
          const Money(1000),
        ),
        isTrue,
      );
    });

    test('EC-PROD-007 — ikram ürünü (0) fiyatlandırılırsa uyarır', () {
      expect(
        ProductRules.isSignificantPriceChange(Money.zero, const Money(500)),
        isTrue,
      );
      expect(
        ProductRules.isSignificantPriceChange(Money.zero, Money.zero),
        isFalse,
      );
    });
  });

  group('normalizeOptional', () {
    test('boş ve yalnızca boşluk → null', () {
      expect(ProductRules.normalizeOptional(''), isNull);
      expect(ProductRules.normalizeOptional('   '), isNull);
      expect(ProductRules.normalizeOptional(null), isNull);
    });

    test('baştaki/sondaki boşluk kırpılır', () {
      expect(ProductRules.normalizeOptional('  Raf A3 '), 'Raf A3');
    });
  });

  test('docs/09 §1 alan sınırları', () {
    expect(ProductRules.nameMaxLength, 120);
    expect(ProductRules.descriptionMaxLength, 500);
    expect(ProductRules.shelfLocationMaxLength, 50);
    expect(ProductRules.searchResultLimit, 50);
  });
}
