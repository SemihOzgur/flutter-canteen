/// Yedek güvenliği ve hata yolları — **rules/03 §7 · REQ-BKUP-004/005/009**
///
/// Mutasyon testi bu dosyanın kapattığı boşlukları ortaya çıkardı: zip-slip ve
/// zip bomb korumaları **yalnızca iyi niyetli arşivlerle** sınanıyordu, yani
/// hiç sınanmıyordu. Doğrulamanın başarısız olduğu yol da hiç yürütülmemişti.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:canteen/application/audit/audit_service.dart';
import 'package:canteen/application/backup/backup_failures.dart';
import 'package:canteen/application/backup/backup_service.dart';
import 'package:canteen/application/backup/restore_service.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/dao/backup_dao.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, Category, Product, Sale, SaleItem, StockMovement, Supplier;
import 'package:canteen/data/files/backup_archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/test_database.dart';

/// REQ-BKUP-005 — doğrulama adımı **başarısız** olduğunda ne olur?
///
/// Üretimde bu, diskin yazdığını geri veremediği durumdur. Enjeksiyon
/// `@protected` metodun alt sınıfta ezilmesiyle yapılır; üretim API'sine test
/// için parametre eklenmez.
class _FailingVerificationBackupService extends BackupService {
  _FailingVerificationBackupService({
    required super.dao,
    required super.schemaVersion,
    required super.paths,
    required super.settings,
    required super.clock,
  });

  @override
  Future<bool> verifyArchive(
    File archive,
    Map<String, String> checksums,
  ) async => false;
}

/// [BackupService.verifyArchive]'i doğrudan sınamak için — `@protected`
/// sözleşmenin kendisi test edilir, yalnızca çağrıldığı yer değil.
class _ExposedBackupService extends BackupService {
  _ExposedBackupService({
    required super.dao,
    required super.schemaVersion,
    required super.paths,
    required super.settings,
    required super.clock,
  });

  Future<bool> verify(File archive, Map<String, String> checksums) =>
      verifyArchive(archive, checksums);
}

/// REQ-BKUP-009 — güvenlik yedeği alınamazsa restore **başlamamalıdır.**
class _FailingBackupService extends BackupService {
  _FailingBackupService({
    required super.dao,
    required super.schemaVersion,
    required super.paths,
    required super.settings,
    required super.clock,
  });

  @override
  Future<Result<BackupResult>> create({
    String? targetDirectory,
    String? createdBy,
    String fileNamePrefix = 'canteen_backup',
  }) async => const Err(BackupFailures.targetNotWritable);
}

