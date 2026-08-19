/// Kimlik doğrulama denetim kayıtları — **REQ-AUDIT-001/004 · docs/18 §3**
///
/// Faz 6'ya girildiğinde docs/18 §3'te tanımlı `userLoggedIn`, `userLoggedOut`,
/// `passwordChanged`, `userCreated`, `userDeactivated` ve `userRenamed`
/// **hiç yazılmıyordu.** Bu dosya boşluğun kapandığını ve kapalı kaldığını
/// doğrular.
///
/// ⚠️ En kritik iddia: bu kayıtların **hiçbiri** parola, hash veya salt
/// taşımaz (BR-SEC-001 · rules/04 §8).
library;

import 'package:canteen/application/audit/audit_actions.dart';
import 'package:canteen/application/audit/audit_service.dart';
import 'package:canteen/application/auth/auth_service.dart';
import 'package:canteen/application/auth/financial_access_service.dart';
import 'package:canteen/application/auth/session_service.dart';
import 'package:canteen/core/logging/app_logger.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, Category, Product, Sale, SaleItem, StockMovement, Supplier;
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

/// Testte kullanılan ayırt edici parolalar — ham bayt taramasında tesadüfen
/// bulunamayacak kadar özgün.
const String password = 'AUDIT-PW-SENTINEL-4T7B';
const String newPassword = 'AUDIT-PW2-SENTINEL-8L3N';

/// `AuditService`'in sır uyarılarını yakalar.
class _WarningLogger implements AppLogger {
  final List<String> errors = [];

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {
    errors.add(message);
  }

  @override
  void noSuchMethod(Invocation invocation) {}
}

