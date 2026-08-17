/// RecoveryCodeService testleri — **docs/17 §8 · EC-REC-001…012 ·
/// BR-AUTH-015/017 · REQ-AUTH-022…028**
///
/// docs/27 §4: gerçek in-memory SQLite üzerinde çalışır.
/// Test önceliği rules/06 §2 → **Authentication** 🔴.
///
/// En kritik iki test:
///   * EC-REC-004 — dört adım **tek transaction**
///   * EC-REC-005 — hata enjekte → **tam rollback**: eski parola VE eski kod
///     hâlâ geçerli
library;

import 'dart:convert';
import 'dart:math';

import 'package:canteen/application/auth/financial_access_failures.dart';
import 'package:canteen/application/auth/financial_access_service.dart';
import 'package:canteen/application/auth/login_throttle.dart';
import 'package:canteen/application/auth/recovery_code_failures.dart';
import 'package:canteen/application/auth/recovery_code_service.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/app_setting_keys.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, Sale, SaleItem, StockMovement;
import 'package:canteen/domain/services/password_hasher.dart';
import 'package:canteen/domain/services/recovery_code.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

/// Enjekte edilen hata — gerçek bir arıza gibi transaction'ı düşürür.
class _InjectedFailure implements Exception {
  const _InjectedFailure();
  @override
  String toString() => 'enjekte edilmiş hata';
}

/// Belirlenen `app_settings` anahtarına yazarken patlayan DAO.
///
/// EC-REC-005 için: kurtarmanın **ortasında** hata üretir, böylece daha önce
/// yazılmış adımların geri alınıp alınmadığı görülür.
class _FailingSettingsDao extends AppSettingsDao {
  _FailingSettingsDao(super.db, {required this.failOnKey});

  final String failOnKey;

  @override
  Future<void> write(String key, String value) {
    if (key == failOnKey) throw const _InjectedFailure();
    return super.write(key, value);
  }
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
  const newPassword = 'yeni-panel-2027';

  late FakeClock clock;
  late CanteenDatabase db;
  late AppSettingsDao settingsDao;
  late AuditLogsDao auditDao;
  late LoginThrottle financialThrottle;
  late LoginThrottle recoveryThrottle;
  late FinancialAccessService access;
  late RecoveryCodeService recovery;

  FinancialAccessService buildAccess({
    AppSettingsDao? settings,
    AuditLogsDao? audit,
  }) => FinancialAccessService(
    db: db,
    settings: settings ?? settingsDao,
    auditLogs: audit ?? auditDao,
    // Deterministik salt üretimi (rules/06 §7).
    hasher: PasswordHasher.withRandom(Random(11)),
    throttle: financialThrottle,
    clock: clock.fn,
  );

  RecoveryCodeService buildRecovery({
    AppSettingsDao? settings,
    AuditLogsDao? audit,
    FinancialAccessService? financialAccess,
    int randomSeed = 23,
  }) => RecoveryCodeService(
    db: db,
    settings: settings ?? settingsDao,
    auditLogs: audit ?? auditDao,
    financialAccess: financialAccess ?? access,
    hasher: PasswordHasher.withRandom(Random(37)),
    throttle: recoveryThrottle,
    random: Random(randomSeed),
    clock: clock.fn,
  );

  setUp(() {
    clock = FakeClock(testEpochUtc);
    db = memoryDatabase(clock: clock.fn);
    settingsDao = AppSettingsDao(db);
    auditDao = AuditLogsDao(db);
    financialThrottle = LoginThrottle();
    recoveryThrottle = LoginThrottle();
    access = buildAccess();
    recovery = buildRecovery();
  });

  tearDown(() => db.close());

  String okValue(Result<String> result) {
    expect(
      result,
      isA<Ok<String>>(),
      reason: 'beklenen: Ok — ${result.failureOrNull}',
    );
    return (result as Ok<String>).value;
  }

  Failure errOf(Result<Object?> result) {
    expect(result, isA<Err<Object?>>(), reason: 'beklenen: Err');
    final failure = result.failureOrNull;
    return failure!;
  }

