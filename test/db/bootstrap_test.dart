/// Bootstrap sırası testleri.
///
/// **KRİTİK SIRA (rules/03 §5 · RSK-003):**
/// ```text
/// AppPaths → ensureDirectories → AppLogger → InstanceLock → DB → runApp
/// ```
/// InstanceLock başarısızsa **veritabanı HİÇ açılmaz.**
library;

import 'dart:convert';
import 'dart:io';

import 'package:canteen/core/errors/app_exception.dart';
import 'package:canteen/core/single_instance/instance_lock.dart';
import 'package:canteen/data/db/database_bootstrap.dart';
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/data/db/raw_sqlite_file.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  late TempAppPaths temp;

  setUp(() async => temp = await TempAppPaths.create());
  tearDown(() => temp.dispose());

  group('açılış sırası', () {
    test('ilk açılış → created; şema + seed hazır', () async {
      expect(File(temp.paths.databaseFile).existsSync(), isFalse);

      final result = await DatabaseBootstrap(paths: temp.paths).open();
      addTearDown(result.database.close);

      expect(result.kind, DatabaseOpenKind.created);
      expect(File(temp.paths.databaseFile).existsSync(), isTrue);
      expect((await tableNames(result.database)).length, 15);
      expect(
        (await result.database.select(result.database.categories).get()).length,
        1,
      );
    });

    test('ikinci açılış → opened; seed çoğalmaz', () async {
      final first = await DatabaseBootstrap(paths: temp.paths).open();
      await first.database.close();

      final second = await DatabaseBootstrap(paths: temp.paths).open();
      addTearDown(second.database.close);

      expect(second.kind, DatabaseOpenKind.opened);
      expect(
        (await second.database.select(second.database.categories).get()).length,
        1,
      );
    });

    test('daha yeni şema → SchemaVersionException, veri değişmez', () async {
      final first = await DatabaseBootstrap(paths: temp.paths).open();
      await first.database.customStatement('PRAGMA user_version = 99;');
      await first.database.close();

      await expectLater(
        DatabaseBootstrap(paths: temp.paths).open(),
        throwsA(isA<SchemaVersionException>()),
      );

      // Reddedilen açılış veriyi bozmamalı.
      expect(
        await RawSqliteFile(temp.paths.databaseFile).readUserVersion(),
        99,
      );
    });
  });

  group('BR-GEN-005 — kilit alınmadan veritabanı açılmaz', () {
    test(
      'kilit BAŞKA SÜREÇTEYKEN DB dosyası OLUŞTURULMAZ',
      () async {
        // OS kilitleri süreç bazlıdır: gerçek dışlama ancak ayrı bir süreçle
        // kanıtlanabilir (Faz 1 `test/support/lock_holder.dart`).
        final holder = await Process.start('dart', [
          'run',
          'test/support/lock_holder.dart',
          temp.paths.lockFile,
          'hold',
        ]);
        // `dart run` derleme çıktısı da stdout'a düşebilir; ilgilendiğimiz satırı
        // ararız.
        final acquiredLine = await holder.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .firstWhere((line) => line.trim().endsWith('ACQUIRED'));
        expect(acquiredLine.trim(), endsWith('ACQUIRED'));

        // Bu süreç main.dart akışını izler.
        final lock = InstanceLock(lockFilePath: temp.paths.lockFile);
        final acquired = lock.tryAcquire();

        expect(
          acquired,
          InstanceLockResult.alreadyRunning,
          reason: 'BR-GEN-005: ikinci örnek kilidi ALMAMALIYDI.',
        );
        // main.dart burada `return` eder — DatabaseBootstrap ÇAĞRILMAZ.

        expect(
          File(temp.paths.databaseFile).existsSync(),
          isFalse,
          reason: 'RSK-003: ikinci örnek veritabanı dosyasına dokunmamalı.',
        );

        await holder.stdin.close();
        await holder.exitCode;
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('kilit alındıktan sonra veritabanı açılabilir', () async {
      final lock = InstanceLock(lockFilePath: temp.paths.lockFile);
      expect(lock.tryAcquire(), InstanceLockResult.acquired);
      addTearDown(lock.release);

      final result = await DatabaseBootstrap(paths: temp.paths).open();
      addTearDown(result.database.close);

      expect(File(temp.paths.databaseFile).existsSync(), isTrue);
    });
  });

  group('main.dart bootstrap sırası — kaynak seviyesinde koruma', () {
    test('InstanceLock kontrolü DatabaseBootstrap\'tan ÖNCE gelir', () {
      final source = File('lib/main.dart').readAsStringSync();

      final lockIndex = source.indexOf('lock.tryAcquire()');
      final dbIndex = source.indexOf('DatabaseBootstrap(');

      expect(lockIndex, greaterThan(-1), reason: 'InstanceLock kullanılmıyor!');
      expect(
        dbIndex,
        greaterThan(-1),
        reason: 'DatabaseBootstrap kullanılmıyor!',
      );
      expect(
        lockIndex,
        lessThan(dbIndex),
        reason:
            'RSK-003: veritabanı, single-instance kilidinden ÖNCE açılıyor — '
            'iki örnek aynı dosyayı bozabilir.',
      );
    });

    test('veri dizini çözümlemesi kilitten ÖNCE gelir', () {
      final source = File('lib/main.dart').readAsStringSync();

      expect(
        source.indexOf('AppPaths.resolve()'),
        lessThan(source.indexOf('lock.tryAcquire()')),
      );
      expect(
        source.indexOf('ensureDirectories()'),
        lessThan(source.indexOf('lock.tryAcquire()')),
      );
    });

    test('kapanışta database.close() çağrılır', () {
      final source = File('lib/main.dart').readAsStringSync();

      expect(
        source,
        contains('database.close()'),
        reason:
            'Windows dosya kilidi katıdır (rules/05 §6); bağlantı kapatılmalı.',
      );
      expect(source, contains('AppLifecycleListener'));
    });
  });

  group('Riverpod entegrasyonu', () {
    test('override edilmeyen canteenDatabaseProvider sessizce çalışmaz', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        () => container.read(canteenDatabaseProvider),
        throwsA(isA<StateError>()),
        reason: 'İkinci bir bağlantı sessizce açılmamalı.',
      );
    });

    test('override edilince repository provider\'ları çözümlenir', () async {
      final result = await DatabaseBootstrap(paths: temp.paths).open();
      addTearDown(result.database.close);

      final container = ProviderContainer(
        overrides: [canteenDatabaseProvider.overrideWithValue(result.database)],
      );
      addTearDown(container.dispose);

      expect(container.read(productRepositoryProvider), isNotNull);
      expect(container.read(saleRepositoryProvider), isNotNull);
      expect(container.read(stockRepositoryProvider), isNotNull);
      expect(container.read(categoriesDaoProvider), isNotNull);
      expect(container.read(appSettingsDaoProvider), isNotNull);
    });

    test('repository provider\'ları DOMAIN arayüz tipini döner', () async {
      final result = await DatabaseBootstrap(paths: temp.paths).open();
      addTearDown(result.database.close);

      final container = ProviderContainer(
        overrides: [canteenDatabaseProvider.overrideWithValue(result.database)],
      );
      addTearDown(container.dispose);

      // Statik tip domain arayüzüdür; tüketici Drift'i görmez.
      final repository = container.read(productRepositoryProvider);
      final found = await repository.findByBarcode('yok-boyle-barkod');
      expect(found.isErr, isTrue);
    });
  });

  group('katman sınırı — rules/01 §1', () {
    test('presentation/ altında drift ve data/db import\'u YOK', () {
      final offenders = <String>[];

      for (final entity in Directory(
        'lib/presentation',
      ).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final banned in const [
          "import 'package:drift/",
          'import "package:drift/',
          // `data/db` Drift satır tiplerini taşır — `User` bunlardan biri ve
          // üretilen `toString()`'i hash + salt basar (rules/04 §8). UI bu
          // tipleri hiç görmemeli; `domain/models/auth_user.dart` kullanılır.
          'data/db/',
          "package:canteen/data/",
        ]) {
          if (source.contains(banned)) {
            offenders.add('${entity.path} → $banned');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'rules/01 §1: presentation altında drift/data import\'u BİR '
            'BUG\'dır → $offenders',
      );
    });

    test('domain/ altında drift · Flutter · dart:io import\'u YOK', () {
      final offenders = <String>[];

      for (final entity in Directory('lib/domain').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final banned in const [
          "import 'package:drift/",
          "import 'package:flutter/",
          "import 'dart:io'",
          "import 'package:flutter_riverpod/",
        ]) {
          if (source.contains(banned)) {
            offenders.add('${entity.path} → $banned');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'rules/01 §1: domain katmanı framework bağımsızdır → $offenders',
      );
    });

    // `lib/application/` Faz 3a'da gerçek ihtiyaçla açıldı (AuthService,
    // SessionService — docs/03 §3). Faz 2'deki "henüz açılmadı" kontrolünün
    // yerini katmanın KENDİ sınırlarını koruyan bu kontrol aldı.
    test('application/ altında widget ve ham SQL YOK', () {
      final applicationDir = Directory('lib/application');
      expect(
        applicationDir.existsSync(),
        isTrue,
        reason:
            'Faz 3a application katmanını açtı; dizin yoksa bu bekçi sessizce '
            'boş geçerdi.',
      );

      final offenders = <String>[];

      for (final entity in applicationDir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final source = entity.readAsStringSync();
        for (final banned in const [
          "import 'package:flutter/",
          "import 'package:flutter_test/",
          '../presentation/',
          'package:canteen/presentation/',
          // rules/01 §1: application katmanı ham SQL detayı içermez.
          'customSelect(',
          'customStatement(',
          'customUpdate(',
          'customInsert(',
          'customWriteInto(',
        ]) {
          if (source.contains(banned)) {
            offenders.add('${entity.path} → $banned');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'rules/01 §1: application katmanı widget bilgisi ve ham SQL '
            'içermez → $offenders',
      );
    });
  });
}
