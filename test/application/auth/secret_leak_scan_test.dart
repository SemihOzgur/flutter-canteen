/// Sır sızıntısı taraması — **BR-SEC-001 · REQ-SEC-002 · REQ-AUTH-014/023**
///
/// `rules/04 §8` şunların hiçbir yere yazılmasını yasaklar: parola (düz metin
/// veya hash), salt, recovery code (düz metin veya hash).
///
/// Diğer testler tek tek alanları kontrol eder. Bu dosya **bütünü** tarar:
/// gerçek bir dosya veritabanı üzerinde tüm auth akışları çalıştırılır, sonra
/// veritabanı dosyasının **ham baytları**, `-wal`/`-shm` yan dosyaları, log
/// dosyaları ve `audit_logs` içeriği aranır.
///
/// Ham bayt taraması önemlidir: bir değer silinmiş olsa bile SQLite sayfasında
/// kalabilir. WAL açık olduğu için (`rules/03 §1`) `-wal` dosyası da taranır —
/// checkpoint'lenmemiş sayfalar orada durur.
///
/// Yedek dosyası taraması (REQ-AUTH-023'ün son maddesi) **Faz 9**'a aittir;
/// yedekleme henüz yoktur.
library;

import 'dart:io';
import 'dart:math';

import 'package:canteen/application/auth/auth_service.dart';
import 'package:canteen/application/auth/financial_access_service.dart';
import 'package:canteen/application/auth/recovery_code_service.dart';
import 'package:canteen/application/auth/session_service.dart';
import 'package:canteen/core/logging/app_logger.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/database_bootstrap.dart';
import 'package:canteen/domain/services/password_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

/// Ayırt edici sırlar — rastgele bir bayt dizisinde tesadüfen bulunamayacak
/// kadar özgün olmalılar ki tarama sonucu kesin olsun.
const String userPassword = 'KANTIN-PW-SENTINEL-7Q4X';
const String dashboardPassword = 'DASH-PW-SENTINEL-9Z2K';
const String newDashboardPassword = 'DASH-PW2-SENTINEL-3M8V';