  /// Kurulum: dashboard parolası + ilk kurtarma kodu.
  Future<String> setUpDashboard() async {
    expect((await access.setPassword(dashboardPassword)).isOk, isTrue);
    return okValue(await recovery.generateInitial());
  }

  Future<List<AppSetting>> settingRows() => db.select(db.appSettings).get();

  Future<List<AuditLog>> auditRows() => db.select(db.auditLogs).get();

  /// Yalnızca **kurtarma** olayları.
  ///
  /// `FinancialAccessService` artık kilit olaylarını da aynı tabloya yazıyor
  /// (REQ-AUTH-020: `dashboardUnlocked` / `dashboardUnlockFailed`). Bu testler
  /// kurtarma akışını doğruladığı için, doğrulamanın parçası olarak yapılan
  /// `access.unlock(...)` çağrılarının ürettiği kayıtlar elenir — aksi hâlde
  /// "kurtarma hiçbir kayıt bırakmadı" iddiası ölçülemez hâle gelirdi.
  Future<List<AuditLog>> recoveryAuditRows() async {
    final rows = await auditRows();
    return rows
        .where(
          (row) => const {
            RecoveryCodeService.actionRecoveryUsed,
            RecoveryCodeService.actionRecoveryFailed,
            RecoveryCodeService.actionRecoveryRegenerated,
          }.contains(row.action),
        )
        .toList();
  }

  /// Bir metnin veritabanının hiçbir `app_settings` değerinde geçmediğini
  /// doğrular (BR-SEC-001 · REQ-AUTH-023).
  Future<void> expectAbsentFromSettings(String secret) async {
    final canonical = RecoveryCode.normalize(secret) ?? secret;
    for (final row in await settingRows()) {
      expect(
        row.value,
        isNot(contains(secret)),
        reason: 'app_settings["${row.key}"] düz metin sır içeriyor',
      );
      expect(row.value, isNot(contains(canonical)));
    }
  }

  // --- Kurulum sihirbazı Adım 3 (REQ-AUTH-022/023) --------------------------

  group('generateInitial — kurulum sihirbazı Adım 3', () {
    test('XXXX-XXXX-XXXX-XXXX biçiminde kod üretir', () async {
      final code = okValue(await recovery.generateInitial());

      expect(code, matches(RegExp(r'^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$')));
      expect(
        code,
        isNot(matches(RegExp('[01ILO]'))),
        reason: 'REQ-AUTH-022: 0/O ve 1/I/l karışma riski taşıyan karakterler',
      );
    });

    test('düz metin kod veritabanına YAZILMAZ — yalnızca hash', () async {
      final code = okValue(await recovery.generateInitial());

      final keys = {for (final row in await settingRows()) row.key};
      expect(keys, contains(AppSettingKeys.dashboardRecoveryHash));
      expect(keys, contains(AppSettingKeys.dashboardRecoverySalt));
      expect(
        keys,
        isNot(contains(AppSettingKeys.dashboardRecoveryUsedAt)),
        reason: 'Yeni kod kullanılmamıştır',
      );

      await expectAbsentFromSettings(code);
    });

    test('kod zaten üretilmişse reddedilir; mevcut kod bozulmaz', () async {
      final code = okValue(await recovery.generateInitial());
      final before = await settingRows();

      final failure = errOf(await recovery.generateInitial());
      expect(failure.code, RecoveryCodeFailures.alreadyConfigured.code);

      expect(
        {for (final row in await settingRows()) row.key: row.value},
        {for (final row in before) row.key: row.value},
      );
      await access.setPassword(dashboardPassword);
      expect(
        (await recovery.resetPasswordWithCode(
          code: code,
          newPassword: newPassword,
        )).isOk,
        isTrue,
        reason: 'mevcut kod geçerli kalmalı',
      );
    });
  });

  // --- EC-REC-012 -----------------------------------------------------------

