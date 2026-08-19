/// Satış numarası testleri — **docs/12 §6.4 · REQ-SALE-005 · EC-SALE-011**
library;

import 'package:canteen/domain/services/sale_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('biçim — YYYY-NNNNNN', () {
    test('docs/12 §6.4 örneği birebir üretilir', () {
      expect(SaleNumber.format(year: 2026, sequence: 148), '2026-000148');
    });

    test('ilk satış 000001', () {
      expect(SaleNumber.format(year: 2026, sequence: 1), '2026-000001');
    });

    test('altı haneyi aşan sayaç KIRPILMAZ', () {
      // Yılda bir milyon satış gerçekçi değildir; yine de numaranın
      // benzersizliği biçim yüzünden kaybedilemez — `ux_sales_number`
      // çakışması satışı hiç oluşturmazdı.
      expect(SaleNumber.format(year: 2026, sequence: 1234567), '2026-1234567');
    });

    test('sıfır veya negatif sıra numarası reddedilir', () {
      expect(
        () => SaleNumber.format(year: 2026, sequence: 0),
        throwsArgumentError,
        reason: '`0` bir satışı değil, "henüz satış yok"u anlatır.',
      );
      expect(
        () => SaleNumber.format(year: 2026, sequence: -1),
        throwsArgumentError,
      );
    });
  });

  group('EC-SALE-011 — yıl değişimi', () {
    test('sayaç anahtarı yıl başına ayrıdır', () {
      expect(SaleNumber.counterKey(2026), 'sale_counter_2026');
      expect(SaleNumber.counterKey(2027), 'sale_counter_2027');
      expect(
        SaleNumber.counterKey(2026),
        isNot(SaleNumber.counterKey(2027)),
        reason:
            'Yeni yılın sayacı 1\'den başlar; ayrı anahtar bunu ayrı bir '
            'sıfırlama işi olmadan sağlar.',
      );
    });

    test('yıl YEREL saatten alınır', () {
      // Fiş numarası kullanıcıya gösterilen bir etikettir. 1 Ocak 02:00'de
      // (UTC+3) kesilen fişin `2025-...` görünmesi kasada açıklanamaz.
      final localNewYear = DateTime(2027, 1, 1, 2);
      expect(SaleNumber.yearOf(localNewYear.toUtc()), 2027);
    });
  });

  group('sequenceOf — EC-SALE-012 çözümlemesi', () {
    test('kendi yılının numarasını çözer', () {
      expect(SaleNumber.sequenceOf('2026-000148', year: 2026), 148);
    });

    test('başka yılın numarasını çözmez', () {
      expect(SaleNumber.sequenceOf('2025-000148', year: 2026), isNull);
    });

    test('bozuk biçim null döner, patlamaz', () {
      expect(SaleNumber.sequenceOf('2026-abc', year: 2026), isNull);
      expect(SaleNumber.sequenceOf('', year: 2026), isNull);
    });

    test('format ↔ sequenceOf gidiş-dönüş', () {
      for (final sequence in [1, 9, 10, 999999, 1000000]) {
        expect(
          SaleNumber.sequenceOf(
            SaleNumber.format(year: 2026, sequence: sequence),
            year: 2026,
          ),
          sequence,
        );
      }
    });
  });
}
