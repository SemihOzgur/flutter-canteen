/// Auth provider wiring testleri — **BR-AUTH-016 · REQ-AUTH-004/021 ·
/// EC-DASH-006 · EC-AUTH-002 · EC-DASH-002 · EC-REC-002**
///
/// Buradaki hatalar servis testlerinin **göremediği** hatalardır: servis
/// testleri bağımlılıkları elle enjekte eder, dolayısıyla yanlış kurulmuş bir
/// provider grafiği onlardan geçer. Bu dosya yalnızca **kurulumu** doğrular:
///
/// | Doğrulanan | İhlal edilirse |
/// |---|---|
/// | Kilit servisi tek örnektir | `logout()` hayalet nesneyi kapatır, kilit açık kalır |
/// | Kilit servisi `autoDispose` değildir | Kilit ekran değişince sessizce sıfırlanır/kurulur |
/// | Yeni container kilitli başlar | EC-DASH-006 — uygulama açılışında kilit açık gelirdi |
/// | Üç bekleme sayacı ayrıdır | Dashboard denemeleri kurtarma ekranını kilitlerdi |
///
/// docs/27 §4: gerçek in-memory SQLite üzerinde çalışır.
/// Test önceliği rules/06 §2 → **Authentication** 🔴.
library;

import 'package:canteen/application/auth/auth_service.dart';
import 'package:canteen/application/auth/financial_access_service.dart';
import 'package:canteen/application/auth/login_throttle.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/application/auth/recovery_code_failures.dart';
import 'package:canteen/application/auth/recovery_code_service.dart';
import 'package:canteen/application/auth/session_service.dart';
import 'package:canteen/application/auth/setup_service.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/db/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  const userPassword = 'kantin-2026';
  const dashboardPassword = 'kasa-panel-2026';

  late FakeClock clock;
  late CanteenDatabase db;

  ProviderContainer newContainer() {
    final container = ProviderContainer(
      overrides: [canteenDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    clock = FakeClock(testEpochUtc);
    db = memoryDatabase(clock: clock.fn);
  });

  tearDown(() => db.close());

  /// Kurulum sihirbazının üç adımı (docs/17 §4) — kurtarma kodunu döndürür.
  Future<String> completeSetup(ProviderContainer container) async {
    final created = await container
        .read(authServiceProvider)
        .createUser(
          username: 'kasa',
          password: userPassword,
          displayName: 'Kasa Görevlisi',
        );
    expect(created.isOk, isTrue);

    expect(
      (await container
              .read(financialAccessProvider)
              .setPassword(dashboardPassword))
          .isOk,
      isTrue,
    );

    final code = await container
        .read(recoveryCodeServiceProvider)
        .generateInitial();
    expect(code, isA<Ok<String>>());
    return (code as Ok<String>).value;
  }

  group('tek örnek — aynı container aynı nesneyi verir', () {
    test('her servis provider\'ı tek örnektir', () {
      final container = newContainer();

      for (final provider in <ProviderListenable<Object>>[
        sessionServiceProvider,
        financialAccessProvider,
        authServiceProvider,
        recoveryCodeServiceProvider,
        setupServiceProvider,
      ]) {
        expect(
          identical(container.read(provider), container.read(provider)),
          isTrue,
          reason:
              'Provider her okumada yeni örnek üretiyor — bellekteki kilit '
              'durumu (BR-AUTH-016) kaybolur.',
        );
      }
    });

    test('servisler beklenen tipleri döndürür', () {
      final container = newContainer();

      expect(container.read(sessionServiceProvider), isA<SessionService>());
      expect(
        container.read(financialAccessProvider),
        isA<FinancialAccessService>(),
      );
      expect(container.read(authServiceProvider), isA<AuthService>());
      expect(
        container.read(recoveryCodeServiceProvider),
        isA<RecoveryCodeService>(),
      );
      expect(container.read(setupServiceProvider), isA<SetupService>());
    });

    test(
      'kilit servisi autoDispose DEĞİLDİR — durum okumalar arasında yaşar',
      () async {
        final container = newContainer();
        await completeSetup(container);

        expect(
          (await container
                  .read(financialAccessProvider)
                  .unlock(dashboardPassword))
              .isOk,
          isTrue,
        );

        expect(
          container.read(financialAccessProvider).isUnlocked,
          isTrue,
          reason:
              'Kilit yalnızca bellektedir (BR-AUTH-016); servis atılırsa açık '
              'kilit sessizce kaybolur.',
        );

        // Yukarıdaki davranış kontrolü `autoDispose`'u **yakalayamaz**:
        // Riverpod dinleyicisi olmayan bir provider'ı iki okuma arasında
        // senkron olarak atmaz ve test ortamında frame scheduler olmadığı için
        // hiç atmayabilir. Bu yüzden tip düzeyinde de doğrulanır — yapısal
        // kontrol kandırılamaz.
        expect(
          financialAccessProvider,
          isNot(isA<AutoDisposeProvider<FinancialAccessService>>()),
          reason:
              'BR-AUTH-016: kilit bellekte yaşar. `autoDispose` yapılırsa '
              'ekran değişiminde servis atılıp yeniden kurulur; açık kilit '
              'sessizce kaybolur veya daha kötüsü, yeni örnek beklenmedik '
              'durumda başlar.',
        );
        for (final provider in [
          sessionServiceProvider,
          authServiceProvider,
          recoveryCodeServiceProvider,
          setupServiceProvider,
          loginThrottleProvider,
          dashboardThrottleProvider,
          recoveryThrottleProvider,
        ]) {
          expect(
            provider,
            isNot(isA<AutoDisposeProvider<Object?>>()),
            reason:
                'Auth servisleri ve bekleme sayaçları da bellekte durum '
                'taşır; hiçbiri autoDispose olamaz. Sorunlu: $provider',
          );
        }
      },
    );
  });

  group('kilit servisi TEK ÖRNEK — davranışsal kanıt', () {
    test('AuthService.logout() gerçek kilidi kapatır (REQ-AUTH-004)', () async {
      final container = newContainer();
      await completeSetup(container);

      final access = container.read(financialAccessProvider);
      expect((await access.unlock(dashboardPassword)).isOk, isTrue);
      expect(access.isUnlocked, isTrue);

      await container.read(authServiceProvider).logout();

      expect(
        access.isUnlocked,
        isFalse,
        reason:
            'logout() başka bir FinancialAccessService örneğini kapatıyor — '
            'gerçek kilit açık kaldı (REQ-AUTH-004 ihlali).',
      );
    });

    test('AuthService.login() gerçek kilidi kapatır (REQ-AUTH-021)', () async {
      final container = newContainer();
      await completeSetup(container);

      final access = container.read(financialAccessProvider);
      expect((await access.unlock(dashboardPassword)).isOk, isTrue);

      final login = await container
          .read(authServiceProvider)
          .login('kasa', userPassword);
      expect(login.isOk, isTrue);

      expect(
        access.isUnlocked,
        isFalse,
        reason: 'Yeni oturum kilidi devralamaz (BR-AUTH-016).',
      );
    });

    test(
      'RecoveryCodeService gerçek kilidi açar (docs/17 §8 son adım)',
      () async {
        final container = newContainer();
        final code = await completeSetup(container);

        final access = container.read(financialAccessProvider);
        expect(access.isUnlocked, isFalse);

        final result = await container
            .read(recoveryCodeServiceProvider)
            .resetPasswordWithCode(code: code, newPassword: 'yeni-panel-2026');
        expect(result.isOk, isTrue);

        expect(
          access.isUnlocked,
          isTrue,
          reason:
              'Kurtarma başka bir kilit örneğini açıyor — kullanıcı parolayı '
              'sıfırladığı hâlde Dashboard kilitli kalır.',
        );
      },
    );

    test('SetupService servislerin aynı örneklerini kullanır', () async {
      final container = newContainer();

      expect(
        await container.read(setupServiceProvider).currentState(),
        SetupState.needsUser,
      );

      await completeSetup(container);

      expect(
        await container.read(setupServiceProvider).currentState(),
        SetupState.complete,
        reason:
            'SetupService farklı servis örneklerini okuyor — kurulum bitmiş '
            'olmasına rağmen sihirbaz açılırdı.',
      );
    });
  });

  group('EC-DASH-006 — yeni container kilitli başlar', () {
    test('kilit kalıcılaştırılmaz; yeni container kilitlidir', () async {
      final first = newContainer();
      await completeSetup(first);
      expect(
        (await first.read(financialAccessProvider).unlock(dashboardPassword))
            .isOk,
        isTrue,
      );

      // Uygulamanın kapanıp yeniden açılması: aynı veritabanı, yeni container.
      final second = newContainer();

      expect(
        second.read(financialAccessProvider).isUnlocked,
        isFalse,
        reason:
            'EC-DASH-006: kilit durumu veritabanına yazılmamalı, uygulama '
            'kilitli başlamalıdır.',
      );
    });
  });

  group('bekleme sayaçları ayrıdır', () {
    test('üç throttle provider\'ı farklı örneklerdir', () {
      final container = newContainer();

      final login = container.read(loginThrottleProvider);
      final dashboard = container.read(dashboardThrottleProvider);
      final recovery = container.read(recoveryThrottleProvider);

      expect(identical(login, dashboard), isFalse);
      expect(identical(login, recovery), isFalse);
      expect(identical(dashboard, recovery), isFalse);

      // Her biri kendi içinde tek örnektir.
      expect(identical(login, container.read(loginThrottleProvider)), isTrue);
      expect(
        identical(dashboard, container.read(dashboardThrottleProvider)),
        isTrue,
      );
      expect(
        identical(recovery, container.read(recoveryThrottleProvider)),
        isTrue,
      );
    });

    test('dashboard beklemesi login ve kurtarma ekranını kilitlemez', () async {
      final container = newContainer();
      final code = await completeSetup(container);

      final access = container.read(financialAccessProvider);
      for (var i = 0; i < LoginThrottle.maxAttempts; i++) {
        expect((await access.unlock('yanlis')).isErr, isTrue);
      }

      // Dashboard artık beklemede (EC-DASH-002).
      final blocked = await access.unlock(dashboardPassword);
      expect(blocked.isErr, isTrue);
      expect(blocked.failureOrNull?.code, 'financial_access_too_many_attempts');

      // Kullanıcı girişi etkilenmez (EC-AUTH-002 ayrı sayaç).
      final login = await container
          .read(authServiceProvider)
          .login('kasa', userPassword);
      expect(
        login.isOk,
        isTrue,
        reason: 'Dashboard denemeleri kullanıcı girişini kilitlememelidir.',
      );

      // Kurtarma akışı etkilenmez (EC-REC-002 ayrı sayaç) — kullanıcı buraya
      // zaten parolayı unuttuğu için gelir.
      final recovered = await container
          .read(recoveryCodeServiceProvider)
          .resetPasswordWithCode(code: code, newPassword: 'yeni-panel-2026');
      expect(
        recovered.isOk,
        isTrue,
        reason: 'Dashboard denemeleri kurtarma ekranını kilitlememelidir.',
      );
    });

    test('kurtarma beklemesi dashboard parolasını kilitlemez', () async {
      final container = newContainer();
      await completeSetup(container);

      final recovery = container.read(recoveryCodeServiceProvider);
      for (var i = 0; i < LoginThrottle.maxAttempts; i++) {
        final attempt = await recovery.resetPasswordWithCode(
          code: 'AAAA-BBBB-CCCC-DDDD',
          newPassword: 'yeni-panel-2026',
        );
        expect(attempt.failureOrNull, RecoveryCodeFailures.invalidCode);
      }

      final unlocked = await container
          .read(financialAccessProvider)
          .unlock(dashboardPassword);
      expect(
        unlocked.isOk,
        isTrue,
        reason: 'Kurtarma denemeleri dashboard parolasını kilitlememelidir.',
      );
    });
  });

  group('log provider\'ı', () {
    test('override edilmezse null\'dır ve servisler yine kurulur', () {
      final container = newContainer();

      expect(container.read(appLoggerProvider), isNull);
      expect(container.read(financialAccessProvider), isNotNull);
      expect(container.read(recoveryCodeServiceProvider), isNotNull);
    });
  });

  group('setupStateProvider', () {
    test('kurulum durumunu yayınlar', () async {
      final container = newContainer();

      expect(
        await container.read(setupStateProvider.future),
        SetupState.needsUser,
      );

      await completeSetup(container);
      container.invalidate(setupStateProvider);

      expect(
        await container.read(setupStateProvider.future),
        SetupState.complete,
      );
    });
  });
}
