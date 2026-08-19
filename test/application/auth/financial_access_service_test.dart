/// FinancialAccessService testleri — **docs/17 §7, §9 · EC-DASH-001…014**
///
/// docs/27 §4: gerçek in-memory SQLite üzerinde çalışır.
/// Test önceliği rules/06 §2 → **Authentication** 🔴.
///
/// En kritik test docs/27 §6.1b'den gelir: *"Parola girilmeden hiçbir
/// dashboard/rapor sorgusunun çalışmadığı doğrulanır (sorgu sayacı ile)"*
/// → `BR-AUTH-012` grubu.
library;

import 'dart:convert';
import 'dart:math';

import 'package:canteen/application/auth/auth_service.dart';
import 'package:canteen/application/auth/financial_access_failures.dart';
import 'package:canteen/application/auth/financial_access_service.dart';
import 'package:canteen/application/auth/login_throttle.dart';
import 'package:canteen/application/auth/session_service.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/app_setting_keys.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, Sale, SaleItem, StockMovement;
import 'package:canteen/domain/services/password_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

/// Sahte finansal veri kaynağı — **sorgu sayacı** (docs/27 §6.1b).
///
/// Gerçek dashboard/rapor sorguları Faz 8'de gelecektir; burada önemli olan
/// sorgunun **çalıştırılıp çalıştırılmadığıdır**, ne döndürdüğü değil.
class SpyFinancialSource {
  int queryCount = 0;

  Future<int> totalRevenueMinor() async {
    queryCount++;
    return 123400;
  }
}

/// Enjekte edilen hata — gerçek bir arıza gibi davranır.
class _InjectedFailure implements Exception {
  const _InjectedFailure();
  @override
  String toString() => 'enjekte edilmiş hata';
}

/// Audit yazımında patlayan DAO — REQ-AUDIT-007.
class _FailingAuditLogsDao extends AuditLogsDao {
  _FailingAuditLogsDao(super.db);

  @override
  Future<int> record({
    required DateTime createdAt,
    required String action,
    required String entityType,
    int? userId,
    int? entityId,
    String? oldValue,
    String? newValue,
    String? metadata,
  }) async {
    throw const _InjectedFailure();
  }
}

