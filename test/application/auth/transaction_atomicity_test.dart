/// Transaction atomikliği — **rules/06 §2 · rules/01 §5**
///
/// `rules/06 §2` bu testleri zorunlu kılar: *"Hata enjekte → hiçbir kayıt
/// oluşmaz."* Servis testlerinin mutlu yolu geçmesi transaction'ın gerçekten
/// sardığını **kanıtlamaz** — sarmalayıcıyı kaldıran mutasyon o testlerin
/// hepsini geçer.
library;

import 'dart:math';

import 'package:canteen/application/auth/auth_service.dart';
import 'package:canteen/application/auth/login_throttle.dart';
import 'package:canteen/application/auth/session_service.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/app_setting_keys.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, Sale, SaleItem, StockMovement;
import 'package:canteen/domain/services/password_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

/// Enjekte edilen hata — gerçek bir arıza gibi transaction'ı düşürür.
class _InjectedFailure implements Exception {
  const _InjectedFailure();
  @override
  String toString() => 'enjekte edilmiş hata';
}

/// Belirlenen adımda patlayan oturum servisi.
class _FailingSessionService extends SessionService {
  _FailingSessionService({
    required super.settings,
    required super.users,
    required super.clock,
    this.failOnSave = false,
    this.failOnClearIfUser = false,
  });

  final bool failOnSave;
  final bool failOnClearIfUser;

  @override
  Future<void> save(int userId) async {
    if (failOnSave) throw const _InjectedFailure();
    return super.save(userId);
  }

  @override
  Future<void> clearIfUser(int userId) async {
    if (failOnClearIfUser) throw const _InjectedFailure();
    return super.clearIfUser(userId);
  }
}

void main() {
  const password = 'kantin-2026';

  late FakeClock clock;
  late CanteenDatabase db;
  late UsersDao usersDao;
  late AppSettingsDao settingsDao;

  setUp(() {
    clock = FakeClock(testEpochUtc);
    db = memoryDatabase(clock: clock.fn);
    usersDao = UsersDao(db);
    settingsDao = AppSettingsDao(db);
  });

  tearDown(() => db.close());

  AuthService buildAuth(SessionService session) => AuthService(
    db: db,
    users: usersDao,
    session: session,
    hasher: PasswordHasher.withRandom(Random(7)),
    throttle: LoginThrottle(),
    clock: clock.fn,
  );

  SessionService plainSession() =>
      SessionService(settings: settingsDao, users: usersDao, clock: clock.fn);

  Future<int> seedUser(AuthService auth, {String username = 'kasa'}) async {
    final result = await auth.createUser(
      username: username,
      password: password,
      displayName: 'Kasa',
    );
    return (result as dynamic).value as int;
  }

  test('login — oturum yazımı patlarsa lastLoginAt GERİ ALINIR', () async {
    final id = await seedUser(buildAuth(plainSession()));
    expect((await usersDao.findById(id))!.lastLoginAt, isNull);

    clock.advance(const Duration(hours: 2));
    final auth = buildAuth(
      _FailingSessionService(
        settings: settingsDao,
        users: usersDao,
        clock: clock.fn,
        failOnSave: true,
      ),
    );

    await expectLater(
      auth.login('kasa', password),
      throwsA(isA<_InjectedFailure>()),
    );

    expect(
      (await usersDao.findById(id))!.lastLoginAt,
      isNull,
      reason:
          'rules/01 §5: lastLoginAt ile oturum aynı transaction\'dadır. '
          'Oturum yazılamadıysa lastLoginAt de yazılmamalıdır.',
    );
    expect(await settingsDao.read(AppSettingKeys.session), isNull);
  });

  test('setActive — oturum temizliği patlarsa isActive GERİ ALINIR', () async {
    final plain = plainSession();
    final id = await seedUser(buildAuth(plain));
    // İkinci kullanıcı: son-aktif koruması devreye girmesin.
    await seedUser(buildAuth(plain), username: 'mudur');
    await plain.save(id);

    final auth = buildAuth(
      _FailingSessionService(
        settings: settingsDao,
        users: usersDao,
        clock: clock.fn,
        failOnClearIfUser: true,
      ),
    );

    await expectLater(
      auth.setActive(id, false),
      throwsA(isA<_InjectedFailure>()),
    );

    expect(
      (await usersDao.findById(id))!.isActive,
      isTrue,
      reason:
          'Pasifleştirme ile oturum düşürme tek transaction\'dır; biri '
          'olmazsa diğeri de olmamalıdır.',
    );
    expect(
      await settingsDao.read(AppSettingKeys.session),
      isNotNull,
      reason: 'Oturum da yerinde kalmalı.',
    );
  });

  test('setActive(false) oturumu ANINDA düşürür — EC-AUTH-003', () async {
    final plain = plainSession();
    final auth = buildAuth(plain);
    final id = await seedUser(auth);
    await seedUser(auth, username: 'mudur');
    await plain.save(id);

    expect(await settingsDao.read(AppSettingKeys.session), isNotNull);

    expect((await auth.setActive(id, false)).isOk, isTrue);

    expect(
      await settingsDao.read(AppSettingKeys.session),
      isNull,
      reason:
          'docs/17 §6: oturum app_settings\'te tutulur ki kullanıcı '
          'pasifleşince AYNI transaction içinde geçersizleştirilebilsin. '
          'load() sırasında temizlenmesi tembel kalırdı.',
    );
  });

  test('setActive(false) BAŞKASININ oturumuna dokunmaz', () async {
    final plain = plainSession();
    final auth = buildAuth(plain);
    final a = await seedUser(auth, username: 'bir');
    final b = await seedUser(auth, username: 'iki');

    await plain.save(a);
    expect((await auth.setActive(b, false)).isOk, isTrue);

    expect(
      await settingsDao.read(AppSettingKeys.session),
      isNotNull,
      reason: 'Oturum a\'ya ait; b pasifleşince düşmemeli.',
    );
  });

  test('createUser — eşzamanlı aynı ad: yalnızca BİRİ başarılı', () async {
    final auth = buildAuth(plainSession());

    // Benzersizlik kontrolü ile insert aynı transaction'da olmasaydı ikisi de
    // kontrolü geçip iki kayıt oluşturabilirdi.
    final results = await Future.wait([
      auth.createUser(username: 'kasa', password: password, displayName: 'Bir'),
      auth.createUser(username: 'KASA', password: password, displayName: 'İki'),
    ]);

    expect(results.where((r) => r.isOk).length, 1);
    expect(results.where((r) => r.isErr).length, 1);
    expect(await usersDao.countAll(), 1);
  });

  test(
    'setActive — eşzamanlı pasifleştirme sistemi kullanıcısız BIRAKMAZ',
    () async {
      final plain = plainSession();
      final auth = buildAuth(plain);
      final a = await seedUser(auth, username: 'bir');
      final b = await seedUser(auth, username: 'iki');

      final results = await Future.wait([
        auth.setActive(a, false),
        auth.setActive(b, false),
      ]);

      expect(results.where((r) => r.isOk).length, 1);
      expect(
        await usersDao.countActive(),
        1,
        reason: 'BR-AUTH-006: en az bir aktif kullanıcı kalmalıdır.',
      );
    },
  );
}