void main() {
  late CanteenDatabase db;
  late AuthService auth;
  late _WarningLogger logger;

  setUp(() {
    db = memoryDatabase();
    logger = _WarningLogger();
    final settings = AppSettingsDao(db);
    auth = AuthService(
      db: db,
      users: UsersDao(db),
      session: SessionService(
        settings: settings,
        users: UsersDao(db),
        clock: () => testEpochUtc,
      ),
      financialAccess: FinancialAccessService(
        db: db,
        settings: settings,
        auditLogs: AuditLogsDao(db),
      ),
      audit: AuditService(
        auditLogs: AuditLogsDao(db),
        clock: () => testEpochUtc,
        logger: logger,
      ),
      clock: () => testEpochUtc,
    );
  });

  tearDown(() => db.close());

  Future<List<AuditLog>> logs() => AuditLogsDao(db).listRecent();

  Future<AuditLog> logOf(String action) async =>
      (await logs()).firstWhere((l) => l.action == action);

  Future<int> createUser({String username = 'ahmet'}) async {
    final result = await auth.createUser(
      username: username,
      password: password,
      displayName: 'Ahmet Yılmaz',
    );
    expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
    return result.valueOrNull!;
  }

  test('userCreated — kullanıcı adı ve görünen ad yazılır', () async {
    final id = await createUser();

    final log = await logOf(AuditActions.userCreated);
    expect(log.entityType, AuditEntities.user);
    expect(log.entityId, id);
    expect(log.newValue, contains('ahmet'));
    expect(log.newValue, contains('Ahmet Yılmaz'));
  });

  test('userLoggedIn — giriş kaydedilir', () async {
    final id = await createUser();

    await auth.login('ahmet', password);

    final log = await logOf(AuditActions.userLoggedIn);
    expect(log.entityId, id);
    expect(log.userId, id);
    expect(log.createdAt, testEpochUtc);
  });

  test('BAŞARISIZ giriş `userLoggedIn` YAZMAZ', () async {
    await createUser();

    await auth.login('ahmet', 'yanlis-parola');

    expect(
      (await logs()).where((l) => l.action == AuditActions.userLoggedIn),
      isEmpty,
      reason:
          'docs/18 §4: audit log\'a yalnızca veriyi DEĞİŞTİREN işlemler '
          'yazılır; başarısız giriş bir değişiklik değildir.',
    );
  });

  test('userLoggedOut — çıkan kullanıcı kaydedilir', () async {
    final id = await createUser();
    await auth.login('ahmet', password);

    await auth.logout();

    final log = await logOf(AuditActions.userLoggedOut);
    expect(
      log.entityId,
      id,
      reason: 'Kimin çıktığı oturum temizlenmeden okunur.',
    );
  });

  test('passwordChanged — değer YAZILMAZ, yalnızca olay', () async {
    final id = await createUser();

    final result = await auth.changePassword(
      userId: id,
      currentPassword: password,
      newPassword: newPassword,
    );
    expect(result.isErr, isFalse);

    final log = await logOf(AuditActions.passwordChanged);
    expect(log.entityId, id);
    expect(
      log.oldValue,
      isNull,
      reason: 'BR-SEC-001: eski parola hiçbir biçimde saklanamaz.',
    );
    expect(log.newValue, isNull);
  });

  test('userDeactivated — yalnızca aktif → pasif geçişinde yazılır', () async {
    final first = await createUser(username: 'ahmet');
    final second = await createUser(username: 'ayse');

    await auth.setActive(second, false);
    expect((await logOf(AuditActions.userDeactivated)).entityId, second);

    // İkinci kez pasifleştirme yeni kayıt üretmez — durum değişmiyor.
    await auth.setActive(second, false);
    expect(
      (await logs()).where((l) => l.action == AuditActions.userDeactivated),
      hasLength(1),
    );

    // Yeniden aktifleştirmenin docs/18 §3'te action'ı YOKTUR ve uydurulmaz.
    await auth.setActive(second, true);
    expect(
      (await logs()).map((l) => l.action),
      isNot(contains('userActivated')),
      reason: 'rules/00 §6: dokümanda olmayan action üretilmez.',
    );
    expect(first, isPositive);
  });

  test('son aktif kullanıcı pasifleştirilemez — kayıt da YAZILMAZ', () async {
    final id = await createUser();

    final result = await auth.setActive(id, false);

    expect(result.isErr, isTrue, reason: 'BR-AUTH-006 · EC-AUTH-005');
    expect(
      (await logs()).where((l) => l.action == AuditActions.userDeactivated),
      isEmpty,
      reason: 'REQ-AUDIT-006: işlem geri alındıysa kayıt da oluşmaz.',
    );
  });

  test('userRenamed — REQ-AUDIT-003, yalnızca değişen alan', () async {
    final id = await createUser();

    await auth.updateDisplayName(id, 'Ahmet Y.');

    final log = await logOf(AuditActions.userRenamed);
    expect(log.oldValue, '{"display_name":"Ahmet Yılmaz"}');
    expect(log.newValue, '{"display_name":"Ahmet Y."}');
  });

  test(
    'BR-SEC-001 — sır koruması auth akışlarında hiç DEVREYE GİRMEZ',
    () async {
      // İki ayrı katman vardır ve ikisi de gereklidir:
      //   1. `AuditService` sır içeren alanı DÜŞÜRÜR (son savunma)
      //   2. Çağıran kod böyle bir alanı zaten GÖNDERMEZ (hijyen)
      //
      // Yalnızca 1'i test etmek 2'nin bozulmasını görünmez kılar: biri
      // `newValue`'ya hash koyduğunda kayıt yine temiz çıkar ve hiçbir şey
      // uyarmaz. Bu test 2. katmanı ölçer.
      final id = await createUser();
      await auth.login('ahmet', password);
      await auth.changePassword(
        userId: id,
        currentPassword: password,
        newPassword: newPassword,
      );
      await auth.updateDisplayName(id, 'Yeni Ad');
      await auth.logout();

      expect(
        logger.errors.where((e) => e.contains('BR-SEC-001')),
        isEmpty,
        reason:
            'Koruma devreye girdiyse çağıran kod sır göndermeye ÇALIŞMIŞ '
            'demektir. Düşürülmüş olması sorunu ortadan kaldırmaz.',
      );
    },
  );

  test(
    'BR-SEC-001 — hiçbir auth kaydı parola, hash veya salt taşımaz',
    () async {
      final id = await createUser();
      await auth.login('ahmet', password);
      await auth.changePassword(
        userId: id,
        currentPassword: password,
        newPassword: newPassword,
      );
      await auth.updateDisplayName(id, 'Yeni Ad');
      await auth.logout();

      final user = await UsersDao(db).findById(id);
      final all = (await logs())
          .map((l) => '${l.oldValue} ${l.newValue} ${l.metadata}')
          .join(' ');

      for (final secret in [
        password,
        newPassword,
        user!.passwordHash,
        user.passwordSalt,
      ]) {
        expect(
          all,
          isNot(contains(secret)),
          reason: 'rules/04 §8: parola, hash ve salt audit log\'a yazılamaz.',
        );
      }
    },
  );
}
