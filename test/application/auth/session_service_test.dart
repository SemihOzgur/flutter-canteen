/// SessionService testleri — **docs/17 §6 · EC-AUTH-003/004 · REQ-AUTH-001/003/006/007**
///
/// docs/27 §4: gerçek in-memory SQLite üzerinde çalışır.
library;

import 'dart:convert';

import 'package:canteen/application/auth/session_service.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/app_setting_keys.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, Sale, SaleItem, StockMovement;
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late FakeClock clock;
  late CanteenDatabase db;
  late UsersDao usersDao;
  late AppSettingsDao settingsDao;
  late SessionService session;

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
  });

  tearDown(() => db.close());

  Future<String?> rawSession() => settingsDao.read(AppSettingKeys.session);

  group('SessionService', () {
    test('oturum yoksa null döner', () async {
      expect(await session.load(), isNull);
    });

    test('save → load oturumdaki kullanıcıyı döndürür', () async {
      final userId = await insertTestUser(db);
      await session.save(userId);

      final loaded = await session.load();
      expect(loaded, isNotNull);
      expect(loaded!.id, userId);
      expect(loaded.username, 'kasa');
    });

    test('loginAt UTC unix-millisecond olarak yazılır', () async {
      final userId = await insertTestUser(db);
      await session.save(userId);

      final decoded = jsonDecode((await rawSession())!) as Map<String, Object?>;
      expect(decoded.keys.toSet(), {'userId', 'loginAt'});
      expect(decoded['userId'], userId);
      expect(decoded['loginAt'], isA<int>());
      expect(decoded['loginAt'], testEpochUtc.millisecondsSinceEpoch);
    });

    test('yerel saatle verilen clock UTC ms olarak yazılır', () async {
      final localClock = FakeClock(
        DateTime.fromMillisecondsSinceEpoch(
          testEpochUtc.millisecondsSinceEpoch,
        ),
      );
      final localSession = SessionService(
        settings: settingsDao,
        users: usersDao,
        clock: localClock.fn,
      );
      final userId = await insertTestUser(db);
      await localSession.save(userId);

      final decoded = jsonDecode((await rawSession())!) as Map<String, Object?>;
      expect(decoded['loginAt'], testEpochUtc.millisecondsSinceEpoch);
    });

    test(
      'REQ-AUTH-003 — oturum kalıcıdır: yeni servis örneği aynı oturumu okur',
      () async {
        final userId = await insertTestUser(db);
        await session.save(userId);

        // Uygulamanın yeniden açılmasını temsil eder: yeni DAO + yeni servis.
        final restarted = SessionService(
          settings: AppSettingsDao(db),
          users: UsersDao(db),
          clock: clock.fn,
        );

        final loaded = await restarted.load();
        expect(loaded?.id, userId);
      },
    );

    test('clear oturumu siler', () async {
      final userId = await insertTestUser(db);
      await session.save(userId);
      await session.clear();

      expect(await rawSession(), isNull);
      expect(await session.load(), isNull);
    });

    test('EC-AUTH-003 — pasif kullanıcının oturumu geçersizdir', () async {
      final userId = await insertTestUser(db);
      await session.save(userId);
      await usersDao.setActive(userId, false);

      expect(await session.load(), isNull);
      expect(await rawSession(), isNull, reason: 'oturum temizlenmeli');
    });

    test('REQ-AUTH-006 — kullanıcı yoksa oturum geçersizdir', () async {
      await settingsDao.write(
        AppSettingKeys.session,
        jsonEncode({'userId': 4242, 'loginAt': 1}),
      );

      expect(await session.load(), isNull);
      expect(await rawSession(), isNull);
    });

    group('EC-AUTH-004 — bozuk oturum verisi', () {
      final corrupt = <String, String>{
        'JSON değil': 'bu bir json degil',
        'yarım JSON': '{"userId": 1,',
        'boş metin': '',
        'dizi': '[1, 2, 3]',
        'düz sayı': '7',
        'alanlar eksik': '{}',
        'loginAt eksik': '{"userId": 1}',
        'userId eksik': '{"loginAt": 123}',
        'userId yanlış tipte': '{"userId": "1", "loginAt": 123}',
        'loginAt yanlış tipte': '{"userId": 1, "loginAt": "dun"}',
        'userId null': '{"userId": null, "loginAt": 123}',
      };

      for (final entry in corrupt.entries) {
        test('${entry.key} → sessizce temizlenir, exception yok', () async {
          await insertTestUser(db);
          await settingsDao.write(AppSettingKeys.session, entry.value);

          // Hiçbir koşulda fırlatmaz (REQ-AUTH-007).
          expect(await session.load(), isNull);
          expect(await rawSession(), isNull, reason: 'oturum temizlenmeli');
        });
      }
    });

    test('bozuk oturum sonrası yeni oturum yazılabilir', () async {
      final userId = await insertTestUser(db);
      await settingsDao.write(AppSettingKeys.session, '{bozuk');

      expect(await session.load(), isNull);

      await session.save(userId);
      expect((await session.load())?.id, userId);
    });

    test('oturum app_settings dışında bir yere yazılmaz', () async {
      final userId = await insertTestUser(db);
      await session.save(userId);

      final settings = await db.select(db.appSettings).get();
      expect(settings.map((s) => s.key), contains(AppSettingKeys.session));
      // `users` tablosunda oturum izi tutulmaz.
      final user = await usersDao.findById(userId);
      expect(user!.lastLoginAt, isNull);
    });
  });
}