  group('EC-REC-012 — recovery kaydı hiç yok', () {
    test('isAvailable false; "Şifremi unuttum" gösterilmez', () async {
      expect(await recovery.isConfigured(), isFalse);
      expect(await recovery.isAvailable(), isFalse);
    });

    test('kurtarma denenirse notConfigured döner', () async {
      await access.setPassword(dashboardPassword);

      final failure = errOf(
        await recovery.resetPasswordWithCode(
          code: 'ABCD-EFGH-JKMN-PQRS',
          newPassword: newPassword,
        ),
      );

      expect(failure.code, RecoveryCodeFailures.notConfigured.code);
      expect(
        await access.unlock(dashboardPassword),
        isA<Ok<void>>(),
        reason: 'Parola değiştirme/giriş yolu açık kalır',
      );
    });

    test('kod üretilmişse isAvailable true', () async {
      await recovery.generateInitial();
      expect(await recovery.isAvailable(), isTrue);
    });

    test('kod kullanılmış işaretliyse isAvailable false', () async {
      await recovery.generateInitial();
      await settingsDao.write(
        AppSettingKeys.dashboardRecoveryUsedAt,
        clock.now().millisecondsSinceEpoch.toString(),
      );

      expect(await recovery.isConfigured(), isTrue);
      expect(await recovery.isAvailable(), isFalse);
    });
  });

  // --- EC-REC-001 / 004 -----------------------------------------------------

  group('EC-REC-001 · EC-REC-004 — başarılı kurtarma', () {
    test('doğru kod parolayı sıfırlar ve YENİ kod döndürür', () async {
      final code = await setUpDashboard();

      final next = okValue(
        await recovery.resetPasswordWithCode(
          code: code,
          newPassword: newPassword,
        ),
      );

      expect(next, matches(RegExp(r'^[A-Z2-9]{4}(-[A-Z2-9]{4}){3}$')));
      expect(next, isNot(code), reason: 'BR-AUTH-017: YENİ kod üretilir');

      // Yeni parola geçerli, eskisi değil.
      access.lock();
      expect((await access.unlock(newPassword)).isOk, isTrue);
      access.lock();
      expect(
        errOf(await access.unlock(dashboardPassword)).code,
        FinancialAccessFailures.wrongPassword.code,
      );
    });

    test(
      'dört adım da uygulanır — parola · eski kod · yeni kod · audit',
      () async {
        final code = await setUpDashboard();
        final hashBefore = await settingsDao.read(
          AppSettingKeys.dashboardRecoveryHash,
        );

        final next = okValue(
          await recovery.resetPasswordWithCode(
            code: code,
            newPassword: newPassword,
            userId: null,
          ),
        );

        // 1) parola güncellendi
        access.lock();
        expect((await access.unlock(newPassword)).isOk, isTrue);

        // 2) eski kod geçersiz — hash üzerine yazıldı, bir daha doğrulanamaz
        expect(
          await settingsDao.read(AppSettingKeys.dashboardRecoveryHash),
          isNot(hashBefore),
        );

        // 3) yeni kod kullanılabilir durumda
        expect(await recovery.isAvailable(), isTrue);
        expect(next, isNotEmpty);

        // 4) audit yazıldı
        final logs = await recoveryAuditRows();
        expect(logs, hasLength(1));
        expect(logs.single.action, RecoveryCodeService.actionRecoveryUsed);
        expect(logs.single.entityType, RecoveryCodeService.auditEntityType);
        expect(logs.single.createdAt, clock.now().toUtc());
      },
    );

    test('BR-AUTH-015 — kullanılan kod bir daha çalışmaz', () async {
      final code = await setUpDashboard();
      await recovery.resetPasswordWithCode(
        code: code,
        newPassword: newPassword,
      );

      final failure = errOf(
        await recovery.resetPasswordWithCode(
          code: code,
          newPassword: 'ucuncu-parola',
        ),
      );
      expect(failure.code, RecoveryCodeFailures.invalidCode.code);

      // Parola değişmedi.
      access.lock();
      expect((await access.unlock(newPassword)).isOk, isTrue);
    });

    test('BR-AUTH-017 — YENİ kod ikinci kurtarmada çalışır', () async {
      final code = await setUpDashboard();
      final second = okValue(
        await recovery.resetPasswordWithCode(
          code: code,
          newPassword: newPassword,
        ),
      );

      final third = okValue(
        await recovery.resetPasswordWithCode(
          code: second,
          newPassword: 'ucuncu-parola',
        ),
      );

      expect(third, isNot(second));
      access.lock();
      expect((await access.unlock('ucuncu-parola')).isOk, isTrue);
    });

    test('başarılı kurtarma finansal kilidi AÇAR — docs/17 §8', () async {
      final code = await setUpDashboard();
      expect(access.isUnlocked, isFalse);

      await recovery.resetPasswordWithCode(
        code: code,
        newPassword: newPassword,
      );

      expect(access.isUnlocked, isTrue);
    });

    test('kilit açılışı dashboard bekleme sayacına takılmaz', () async {
      final code = await setUpDashboard();

      // Kullanıcı parolayı unuttu: 5 hatalı deneme → 30 sn bekleme.
      for (var i = 0; i < LoginThrottle.maxAttempts; i++) {
        await access.unlock('yanlis-$i');
      }
      expect(
        errOf(await access.unlock(dashboardPassword)).code,
        FinancialAccessFailures.tooManyAttempts(
          const Duration(seconds: 30),
        ).code,
      );

      await recovery.resetPasswordWithCode(
        code: code,
        newPassword: newPassword,
      );

      expect(access.isUnlocked, isTrue);
      access.lock();
      expect(
        (await access.unlock(newPassword)).isOk,
        isTrue,
        reason: 'Kurtarma sonrası sayaç sıfırlanır',
      );
    });
  });