void main() {
  late TempAppPaths temp;
  late CanteenDatabase db;
  late FakeClock clock;

  setUp(() async {
    temp = await TempAppPaths.create();
    clock = FakeClock(testEpochUtc);
    db = fileDatabase(temp.paths.databaseFile, clock: clock.fn);
    await insertTestUser(db);
    await insertTestProduct(db);
  });

  tearDown(() async {
    await db.close();
    temp.dispose();
  });

  BackupService buildService() => BackupService(
    dao: BackupDao(db),
    schemaVersion: db.schemaVersion,
    paths: temp.paths,
    settings: AppSettingsDao(db),
    audit: AuditService(auditLogs: AuditLogsDao(db), clock: clock.fn),
    clock: clock.fn,
  );

  // -------------------------------------------------------------------------
  // rules/03 §7 — kötü niyetli arşiv
  // -------------------------------------------------------------------------

  group('rules/03 §7 — zip-slip', () {
    test('`../` içeren girdi REDDEDİLİR ve hiçbir dosya yazılmaz', () async {
      final evil = File(p.join(temp.dir.path, 'slip.canteenbackup'));
      await BackupArchive.packRaw(
        entries: {
          'zararsiz.txt': [1, 2, 3],
          '../kacak.txt': [9, 9, 9],
        },
        target: evil,
      );
      final outDir = Directory(p.join(temp.dir.path, 'out'));

      await expectLater(
        BackupArchive.extract(archiveFile: evil, targetDirectory: outDir),
        throwsA(isA<BackupArchiveException>()),
      );

      expect(
        File(p.join(temp.dir.path, 'kacak.txt')).existsSync(),
        isFalse,
        reason: 'Hedef dizinin DIŞINA yazılamaz.',
      );
      expect(
        outDir.existsSync() && outDir.listSync().isNotEmpty,
        isFalse,
        reason:
            'Kısmi çıkarma bırakmak, saldırganın yazdırmayı başardığı '
            'dosyaları diskte bırakırdı.',
      );
    });

    test('MUTLAK yol içeren girdi reddedilir', () async {
      final evil = File(p.join(temp.dir.path, 'abs.canteenbackup'));
      await BackupArchive.packRaw(
        entries: {
          '/etc/passwd': [1],
        },
        target: evil,
      );

      await expectLater(
        BackupArchive.extract(
          archiveFile: evil,
          targetDirectory: Directory(p.join(temp.dir.path, 'out2')),
        ),
        throwsA(isA<BackupArchiveException>()),
      );
    });

    test('derin ama GÜVENLİ yol kabul edilir', () async {
      final ok = File(p.join(temp.dir.path, 'ok.canteenbackup'));
      await BackupArchive.packRaw(
        entries: {
          'images/alt/derin.jpg': [1, 2],
        },
        target: ok,
      );
      final outDir = Directory(p.join(temp.dir.path, 'out3'));

      await BackupArchive.extract(archiveFile: ok, targetDirectory: outDir);

      expect(
        File(p.join(outDir.path, 'images', 'alt', 'derin.jpg')).existsSync(),
        isTrue,
      );
    });
  });

  group('rules/03 §7 — zip bomb', () {
    test('açılmamış boyut sınırı aşılırsa REDDEDİLİR', () async {
      final big = File(p.join(temp.dir.path, 'bomb.canteenbackup'));
      // Sıkıştırılınca küçülen ama açılınca büyüyen içerik — bombanın özü.
      await BackupArchive.packRaw(
        entries: {'sisik.bin': Uint8List(200 * 1024)},
        target: big,
      );

      await expectLater(
        BackupArchive.extract(
          archiveFile: big,
          targetDirectory: Directory(p.join(temp.dir.path, 'bomb_out')),
          maxBytes: 100 * 1024,
        ),
        throwsA(isA<BackupArchiveException>()),
      );
    });

    test('sınırın altındaki arşiv açılır', () async {
      final small = File(p.join(temp.dir.path, 'small.canteenbackup'));
      await BackupArchive.packRaw(
        entries: {'kucuk.bin': Uint8List(1024)},
        target: small,
      );
      final outDir = Directory(p.join(temp.dir.path, 'small_out'));

      await BackupArchive.extract(
        archiveFile: small,
        targetDirectory: outDir,
        maxBytes: 100 * 1024,
      );

      expect(File(p.join(outDir.path, 'kucuk.bin')).existsSync(), isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // REQ-BKUP-004/005 — doğrulama başarısız
  // -------------------------------------------------------------------------

  group('REQ-BKUP-004/005 — doğrulama başarısız olursa', () {
    test('dosya nihai adını ALMAZ ve `.tmp` de kalmaz', () async {
      final failing = _FailingVerificationBackupService(
        dao: BackupDao(db),
        schemaVersion: db.schemaVersion,
        paths: temp.paths,
        settings: AppSettingsDao(db),
        clock: clock.fn,
      );

      final result = await failing.create();

      expect(result.failureOrNull, BackupFailures.verificationFailed);
      // `auto/` alt klasörü kurulumda zaten var; yalnızca DOSYALARA bakılır.
      final files = Directory(
        temp.paths.backupsDir,
      ).listSync().whereType<File>();
      expect(
        files,
        isEmpty,
        reason:
            'Doğrulanmamış bir dosya ne nihai adını alır ne de yarım hâliyle '
            'kalır — kullanıcı onu geçerli bir yedek sanmamalıdır.',
      );
    });

    test('REQ-BKUP-005 — checksum TUTMAZSA doğrulama başarısızdır', () async {
      // Sözleşmenin kendisi sınanır: "arşivi tekrar oku ve checksum'ları
      // karşılaştır". Yalnızca mutlu yolu test etmek, karşılaştırmanın hiç
      // yapılmadığı bir implementasyonu da geçirirdi.
      final backup = await buildService().create();
      final file = backup.valueOrNull!.file;
      final exposed = _ExposedBackupService(
        dao: BackupDao(db),
        schemaVersion: db.schemaVersion,
        paths: temp.paths,
        settings: AppSettingsDao(db),
        clock: clock.fn,
      );

      // Gerçek checksum'lar → doğrulama geçer.
      final extractDir = Directory(p.join(temp.dir.path, 'real'));
      await BackupArchive.extract(
        archiveFile: file,
        targetDirectory: extractDir,
      );
      final real = <String, String>{
        BackupArchive.databaseEntry: await BackupArchive.sha256OfFile(
          File(p.join(extractDir.path, BackupArchive.databaseEntry)),
        ),
      };
      expect(await exposed.verify(file, real), isTrue);

      // YANLIŞ checksum → doğrulama BAŞARISIZ olmalıdır.
      expect(
        await exposed.verify(file, {BackupArchive.databaseEntry: 'a' * 64}),
        isFalse,
        reason: 'Uyuşmayan checksum sessizce kabul edilemez.',
      );

      // Arşivde OLMAYAN dosya → başarısız.
      expect(await exposed.verify(file, {'yok.bin': 'b' * 64}), isFalse);
    });

    test('doğrulama BAŞARILIYSA dosya oluşur (kontrol grubu)', () async {
      final result = await buildService().create();

      expect(result.isErr, isFalse);
      expect(
        Directory(temp.paths.backupsDir).listSync().whereType<File>().where(
          (f) => f.path.endsWith(BackupArchive.extension),
        ),
        hasLength(1),
      );
    });
  });

  // -------------------------------------------------------------------------
  // REQ-BKUP-009 — güvenlik yedeği
  // -------------------------------------------------------------------------

  test('REQ-BKUP-009 — güvenlik yedeği alınamazsa restore BAŞLAMAZ', () async {
    // Önce geçerli bir yedek üret (normal servisle).
    final backup = await buildService().create();
    expect(backup.isErr, isFalse);

    final restore = RestoreService(
      paths: temp.paths,
      dao: BackupDao(db),
      // Güvenlik yedeği alamayan servis.
      backupService: _FailingBackupService(
        dao: BackupDao(db),
        schemaVersion: db.schemaVersion,
        paths: temp.paths,
        settings: AppSettingsDao(db),
        clock: clock.fn,
      ),
      supportedSchemaVersion: db.schemaVersion,
      clock: clock.fn,
    );
    final preview = await restore.validate(backup.valueOrNull!.file);
    expect(preview.isErr, isFalse, reason: '${preview.failureOrNull}');

    var closed = false;
    final result = await restore.apply(
      preview: preview.valueOrNull!,
      confirmation: RestoreService.confirmationPhrase,
      closeDatabase: () async => closed = true,
    );

    expect(result.failureOrNull, BackupFailures.safetyBackupFailed);
    expect(
      closed,
      isFalse,
      reason:
          'Güvenlik yedeği olmadan bağlantı bile kapatılmaz; veriye hiç '
          'dokunulmaz.',
    );
    expect(
      File(temp.paths.restoreMarkerFile).existsSync(),
      isFalse,
      reason: 'Başlamayan restore işaret bırakmaz.',
    );
    expect(File(temp.paths.databaseFile).existsSync(), isTrue);
  });
}
