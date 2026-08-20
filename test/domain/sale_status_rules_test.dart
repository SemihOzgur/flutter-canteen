/// Satış durumu makinesi — **docs/14 §2 · REQ-RET-007 · BR-RET-001/006**
///
/// Durum **her iade sonrası yeniden hesaplanır**; hiçbir yerde elle atanmaz.
/// Sınır davranışları burada, saf Dart'ta sınanır — servis testinde bir
/// off-by-one yalnızca belirli bir veri kurulumunda görünürdü.
library;

import 'package:canteen/domain/enums/sale_status.dart';
import 'package:canteen/domain/services/sale_status_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  SaleStatus statusFor(int sold, int returned) =>
      SaleStatusRules.fromReturnedQuantities(
        totalSold: sold,
        totalReturned: returned,
      );

  group('docs/14 §2 — durum hesaplama', () {
    test('hiç iade yoksa completed', () {
      expect(statusFor(6, 0), SaleStatus.completed);
    });

    test('SINIR — 1 adet iade partiallyReturned yapar', () {
      expect(statusFor(6, 1), SaleStatus.partiallyReturned);
    });

    test('SINIR — son adet iade edilince returned', () {
      expect(statusFor(6, 6), SaleStatus.returned);
    });

    test('SINIR — bir eksiği hâlâ partiallyReturned', () {
      expect(statusFor(6, 5), SaleStatus.partiallyReturned);
    });

    test('tek adetlik satış tek iadeyle returned olur', () {
      // `0 < iade < satılan` aralığı burada BOŞTUR; kısmi duruma hiç girilmez.
      expect(statusFor(1, 0), SaleStatus.completed);
      expect(statusFor(1, 1), SaleStatus.returned);
    });

    test('savunma — iade satılandan fazlaysa returned', () {
      // Şemadaki CHECK bunu engeller; kural yine de tanımsız kalmamalıdır.
      expect(statusFor(3, 5), SaleStatus.returned);
    });

    test('savunma — negatif iade completed sayılır', () {
      expect(statusFor(3, -1), SaleStatus.completed);
    });

    test('`cancelled` bu kuraldan ASLA üretilmez', () {
      // docs/14 §1 — iptal bir iade sonucu değil, ayrı bir kullanıcı
      // eylemidir. Kural onu üretebilseydi bir iade satışı sessizce iptal
      // edilmiş gösterirdi.
      for (var sold = 0; sold <= 5; sold++) {
        for (var returned = -2; returned <= 7; returned++) {
          expect(statusFor(sold, returned), isNot(SaleStatus.cancelled));
        }
      }
    });
  });

  group('BR-RET-001 — iptal edilebilirlik', () {
    test('completed ve hiç iade yoksa iptal EDİLEBİLİR', () {
      expect(
        SaleStatusRules.canCancel(
          status: SaleStatus.completed,
          totalReturned: 0,
        ),
        isTrue,
      );
    });

    test('SINIR — tek adet iade bile iptali ENGELLER', () {
      // Aksi hâlde iade hareketlerinin üzerine bir de tam iptal hareketi
      // yazılır ve stok İKİ KEZ geri eklenirdi.
      expect(
        SaleStatusRules.canCancel(
          status: SaleStatus.partiallyReturned,
          totalReturned: 1,
        ),
        isFalse,
      );
    });

    test('BR-RET-006 — iptal edilmiş satış tekrar iptal EDİLEMEZ', () {
      expect(
        SaleStatusRules.canCancel(
          status: SaleStatus.cancelled,
          totalReturned: 0,
        ),
        isFalse,
      );
    });

    test('tamamı iade edilmiş satış iptal EDİLEMEZ', () {
      expect(
        SaleStatusRules.canCancel(
          status: SaleStatus.returned,
          totalReturned: 6,
        ),
        isFalse,
      );
    });
  });

  group('BR-RET-006 — iade edilebilirlik', () {
    bool canReturn(SaleStatus status, int sold, int returned) =>
        SaleStatusRules.canReturn(
          status: status,
          totalSold: sold,
          totalReturned: returned,
        );

    test('completed satıştan iade YAPILABİLİR', () {
      expect(canReturn(SaleStatus.completed, 6, 0), isTrue);
    });

    test('kısmi iadeli satıştan kalan miktar iade EDİLEBİLİR', () {
      expect(canReturn(SaleStatus.partiallyReturned, 6, 5), isTrue);
    });

    test('SINIR — tamamı iade edilmişse iade EDİLEMEZ', () {
      expect(canReturn(SaleStatus.returned, 6, 6), isFalse);
    });

    test('İPTAL edilmiş satıştan iade EDİLEMEZ', () {
      // İptal zaten tüm stoğu geri eklemiştir; iade ikinci kez eklerdi.
      expect(
        canReturn(SaleStatus.cancelled, 6, 0),
        isFalse,
        reason: 'BR-RET-006 — kalan miktar olsa BİLE iade edilemez.',
      );
    });
  });
}