  // --- EC-REC-002 -----------------------------------------------------------

  group('EC-REC-002 — kullanılmış kod', () {
    test('ayırt edici mesajla reddedilir', () async {
      final code = await setUpDashboard();
      // Kullanılmış durum: restore veya yarım kalmış eski kurulum
      // (EC-REC-010) — hash yerinde ama kod tüketilmiş.
      await settingsDao.write(
        AppSettingKeys.dashboardRecoveryUsedAt,
        clock.now().millisecondsSinceEpoch.toString(),
      );

      final failure = errOf(
        await recovery.resetPasswordWithCode(
          code: code,
          newPassword: newPassword,
        ),
      );

      expect(failure.code, RecoveryCodeFailures.alreadyUsed.code);
      expect(failure.userMessage, contains('daha önce kullanılmış'));
      expect(
        failure.code,
        isNot(RecoveryCodeFailures.invalidCode.code),
        reason: 'docs/17 §8 akış diyagramı bu dalı yanlış koddan ayırır',
      );

      // Parola değişmedi.
      expect((await access.unlock(dashboardPassword)).isOk, isTrue);
    });

    test('yanlış kod, kullanılmışlık bilgisini SIZDIRMAZ', () async {
      await setUpDashboard();
      await settingsDao.write(
        AppSettingKeys.dashboardRecoveryUsedAt,
        clock.now().millisecondsSinceEpoch.toString(),
      );

      final failure = errOf(
        await recovery.resetPasswordWithCode(
          code: 'ABCD-EFGH-JKMN-PQRS',
          newPassword: newPassword,
        ),
      );

      expect(
        failure.code,
        RecoveryCodeFailures.invalidCode.code,
        reason: 'Kodu bilmeyen biri "bu kod kullanılmış" bilgisini almamalı',
      );
    });
  });

  // --- EC-REC-003 -----------------------------------------------------------

