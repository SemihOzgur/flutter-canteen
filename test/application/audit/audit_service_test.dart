/// Denetim kaydı servisi — **REQ-AUDIT-002/003/004/005/006/007 · docs/18**
///
/// | Test | Kural |
/// |---|---|
/// | Sır içeren alanlar **düşürülür** | REQ-AUDIT-004 · BR-SEC-001 |
/// | Düşürülen değer log'a da yazılmaz | rules/04 §8 |
/// | Tanımsız action yazılmaz | rules/00 §6 |
/// | Yazım hatası ana işlemi düşürmez | REQ-AUDIT-007 |
/// | Kayıt işlemle aynı transaction'da | REQ-AUDIT-006 |
/// | Yalnızca değişen alanlar | REQ-AUDIT-003 |
library;

import 'package:canteen/application/audit/audit_actions.dart';
import 'package:canteen/application/audit/audit_service.dart';
import 'package:canteen/core/logging/app_logger.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, Category, Product, Sale, SaleItem, StockMovement, Supplier;
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

/// Yazdığı her satırı bellekte tutan log — sızıntı taraması için.
class _RecordingLogger implements AppLogger {
  final List<String> messages = [];

  @override
  void error(String message, {Object? error, StackTrace? stackTrace}) {
    messages.add('$message $error');
  }

  @override
  void noSuchMethod(Invocation invocation) {
    if (invocation.positionalArguments.isNotEmpty) {
      messages.add('${invocation.positionalArguments.first}');
    }
  }
}

