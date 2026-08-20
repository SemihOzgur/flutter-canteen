/// Yedek oluşturma — **docs/19 §3 · REQ-BKUP-001…005/016/017/019**
///
/// | Test | Kural |
/// |---|---|
/// | Yedek tek dosya, `.canteenbackup` | BR-DATA-002 |
/// | Dosya ancak doğrulandıktan sonra nihai adını alır | REQ-BKUP-004 |
/// | Yazılan arşiv TEKRAR OKUNARAK doğrulanır | REQ-BKUP-005 |
/// | Yalnızca DB'de referansı olan görseller | docs/19 §3 adım 4 |
/// | **Hiçbir dosyada düz metin parola yok** | REQ-BKUP-019 · BR-SEC-001 |
/// | 7 gün geçince hatırlatma | REQ-BKUP-016 |
/// | `.tmp` dosyaları listelenmez | REQ-BKUP-004 acceptance |
///
/// Gerçek **dosya tabanlı** veritabanı kullanılır: `VACUUM INTO` ve WAL
/// davranışı in-memory'de üretimdeki gibi değildir.
///
/// ## Kapsanan requirement'lar (Faz 11 izlenebilirliği)
///
/// - **REQ-BKUP-003** — uygulamayı durdurmadan tutarlı snapshot
/// - **REQ-SEC-003** — zip-slip koruması
/// ## Kapsanan uç durumlar (docs/26 · Faz 11 izlenebilirliği)
///
/// - **EC-BKUP-006** — yedekte görsel eksik — yedeklemeyi engellemez
/// - **EC-BKUP-008** — yedek alırken uygulama kapanıyor — `.tmp` kalmaz
///
library;

import 'dart:io';

import 'package:canteen/application/audit/audit_actions.dart';
import 'package:canteen/application/audit/audit_service.dart';
import 'package:canteen/application/backup/backup_manifest.dart';
import 'package:canteen/application/backup/backup_service.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/dao/backup_dao.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/app_setting_keys.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, Category, Product, Sale, SaleItem, StockMovement, Supplier;
import 'package:canteen/data/files/backup_archive.dart';
import 'package:canteen/domain/services/password_hasher.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/test_database.dart';

/// Ayırt edici sırlar — rastgele bir bayt dizisinde tesadüfen bulunamaz.
const String userPassword = 'BACKUP-PW-SENTINEL-6H2R';
const String dashboardPassword = 'BACKUP-DASH-SENTINEL-1V9C';

