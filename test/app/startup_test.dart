/// Açılış rotası testleri — **docs/03 §6 adım 7/9/10 · EC-AUTH-003/004/008 ·
/// EC-DASH-006 · REQ-AUTH-001/006/016/022**
///
/// `main()` unit test edilemez; bu yüzden açılış kararı `resolveInitialRoute`
/// içinde yaşar ve burada **gerçek servislerle** (in-memory SQLite, docs/27 §4)
/// doğrulanır.
///
/// Test önceliği rules/06 §2 → **Authentication** 🔴.
library;

import 'dart:io';

import 'package:canteen/app/router.dart';
import 'package:canteen/app/startup.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/data/db/app_setting_keys.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/db/providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  const userPassword = 'kantin-2026';
  const dashboardPassword = 'kasa-panel-2026';

  late FakeClock clock;
  late CanteenDatabase db;
  late ProviderContainer container;

  setUp(() {
    clock = FakeClock(testEpochUtc);
    db = memoryDatabase(clock: clock.fn);
    container = ProviderContainer(
      overrides: [canteenDatabaseProvider.overrideWithValue(db)],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  /// `main.dart`'ın adım 6–7'de yaptığı çağrının aynısı.
  Future<String> bootstrapRoute() => resolveInitialRoute(
    setup: container.read(setupServiceProvider),
    session: container.read(sessionServiceProvider),
  );

  Future<void> createUser({String username = 'kasa'}) async {
    final created = await container
        .read(authServiceProvider)
        .createUser(
          username: username,
          password: userPassword,
          displayName: 'Kasa Görevlisi',
        );
    expect(created.isOk, isTrue);
  }

  Future<void> completeSetup() async {
    await createUser();
    expect(
      (await container
              .read(financialAccessProvider)
              .setPassword(dashboardPassword))
          .isOk,
      isTrue,
    );
    expect(
      (await container.read(recoveryCodeServiceProvider).generateInitial())
          .isOk,
      isTrue,
    );
  }

  group('adım 7 — kurulum kontrolü', () {
    test('hiç kullanıcı yok → sihirbaz (EC-AUTH-008)', () async {
      expect(
        await bootstrapRoute(),
        AppRoutes.setup,
        reason:
            'EC-AUTH-008: hiç kullanıcı yokken login gösterilirse kullanıcı '
            'sisteme hiç giremez.',
      );
    });

    test(
      'yarım kurulum: kullanıcı var, dashboard parolası yok → sihirbaz',
      () async {
        await createUser();

        expect(
          await bootstrapRoute(),
          AppRoutes.setup,
          reason:
              'REQ-AUTH-016: sihirbaz Adım 2 atlanırsa dashboard parolası hiç '
              'oluşmaz ve kullanıcı eksiği fark etmez.',
        );
      },
    );

    test('yarım kurulum: kurtarma kodu yok → sihirbaz', () async {
      await createUser();
      expect(
        (await container
                .read(financialAccessProvider)
                .setPassword(dashboardPassword))
            .isOk,
        isTrue,
      );

      expect(
        await bootstrapRoute(),
        AppRoutes.setup,
        reason:
            'REQ-AUTH-022: kurtarma kodu üretilmeden kurulum tamamlanmış '
            'sayılmaz (EC-REC-012).',
      );
    });

    test('kurulum yarımken oturum varlığı kararı değiştirmez', () async {
      await createUser();
      // Kullanıcı oluşturulduktan sonra bir şekilde oturum açılmış olsa bile
      // (örn. eski bir sürümden kalma kayıt) sihirbaz önceliklidir.
      await container.read(sessionServiceProvider).save(1);

      expect(await bootstrapRoute(), AppRoutes.setup);
    });
  });

  group('adım 9 — oturum', () {
    test('kurulum tam, oturum yok → login', () async {
      await completeSetup();

      expect(await bootstrapRoute(), AppRoutes.login);
    });

    test('geçerli oturum → ana ekran (REQ-AUTH-001)', () async {
      await completeSetup();
      final login = await container
          .read(authServiceProvider)
          .login('kasa', userPassword);
      expect(login.isOk, isTrue);

      expect(await bootstrapRoute(), AppRoutes.home);
    });

    test('logout sonrası → login (REQ-AUTH-004)', () async {
      await completeSetup();
      expect(
        (await container.read(authServiceProvider).login('kasa', userPassword))
            .isOk,
        isTrue,
      );
      await container.read(authServiceProvider).logout();

      expect(await bootstrapRoute(), AppRoutes.login);
    });

    test('bozuk oturum verisi → login, çökme yok (EC-AUTH-004)', () async {
      await completeSetup();
      await container
          .read(appSettingsDaoProvider)
          .write(AppSettingKeys.session, '{bozuk-json');

      expect(await bootstrapRoute(), AppRoutes.login);
      expect(
        await container
            .read(appSettingsDaoProvider)
            .read(AppSettingKeys.session),
        isNull,
        reason: 'EC-AUTH-004: bozuk oturum sessizce temizlenir.',
      );
    });

    test(
      'oturumdaki kullanıcı pasifleştirilmiş → login (EC-AUTH-003)',
      () async {
        await completeSetup();
        // İkinci kullanıcı: son aktif kullanıcı pasifleştirilemez (BR-AUTH-006).
        await createUser(username: 'ikinci');

        final login = await container
            .read(authServiceProvider)
            .login('kasa', userPassword);
        expect(login.isOk, isTrue);
        final userId = login.valueOrNull!.id;

        expect(
          (await container.read(authServiceProvider).setActive(userId, false))
              .isOk,
          isTrue,
        );

        expect(await bootstrapRoute(), AppRoutes.login);
      },
    );
  });

  group('adım 10 — finansal kilit KAPALI başlar', () {
    test(
      'açılış rotası çözüldükten sonra kilit kapalıdır (EC-DASH-006)',
      () async {
        await completeSetup();
        expect(
          (await container
                  .read(authServiceProvider)
                  .login('kasa', userPassword))
              .isOk,
          isTrue,
        );

        expect(await bootstrapRoute(), AppRoutes.home);
        expect(
          container.read(financialAccessProvider).isUnlocked,
          isFalse,
          reason:
              'BR-AUTH-013/016: normal giriş Dashboard ve Raporlara otomatik '
              'erişim vermez.',
        );
      },
    );

    test('bootstrap kilidi açan bir çağrı İÇERMEZ — kaynak seviyesinde', () {
      final source = File('lib/main.dart').readAsStringSync();

      for (final banned in const [
        '.unlock(',
        'unlockAfterRecovery',
        'financialAccessProvider',
      ]) {
        expect(
          source.contains(banned),
          isFalse,
          reason:
              'BR-AUTH-016 · EC-DASH-006: açılış kilidi açmaz; main.dart '
              'kilide hiç dokunmamalıdır → $banned',
        );
      }
    });

    test('bootstrap sırası: kurulum/oturum çözümü runApp\'ten ÖNCE', () {
      final source = File('lib/main.dart').readAsStringSync();

      final resolveIndex = source.indexOf('resolveInitialRoute(');
      final runAppIndex = source.indexOf('UncontrolledProviderScope');

      expect(
        resolveIndex,
        greaterThan(-1),
        reason: 'docs/03 §6 adım 7/9 bootstrap\'ta yok!',
      );
      expect(
        resolveIndex,
        lessThan(runAppIndex),
        reason:
            'Karar ilk kare çizilmeden verilmelidir; aksi hâlde uygulama önce '
            'yanlış ekranı gösterip sıçrar.',
      );
    });

    test('aktif sepet restore Faz 5\'tir — bootstrap\'a girmemiştir', () {
      final source = File('lib/main.dart').readAsStringSync();

      expect(source.contains('cart'), isFalse);
      expect(source.contains('Cart'), isFalse);
    });
  });

  group('router', () {
    test('tüm rotalar tanımlıdır ve adları benzersizdir', () {
      final routes = AppRoutes.routes();

      expect(routes.keys.toSet(), {
        AppRoutes.setup,
        AppRoutes.login,
        AppRoutes.home,
        // Faz 3a — docs/17 §8, §9, §11.
        AppRoutes.users,
        AppRoutes.financialAccessSettings,
      });
      expect(
        routes.length,
        5,
        reason: 'Aynı yol iki kez tanımlanırsa biri sessizce kaybolur.',
      );
    });

    test('resolveInitialRoute yalnızca tanımlı rota döndürür', () async {
      final routes = AppRoutes.routes();

      expect(routes.containsKey(await bootstrapRoute()), isTrue);

      await completeSetup();
      expect(routes.containsKey(await bootstrapRoute()), isTrue);
    });
  });
}