void main() {
  late TempAppPaths temp;
  late FakeClock clock;
  late DatabaseOpenResult opened;
  late AppLogger logger;

  late AuthService auth;
  late FinancialAccessService access;
  late RecoveryCodeService recovery;
  late AppSettingsDao settingsDao;

  setUp(() async {
    temp = await TempAppPaths.create();
    clock = FakeClock(testEpochUtc);

    opened = await DatabaseBootstrap(paths: temp.paths, clock: clock.fn).open();
    final db = opened.database;

    logger = AppLogger(logsDirPath: temp.paths.logsDir, clock: clock.fn);
    await logger.init();

    final usersDao = UsersDao(db);
    final auditDao = AuditLogsDao(db);
    settingsDao = AppSettingsDao(db);

    access = FinancialAccessService(
      db: db,
      settings: settingsDao,
      auditLogs: auditDao,
      hasher: PasswordHasher.withRandom(Random(11)),
      clock: clock.fn,
      logger: logger,
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
      clock: clock.fn,
    );
    recovery = RecoveryCodeService(
      db: db,
      settings: settingsDao,
      auditLogs: auditDao,
      financialAccess: access,
      hasher: PasswordHasher.withRandom(Random(13)),
      random: Random(17),
      clock: clock.fn,
      logger: logger,
    );
  });

  tearDown(() async {
    await opened.database.close();
    temp.dispose();
  });

  /// Tüm auth akışlarını uçtan uca çalıştırır ve üretilen düz metin kodları
  /// döndürür.
  Future<List<String>> runEveryAuthFlow() async {
    final codes = <String>[];

    // Kurulum sihirbazı
    expect(
      await auth.createUser(
        username: 'kasa',
        password: userPassword,
        displayName: 'Kasa Görevlisi',
      ),
      isA<Ok<int>>(),
    );
    expect(await access.setPassword(dashboardPassword), isA<Ok<void>>());

    final first = await recovery.generateInitial();
    expect(first, isA<Ok<String>>());
    codes.add((first as Ok<String>).value);

    // Giriş, kilit açma, başarısız denemeler
    expect(await auth.login('kasa', userPassword), isA<Ok>());
    expect(await auth.login('kasa', 'YANLIS-PAROLA'), isA<Err>());
    expect(await access.unlock(dashboardPassword), isA<Ok<void>>());
    expect(await access.unlock('YANLIS-DASH'), isA<Err<void>>());

    // Kurtarma: kod kullanılır, yenisi doğar
    final reset = await recovery.resetPasswordWithCode(
      code: codes.first,
      newPassword: newDashboardPassword,
    );
    expect(reset, isA<Ok<String>>());
    codes.add((reset as Ok<String>).value);

    // Ayarlardan yenileme
    final again = await recovery.regenerate(
      currentPassword: newDashboardPassword,
    );
    expect(again, isA<Ok<String>>());
    codes.add((again as Ok<String>).value);

    await auth.logout();

    // Yazılanların diske inmesi için checkpoint.
    await opened.database.customStatement('PRAGMA wal_checkpoint(FULL);');
    return codes;
  }

  /// Veri dizinindeki tüm dosyaları ham bayt olarak okur.
  List<({String path, List<int> bytes})> allDataFiles() {
    final files = <({String path, List<int> bytes})>[];
    for (final entity in Directory(
      temp.paths.rootPath,
    ).listSync(recursive: true)) {
      if (entity is! File) continue;
      files.add((path: entity.path, bytes: entity.readAsBytesSync()));
    }
    return files;
  }

  bool containsAscii(List<int> haystack, String needle) {
    final pattern = needle.codeUnits;
    if (pattern.isEmpty || haystack.length < pattern.length) return false;
    for (var i = 0; i <= haystack.length - pattern.length; i++) {
      var match = true;
      for (var j = 0; j < pattern.length; j++) {
        if (haystack[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }

  test('düz metin parola ve kod HİÇBİR dosyada bulunmaz', () async {
    final codes = await runEveryAuthFlow();

    final secrets = <String>[
      userPassword,
      dashboardPassword,
      newDashboardPassword,
      ...codes,
      // Kodun tiresiz hâli de aranır: saklama kanonik form üzerindendir.
      ...codes.map((c) => c.replaceAll('-', '')),
    ];

    final files = allDataFiles();
    expect(
      files.where((f) => f.path.endsWith('.sqlite')).length,
      greaterThan(0),
      reason: 'Tarama anlamlı olması için veritabanı dosyası bulunmalı.',
    );

    final offenders = <String>[];
    for (final file in files) {
      for (final secret in secrets) {
        if (containsAscii(file.bytes, secret)) {
          offenders.add('${file.path} → "$secret"');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason:
          'BR-SEC-001 · REQ-AUTH-014/023: düz metin parola veya kurtarma kodu '
          'veri dizinindeki HİÇBİR dosyada bulunamaz — veritabanı sayfaları, '
          '-wal/-shm ve log dosyaları dâhil. Bulunanlar: $offenders',
    );
  });

  test('log dosyaları sır içermez — rules/04 §8', () async {
    final codes = await runEveryAuthFlow();

    // Sızıntı olsaydı yakalanacağını kanıtla: tarama gerçekten çalışıyor mu?
    logger.info('tarama-kontrol-dizesi');

    final logs = Directory(
      temp.paths.logsDir,
    ).listSync().whereType<File>().map((f) => f.readAsStringSync()).join('\n');

    expect(
      logs,
      contains('tarama-kontrol-dizesi'),
      reason: 'Log dosyası okunamıyorsa bu test hiçbir şey kanıtlamaz.',
    );

    for (final secret in [
      userPassword,
      dashboardPassword,
      newDashboardPassword,
      ...codes,
    ]) {
      expect(logs, isNot(contains(secret)));
    }
  });

  test('audit kayıtları parola, kod, hash veya salt taşımaz', () async {
    final codes = await runEveryAuthFlow();
    final db = opened.database;

    final rows = await db.select(db.auditLogs).get();
    expect(
      rows,
      isNotEmpty,
      reason: 'Audit yazılmıyorsa bu test hiçbir şey kanıtlamaz.',
    );

    // Saklanan hash ve salt değerleri de yasaktır (rules/04 §8).
    final storedSecrets = <String>[];
    for (final row in await db.select(db.appSettings).get()) {
      storedSecrets.add(row.value);
    }
    for (final row in await db.select(db.users).get()) {
      storedSecrets
        ..add(row.passwordHash)
        ..add(row.passwordSalt);
    }

    final forbidden = <String>[
      userPassword,
      dashboardPassword,
      newDashboardPassword,
      ...codes,
      ...storedSecrets,
    ];

    for (final row in rows) {
      final serialized = [
        row.action,
        row.entityType,
        row.oldValue ?? '',
        row.newValue ?? '',
        row.metadata ?? '',
      ].join('|');

      for (final secret in forbidden) {
        expect(
          serialized,
          isNot(contains(secret)),
          reason:
              'REQ-AUDIT-004 · rules/04 §8: audit kaydı sır taşıyamaz. '
              'Kayıt: ${row.action}',
        );
      }
    }
  });

  test('users ve app_settings düz metin sır içermez', () async {
    final codes = await runEveryAuthFlow();
    final db = opened.database;

    final plain = [
      userPassword,
      dashboardPassword,
      newDashboardPassword,
      ...codes,
    ];

    for (final row in await db.select(db.users).get()) {
      for (final secret in plain) {
        expect(row.toString(), isNot(contains(secret)));
      }
      expect(row.passwordHash.length, 64, reason: 'SHA-256 hex bekleniyor');
      expect(row.passwordSalt.length, 32);
    }

    for (final row in await db.select(db.appSettings).get()) {
      for (final secret in plain) {
        expect(
          row.value,
          isNot(contains(secret)),
          reason: 'app_settings["${row.key}"] düz metin sır taşıyor.',
        );
      }
    }
  });
}