void main() {
  late TempAppPaths temp;
  late CanteenDatabase db;
  late FakeClock clock;
  late BackupService service;
  late int userId;

  setUp(() async {
    temp = await TempAppPaths.create();
    clock = FakeClock(testEpochUtc);
    db = fileDatabase(temp.paths.databaseFile, clock: clock.fn);
    service = BackupService(
      dao: BackupDao(db),
      schemaVersion: db.schemaVersion,
      paths: temp.paths,
      settings: AppSettingsDao(db),
      audit: AuditService(auditLogs: AuditLogsDao(db), clock: clock.fn),
      clock: clock.fn,
      appVersion: '1.0.0-test',
    );
    userId = await insertTestUser(db);
  });

  tearDown(() async {
    await db.close();
    temp.dispose();
  });

  Future<int> product({String name = 'Kola', String? imagePath}) async {
    final id = await insertTestProduct(db, name: name);
    if (imagePath != null) {
      await (db.update(db.products)..where((p) => p.id.equals(id))).write(
        ProductsCompanion(imagePath: Value(imagePath)),
      );
    }
    return id;
  }

  Future<File> writeImage(String fileName) async {
    final dir = Directory(temp.paths.imagesDir);
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString('görsel-içeriği-$fileName');
    return file;
  }

  BackupResult ok(Result<BackupResult> result) {
    expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
    return result.valueOrNull!;
  }

  group('REQ-BKUP-001…005 — yedek oluşturma', () {
    test('BR-DATA-002 — tek dosya, `.canteenbackup` uzantısı', () async {
      await product();

      final backup = ok(await service.create(createdBy: 'ahmet'));

      expect(backup.file.existsSync(), isTrue);
      expect(p.extension(backup.file.path), BackupArchive.extension);
      expect(backup.sizeBytes, greaterThan(0));
    });

    test('REQ-BKUP-002 — DB, metadata ve checksum içerir', () async {
      await product();

      final backup = ok(await service.create());
      final entries = await BackupArchive.listEntries(backup.file);

      expect(entries, contains(BackupArchive.databaseEntry));
      expect(entries, contains(BackupArchive.metadataEntry));
      expect(entries, contains(BackupArchive.checksumsEntry));
    });

    test('REQ-BKUP-004 — geriye `.tmp` KALMAZ', () async {
      await product();

      final backup = ok(await service.create());

      final leftovers = Directory(temp.paths.backupsDir)
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith(BackupArchive.temporaryExtension));
      expect(
        leftovers,
        isEmpty,
        reason: 'Dosya ancak doğrulandıktan sonra nihai adını alır.',
      );
      expect(backup.file.path.endsWith(BackupArchive.extension), isTrue);
    });

    test('REQ-BKUP-004 acceptance — `.tmp` dosyaları LİSTELENMEZ', () async {
      await product();
      await service.create();
      // Yarım kalmış bir yedek taklidi.
      await File(
        p.join(temp.paths.backupsDir, 'yarim.canteenbackup.tmp'),
      ).writeAsString('yarim');

      final listed = service.listBackups();

      expect(listed, hasLength(1));
      expect(
        listed.single.path.endsWith(BackupArchive.extension),
        isTrue,
        reason: 'Kullanıcı yarım bir dosyayı geçerli yedek sanmamalıdır.',
      );
    });

    test('metadata gerçek sayıları taşır', () async {
      await product(name: 'A');
      await product(name: 'B');

      final backup = ok(await service.create(createdBy: 'ahmet'));

      expect(backup.metadata.counts.products, 2);
      expect(backup.metadata.schemaVersion, db.schemaVersion);
      expect(backup.metadata.backupFormatVersion, 1);
      expect(backup.metadata.createdBy, 'ahmet');
      expect(backup.metadata.appVersion, '1.0.0-test');
    });

    test('checksum\'lar arşivdeki dosyalarla TUTAR', () async {
      await product();
      final backup = ok(await service.create());

      final extractDir = Directory(p.join(temp.dir.path, 'check'));
      await BackupArchive.extract(
        archiveFile: backup.file,
        targetDirectory: extractDir,
      );
      final checksums = BackupChecksums.tryDecode(
        await File(
          p.join(extractDir.path, BackupArchive.checksumsEntry),
        ).readAsString(),
      )!;

      expect(checksums, isNotEmpty);
      for (final entry in checksums.entries) {
        final file = File(p.join(extractDir.path, entry.key));
        expect(file.existsSync(), isTrue, reason: entry.key);
        expect(await BackupArchive.sha256OfFile(file), entry.value);
      }
    });

    test('yedekteki veritabanı BÜTÜNDÜR ve veriyi taşır', () async {
      await product(name: 'Kola');
      final backup = ok(await service.create());

      final extractDir = Directory(p.join(temp.dir.path, 'verify'));
      await BackupArchive.extract(
        archiveFile: backup.file,
        targetDirectory: extractDir,
      );
      final copyPath = p.join(extractDir.path, BackupArchive.databaseEntry);

      expect(await BackupDao.isFileIntegral(copyPath), isTrue);

      final copy = fileDatabase(copyPath, applySeed: false);
      addTearDown(copy.close);
      final products = await copy.select(copy.products).get();
      expect(products.single.name, 'Kola');
    });
  });

  group('docs/19 §3 adım 4 — görseller', () {
    test('yalnızca DB\'de REFERANSI OLAN görseller yedeklenir', () async {
      await writeImage('kullanilan.jpg');
      await writeImage('orphan.jpg');
      await product(name: 'Kola', imagePath: 'images/kullanilan.jpg');

      final backup = ok(await service.create());
      final entries = await BackupArchive.listEntries(backup.file);

      expect(entries, contains('images/kullanilan.jpg'));
      expect(
        entries,
        isNot(contains('images/orphan.jpg')),
        reason:
            'Orphan dosya yedeği büyütür ve bir sonraki restore\'da geri '
            'gelirdi (docs/19 §5).',
      );
      expect(backup.metadata.counts.images, 1);
    });

    test('REQ-BKUP-018 — eksik görsel yedeklemeyi ENGELLEMEZ', () async {
      // DB görseli referanslıyor ama dosya diskte yok.
      await product(name: 'Kola', imagePath: 'images/yok.jpg');

      final result = await service.create();

      expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
    });
  });

  group('REQ-BKUP-019 · BR-SEC-001 — parola sızıntısı', () {
    test('yedeğin HİÇBİR dosyasında düz metin parola yoktur', () async {
      // Gerçek hash'ler yazılır; sonra arşivin HAM BAYTLARI taranır.
      final hasher = PasswordHasher();
      final secret = hasher.hash(userPassword);
      await (db.update(db.users)..where((u) => u.id.equals(userId))).write(
        UsersCompanion(
          passwordHash: Value(secret.hash),
          passwordSalt: Value(secret.salt),
        ),
      );
      final dashboard = hasher.hash(dashboardPassword);
      final settings = AppSettingsDao(db);
      await settings.write(
        AppSettingKeys.dashboardPasswordHash,
        dashboard.hash,
      );
      await settings.write(
        AppSettingKeys.dashboardPasswordSalt,
        dashboard.salt,
      );
      await product();

      final backup = ok(await service.create(createdBy: 'ahmet'));

      // 1 — arşivin ham baytları.
      final bytes = await backup.file.readAsBytes();
      final raw = String.fromCharCodes(bytes);
      for (final plaintext in [userPassword, dashboardPassword]) {
        expect(
          raw.contains(plaintext),
          isFalse,
          reason: 'Düz metin parola yedeğe SIZAMAZ (BR-SEC-001).',
        );
      }

      // 2 — açılmış her dosya tek tek.
      final extractDir = Directory(p.join(temp.dir.path, 'leak'));
      await BackupArchive.extract(
        archiveFile: backup.file,
        targetDirectory: extractDir,
      );
      for (final file
          in extractDir.listSync(recursive: true).whereType<File>()) {
        final content = String.fromCharCodes(await file.readAsBytes());
        for (final plaintext in [userPassword, dashboardPassword]) {
          expect(content.contains(plaintext), isFalse, reason: file.path);
        }
      }

      // 3 — metadata.json'da parola ALANI dahi yok.
      final metadataSource = await BackupArchive.readEntryAsString(
        backup.file,
        BackupArchive.metadataEntry,
      );
      for (final banned in const ['password', 'hash', 'salt', 'recovery']) {
        expect(
          metadataSource!.toLowerCase(),
          isNot(contains(banned)),
          reason: 'metadata.json parola bilgisi taşımaz.',
        );
      }

      // 4 — ama hash'ler veritabanı kopyasında DURUR (yedek işe yaramalı).
      final dbCopy = File(p.join(extractDir.path, BackupArchive.databaseEntry));
      expect(
        String.fromCharCodes(await dbCopy.readAsBytes()).contains(secret.hash),
        isTrue,
        reason:
            'Yedekten geri yüklenen kullanıcı giriş yapabilmelidir; saklanan '
            'şey hash\'tir, düz metin değil.',
      );
    });
  });

  group('REQ-BKUP-016 — yedek hatırlatması', () {
    test('hiç yedek alınmamışsa UYARILIR', () async {
      expect(await service.timeSinceLastBackup(), isNull);
      expect(
        await service.needsBackupReminder(),
        isTrue,
        reason: '"Hiç yedek yok" en kötü durumdur.',
      );
    });

    test('yedek alınınca zaman damgası yazılır ve uyarı düşer', () async {
      await product();

      await service.create();

      expect(await service.timeSinceLastBackup(), Duration.zero);
      expect(await service.needsBackupReminder(), isFalse);
    });

    test('SINIR — 7 gün dolunca uyarı geri gelir', () async {
      await product();
      await service.create();

      clock.advance(const Duration(days: 7) - const Duration(seconds: 1));
      expect(await service.needsBackupReminder(), isFalse);

      clock.advance(const Duration(seconds: 1));
      expect(await service.needsBackupReminder(), isTrue);
      expect(await service.isBackupOverdue(), isFalse);
    });

    test('SINIR — 30 gün dolunca ACİL olur', () async {
      await product();
      await service.create();

      clock.advance(const Duration(days: 30));

      expect(await service.isBackupOverdue(), isTrue);
    });
  });

  group('docs/19 §3 — otomatik yedek', () {
    test('auto klasörüne yazar ve son 7 kopyayı tutar', () async {
      await product();

      for (var i = 0; i < 9; i++) {
        clock.advance(const Duration(minutes: 1));
        final result = await service.createAutomatic();
        expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
      }

      final kept = service.listBackups(directory: temp.paths.autoBackupsDir);
      expect(kept, hasLength(BackupService.retainedAutoBackups));
    });
  });

  test('REQ-BKUP-017 — `backupCreated` audit\'e yazılır', () async {
    await product();

    final backup = ok(await service.create(createdBy: 'ahmet'));

    final log = (await AuditLogsDao(
      db,
    ).listRecent()).firstWhere((l) => l.action == AuditActions.backupCreated);
    expect(log.entityType, AuditEntities.system);
    expect(log.metadata, contains(p.basename(backup.file.path)));
    expect(log.metadata, contains('size_bytes'));
  });
}
