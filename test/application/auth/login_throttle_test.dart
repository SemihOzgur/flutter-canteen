/// Giriş denemesi sayacı — **EC-AUTH-002 · REQ-AUTH-011**
///
/// `AuthService` üzerinden yapılan davranış testleri `auth_service_test.dart`
/// içindedir. Buradakiler sayacın **kendi** sözleşmesini doğrular.
library;

import 'package:canteen/application/auth/login_throttle.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);

  group('eşik ve bekleme', () {
    test('5. hatada kilitlenir, öncesinde kilit yok', () {
      final throttle = LoginThrottle();

      for (var i = 0; i < LoginThrottle.maxAttempts - 1; i++) {
        throttle.registerFailure('kasa', t0);
        expect(throttle.remainingLock('kasa', t0), isNull, reason: 'deneme $i');
      }

      throttle.registerFailure('kasa', t0);
      expect(throttle.remainingLock('kasa', t0), LoginThrottle.lockDuration);
    });

    test('bekleme dolunca sayaç sıfırlanır — tek hata yeniden kilitlemez', () {
      final throttle = LoginThrottle();
      for (var i = 0; i < LoginThrottle.maxAttempts; i++) {
        throttle.registerFailure('kasa', t0);
      }

      final after = t0.add(LoginThrottle.lockDuration);
      expect(throttle.remainingLock('kasa', after), isNull);

      throttle.registerFailure('kasa', after);
      expect(
        throttle.remainingLock('kasa', after),
        isNull,
        reason: 'Sayaç sıfırlanmadıysa tek hata beklemeyi geri getirir.',
      );
    });

    test('anahtarlar birbirinden bağımsız', () {
      final throttle = LoginThrottle();
      for (var i = 0; i < LoginThrottle.maxAttempts; i++) {
        throttle.registerFailure('kasa', t0);
      }

      expect(throttle.remainingLock('kasa', t0), isNotNull);
      expect(throttle.remainingLock('mudur', t0), isNull);
    });

    test('reset beklemeyi kaldırır', () {
      final throttle = LoginThrottle();
      for (var i = 0; i < LoginThrottle.maxAttempts; i++) {
        throttle.registerFailure('kasa', t0);
      }

      throttle.reset('kasa');
      expect(throttle.remainingLock('kasa', t0), isNull);
    });
  });

  group('bellek sınırı', () {
    test('kilitlenmemiş eski kayıtlar temizlenir', () {
      final throttle = LoginThrottle();

      // Anahtar kullanıcı girdisidir; var olmayan adlar da kayıt açar.
      for (var i = 0; i < 500; i++) {
        throttle.registerFailure('deneme-$i', t0);
      }
      expect(throttle.trackedKeyCount, 500);

      final later = t0
          .add(LoginThrottle.idleRetention)
          .add(const Duration(seconds: 1));
      throttle.registerFailure('yeni', later);

      expect(
        throttle.trackedKeyCount,
        1,
        reason:
            'Eşiğe ulaşmamış eski kayıtlar bellekte birikmemeli — anahtar '
            'kullanıcı girdisidir.',
      );
    });

    test('KİLİTLİ kayıt süresi dolmadan temizlenmez', () {
      final throttle = LoginThrottle();
      for (var i = 0; i < LoginThrottle.maxAttempts; i++) {
        throttle.registerFailure('kilitli', t0);
      }

      // Temizlik tetiklenir, ama kilit hâlâ sürüyor.
      throttle.registerFailure('baska', t0.add(const Duration(seconds: 10)));

      expect(
        throttle.remainingLock('kilitli', t0.add(const Duration(seconds: 10))),
        isNotNull,
        reason: 'Temizlik aktif bir beklemeyi iptal edemez.',
      );
    });
  });
}
