/// AuthService testleri — **docs/17 §2, §3, §5, §6, §11 · EC-AUTH-001…008**
///
/// docs/27 §4: gerçek in-memory SQLite üzerinde çalışır.
/// Test önceliği rules/06 §2 → **Authentication** 🔴.
library;

import 'dart:convert';
import 'dart:math';

import 'package:canteen/application/auth/auth_failures.dart';
import 'package:canteen/application/auth/auth_service.dart';
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

void main() {
  const password = 'kantin-2026';

  late FakeClock clock;
  late CanteenDatabase db;
  late UsersDao usersDao;
  late AppSettingsDao settingsDao;
  late SessionService session;
  late AuthService auth;

  setUp(() {
    clock = FakeClock(testEpochUtc);
    db = memoryDatabase(clock: clock.fn);
    usersDao = UsersDao(db);
    settingsDao = AppSettingsDao(db);
    session = SessionService(
      settings: settingsDao,
      users: usersDao,
      clock: clock.fn,
    );
    auth = AuthService(
      db: db,
      users: usersDao,
      session: session,
      // Deterministik salt üretimi (rules/06 §7).
      hasher: PasswordHasher.withRandom(Random(7)),
      throttle: LoginThrottle(),
      clock: clock.fn,
    );
  });

  tearDown(() => db.close());

  Future<int> createUser({
    String username = 'kasa',
    String pass = password,
    String displayName = 'Kasa Görevlisi',
  }) async {
    final result = await auth.createUser(
      username: username,
      password: pass,
      displayName: displayName,
    );
    expect(result, isA<Ok<int>>(), reason: 'kullanıcı oluşturulamadı');
    return (result as Ok<int>).value;
  }

  Failure failureOf(Result<Object?> result) {
    expect(result.isErr, isTrue, reason: 'hata bekleniyordu');
    return result.failureOrNull!;
  }

  // -------------------------------------------------------------------------
  group('kurulum — EC-AUTH-008 / REQ-AUTH-002', () {
    test('hiç kullanıcı yoksa needsSetup true', () async {
      expect(await auth.needsSetup(), isTrue);
    });

    test('kullanıcı oluşturulunca needsSetup false', () async {
      await createUser();
      expect(await auth.needsSetup(), isFalse);
    });

    test('yalnızca pasif kullanıcı varsa bile needsSetup false', () async {
      final id = await createUser();
      await usersDao.setActive(id, false);
      expect(
        await auth.needsSetup(),
        isFalse,
        reason: 'pasif kullanıcı varken sistem yeni kurulum değildir',
      );
    });
  });

  // -------------------------------------------------------------------------
  group('createUser', () {
    test('BR-SEC-001 — düz metin parola saklanmaz', () async {
      final id = await createUser();
      final user = (await usersDao.findById(id))!;

      expect(user.passwordHash, isNot(contains(password)));
      expect(user.passwordSalt, isNot(contains(password)));
      expect(user.passwordHash.length, 64, reason: 'SHA-256 hex');
      expect(user.passwordHash, isNot(password));

      // Tüm satırın hiçbir metin alanında düz metin bulunmaz.
      final rows = await db.select(db.users).get();
      for (final row in rows) {
        expect(row.toString(), isNot(contains(password)));
      }
    });

    test('aynı parola iki kullanıcıda farklı hash üretir', () async {
      final a = await createUser(username: 'ahmet');
      final b = await createUser(username: 'mehmet');

      final first = (await usersDao.findById(a))!;
      final second = (await usersDao.findById(b))!;

      expect(first.passwordSalt, isNot(second.passwordSalt));
      expect(first.passwordHash, isNot(second.passwordHash));
    });

    test('EC-AUTH-006 — kullanıcı adı küçük harfe normalize edilir', () async {
      final id = await createUser(username: '  KaSa  ');
      expect((await usersDao.findById(id))!.username, 'kasa');
    });

    test('kullanıcı adı benzersizdir — anlamlı Türkçe hata', () async {
      await createUser(username: 'kasa');
      final again = await auth.createUser(
        username: 'KASA',
        password: password,
        displayName: 'İkinci',
      );

      final failure = failureOf(again);
      expect(failure.code, AuthFailures.usernameExists.code);
      expect(failure.userMessage, contains('kullanıcı adı'));
      expect(await usersDao.countAll(), 1);
    });

    test('boş kullanıcı adı / parola / görünen ad reddedilir', () async {
      expect(
        failureOf(
          await auth.createUser(
            username: '   ',
            password: password,
            displayName: 'Ad',
          ),
        ).code,
        AuthFailures.usernameRequired.code,
      );
      expect(
        failureOf(
          await auth.createUser(
            username: 'kasa',
            password: '',
            displayName: 'Ad',
          ),
        ).code,
        AuthFailures.passwordRequired.code,
      );
      expect(
        failureOf(
          await auth.createUser(
            username: 'kasa',
            password: password,
            displayName: '  ',
          ),
        ).code,
        AuthFailures.displayNameRequired.code,
      );
      expect(await usersDao.countAll(), 0);
    });
  });

  // -------------------------------------------------------------------------
  group('login', () {
    test('doğru bilgilerle giriş başarılıdır', () async {
      final id = await createUser();
      final result = await auth.login('kasa', password);

      expect(result, isA<Ok<User>>());
      expect((result as Ok<User>).value.id, id);
    });

    test('başarılı giriş lastLoginAt günceller', () async {
      final id = await createUser();
      expect((await usersDao.findById(id))!.lastLoginAt, isNull);

      clock.advance(const Duration(hours: 3));
      final result = await auth.login('kasa', password);

      final loggedIn = (result as Ok<User>).value;
      expect(loggedIn.lastLoginAt, clock.current);
      expect((await usersDao.findById(id))!.lastLoginAt, clock.current);
    });

    test('başarılı giriş oturumu yazar', () async {
      final id = await createUser();
      clock.advance(const Duration(minutes: 5));
      await auth.login('kasa', password);

      final raw = await settingsDao.read(AppSettingKeys.session);
      final decoded = jsonDecode(raw!) as Map<String, Object?>;
      expect(decoded['userId'], id);
      expect(decoded['loginAt'], clock.current.millisecondsSinceEpoch);
      expect((await session.load())?.id, id);
    });

    test('EC-AUTH-006 — kullanıcı adı büyük harfle girilebilir', () async {
      await createUser(username: 'kasa');

      expect((await auth.login('KASA', password)).isOk, isTrue);
      expect((await auth.login('  Kasa ', password)).isOk, isTrue);
    });

    test(
      'EC-AUTH-001 — bilinmeyen kullanıcı ve hatalı parola AYNI hatayı verir',
      () async {
        await createUser(username: 'kasa');

        final wrongPassword = await auth.login('kasa', 'yanlis');
        final unknownUser = await auth.login('yokboyle', password);

        final a = failureOf(wrongPassword);
        final b = failureOf(unknownUser);

        expect(a.code, AuthFailures.invalidCredentials.code);
        expect(b.code, a.code);
        expect(b.userMessage, a.userMessage);
        expect(a.userMessage, 'Kullanıcı adı veya parola hatalı.');
      },
    );

    test('pasif kullanıcı da aynı genel hatayı alır', () async {
      final id = await createUser();
      await usersDao.setActive(id, false);

      final failure = failureOf(await auth.login('kasa', password));
      expect(failure.code, AuthFailures.invalidCredentials.code);
      expect(
        failure.userMessage,
        AuthFailures.invalidCredentials.userMessage,
        reason: 'kullanıcının var olduğu sızdırılmamalı',
      );
    });

    test('başarısız giriş oturum yazmaz', () async {
      await createUser();
      await auth.login('kasa', 'yanlis');

      expect(await settingsDao.read(AppSettingKeys.session), isNull);
      expect(await session.load(), isNull);
    });

    test('hata mesajı düz metin parola içermez (BR-SEC-001)', () async {
      await createUser();
      final failure = failureOf(await auth.login('kasa', '${password}x'));

      expect(failure.userMessage, isNot(contains(password)));
      expect(failure.toString(), isNot(contains(password)));
    });
  });

  // -------------------------------------------------------------------------
  group('EC-AUTH-002 / REQ-AUTH-011 — hatalı deneme sınırı', () {
    Future<void> failTimes(int times, {String username = 'kasa'}) async {
      for (var i = 0; i < times; i++) {
        final result = await auth.login(username, 'yanlis');
        expect(
          result.failureOrNull?.code,
          AuthFailures.invalidCredentials.code,
        );
      }
    }

    test(
      '5 hatalı denemeden sonra doğru parola bile beklemeye takılır',
      () async {
        await createUser();
        await failTimes(5);

        final blocked = await auth.login('kasa', password);
        final failure = failureOf(blocked);
        expect(
          failure.code,
          AuthFailures.tooManyAttempts(const Duration(seconds: 30)).code,
        );
        expect(failure.userMessage, contains('30 saniye'));
      },
    );

    test('4 hatalı denemeden sonra giriş hâlâ mümkündür', () async {
      await createUser();
      await failTimes(4);

      expect((await auth.login('kasa', password)).isOk, isTrue);
    });

    test('30 saniye sonra bekleme kalkar ve sayaç sıfırlanır', () async {
      await createUser();
      await failTimes(5);
      expect((await auth.login('kasa', password)).isErr, isTrue);

      clock.advance(const Duration(seconds: 30));
      expect((await auth.login('kasa', password)).isOk, isTrue);
    });

    test('bekleme dolduktan SONRA tek hata yeniden kilitlemez', () async {
      // Yukarıdaki test sayacın sıfırlandığını KANITLAMAZ: başarılı giriş
      // zaten `reset` çağırır, bu yüzden sayaç sıfırlanmasa da geçer.
      // Gerçek kanıt, beklemeden sonra tek bir hatanın yeniden kilitlememesi.
      await createUser();
      await failTimes(5);

      clock.advance(const Duration(seconds: 30));
      await failTimes(1); // beklemenin ardından ilk hata

      final result = await auth.login('kasa', password);
      expect(
        result.isOk,
        isTrue,
        reason:
            'EC-AUTH-002: bekleme bitince sayaç sıfırlanır. Sıfırlanmazsa '
            'kullanıcı tek yazım hatasında 30 sn daha kilitlenir.',
      );
    });

    test('bekleme dolmadan önce hâlâ engellidir', () async {
      await createUser();
      await failTimes(5);

      clock.advance(const Duration(seconds: 29));
      final failure = failureOf(await auth.login('kasa', password));
      expect(
        failure.code,
        AuthFailures.tooManyAttempts(const Duration(seconds: 1)).code,
      );
      expect(failure.userMessage, contains('1 saniye'));
    });

    test('başarılı giriş sayacı sıfırlar', () async {
      await createUser();
      await failTimes(4);
      expect((await auth.login('kasa', password)).isOk, isTrue);

      // Sayaç sıfırlandığı için 4 hata daha beklemeye yol açmaz.
      await failTimes(4);
      expect((await auth.login('kasa', password)).isOk, isTrue);
    });

    test('sayaç kullanıcı adı başınadır', () async {
      await createUser(username: 'kasa');
      await createUser(username: 'mudur');

      await failTimes(5, username: 'kasa');

      expect(
        (await auth.login('mudur', password)).isOk,
        isTrue,
        reason: 'başka kullanıcı etkilenmemeli',
      );
    });

    test(
      'sayaç bellektedir: yeni servis örneği sıfır sayaçla başlar',
      () async {
        await createUser();
        await failTimes(5);
        expect((await auth.login('kasa', password)).isErr, isTrue);

        // Uygulamanın yeniden başlatılması.
        final restarted = AuthService(
          db: db,
          users: usersDao,
          session: session,
          hasher: PasswordHasher.withRandom(Random(7)),
          clock: clock.fn,
        );
        expect((await restarted.login('kasa', password)).isOk, isTrue);
      },
    );
  });

  // -------------------------------------------------------------------------
  group('logout', () {
    test('REQ-AUTH-004 — oturum temizlenir', () async {
      await createUser();
      await auth.login('kasa', password);
      expect(await session.load(), isNotNull);

      await auth.logout();

      expect(await settingsDao.read(AppSettingKeys.session), isNull);
      expect(await auth.currentUser(), isNull);
    });

    test('logout kullanıcıyı silmez veya pasifleştirmez', () async {
      final id = await createUser();
      await auth.login('kasa', password);
      await auth.logout();

      final user = await usersDao.findById(id);
      expect(user, isNotNull);
      expect(user!.isActive, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  group('changePassword', () {
    test('mevcut parola doğruysa değişir', () async {
      final id = await createUser();
      final before = (await usersDao.findById(id))!;

      final result = await auth.changePassword(
        userId: id,
        currentPassword: password,
        newPassword: 'yeni-parola',
      );
      expect(result.isOk, isTrue);

      expect((await auth.login('kasa', 'yeni-parola')).isOk, isTrue);
      expect((await auth.login('kasa', password)).isErr, isTrue);

      final after = (await usersDao.findById(id))!;
      expect(after.passwordHash, isNot(before.passwordHash));
      expect(after.passwordSalt, isNot(before.passwordSalt));
      expect(after.passwordHash, isNot(contains('yeni-parola')));
    });

    test('mevcut parola yanlışsa reddedilir', () async {
      final id = await createUser();
      final before = (await usersDao.findById(id))!;

      final failure = failureOf(
        await auth.changePassword(
          userId: id,
          currentPassword: 'yanlis',
          newPassword: 'yeni-parola',
        ),
      );
      expect(failure.code, AuthFailures.currentPasswordWrong.code);

      expect((await usersDao.findById(id))!.passwordHash, before.passwordHash);
      expect((await auth.login('kasa', password)).isOk, isTrue);
    });

    test('boş yeni parola reddedilir', () async {
      final id = await createUser();
      expect(
        failureOf(
          await auth.changePassword(
            userId: id,
            currentPassword: password,
            newPassword: '',
          ),
        ).code,
        AuthFailures.passwordRequired.code,
      );
    });

    test('olmayan kullanıcı reddedilir', () async {
      expect(
        failureOf(
          await auth.changePassword(
            userId: 999,
            currentPassword: password,
            newPassword: 'yeni-parola',
          ),
        ).code,
        AuthFailures.userNotFound.code,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('setActive — BR-AUTH-006 / EC-AUTH-005', () {
    test('son aktif kullanıcı pasifleştirilemez', () async {
      final id = await createUser();

      final failure = failureOf(await auth.setActive(id, false));
      expect(failure.code, AuthFailures.lastActiveUser.code);

      final user = (await usersDao.findById(id))!;
      expect(user.isActive, isTrue, reason: 'kullanıcı aktif kalmalı');
      expect(await usersDao.countActive(), 1);
    });

    test('ikinci aktif kullanıcı varken pasifleştirme yapılabilir', () async {
      final first = await createUser(username: 'kasa');
      await createUser(username: 'mudur');

      expect((await auth.setActive(first, false)).isOk, isTrue);
      expect((await usersDao.findById(first))!.isActive, isFalse);
      expect(await usersDao.countActive(), 1);
    });

    test('pasifleştirme kullanıcıyı SİLMEZ', () async {
      final first = await createUser(username: 'kasa');
      await createUser(username: 'mudur');
      await auth.setActive(first, false);

      expect(await usersDao.countAll(), 2);
      expect(await usersDao.findById(first), isNotNull);
      expect((await usersDao.listAll()).length, 2);
      expect((await usersDao.listActive()).length, 1);
    });

    test('pasif kullanıcı tekrar aktifleştirilebilir', () async {
      final first = await createUser(username: 'kasa');
      await createUser(username: 'mudur');
      await auth.setActive(first, false);

      expect((await auth.setActive(first, true)).isOk, isTrue);
      expect(await usersDao.countActive(), 2);
    });

    test('son aktif kullanıcıyı yeniden aktif yapmak hata değildir', () async {
      final id = await createUser();
      expect((await auth.setActive(id, true)).isOk, isTrue);
    });

    test('olmayan kullanıcı reddedilir', () async {
      await createUser();
      expect(
        failureOf(await auth.setActive(999, false)).code,
        AuthFailures.userNotFound.code,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('updateDisplayName', () {
    test('görünen ad değişir', () async {
      final id = await createUser();
      expect((await auth.updateDisplayName(id, '  Ayşe Yılmaz ')).isOk, isTrue);
      expect((await usersDao.findById(id))!.displayName, 'Ayşe Yılmaz');
    });

    test('boş ad reddedilir', () async {
      final id = await createUser();
      expect(
        failureOf(await auth.updateDisplayName(id, '   ')).code,
        AuthFailures.displayNameRequired.code,
      );
      expect((await usersDao.findById(id))!.displayName, 'Kasa Görevlisi');
    });

    test('olmayan kullanıcı reddedilir', () async {
      expect(
        failureOf(await auth.updateDisplayName(999, 'Ad')).code,
        AuthFailures.userNotFound.code,
      );
    });
  });

  // -------------------------------------------------------------------------
  group('kullanıcı listesi', () {
    test('listAll pasifleri de içerir, listActive içermez', () async {
      final first = await createUser(username: 'zeynep');
      await createUser(username: 'ahmet');
      await auth.setActive(first, false);

      final all = await usersDao.listAll();
      expect(all.map((u) => u.username), ['ahmet', 'zeynep']);
      expect((await usersDao.listActive()).map((u) => u.username), ['ahmet']);
    });
  });
}
