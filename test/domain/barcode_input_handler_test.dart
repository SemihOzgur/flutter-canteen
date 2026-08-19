/// Barkod giriş işleyicisi testleri — **docs/11 §2 · REQ-BARC-001/002/008**
///
/// Saat enjekte edilir: 35 ms ile 36 ms arasındaki fark **hiçbir gerçek
/// bekleme olmadan** doğrulanır (rules/06 §7 — determinizm).
library;

import 'package:canteen/domain/services/barcode_input_handler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late BarcodeInputHandler handler;

  setUp(() {
    now = DateTime.utc(2026, 1, 1);
    handler = BarcodeInputHandler(clock: () => now);
  });

  void advance(int milliseconds) {
    now = now.add(Duration(milliseconds: milliseconds));
  }

  /// Scanner hızında yazar (karakter başına [gapMs] ms).
  void scan(String text, {int gapMs = 5}) {
    for (final char in text.split('')) {
      handler.handleCharacter(char);
      advance(gapMs);
    }
  }

  group('scanner girdisi barkod olarak tanınır', () {
    test('hızlı karakterler + Enter → barkod', () {
      scan('8690000000001');

      final result = handler.handleEnter();

      expect(result.isScanned, isTrue);
      expect(result.barcode, '8690000000001');
    });

    test('BR-BARC-009 — baştaki sıfırlar KORUNUR', () {
      scan('0001234');

      expect(
        handler.handleEnter().barcode,
        '0001234',
        reason: 'Barkod metindir; sayıya çevrilirse baştaki sıfır kaybolur.',
      );
    });

    test('okuma sonrası tampon temizlenir — ikinci okuma karışmaz', () {
      scan('11112222');
      expect(handler.handleEnter().barcode, '11112222');

      scan('33334444');
      expect(handler.handleEnter().barcode, '33334444');
    });
  });

  group('insan yazımı barkod SAYILMAZ', () {
    test('yavaş yazım (80 ms) Enter\'ı normal bırakır', () {
      scan('merhaba', gapMs: 80);

      final result = handler.handleEnter();

      expect(
        result.outcome,
        BarcodeInputOutcome.passThrough,
        reason:
            'docs/11 §2: insan yazımı 80–300 ms aralığındadır; form gönderimi '
            'engellenmemelidir.',
      );
      expect(result.barcode, isNull);
    });

    test('eşik SINIRI: 35 ms tanınır, 36 ms tanınmaz', () {
      scan('12345678', gapMs: 35);
      expect(
        handler.handleEnter().isScanned,
        isTrue,
        reason: 'Tam eşik değeri hâlâ scanner sayılır.',
      );

      handler.reset();
      scan('12345678', gapMs: 36);
      expect(
        handler.handleEnter().outcome,
        BarcodeInputOutcome.passThrough,
        reason: 'Eşiğin bir milisaniye üstü insan yazımıdır.',
      );
    });

    test('yavaş aralık ÖNCEKİ tamponu geçersiz kılar', () {
      scan('999');
      advance(500);
      scan('8690000000001');

      expect(
        handler.handleEnter().barcode,
        '8690000000001',
        reason: 'Duraklama öncesi karakterler barkoda karışmamalıdır.',
      );
    });

    test('boş tamponla Enter normal Enter\'dır', () {
      expect(handler.handleEnter().outcome, BarcodeInputOutcome.passThrough);
    });
  });

  group('uzunluk sınırları — docs/11 §2', () {
    test('4 karakterden kısa girdi barkod değildir', () {
      scan('123');

      expect(handler.handleEnter().outcome, BarcodeInputOutcome.passThrough);
    });

    test('tam 4 karakter barkoddur', () {
      scan('1234');

      expect(handler.handleEnter().barcode, '1234');
    });

    test('64 karakteri aşan girdi tamponu TEMİZLER', () {
      // 1 ms aralık bilinçlidir: 65 karakter 5 ms ile yazılsaydı 325 ms
      // ederdi ve uzunluk sınırına varmadan zaman aşımı devreye girerdi.
      scan('9' * 65, gapMs: 1);

      expect(
        handler.buffer.length,
        lessThanOrEqualTo(BarcodeInputHandler.maxLength),
        reason:
            'Barkod olamayacak kadar uzun dizi sonraki okumayı kirletmemeli.',
      );
    });
  });

  group('buffer zaman aşımı — 300 ms', () {
    test('sonlandırıcı gelmezse tampon atılır', () {
      scan('8690000000001');
      advance(400);

      expect(
        handler.handleEnter().outcome,
        BarcodeInputOutcome.passThrough,
        reason:
            'docs/11 §2: sonlandırıcı gelmezse tampon atılır — yarım kalmış '
            'bir okuma dakikalar sonra tamamlanmış sayılamaz.',
      );
    });

    test('TERK EDİLMİŞ tampondan sonraki okuma zehirlenmez', () {
      // Kullanıcı arama kutusuna yazıp duraksadı, sonra okuttu. Bu yeni bir
      // giriştir; zehirlenirse okuma yutulur ve ikinci kez okutmak gerekir.
      scan('1111');
      advance(400);
      scan('8690000000001');

      expect(handler.isPoisoned, isFalse);
      expect(handler.handleEnter().barcode, '8690000000001');
    });
  });

  group('zaman aşımı ile uzunluk sınırının ETKİLEŞİMİ — docs/11 §2', () {
    test('OD-021 — uzun okuma KIRPILMIŞ barkod ÜRETMEZ', () {
      // 40 karakter × 10 ms = 400 ms > 300 ms. Şema "yeni giriş başlat"
      // deseydi kalan ~10 karakter geçerli bir barkod gibi dönerdi; OD-021
      // bunu yasaklar (EC-BARC-002/008).
      scan('1234567890' * 4, gapMs: 10);

      final result = handler.handleEnter();

      expect(
        result.outcome,
        BarcodeInputOutcome.passThrough,
        reason:
            'Kayıp okumayı kullanıcı görür ve tekrar okutur; kırpılmış '
            'barkod sessizce yanlış veri üretir.',
      );
      expect(result.barcode, isNull);
    });

    test('zehir yalnızca Enter ile temizlenir', () {
      // Kesintisiz uzun akış: zehirlenir.
      scan('1234567890' * 4, gapMs: 10);

      expect(handler.isPoisoned, isTrue);
      expect(handler.handleEnter().outcome, BarcodeInputOutcome.passThrough);

      // Enter sayfayı temizledi: sonraki okuma normal çalışır.
      expect(handler.isPoisoned, isFalse);
      scan('8690000000001');
      expect(handler.handleEnter().barcode, '8690000000001');
    });

    test('64 karakter aşımı da zehirler — kırpılma kaynağı aynı', () {
      scan('9' * 65, gapMs: 1);

      expect(handler.isPoisoned, isTrue);
      expect(handler.handleEnter().outcome, BarcodeInputOutcome.passThrough);
    });

    test('EAN-13 en yavaş scanner hızında bile okunur', () {
      scan('8690000000001', gapMs: 15);

      expect(
        handler.handleEnter().isScanned,
        isTrue,
        reason: '13 × 15 ms = 195 ms < 300 ms — gerçek kullanım güvende.',
      );
    });
  });

  group('REQ-BARC-010 — tanılama', () {
    test('ham tampon dışarıdan okunabilir', () {
      scan('869000');

      expect(handler.buffer, '869000');
      expect(handler.isBuffering, isTrue);

      handler.reset();
      expect(handler.buffer, isEmpty);
      expect(handler.isBuffering, isFalse);
    });
  });
}
