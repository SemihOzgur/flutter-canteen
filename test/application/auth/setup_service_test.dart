/// SetupService testleri — **docs/17 §4 · docs/22 F1 ·
/// REQ-AUTH-002/016/022/024 · EC-AUTH-008 · EC-DASH-011**
///
/// docs/27 §4: gerçek in-memory SQLite üzerinde çalışır.
/// Test önceliği rules/06 §2 → **Authentication** 🔴.
///
/// Buradaki asıl soru şudur: kurulum sihirbazı **yarım kalırsa** açılış bunu
/// görebiliyor mu? Sihirbazın üç zorunlu adımı üç ayrı transaction olduğu için
/// (kurtarma kodu kullanıcıya gösterilip onaylanmalıdır — REQ-AUTH-024) her
/// adımdan sonra çökme mümkündür.
library;

import 'dart:math';

import 'package:canteen/application/auth/auth_service.dart';
import 'package:canteen/application/auth/financial_access_service.dart';
import 'package:canteen/application/auth/login_throttle.dart';
import 'package:canteen/application/auth/recovery_code_service.dart';
import 'package:canteen/application/auth/session_service.dart';
import 'package:canteen/application/auth/setup_service.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/app_setting_keys.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, Sale, SaleItem, StockMovement;
import 'package:canteen/domain/services/password_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  const userPassword = 'kantin-2026';
  const dashboardPassword = 'kasa-panel-2026';

  late FakeClock clock;
  late CanteenDatabase db;
  late AppSettingsDao settingsDao;
  late UsersDao usersDao;
  late AuthService auth;
  late FinancialAccessService access;
  late RecoveryCodeService recovery;
  late SetupService setup;

  setUp(() {
    clock = FakeClock(testEpochUtc);
    db = memoryDatabase(clock: clock.fn);
    settingsDao = AppSettingsDao(db);
    usersDao = UsersDao(db);
    access = FinancialAccessService(
      db: db,
      settings: settingsDao,
      auditLogs: AuditLogsDao(db),
      // Deterministik salt üretimi (rules/06 §7).
      hasher: PasswordHasher.withRandom(Random(11)),
      throttle: LoginThrottle(),
      clock: clock.fn,
    );
    auth = AuthService(
      db: db,
      users: usersDao,
      session: SessionService(
        settings: settingsDao,
        users: usersDao,
        clock: clock.fn,
      ),
      financialAccess: access,
      hasher: PasswordHasher.withRandom(Random(7)),
      throttle: LoginThrottle(),
      clock: clock.fn,
    );
    recovery = RecoveryCodeService(
      db: db,
      settings: settingsDao,
      auditLogs: AuditLogsDao(db),
      financialAccess: access,
      hasher: PasswordHasher.withRandom(Random(37)),
      throttle: LoginThrottle(),
      random: Random(23),
      clock: clock.fn,
    );
    setup = SetupService(
      auth: auth,
      financialAccess: access,
      recoveryCode: recovery,
    );
  });

  tearDown(() => db.close());

  /// Sihirbaz Adım 1 (docs/17 §4).
  Future<void> step1CreateUser() async {
    final result = await auth.createUser(
      username: 'kasa',
      password: userPassword,
      displayName: 'Kasa Görevlisi',
    );
    expect(result, isA<Ok<int>>(), reason: 'Adım 1 tamamlanamadı');
  }

  /// Sihirbaz Adım 2 (REQ-AUTH-016).
  Future<void> step2SetDashboardPassword() async {
    expect((await access.setPassword(dashboardPassword)).isOk, isTrue);
  }

  /// Sihirbaz Adım 3 (REQ-AUTH-022).
  Future<void> step3GenerateRecoveryCode() async {
    expect((await recovery.generateInitial()).isOk, isTrue);
  }

  group('kurulum sırası — docs/17 §4', () {
    test('boş veritabanı → needsUser (EC-AUTH-008)', () async {
      expect(await setup.currentState(), SetupState.needsUser);
      expect(await setup.isComplete(), isFalse);
    });

    test('Adım 1 sonrası → needsDashboardPassword', () async {
      await step1CreateUser();

      expect(
        await setup.currentState(),
        SetupState.needsDashboardPassword,
        reason:
            'REQ-AUTH-016: kullanıcı var ama dashboard parolası yok — kurulum '
            'tamamlanmış sayılamaz',
      );
      expect(
        await auth.needsSetup(),
        isFalse,
        reason: 'needsSetup yalnızca Adım 1 sorusudur; sinyal o değildir',
      );
    });

    test('Adım 2 sonrası → needsRecoveryCode', () async {
      await step1CreateUser();
      await step2SetDashboardPassword();

      expect(
        await setup.currentState(),
        SetupState.needsRecoveryCode,
        reason:
            'REQ-AUTH-022: kurtarma kodu üretilmemiş. EC-REC-012 gereği '
            '"Şifremi unuttum" gösterilmeyeceği için kullanıcı eksiği fark '
            'edemezdi.',
      );
    });

    test('Adım 3 sonrası → complete', () async {
      await step1CreateUser();
      await step2SetDashboardPassword();
      await step3GenerateRecoveryCode();

      expect(await setup.currentState(), SetupState.complete);
      expect(await setup.isComplete(), isTrue);
    });
  });

  group('yarım kalan kurulum tespit edilir', () {
    test('Adım 1 sonrası çökme — yeni açılışta sihirbaz devam eder', () async {
      await step1CreateUser();

      // "Çökme": aynı veritabanı, yepyeni servis örnekleri (uygulama restart).
      final restartedAccess = FinancialAccessService(
        db: db,
        settings: settingsDao,
        auditLogs: AuditLogsDao(db),
        hasher: PasswordHasher.withRandom(Random(11)),
        clock: clock.fn,
      );
      final restartedSetup = SetupService(
        auth: AuthService(
          db: db,
          users: usersDao,
          session: SessionService(
            settings: settingsDao,
            users: usersDao,
            clock: clock.fn,
          ),
          financialAccess: restartedAccess,
          hasher: PasswordHasher.withRandom(Random(7)),
          clock: clock.fn,
        ),
        financialAccess: restartedAccess,
        recoveryCode: RecoveryCodeService(
          db: db,
          settings: settingsDao,
          auditLogs: AuditLogsDao(db),
          financialAccess: restartedAccess,
          hasher: PasswordHasher.withRandom(Random(37)),
          random: Random(23),
          clock: clock.fn,
        ),
      );

      expect(
        await restartedSetup.currentState(),
        SetupState.needsDashboardPassword,
      );
    });

    test(
      'Adım 2 yarım kalırsa (yalnızca hash) kurulum eksik sayılır',
      () async {
        await step1CreateUser();
        // Yarım yazım simülasyonu: salt olmadan hash.
        await settingsDao.write(AppSettingKeys.dashboardPasswordHash, 'x' * 64);

        expect(
          await setup.currentState(),
          SetupState.needsDashboardPassword,
          reason: 'isConfigured hem hash hem salt ister',
        );
      },
    );

    test(
      'Adım 3 yarım kalırsa (yalnızca hash) kurulum eksik sayılır',
      () async {
        await step1CreateUser();
        await step2SetDashboardPassword();
        await settingsDao.write(AppSettingKeys.dashboardRecoveryHash, 'x' * 64);

        expect(await setup.currentState(), SetupState.needsRecoveryCode);
      },
    );

    test('yalnızca pasif kullanıcı varsa Adım 1 tamam sayılır', () async {
      await step1CreateUser();
      await auth.createUser(
        username: 'mudur',
        password: userPassword,
        displayName: 'Müdür',
      );
      final id = (await usersDao.findByUsername('kasa'))!.id;
      expect((await auth.setActive(id, false)).isOk, isTrue);

      expect(
        await setup.currentState(),
        SetupState.needsDashboardPassword,
        reason: 'pasif kullanıcı varken sistem "yeni kurulum" değildir',
      );
    });
  });

  group('kullanılmış kurtarma kodu kurulumu geçersiz kılmaz', () {
    test('used_at dolu olsa bile complete (EC-REC-010)', () async {
      await step1CreateUser();
      await step2SetDashboardPassword();
      await step3GenerateRecoveryCode();

      // Restore sonrası oluşabilen durum: kayıt var, kullanılmış işaretli.
      await settingsDao.write(
        AppSettingKeys.dashboardRecoveryUsedAt,
        clock.now().toUtc().millisecondsSinceEpoch.toString(),
      );

      expect(await recovery.isAvailable(), isFalse);
      expect(
        await setup.currentState(),
        SetupState.complete,
        reason:
            'kullanılabilirlik (EC-REC-012) ayrı bir sorudur; kurulum yapılmıştır',
      );
    });
  });
}