void main() {
  const dashboardPassword = 'kasa-panel-2026';

  late FakeClock clock;
  late CanteenDatabase db;
  late AppSettingsDao settingsDao;
  late AuditLogsDao auditDao;
  late LoginThrottle throttle;
  late FinancialAccessService access;

  FinancialAccessService buildService({
    LoginThrottle? withThrottle,
    AuditLogsDao? audit,
  }) {
    return FinancialAccessService(
      db: db,
      settings: settingsDao,
      auditLogs: audit ?? auditDao,
      // Deterministik salt üretimi (rules/06 §7).
      hasher: PasswordHasher.withRandom(Random(11)),
      throttle: withThrottle ?? throttle,
      clock: clock.fn,
    );
  }

  setUp(() {
    clock = FakeClock(testEpochUtc);
    db = memoryDatabase(clock: clock.fn);
    settingsDao = AppSettingsDao(db);
    auditDao = AuditLogsDao(db);
    throttle = LoginThrottle();
    access = buildService();
  });

  tearDown(() => db.close());

  Future<void> configure([String password = dashboardPassword]) async {
    final result = await access.setPassword(password);
    expect(result, isA<Ok<void>>(), reason: 'dashboard parolası kurulamadı');
  }

  Future<void> unlock([String password = dashboardPassword]) async {
    final result = await access.unlock(password);
    expect(result, isA<Ok<void>>(), reason: 'kilit açılamadı');
  }

  Future<Set<String>> settingKeys() async {
    final rows = await db.select(db.appSettings).get();
    return rows.map((row) => row.key).toSet();
  }

  Future<List<AuditLog>> auditRows() => db.select(db.auditLogs).get();

  // --- BR-AUTH-012 — kilit görsel bir perde değildir ------------------------

  group('BR-AUTH-012 · REQ-AUTH-019 — sorgu sayacı (docs/27 §6.1b)', () {
    test('kilit kapalıyken finansal sorgu HİÇ çalıştırılmaz', () async {
      await configure();
      final source = SpyFinancialSource();

      final result = await access.guard(source.totalRevenueMinor);

      expect(
        source.queryCount,
        0,
        reason:
            'BR-AUTH-012: parola doğrulanmadan finansal sorgu çalıştırılamaz — '
            'arka planda hiçbir ciro/kâr verisi yüklenmez.',
      );
      expect(result, isA<Err<int>>());
      expect(
        result.failureOrNull?.code,
        FinancialAccessFailures.locked.code,
        reason: 'kilit hatası döndürülmelidir',
      );
    });

    test('kilit açılınca sorgu çalışır ve sonucu döner', () async {
      await configure();
      final source = SpyFinancialSource();

      await unlock();
      final result = await access.guard(source.totalRevenueMinor);

      expect(source.queryCount, 1, reason: 'kilit açıkken sorgu çalışmalıdır');
      expect((result as Ok<int>).value, 123400);
    });

    test('yanlış parola denemesi sorguyu çalıştırmaz', () async {
      await configure();
      final source = SpyFinancialSource();

      final attempt = await access.unlock('yanlis-parola');
      final result = await access.guard(source.totalRevenueMinor);

      expect(attempt, isA<Err<void>>());
      expect(
        source.queryCount,
        0,
        reason: 'BR-AUTH-012: başarısız denemeden sonra da sorgu çalışmaz',
      );
      expect(result, isA<Err<int>>());
    });

    test('FinancialGate kilit kapalıyken kaynağa erişim vermez', () async {
      await configure();
      final source = SpyFinancialSource();
      final gate = access.gate(source);

      final locked = await gate.run((s) => s.totalRevenueMinor());
      expect(
        source.queryCount,
        0,
        reason: 'BR-AUTH-012: kapı kapalıyken kaynak hiç kullanılmaz',
      );
      expect(locked, isA<Err<int>>());

      await unlock();
      final opened = await gate.run((s) => s.totalRevenueMinor());
      expect(source.queryCount, 1);
      expect((opened as Ok<int>).value, 123400);
    });

    test('parola kurulmamışken de sorgu çalıştırılmaz', () async {
      final source = SpyFinancialSource();

      final result = await access.guard(source.totalRevenueMinor);

      expect(source.queryCount, 0);
      expect(result.failureOrNull?.code, FinancialAccessFailures.locked.code);
    });
  });

  // --- Kurulum (REQ-AUTH-016/017) ------------------------------------------

  group('kurulum — REQ-AUTH-016/017 · BR-AUTH-009', () {
    test('başlangıçta parola kurulu değildir', () async {
      expect(await access.isConfigured(), isFalse);
    });

    test('setPassword hash + salt yazar ve isConfigured true olur', () async {
      await configure();

      expect(await access.isConfigured(), isTrue);
      expect(
        await settingsDao.read(AppSettingKeys.dashboardPasswordHash),
        isNotNull,
      );
      expect(
        await settingsDao.read(AppSettingKeys.dashboardPasswordSalt),
        isNotNull,
      );
    });

    test('EC-DASH-011 — boş parola reddedilir', () async {
      final result = await access.setPassword('');

      expect(
        result.failureOrNull?.code,
        FinancialAccessFailures.passwordRequired.code,
      );
      expect(await access.isConfigured(), isFalse);
    });

    test(
      'zaten kurulmuşsa setPassword reddedilir ve parola değişmez',
      () async {
        await configure();
        final hashBefore = await settingsDao.read(
          AppSettingKeys.dashboardPasswordHash,
        );

        final result = await access.setPassword('yeni-parola');

        expect(
          result.failureOrNull?.code,
          FinancialAccessFailures.alreadyConfigured.code,
        );
        expect(
          await settingsDao.read(AppSettingKeys.dashboardPasswordHash),
          hashBefore,
          reason: 'BR-AUTH-010: mevcut parola bilinmeden değiştirilemez',
        );
        // Eski parola hâlâ geçerli olmalıdır.
        await unlock();
      },
    );

    test(
      'BR-SEC-001 — düz metin parola app_settings içinde bulunmaz',
      () async {
        await configure();

        final rows = await db.select(db.appSettings).get();
        for (final row in rows) {
          expect(
            row.value.contains(dashboardPassword),
            isFalse,
            reason: 'BR-SEC-001: düz metin parola saklanamaz (${row.key})',
          );
        }
      },
    );

    test('EC-DASH-009 — kullanıcı parolasıyla aynı olabilir', () async {
      const shared = 'ayni-parola';
      final usersDao = UsersDao(db);
      final session = SessionService(
        settings: settingsDao,
        users: usersDao,
        clock: clock.fn,
      );
      final auth = AuthService(
        db: db,
        users: usersDao,
        session: session,
        financialAccess: access,
        hasher: PasswordHasher.withRandom(Random(3)),
        clock: clock.fn,
      );
      final created = await auth.createUser(
        username: 'kasa',
        password: shared,
        displayName: 'Kasa Görevlisi',
      );
      expect(created, isA<Ok<int>>());

      final result = await access.setPassword(shared);

      expect(
        result,
        isA<Ok<void>>(),
        reason: 'EC-DASH-009: izin verilir; engelleme yoktur',
      );
      // Her iki parola da bağımsız olarak çalışır.
      expect(await auth.login('kasa', shared), isA<Ok>());
      await unlock(shared);
    });
  });

  // --- Kilit açma (docs/17 §7) ---------------------------------------------

  group('kilit açma — docs/17 §7', () {
    test('doğru parola kilidi açar', () async {
      await configure();

      expect(access.isUnlocked, isFalse);
      await unlock();
      expect(access.isUnlocked, isTrue);
    });

    test('yanlış parola kilidi açmaz', () async {
      await configure();

      final result = await access.unlock('yanlis');

      expect(
        result.failureOrNull?.code,
        FinancialAccessFailures.wrongPassword.code,
      );
      expect(access.isUnlocked, isFalse);
    });

    test('parola kurulmamışsa uygun hata döner', () async {
      final result = await access.unlock(dashboardPassword);

      expect(
        result.failureOrNull?.code,
        FinancialAccessFailures.notConfigured.code,
      );
      expect(access.isUnlocked, isFalse);
    });

    test('hata mesajı parola/hash/salt sızdırmaz — rules/04 §8', () async {
      await configure();
      final hash = (await settingsDao.read(
        AppSettingKeys.dashboardPasswordHash,
      ))!;
      final salt = (await settingsDao.read(
        AppSettingKeys.dashboardPasswordSalt,
      ))!;

      final failure = (await access.unlock('yanlis')).failureOrNull!;
      final text = '${failure.userMessage} ${failure.code} $failure';

      expect(text.contains(dashboardPassword), isFalse);
      expect(text.contains('yanlis'), isFalse);
      expect(text.contains(hash), isFalse);
      expect(text.contains(salt), isFalse);
    });

    test('EC-DASH-003 — vazgeçmek kilidi açmaz', () async {
      await configure();

      // "Vazgeç": parola hiç denenmez; servis çağrılmaz.
      expect(
        access.isUnlocked,
        isFalse,
        reason: 'EC-DASH-003: kilit kapalı kalır',
      );
    });

    test(
      'EC-DASH-004/013 — bir kez açılınca oturum boyunca açık kalır',
      () async {
        await configure();
        await unlock();
        final source = SpyFinancialSource();

        // Dashboard → Satış ekranı → Raporlar gidiş gelişi: parola tekrar sorulmaz.
        await access.guard(source.totalRevenueMinor); // dashboard
        await access.guard(source.totalRevenueMinor); // raporlar

        expect(access.isUnlocked, isTrue);
        expect(source.queryCount, 2, reason: 'tek kilit her iki ekranı kapsar');
      },
    );

    test(
      'EC-DASH-006 — yeni servis örneği (uygulama restart) kilitli başlar',
      () async {
        await configure();
        await unlock();
        expect(access.isUnlocked, isTrue);

        // Uygulama kapanıp açıldı: yeni örnek, aynı veritabanı.
        final restarted = buildService(withThrottle: LoginThrottle());

        expect(
          restarted.isUnlocked,
          isFalse,
          reason: 'REQ-AUTH-021: kilit uygulama kapanışında sıfırlanır',
        );
        expect(
          await restarted.isConfigured(),
          isTrue,
          reason: 'parola kalıcıdır, kilit durumu değil',
        );
        final source = SpyFinancialSource();
        await restarted.guard(source.totalRevenueMinor);
        expect(source.queryCount, 0);
      },
    );

    test('BR-AUTH-016 — kilit durumu veritabanına YAZILMAZ', () async {
      await configure();
      final keysBefore = await settingKeys();

      await unlock();
      final keysAfterUnlock = await settingKeys();
      access.lock();
      final keysAfterLock = await settingKeys();

      expect(
        keysAfterUnlock,
        keysBefore,
        reason: 'BR-AUTH-016: kilit yalnızca bellekte tutulur',
      );
      expect(keysAfterLock, keysBefore);
      expect(keysBefore, {
        AppSettingKeys.dashboardPasswordHash,
        AppSettingKeys.dashboardPasswordSalt,
      }, reason: 'app_settings içinde kilit anahtarı bulunmamalıdır');
    });

    test('lock() kilidi kapatır ve sorgular yeniden engellenir', () async {
      await configure();
      await unlock();
      final source = SpyFinancialSource();

      access.lock();
      final result = await access.guard(source.totalRevenueMinor);

      expect(access.isUnlocked, isFalse);
      expect(source.queryCount, 0);
      expect(result, isA<Err<int>>());
    });
  });

  // --- Throttle (EC-DASH-002) ----------------------------------------------

  group('EC-DASH-002 — 5 yanlış denemede 30 sn bekleme', () {
    test('5. yanlış denemeden sonra bekleme uygulanır', () async {
      await configure();

      for (var i = 0; i < LoginThrottle.maxAttempts; i++) {
        final result = await access.unlock('yanlis');
        expect(
          result.failureOrNull?.code,
          FinancialAccessFailures.wrongPassword.code,
          reason: '${i + 1}. deneme henüz beklemeye girmemeliydi',
        );
      }

      final blocked = await access.unlock(dashboardPassword);
      expect(
        blocked.failureOrNull?.code,
        FinancialAccessFailures.tooManyAttempts(
          LoginThrottle.lockDuration,
        ).code,
        reason:
            'EC-DASH-002: doğru parola bile bekleme sırasında kabul edilmez',
      );
      expect(access.isUnlocked, isFalse);
    });

    test('bekleme sırasında sorgu yine çalıştırılmaz', () async {
      await configure();
      final source = SpyFinancialSource();

      for (var i = 0; i < LoginThrottle.maxAttempts; i++) {
        await access.unlock('yanlis');
      }
      await access.unlock(dashboardPassword);
      final result = await access.guard(source.totalRevenueMinor);

      expect(source.queryCount, 0);
      expect(result, isA<Err<int>>());
    });

    test('30 sn sonra doğru parola kilidi açar', () async {
      await configure();
      for (var i = 0; i < LoginThrottle.maxAttempts; i++) {
        await access.unlock('yanlis');
      }

      clock.advance(LoginThrottle.lockDuration + const Duration(seconds: 1));
      await unlock();

      expect(access.isUnlocked, isTrue);
    });

    test('BR-AUTH-008 — throttle kullanıcıya değil sisteme aittir', () async {
      await configure();

      // Dashboard parolası sistemde tektir: denemeler tek anahtarda toplanır.
      for (var i = 0; i < LoginThrottle.maxAttempts; i++) {
        await access.unlock('yanlis');
      }

      expect(
        throttle.remainingLock(
          FinancialAccessService.throttleKey,
          clock.current.toUtc(),
        ),
        isNotNull,
      );
      expect(throttle.trackedKeyCount, 1);
    });
  });

  // --- Parola değiştirme (docs/17 §9) --------------------------------------

  group('parola değiştirme — docs/17 §9 · BR-AUTH-010', () {
    test('doğru mevcut parola ile değişir; yeni parola geçerli olur', () async {
      await configure();

      final result = await access.changePassword(
        current: dashboardPassword,
        next: 'yeni-parola-2027',
      );

      expect(result, isA<Ok<void>>());
      expect(
        (await access.unlock(dashboardPassword)).failureOrNull?.code,
        FinancialAccessFailures.wrongPassword.code,
        reason: 'eski parola artık geçersizdir',
      );
      await unlock('yeni-parola-2027');
    });

    test('EC-DASH-008 — mevcut parola yanlışsa reddedilir', () async {
      await configure();
      final hashBefore = await settingsDao.read(
        AppSettingKeys.dashboardPasswordHash,
      );

      final result = await access.changePassword(
        current: 'yanlis',
        next: 'yeni-parola-2027',
      );

      expect(
        result.failureOrNull?.code,
        FinancialAccessFailures.currentPasswordWrong.code,
      );
      expect(
        await settingsDao.read(AppSettingKeys.dashboardPasswordHash),
        hashBefore,
        reason: 'EC-DASH-008: değişiklik hiç uygulanmaz',
      );
      await unlock();
    });

    test('boş yeni parola reddedilir', () async {
      await configure();

      final result = await access.changePassword(
        current: dashboardPassword,
        next: '',
      );

      expect(
        result.failureOrNull?.code,
        FinancialAccessFailures.passwordRequired.code,
      );
      await unlock();
    });

    test('parola kurulmamışken değiştirilemez', () async {
      final result = await access.changePassword(
        current: 'her-neyse',
        next: 'yeni',
      );

      expect(
        result.failureOrNull?.code,
        FinancialAccessFailures.notConfigured.code,
      );
      expect(await access.isConfigured(), isFalse);
    });

    test('parola değişimi kilit durumunu değiştirmez', () async {
      await configure();
      await unlock();

      await access.changePassword(
        current: dashboardPassword,
        next: 'yeni-parola-2027',
      );

      expect(
        access.isUnlocked,
        isTrue,
        reason: 'docs/17 §9 kilidi kapatmayı gerektirmez',
      );
    });

    test('yeni parola düz metin olarak saklanmaz — BR-SEC-001', () async {
      await configure();
      const next = 'yeni-parola-2027';

      await access.changePassword(current: dashboardPassword, next: next);

      final rows = await db.select(db.appSettings).get();
      for (final row in rows) {
        expect(row.value.contains(next), isFalse, reason: row.key);
      }
    });
  });

  // --- Audit (REQ-AUTH-020 · docs/18 §3) -----------------------------------

  group('REQ-AUTH-020 — kilit olayları audit log\'a yazılır', () {
    late int userId;

    setUp(() async {
      // `audit_logs.user_id` → `users.id` FK'sı gerçek bir kullanıcı ister.
      userId = await insertTestUser(db);
    });

    test('doğru parola → dashboardUnlocked (docs/22 F9)', () async {
      await configure();

      final result = await access.unlock(dashboardPassword, userId: userId);

      expect(result, isA<Ok<void>>());
      final logs = await auditRows();
      expect(logs, hasLength(1));
      expect(logs.single.action, FinancialAccessService.actionUnlocked);
      expect(logs.single.entityType, FinancialAccessService.auditEntityType);
      expect(logs.single.userId, userId);
      expect(
        logs.single.entityId,
        isNull,
        reason: 'docs/18 §2: sistem geneli varlıkta entity_id yoktur',
      );
      expect(
        logs.single.metadata,
        isNull,
        reason: 'docs/18 §3: dashboardUnlocked metadata taşımaz',
      );
      expect(logs.single.createdAt, clock.now().toUtc());
    });

    test('yanlış parola → dashboardUnlockFailed + deneme sayısı', () async {
      await configure();

      await access.unlock('yanlis', userId: userId);
      await access.unlock('yine-yanlis', userId: userId);

      final logs = await auditRows();
      expect(logs, hasLength(2));
      expect(
        logs.map((log) => log.action),
        everyElement(FinancialAccessService.actionUnlockFailed),
      );
      expect(
        logs.map((log) => jsonDecode(log.metadata!)),
        [
          {'attempts': 1},
          {'attempts': 2},
        ],
        reason: 'docs/18 §3: ardışık deneme sayısı',
      );
    });

    test('EC-DASH-002 — bekleme sırasındaki deneme kayıt üretmez', () async {
      await configure();

      for (var i = 0; i < LoginThrottle.maxAttempts; i++) {
        await access.unlock('yanlis', userId: userId);
      }
      // Bekleme başladı: parola artık **denenmiyor** bile.
      final blocked = await access.unlock(dashboardPassword, userId: userId);

      expect(
        blocked.failureOrNull?.code,
        FinancialAccessFailures.tooManyAttempts(
          LoginThrottle.lockDuration,
        ).code,
      );
      expect(
        await auditRows(),
        hasLength(LoginThrottle.maxAttempts),
        reason: 'yalnızca gerçekten denenen 5 parola kaydedilir',
      );
    });

    test('parola kurulmamışken deneme kayıt üretmez', () async {
      final result = await access.unlock(dashboardPassword, userId: userId);

      expect(
        result.failureOrNull?.code,
        FinancialAccessFailures.notConfigured.code,
      );
      expect(await auditRows(), isEmpty);
    });

    test('kurulum (setPassword) audit yazmaz', () async {
      await configure();

      expect(
        await auditRows(),
        isEmpty,
        reason:
            'docs/18 §3 kurulumda parola belirlemek için action tanımlamaz; '
            'dashboardPasswordChanged docs/17 §9 değiştirme akışına aittir',
      );
    });

    test('changePassword → dashboardPasswordChanged (docs/17 §9)', () async {
      await configure();

      final result = await access.changePassword(
        current: dashboardPassword,
        next: 'yeni-parola-2027',
        userId: userId,
      );

      expect(result, isA<Ok<void>>());
      final logs = await auditRows();
      expect(logs, hasLength(1));
      expect(logs.single.action, FinancialAccessService.actionPasswordChanged);
      expect(logs.single.userId, userId);
    });

    test('mevcut parola yanlışsa audit yazılmaz', () async {
      await configure();

      await access.changePassword(
        current: 'yanlis',
        next: 'yeni-parola-2027',
        userId: userId,
      );

      expect(
        await auditRows(),
        isEmpty,
        reason: 'EC-DASH-008: hiçbir şey değişmedi, denetlenecek olay yok',
      );
    });

    test(
      'REQ-AUDIT-004 · rules/04 §8 — kayıtlar parola/hash/salt taşımaz',
      () async {
        await configure();
        const next = 'yeni-parola-2027';

        await access.unlock('yanlis-deneme', userId: userId);
        await access.unlock(dashboardPassword, userId: userId);
        await access.changePassword(
          current: dashboardPassword,
          next: next,
          userId: userId,
        );

        final hash = (await settingsDao.read(
          AppSettingKeys.dashboardPasswordHash,
        ))!;
        final salt = (await settingsDao.read(
          AppSettingKeys.dashboardPasswordSalt,
        ))!;
        final secrets = <String>[
          dashboardPassword,
          next,
          'yanlis-deneme',
          hash,
          salt,
        ];

        final logs = await auditRows();
        expect(logs, hasLength(3));
        for (final log in logs) {
          final serialized = [
            log.action,
            log.entityType,
            log.oldValue ?? '',
            log.newValue ?? '',
            log.metadata ?? '',
          ].join('|');
          for (final secret in secrets) {
            expect(
              serialized,
              isNot(contains(secret)),
              reason:
                  'rules/04 §8: audit kaydı parola/hash/salt taşıyamaz '
                  '(${log.action})',
            );
          }
        }
      },
    );

    test('REQ-AUDIT-007 — audit patlarsa kilit yine açılır', () async {
      await configure();
      final broken = buildService(audit: _FailingAuditLogsDao(db));

      final result = await broken.unlock(dashboardPassword, userId: userId);

      expect(
        result,
        isA<Ok<void>>(),
        reason: 'docs/18 §7: audit hatası ana işlemi başarısız kılmaz',
      );
      expect(broken.isUnlocked, isTrue);
      expect(await auditRows(), isEmpty);
    });

    test('REQ-AUDIT-007 — audit patlarsa parola yine değişir', () async {
      await configure();
      final broken = buildService(audit: _FailingAuditLogsDao(db));

      final result = await broken.changePassword(
        current: dashboardPassword,
        next: 'yeni-parola-2027',
        userId: userId,
      );

      expect(result, isA<Ok<void>>());
      expect(
        (await access.unlock('yeni-parola-2027')).isOk,
        isTrue,
        reason:
            'audit kaydı parola yazımıyla aynı transaction içindedir; hatası '
            'yukarı taşınsaydı parola değişikliği de geri alınırdı',
      );
    });

    test('userId verilmezse kayıt yine yazılır (docs/18 §2)', () async {
      await configure();

      await access.unlock(dashboardPassword);

      final logs = await auditRows();
      expect(logs, hasLength(1));
      expect(logs.single.userId, isNull);
    });
  });

  // --- Logout bağlantısı (REQ-AUTH-004) ------------------------------------

  group('EC-DASH-005 — logout kilidi kapatır (REQ-AUTH-004)', () {
    late AuthService auth;
    late SessionService session;

    setUp(() {
      final usersDao = UsersDao(db);
      session = SessionService(
        settings: settingsDao,
        users: usersDao,
        clock: clock.fn,
      );
      auth = AuthService(
        db: db,
        users: usersDao,
        session: session,
        hasher: PasswordHasher.withRandom(Random(5)),
        financialAccess: access,
        clock: clock.fn,
      );
    });

    Future<void> createAndLogin() async {
      final created = await auth.createUser(
        username: 'kasa',
        password: 'kantin-2026',
        displayName: 'Kasa Görevlisi',
      );
      expect(created, isA<Ok<int>>());
      expect(await auth.login('kasa', 'kantin-2026'), isA<Ok>());
    }

    test('BR-AUTH-016 — kilit BAŞKA kullanıcıya DEVREDİLMEZ', () async {
      // Kilit oturum kapsamlıdır. Oturum logout dışı bir yolla düşerse
      // (pasifleştirme, bozuk oturum, Faz 9 restore) kilidin açık kalması
      // sıradaki kullanıcıya parolasız Dashboard verirdi.
      final usersDao = UsersDao(db);
      expect(
        await auth.createUser(
          username: 'a',
          password: 'parola-a',
          displayName: 'A',
        ),
        isA<Ok<int>>(),
      );
      expect(
        await auth.createUser(
          username: 'b',
          password: 'parola-b',
          displayName: 'B',
        ),
        isA<Ok<int>>(),
      );
      expect(await usersDao.countActive(), 2);
      await configure();

      await auth.login('a', 'parola-a');
      expect((await access.unlock(dashboardPassword)).isOk, isTrue);
      expect(access.isUnlocked, isTrue);

      // A kendini pasifleştirir — logout YOK, son aktif kullanıcı da değil.
      final aId = (await usersDao.findByUsername('a'))!.id;
      expect((await auth.setActive(aId, false)).isOk, isTrue);
      expect(
        access.isUnlocked,
        isFalse,
        reason: 'Oturum düştüğü anda kilit de kapanmalı.',
      );

      // B giriş yapar — kilit yine kapalı olmalı.
      expect((await auth.login('b', 'parola-b')).isOk, isTrue);
      expect(
        access.isUnlocked,
        isFalse,
        reason:
            'BR-AUTH-012/016: B dashboard parolasını girmeden finansal veri '
            'göremez.',
      );

      final leaked = await access.guard(() async => 'ciro');
      expect(
        leaked.isErr,
        isTrue,
        reason: 'Sorgu çalışmamalı — kilit devredilemez.',
      );
    });

    test('logout finansal kilidi kapatır ve oturumu temizler', () async {
      await configure();
      await createAndLogin();
      await unlock();
      final source = SpyFinancialSource();

      await auth.logout();

      expect(access.isUnlocked, isFalse, reason: 'REQ-AUTH-004');
      expect(await auth.currentUser(), isNull);
      final result = await access.guard(source.totalRevenueMinor);
      expect(source.queryCount, 0);
      expect(result, isA<Err<int>>());
    });

    test('tekrar giriş kilidi kendiliğinden açmaz', () async {
      await configure();
      await createAndLogin();
      await unlock();
      await auth.logout();

      expect(await auth.login('kasa', 'kantin-2026'), isA<Ok>());

      expect(
        access.isUnlocked,
        isFalse,
        reason: 'EC-DASH-005: dashboard parolası tekrar sorulur',
      );
    });
  });

  // --- Kilit dışı işlemler (BR-AUTH-014) -----------------------------------

  test('EC-DASH-014 — kilit dışı işlemler etkilenmez', () async {
    await configure();
    final usersDao = UsersDao(db);
    final session = SessionService(
      settings: settingsDao,
      users: usersDao,
      clock: clock.fn,
    );
    final auth = AuthService(
      db: db,
      users: usersDao,
      session: session,
      hasher: PasswordHasher.withRandom(Random(9)),
      financialAccess: access,
      clock: clock.fn,
    );
    await auth.createUser(
      username: 'kasa',
      password: 'kantin-2026',
      displayName: 'Kasa Görevlisi',
    );

    // Kilit KAPALIYKEN: giriş, ürün okuma ve ayar okuma sorunsuz çalışır —
    // dashboard parolası hiçbir yerde istenmez (BR-AUTH-014).
    expect(access.isUnlocked, isFalse);
    expect(await auth.login('kasa', 'kantin-2026'), isA<Ok>());

    final productId = await insertTestProduct(db);
    final products = await db.select(db.products).get();
    expect(products.single.id, productId);
    expect(await db.select(db.categories).get(), isNotEmpty);
  });
}