  group('EC-REC-003 — hatalı deneme sayacı', () {
    test('5 yanlış kod → 30 sn bekleme', () async {
      await setUpDashboard();

      for (var i = 0; i < LoginThrottle.maxAttempts; i++) {
        final failure = errOf(
          await recovery.resetPasswordWithCode(
            code: 'ABCD-EFGH-JKMN-PQR$i',
            newPassword: newPassword,
          ),
        );
        expect(failure.code, RecoveryCodeFailures.invalidCode.code);
      }

      final failure = errOf(
        await recovery.resetPasswordWithCode(
          code: 'ABCD-EFGH-JKMN-PQRS',
          newPassword: newPassword,
        ),
      );
      expect(
        failure.code,
        RecoveryCodeFailures.tooManyAttempts
            .call(const Duration(seconds: 30))
            .code,
      );
      expect(failure.userMessage, contains('30 saniye'));
    });

    test('bekleme dolunca yeniden denenebilir', () async {
      final code = await setUpDashboard();
      for (var i = 0; i < LoginThrottle.maxAttempts; i++) {
        await recovery.resetPasswordWithCode(
          code: 'ABCD-EFGH-JKMN-PQR$i',
          newPassword: newPassword,
        );
      }

      clock.advance(LoginThrottle.lockDuration + const Duration(seconds: 1));

      expect(
        (await recovery.resetPasswordWithCode(
          code: code,
          newPassword: newPassword,
        )).isOk,
        isTrue,
      );
    });

    test(
      'hatalı denemeler audit log\'a yazılır — kod değeri YAZILMAZ',
      () async {
        await setUpDashboard();
        const wrong = 'ABCD-EFGH-JKMN-PQRS';

        await recovery.resetPasswordWithCode(
          code: wrong,
          newPassword: newPassword,
        );

        final logs = await auditRows();
        expect(logs, hasLength(1));
        expect(logs.single.action, RecoveryCodeService.actionRecoveryFailed);
        expect(
          jsonDecode(logs.single.metadata!),
          {'attempts': 1},
          reason: 'docs/18 §3: ardışık deneme sayısı',
        );
        expect(logs.single.metadata, isNot(contains('ABCD')));
      },
    );

    test('biçimsiz kod ile yanlış kod AYNI mesajı alır', () async {
      await setUpDashboard();

      final malformed = errOf(
        await recovery.resetPasswordWithCode(
          code: 'not-a-code',
          newPassword: newPassword,
        ),
      );
      final wrong = errOf(
        await recovery.resetPasswordWithCode(
          code: 'ABCD-EFGH-JKMN-PQRS',
          newPassword: newPassword,
        ),
      );

      expect(malformed.code, wrong.code);
      expect(malformed.userMessage, wrong.userMessage);
    });

    test('başarılı kurtarma sayacı sıfırlar', () async {
      final code = await setUpDashboard();
      for (var i = 0; i < LoginThrottle.maxAttempts - 1; i++) {
        await recovery.resetPasswordWithCode(
          code: 'ABCD-EFGH-JKMN-PQR$i',
          newPassword: newPassword,
        );
      }

      final next = okValue(
        await recovery.resetPasswordWithCode(
          code: code,
          newPassword: newPassword,
        ),
      );
      expect(recoveryThrottle.failureCount(RecoveryCodeService.throttleKey), 0);
      expect(next, isNotEmpty);
    });
  });

  // --- EC-REC-005 — TAM ROLLBACK -------------------------------------------