void main() {
  late CanteenDatabase db;
  late _RecordingLogger logger;
  late AuditService service;
  late int userId;

  setUp(() async {
    db = memoryDatabase();
    // `audit_logs.user_id` bir yabancı anahtardır; olmayan bir kullanıcıyla
    // yazım sessizce düşer (REQ-AUDIT-007 gereği doğru davranış) ve test
    // yanlış sebeple kırılırdı.
    userId = await insertTestUser(db);
    logger = _RecordingLogger();
    service = AuditService(
      auditLogs: AuditLogsDao(db),
      clock: () => testEpochUtc,
      logger: logger,
    );
  });

  tearDown(() => db.close());

  Future<List<AuditLog>> logs() => AuditLogsDao(db).listRecent();

  group('REQ-AUDIT-004 · BR-SEC-001 — sır yazılamaz', () {
    const secret = 'SENTINEL-SIR-9Q4X';

    test('parola, hash, salt ve recovery alanları DÜŞÜRÜLÜR', () async {
      await service.record(
        action: AuditActions.passwordChanged,
        entityType: AuditEntities.user,
        entityId: 1,
        newValue: {
          'password': secret,
          'password_hash': secret,
          'passwordSalt': secret,
          'dashboard_recovery_hash': secret,
          'display_name': 'Ahmet',
        },
      );

      final log = (await logs()).single;
      expect(
        log.newValue,
        contains('Ahmet'),
        reason: 'Sır olmayan alanlar korunur — iz tamamen kaybedilmez.',
      );
      expect(log.newValue, isNot(contains(secret)));
      for (final banned in const ['password', 'hash', 'salt', 'recovery']) {
        expect(
          log.newValue!.toLowerCase(),
          isNot(contains(banned)),
          reason: '"$banned" içeren alan adı bile yazılmamalıdır.',
        );
      }
    });

    test('üç alanın da (old/new/metadata) taraması yapılır', () async {
      await service.record(
        action: AuditActions.passwordChanged,
        entityType: AuditEntities.user,
        entityId: 1,
        oldValue: {'passwordHash': secret},
        newValue: {'salt': secret},
        metadata: {'recoveryCode': secret},
      );

      final log = (await logs()).single;
      for (final field in [log.oldValue, log.newValue, log.metadata]) {
        expect(field ?? '', isNot(contains(secret)));
      }
    });

    test('düşürülen DEĞER log dosyasına da yazılmaz', () async {
      // Yasağı log dosyasına taşımak yasağı kaldırmaktır (rules/04 §8).
      await service.record(
        action: AuditActions.passwordChanged,
        entityType: AuditEntities.user,
        entityId: 1,
        newValue: {'password_hash': secret},
      );

      expect(logger.messages, isNotEmpty, reason: 'Olay raporlanmalıdır.');
      for (final message in logger.messages) {
        expect(
          message,
          isNot(contains(secret)),
          reason: 'Log yalnızca ANAHTAR adını yazar, değeri değil.',
        );
        expect(message, contains('password_hash'));
      }
    });

    test('tüm alanlar düşerse kayıt yine yazılır, alan null olur', () async {
      await service.record(
        action: AuditActions.passwordChanged,
        entityType: AuditEntities.user,
        entityId: 7,
        newValue: {'password_hash': secret},
      );

      final log = (await logs()).single;
      expect(log.entityId, 7, reason: 'İz korunur.');
      expect(log.newValue, isNull);
    });
  });

  group('rules/00 §6 — tanımsız action', () {
    test('dokümanda olmayan action YAZILMAZ', () async {
      await service.record(
        action: 'benimUydurdugumIslem',
        entityType: AuditEntities.product,
        entityId: 1,
      );

      expect(await logs(), isEmpty);
      expect(logger.messages.join(), contains('benimUydurdugumIslem'));
    });
  });

  group('REQ-AUDIT-007 — audit hatası ana işlemi düşürmez', () {
    test('serileştirilemeyen metadata exception FIRLATMAZ', () async {
      // docs/18 §9 acceptance criteria: "metadata alanı serileştirilemiyor →
      // satış başarıyla kaydedilir, hata log dosyasına yazılır".
      await expectLater(
        service.record(
          action: AuditActions.saleCompleted,
          entityType: AuditEntities.sale,
          entityId: 1,
          metadata: {'olmaz': Object()},
        ),
        completes,
      );
      expect(logger.messages, isNotEmpty);
    });

    test('veritabanı kapalıyken bile exception FIRLATMAZ', () async {
      await db.close();

      await expectLater(
        service.record(
          action: AuditActions.saleCompleted,
          entityType: AuditEntities.sale,
          entityId: 1,
        ),
        completes,
      );

      // tearDown ikinci kez kapatmasın diye yeniden açılır.
      db = memoryDatabase();
    });
  });

  group('REQ-AUDIT-002/003 — kayıt içeriği', () {
    test('zaman, kullanıcı, işlem, varlık türü ve kimliği yazılır', () async {
      await service.record(
        action: AuditActions.productPriceChanged,
        entityType: AuditEntities.product,
        entityId: 42,
        userId: userId,
      );

      final log = (await logs()).single;
      expect(log.createdAt, testEpochUtc);
      expect(log.userId, userId);
      expect(log.action, 'productPriceChanged');
      expect(log.entityType, 'product');
      expect(log.entityId, 42);
    });

    test('REQ-AUDIT-003 — yalnızca değişen alan saklanır', () async {
      // docs/18 §9 acceptance criteria birebir.
      await service.record(
        action: AuditActions.productPriceChanged,
        entityType: AuditEntities.product,
        entityId: 1,
        oldValue: {'sale_price_minor': 2500},
        newValue: {'sale_price_minor': 3000},
      );

      final log = (await logs()).single;
      expect(log.oldValue, '{"sale_price_minor":2500}');
      expect(log.newValue, '{"sale_price_minor":3000}');
    });

    test('boş harita null yazılır — gereksiz `{}` şişirmez', () async {
      await service.record(
        action: AuditActions.userLoggedIn,
        entityType: AuditEntities.user,
        entityId: 1,
        newValue: const {},
      );

      expect((await logs()).single.newValue, isNull);
    });
  });

  test(
    'REQ-AUDIT-006 — kayıt çağıranın transaction\'ıyla GERİ ALINIR',
    () async {
      // docs/18 §9: "stok güncellemesi hata veriyor → satış kaydı oluşmaz ve
      // saleCompleted audit kaydı da oluşmaz."
      await expectLater(
        db.transaction(() async {
          await service.record(
            action: AuditActions.saleCompleted,
            entityType: AuditEntities.sale,
            entityId: 1,
          );
          throw StateError('işlem yarıda kaldı');
        }),
        throwsStateError,
      );

      expect(
        await logs(),
        isEmpty,
        reason:
            'Audit kaydı işlemle aynı transaction içindedir; işlem geri '
            'alınırsa kayıt da geri alınır.',
      );
    },
  );
}