  group('EC-REC-005 — hata enjeksiyonu: tam rollback', () {
    test(
      'yeni kod yazımı patlarsa eski parola VE eski kod geçerli kalır',
      () async {
        final code = await setUpDashboard();
        final hashBefore = await settingsDao.read(
          AppSettingKeys.dashboardRecoveryHash,
        );

        // Adım 3'te (yeni kod yazımı) patlar: adım 1 (parola) ve adım 2
        // (used_at) o ana kadar yazılmıştır — geri alınmaları gerekir.
        final failingSettings = _FailingSettingsDao(
          db,
          failOnKey: AppSettingKeys.dashboardRecoveryHash,
        );
        final brokenRecovery = buildRecovery(
          settings: failingSettings,
          financialAccess: buildAccess(settings: failingSettings),
        );

        await expectLater(
          brokenRecovery.resetPasswordWithCode(
            code: code,
            newPassword: newPassword,
          ),
          throwsA(isA<_InjectedFailure>()),
        );

        // 1) Eski dashboard parolası hâlâ geçerli.
        expect(
          (await access.unlock(dashboardPassword)).isOk,
          isTrue,
          reason: 'EC-REC-005: parola güncellemesi geri alınmalı',
        );
        access.lock();
        expect(
          errOf(await access.unlock(newPassword)).code,
          FinancialAccessFailures.wrongPassword.code,
        );

        // 2) Eski kod hâlâ geçerli: hash değişmedi ve used_at yazılmadı.
        expect(
          await settingsDao.read(AppSettingKeys.dashboardRecoveryHash),
          hashBefore,
        );
        expect(
          await settingsDao.read(AppSettingKeys.dashboardRecoveryUsedAt),
          isNull,
          reason: 'Adım 2 de geri alınmalı — kod tüketilmiş sayılamaz',
        );
        expect(await recovery.isAvailable(), isTrue);

        // 3) Audit kaydı oluşmadı (REQ-AUDIT-006).
        expect(await recoveryAuditRows(), isEmpty);

        // 4) Kilit açılmadı.
        access.lock();
        expect(access.isUnlocked, isFalse);

        // 5) Eski kod gerçekten çalışıyor.
        expect(
          (await recovery.resetPasswordWithCode(
            code: code,
            newPassword: newPassword,
          )).isOk,
          isTrue,
        );
      },
    );

    test('parola yazımı patlarsa hiçbir adım uygulanmaz', () async {
      final code = await setUpDashboard();

      final failingSettings = _FailingSettingsDao(
        db,
        failOnKey: AppSettingKeys.dashboardPasswordHash,
      );
      final brokenRecovery = buildRecovery(
        settings: failingSettings,
        financialAccess: buildAccess(settings: failingSettings),
      );

      await expectLater(
        brokenRecovery.resetPasswordWithCode(
          code: code,
          newPassword: newPassword,
        ),
        throwsA(isA<_InjectedFailure>()),
      );

      expect((await access.unlock(dashboardPassword)).isOk, isTrue);
      expect(await recovery.isAvailable(), isTrue);
      expect(await recoveryAuditRows(), isEmpty);
      expect(
        (await recovery.resetPasswordWithCode(
          code: code,
          newPassword: newPassword,
        )).isOk,
        isTrue,
      );
    });

    test(
      'REQ-AUDIT-007 — audit yazımı patlarsa kurtarma BAŞARILI kalır',
      () async {
        final code = await setUpDashboard();
        final brokenAudit = buildRecovery(audit: _FailingAuditLogsDao(db));

        final next = okValue(
          await brokenAudit.resetPasswordWithCode(
            code: code,
            newPassword: newPassword,
          ),
        );

        expect(next, isNotEmpty);
        access.lock();
        expect(
          (await access.unlock(newPassword)).isOk,
          isTrue,
          reason: 'docs/18 §7: audit hatası ana işlemi başarısız kılmaz',
        );
        expect(await recoveryAuditRows(), isEmpty);
      },
    );
  });

  // --- EC-REC-011 -----------------------------------------------------------

  group('EC-REC-011 — normalizasyon', () {
    test('küçük harf · tiresiz · boşluklu kod kabul edilir', () async {
      for (final transform in <String Function(String)>[
        (code) => code.toLowerCase(),
        (code) => code.replaceAll('-', ''),
        (code) => code.replaceAll('-', ' '),
        (code) => '  ${code.toLowerCase().replaceAll('-', '')}  ',
      ]) {
        clock = FakeClock(testEpochUtc);
        await db.close();
        db = memoryDatabase(clock: clock.fn);
        settingsDao = AppSettingsDao(db);
        auditDao = AuditLogsDao(db);
        financialThrottle = LoginThrottle();
        recoveryThrottle = LoginThrottle();
        access = buildAccess();
        recovery = buildRecovery();

        final code = await setUpDashboard();
        expect(
          (await recovery.resetPasswordWithCode(
            code: transform(code),
            newPassword: newPassword,
          )).isOk,
          isTrue,
          reason: 'EC-REC-011: "${transform(code)}" kabul edilmeliydi',
        );
      }
    });
  });

  // --- EC-REC-008 / 009 — Ayarlar'dan yenileme ------------------------------

  group('EC-REC-008 · EC-REC-009 — regenerate', () {
    test('parola doğruysa yeni kod üretilir, eskisi geçersizleşir', () async {
      final code = await setUpDashboard();

      final next = okValue(
        await recovery.regenerate(currentPassword: dashboardPassword),
      );

      expect(next, isNot(code));

      // Eski kod artık çalışmaz.
      expect(
        errOf(
          await recovery.resetPasswordWithCode(
            code: code,
            newPassword: newPassword,
          ),
        ).code,
        RecoveryCodeFailures.invalidCode.code,
      );

      // Yenisi çalışır.
      expect(
        (await recovery.resetPasswordWithCode(
          code: next,
          newPassword: newPassword,
        )).isOk,
        isTrue,
      );
    });

    test('parola yanlışsa reddedilir; ESKİ kod geçerli kalır', () async {
      final code = await setUpDashboard();

      final failure = errOf(
        await recovery.regenerate(currentPassword: 'yanlis-parola'),
      );
      expect(failure.code, FinancialAccessFailures.currentPasswordWrong.code);
      expect(await auditRows(), isEmpty);

      expect(
        (await recovery.resetPasswordWithCode(
          code: code,
          newPassword: newPassword,
        )).isOk,
        isTrue,
        reason: 'EC-REC-008: eski kod geçerli kalır',
      );
    });

    test('regenerate finansal kilidi AÇMAZ', () async {
      await setUpDashboard();
      await recovery.regenerate(currentPassword: dashboardPassword);
      expect(access.isUnlocked, isFalse);
    });

    test('audit yazılır — kod değeri YAZILMAZ', () async {
      await setUpDashboard();
      final next = okValue(
        await recovery.regenerate(currentPassword: dashboardPassword),
      );

      final logs = await auditRows();
      expect(logs, hasLength(1));
      expect(logs.single.action, RecoveryCodeService.actionRecoveryRegenerated);
      expect(
        logs.single.metadata ?? '',
        isNot(contains(next.split('-').first)),
      );
    });

    test('dashboard parolası yoksa notConfigured', () async {
      await recovery.generateInitial();
      final failure = errOf(
        await recovery.regenerate(currentPassword: dashboardPassword),
      );
      expect(failure.code, FinancialAccessFailures.notConfigured.code);
    });
  });

  // --- BR-SEC-001 — sızıntı yok --------------------------------------------

  group('BR-SEC-001 · REQ-AUDIT-004 — düz metin sızıntısı yok', () {
    test('audit kayıtlarında kod, parola, hash veya salt bulunmaz', () async {
      final code = await setUpDashboard();
      final next = okValue(
        await recovery.resetPasswordWithCode(
          code: code,
          newPassword: newPassword,
          userId: null,
        ),
      );
      // Bir de başarısız deneme.
      await recovery.resetPasswordWithCode(
        code: 'ABCD-EFGH-JKMN-PQRS',
        newPassword: newPassword,
      );

      final storedHash = (await settingsDao.read(
        AppSettingKeys.dashboardRecoveryHash,
      ))!;
      final storedSalt = (await settingsDao.read(
        AppSettingKeys.dashboardRecoverySalt,
      ))!;
      final passwordHash = (await settingsDao.read(
        AppSettingKeys.dashboardPasswordHash,
      ))!;
      final passwordSalt = (await settingsDao.read(
        AppSettingKeys.dashboardPasswordSalt,
      ))!;

      final secrets = <String>[
        code,
        RecoveryCode.normalize(code)!,
        next,
        RecoveryCode.normalize(next)!,
        dashboardPassword,
        newPassword,
        storedHash,
        storedSalt,
        passwordHash,
        passwordSalt,
      ];

      final logs = await auditRows();
      expect(logs, hasLength(2));

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
                'rules/04 §8: audit kaydı parola/kod/hash/salt taşıyamaz '
                '(${log.action})',
          );
        }
      }
    });

    test('veritabanında düz metin kod bulunmaz', () async {
      final code = await setUpDashboard();
      final next = okValue(
        await recovery.resetPasswordWithCode(
          code: code,
          newPassword: newPassword,
        ),
      );

      await expectAbsentFromSettings(code);
      await expectAbsentFromSettings(next);
      await expectAbsentFromSettings(dashboardPassword);
      await expectAbsentFromSettings(newPassword);
    });
  });

  // --- Girdi doğrulaması ----------------------------------------------------

  test('yeni parola boşsa reddedilir; kod harcanmaz', () async {
    final code = await setUpDashboard();

    final failure = errOf(
      await recovery.resetPasswordWithCode(code: code, newPassword: ''),
    );
    expect(failure.code, FinancialAccessFailures.passwordRequired.code);

    expect(await recovery.isAvailable(), isTrue);
    expect(
      (await recovery.resetPasswordWithCode(
        code: code,
        newPassword: newPassword,
      )).isOk,
      isTrue,
    );
  });
}
