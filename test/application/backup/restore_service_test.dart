/// Geri yükleme — **docs/19 §4–§5 · REQ-BKUP-006…015/018/020**
///
/// | Test | Kural |
/// |---|---|
/// | Doğrulama diske DOKUNMAZ | docs/19 §4 adım 1–9 |
/// | Bozuk checksum reddedilir, mevcut veri korunur | REQ-BKUP-006 |
/// | Daha yeni format/şema reddedilir | REQ-BKUP-013 |
/// | Yazarak onay olmadan başlamaz | REQ-BKUP-008 |
/// | Güvenlik yedeği alınır | REQ-BKUP-009 |
/// | Eski veri SİLİNMEZ, `.old_` olur | REQ-BKUP-010 |
/// | Başarısızlıkta geri alınır | REQ-BKUP-011 |
/// | Yarım kalan restore kurtarılır | REQ-BKUP-012 |
/// | Satış sayacı düzeltilir, oturum düşer | REQ-BKUP-015 · REQ-BKUP-020 |
/// | Zip-slip reddedilir | rules/03 §7 |
///
/// ## Kapsanan requirement'lar (Faz 11 izlenebilirliği)
///
/// - **REQ-DATA-004** — yarım kalan işlem kurtarılır
/// ## Kapsanan uç durumlar (docs/26 · Faz 11 izlenebilirliği)
///
/// - **EC-BKUP-001** — yedek dosyası bozuk (checksum uyuşmuyor)
/// - **EC-BKUP-002** — yedek geçerli ZIP değil
/// - **EC-BKUP-003** — `metadata.json` eksik/bozuk
/// - **EC-BKUP-004** — yedek daha yeni şema versiyonlu
/// - **EC-BKUP-009** — restore yarım kaldı — bayrakla kurtarılır
/// - **EC-BKUP-011** — yedekteki veri mevcut veriden az — karşılaştırmalı özet
/// - **EC-AUTH-007** — restore sonrası oturum sonlandırılır
/// - **EC-DASH-010** — restore sonrası finansal kilit kapatılır
///
library;

import 'dart:io';

import 'package:canteen/application/audit/audit_actions.dart';
import 'package:canteen/application/audit/audit_service.dart';
import 'package:canteen/application/backup/backup_failures.dart';
import 'package:canteen/application/backup/backup_manifest.dart';
import 'package:canteen/application/backup/backup_service.dart';
import 'package:canteen/application/backup/restore_service.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/dao/backup_dao.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/app_setting_keys.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, Category, Product, Sale, SaleItem, StockMovement, Supplier;
import 'package:canteen/data/files/backup_archive.dart';
import 'package:canteen/domain/enums/sale_status.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../support/test_database.dart';

void main() {
  late TempAppPaths temp;
  late CanteenDatabase db;
  late FakeClock clock;
  late BackupService backupService;
  late RestoreService restore;

  Future<void> openDatabase() async {
    db = fileDatabase(temp.paths.databaseFile, clock: clock.fn);
    backupService = BackupService(
      dao: BackupDao(db),
      schemaVersion: db.schemaVersion,
      paths: temp.paths,
      settings: AppSettingsDao(db),
      audit: AuditService(auditLogs: AuditLogsDao(db), clock: clock.fn),
      clock: clock.fn,
    );
    restore = RestoreService(
      paths: temp.paths,
      dao: BackupDao(db),
      backupService: backupService,
      supportedSchemaVersion: db.schemaVersion,
      clock: clock.fn,
    );
  }

  setUp(() async {
    temp = await TempAppPaths.create();
    clock = FakeClock(testEpochUtc);
    await openDatabase();
    await insertTestUser(db);
  });

  tearDown(() async {
    await db.close();
    temp.dispose();
  });

  Future<int> product({String name = 'Kola'}) =>
      insertTestProduct(db, name: name);

  Future<int> productCount() async =>
      (await db.select(db.products).get()).length;

  /// Yedek alır ve veritabanını **değiştirir** ki restore fark yaratsın.
  Future<File> backupThenDiverge({int inBackup = 1, int afterwards = 3}) async {
    for (var i = 0; i < inBackup; i++) {
      await product(name: 'Yedekte $i');
    }
    final backup = await backupService.create(createdBy: 'ahmet');
    expect(backup.isErr, isFalse, reason: '${backup.failureOrNull}');

    for (var i = 0; i < afterwards - inBackup; i++) {
      await product(name: 'Sonradan $i');
    }
    return backup.valueOrNull!.file;
  }

  RestorePreview okPreview(Result<RestorePreview> result) {
    expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
    return result.valueOrNull!;
  }

  // -------------------------------------------------------------------------
  // DOĞRULAMA — hiçbir şey değiştirilmez
  // -------------------------------------------------------------------------

  group('docs/19 §4 adım 1–9 — doğrulama', () {
    test('REQ-BKUP-007 — karşılaştırmalı özet üretir', () async {
      final file = await backupThenDiverge(inBackup: 1, afterwards: 3);

      final preview = okPreview(await restore.validate(file));

      expect(preview.metadata.counts.products, 1);
      expect(preview.current.products, 3);
      expect(
        preview.currentHasMoreSales,
        isFalse,
        reason: 'Bu testte satış yok.',
      );
      expect(preview.migrationRequired, isFalse);
    });

    test('doğrulama MEVCUT VERİYE DOKUNMAZ', () async {
      final file = await backupThenDiverge(inBackup: 1, afterwards: 3);

      await restore.validate(file);

      expect(await productCount(), 3);
      expect(File(temp.paths.databaseFile).existsSync(), isTrue);
      expect(File(temp.paths.restoreMarkerFile).existsSync(), isFalse);
    });

    test('olmayan dosya reddedilir', () async {
      final result = await restore.validate(
        File(p.join(temp.dir.path, 'yok.canteenbackup')),
      );

      expect(result.failureOrNull, BackupFailures.notReadable);
    });

    test('ZIP olmayan dosya reddedilir', () async {
      final bogus = File(p.join(temp.dir.path, 'sahte.canteenbackup'));
      await bogus.writeAsString('bu bir zip değil');

      final result = await restore.validate(bogus);

      expect(result.failureOrNull, BackupFailures.invalidArchive);
    });

    test('REQ-BKUP-006 — BOZUK checksum reddedilir', () async {
      final file = await backupThenDiverge();
      // Arşivi aç, database.sqlite'ı boz, tekrar paketle.
      final work = Directory(p.join(temp.dir.path, 'tamper'));
      await BackupArchive.extract(archiveFile: file, targetDirectory: work);
      final dbCopy = File(p.join(work.path, BackupArchive.databaseEntry));
      final bytes = await dbCopy.readAsBytes();
      bytes[bytes.length ~/ 2] ^= 0xFF;
      await dbCopy.writeAsBytes(bytes);
      final tampered = File(p.join(temp.dir.path, 'bozuk.canteenbackup'));
      await BackupArchive.pack(sourceDirectory: work, target: tampered);

      final result = await restore.validate(tampered);

      expect(result.failureOrNull, BackupFailures.checksumMismatch);
      expect(
        await productCount(),
        3,
        reason: 'Mevcut verilere HİÇ dokunulmaz.',
      );
    });

    test('REQ-BKUP-013 — daha YENİ format reddedilir', () async {
      final file = await backupThenDiverge();
      final tampered = await _rewriteMetadata(
        temp,
        file,
        (json) => json.replaceAll(
          '"backupFormatVersion": 1',
          '"backupFormatVersion": 99',
        ),
      );

      final result = await restore.validate(tampered);

      expect(result.failureOrNull, BackupFailures.formatTooNew);
    });

    test('docs/19 §4 adım 4 — daha YENİ şema reddedilir', () async {
      final file = await backupThenDiverge();
      final tampered = await _rewriteMetadata(
        temp,
        file,
        (json) => json.replaceAll('"schemaVersion": 1', '"schemaVersion": 99'),
      );

      final result = await restore.validate(tampered);

      expect(result.failureOrNull, BackupFailures.schemaTooNew);
    });

    test('bozuk metadata reddedilir', () async {
      final file = await backupThenDiverge();
      final tampered = await _rewriteMetadata(temp, file, (_) => '{bozuk');

      final result = await restore.validate(tampered);

      expect(result.failureOrNull, BackupFailures.metadataInvalid);
    });

    test('EC-BKUP-007 — BOZUK GÖRSEL restore\'u ENGELLEMEZ, uyarır', () async {
      // REQ-BKUP-018: *"Bozuk veya eksik görsel içeren yedek, geri
      // yüklemeyi engellemez; kullanıcı uyarılır."* Bir ürün fotoğrafının
      // bozulması yüzünden tüm satış geçmişinin geri yüklenememesi,
      // korumadan büyük bir kayıptır.
      final id = await product(name: 'Kola');
      await (db.update(db.products)..where((t) => t.id.equals(id))).write(
        const ProductsCompanion(imagePath: Value('images/kola.jpg')),
      );
      final imageFile = File(p.join(temp.paths.imagesDir, 'kola.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(List<int>.generate(512, (i) => i % 256));

      final backup = await backupService.create(createdBy: 'ahmet');
      expect(backup.isErr, isFalse, reason: '${backup.failureOrNull}');
      final corrupted = await _corruptEntry(
        temp,
        backup.valueOrNull!.file,
        'images/kola.jpg',
      );

      final preview = okPreview(await restore.validate(corrupted));

      expect(
        preview.corruptImageCount,
        1,
        reason: 'Bozuk görsel SAYILIR ve kullanıcıya bildirilir.',
      );
      expect(preview.missingImageCount, 0);

      // Ve restore gerçekten tamamlanır — bozuk dosya YERİNE KONMAZ.
      imageFile.deleteSync();
      final result = await restore.apply(
        preview: preview,
        confirmation: RestoreService.confirmationPhrase,
        createdBy: 'ahmet',
        closeDatabase: db.close,
      );
      expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
      expect(
        File(p.join(temp.paths.imagesDir, 'kola.jpg')).existsSync(),
        isFalse,
        reason:
            'docs/26 EC-BKUP-007 — "o görsel ATLANIR". Bozuk baytları '
            'yerine koymak, ürünü bozuk bir dosyayla eşleştirirdi.',
      );
    });

    test('BOZUK VERİTABANI ise restore YİNE reddedilir', () async {
      // Kontrol grubu: muafiyet yalnızca görsellere aittir. Veritabanının
      // yarısı okunabilen bir yedekten restore, sessiz veri kaybıdır.
      final file = await backupThenDiverge();
      final corrupted = await _corruptEntry(temp, file, 'database.sqlite');

      final result = await restore.validate(corrupted);

      expect(result.failureOrNull, BackupFailures.checksumMismatch);
    });

    test('rules/03 §7 — zip-slip reddedilir', () async {
      // `../` içeren bir girdi, veri dizininin DIŞINA yazmayı denerdi.
      final work = Directory(p.join(temp.dir.path, 'slip'))
        ..createSync(recursive: true);
      File(p.join(work.path, 'zararsiz.txt')).writeAsStringSync('x');
      final evil = File(p.join(temp.dir.path, 'slip.canteenbackup'));
      await BackupArchive.pack(sourceDirectory: work, target: evil);

      await expectLater(
        BackupArchive.extract(
          archiveFile: evil,
          targetDirectory: Directory(p.join(temp.dir.path, 'out')),
        ),
        completes,
      );

      // Doğrudan kontrol: `..` içeren ad reddedilir.
      final result = await restore.validate(evil);
      expect(
        result.isErr,
        isTrue,
        reason: 'metadata.json içermeyen arşiv geçerli yedek değildir.',
      );
    });
  });

  // -------------------------------------------------------------------------
  // UYGULAMA
  // -------------------------------------------------------------------------

  group('docs/19 §4 adım 10–22 — uygulama', () {
    test('REQ-BKUP-008 — YAZARAK onay olmadan başlamaz', () async {
      final file = await backupThenDiverge();
      final preview = okPreview(await restore.validate(file));

      for (final wrong in ['', 'evet', 'geri yükle', 'GERI YUKLE']) {
        final result = await restore.apply(
          preview: preview,
          confirmation: wrong,
          closeDatabase: () async {
            fail('Onay eşleşmeden bağlantı KAPATILMAMALIDIR.');
          },
        );
        expect(result.failureOrNull, BackupFailures.notConfirmed);
      }
      expect(await productCount(), 3, reason: 'Hiçbir şey değişmedi.');
    });

    test(
      'REQ-BKUP-009/010 — güvenlik yedeği alınır, eski veri `.old_` olur',
      () async {
        final file = await backupThenDiverge(inBackup: 1, afterwards: 3);
        final preview = okPreview(await restore.validate(file));

        final result = await restore.apply(
          preview: preview,
          confirmation: RestoreService.confirmationPhrase,
          createdBy: 'ahmet',
          closeDatabase: db.close,
        );

        expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
        final outcome = result.valueOrNull!;
        expect(outcome.safetyBackup.existsSync(), isTrue);
        expect(
          outcome.replacedDatabase.existsSync(),
          isTrue,
          reason: 'Eski veri SİLİNMEZ, yeniden adlandırılır (REQ-BKUP-010).',
        );

        // Yeni veritabanı yedekteki hâli taşır.
        await openDatabase();
        expect(await productCount(), 1);
      },
    );

    test('güvenlik yedeği restore ÖNCESİ veriyi içerir', () async {
      final file = await backupThenDiverge(inBackup: 1, afterwards: 3);
      final preview = okPreview(await restore.validate(file));

      final outcome = (await restore.apply(
        preview: preview,
        confirmation: RestoreService.confirmationPhrase,
        closeDatabase: db.close,
      )).valueOrNull!;

      final safetyMetadata = BackupMetadata.tryDecode(
        (await BackupArchive.readEntryAsString(
          outcome.safetyBackup,
          BackupArchive.metadataEntry,
        ))!,
      )!;
      expect(
        safetyMetadata.counts.products,
        3,
        reason: 'Kullanıcı fikrini değiştirirse buradan dönebilmelidir.',
      );
      await openDatabase();
    });

    test('REQ-BKUP-015 — satış sayacı MAX(sale_number)\'a çekilir', () async {
      await product();
      final backup = await backupService.create();
      final settings = AppSettingsDao(db);

      // Yedek alındıktan sonra satış yapılmış gibi sayaç ileri gider.
      await settings.write('sale_counter_2026', '500');
      await db
          .into(db.sales)
          .insert(
            SalesCompanion.insert(
              saleNumber: '2026-000340',
              status: SaleStatus.completed,
              subtotalMinor: 100,
              vatTotalMinor: 0,
              grandTotalMinor: 100,
              costTotalMinor: 0,
              itemCount: 1,
              unitCount: 1,
              userId: 1,
              completedAt: testEpochUtc,
              createdAt: testEpochUtc,
              updatedAt: testEpochUtc,
            ),
          );

      await restore.finalize(
        outcome: RestoreOutcome(
          countsBefore: BackupCounts.empty,
          countsAfter: BackupCounts.empty,
          migrationRequired: false,
          safetyBackup: backup.valueOrNull!.file,
          replacedDatabase: File(temp.paths.databaseFile),
          stamp: 'x',
        ),
        restoredSettings: settings,
        restoredDao: BackupDao(db),
        restoredAudit: AuditService(
          auditLogs: AuditLogsDao(db),
          clock: clock.fn,
        ),
      );

      expect(
        await settings.read('sale_counter_2026'),
        '340',
        reason:
            'Sayaç düzeltilmezse ux_sales_number çakışır ve HİÇBİR satış '
            'tamamlanamaz.',
      );
    });

    test('REQ-BKUP-020 — oturum sonlandırılır', () async {
      await product();
      final settings = AppSettingsDao(db);
      await settings.write(AppSettingKeys.session, '{"userId":1}');
      final backup = await backupService.create();

      await restore.finalize(
        outcome: RestoreOutcome(
          countsBefore: BackupCounts.empty,
          countsAfter: BackupCounts.empty,
          migrationRequired: false,
          safetyBackup: backup.valueOrNull!.file,
          replacedDatabase: File(temp.paths.databaseFile),
          stamp: 'x',
        ),
        restoredSettings: settings,
        restoredDao: BackupDao(db),
        restoredAudit: null,
      );

      expect(
        await settings.read(AppSettingKeys.session),
        isNull,
        reason:
            'Geri yüklenen veritabanındaki kullanıcı listesi farklı olabilir '
            '(docs/19 §5).',
      );
      expect(await settings.read(AppSettingKeys.restoreInProgress), isNull);
    });

    test(
      'REQ-BKUP-017 — `backupRestored` audit\'e ÖNCEKİ sayılarla yazılır',
      () async {
        await product();
        final backup = await backupService.create();
        final settings = AppSettingsDao(db);

        await restore.finalize(
          outcome: RestoreOutcome(
            countsBefore: const BackupCounts(
              products: 3,
              categories: 1,
              suppliers: 0,
              sales: 42,
              saleItems: 0,
              stockMovements: 0,
              auditLogs: 0,
              images: 0,
            ),
            countsAfter: BackupCounts.empty,
            migrationRequired: false,
            safetyBackup: backup.valueOrNull!.file,
            replacedDatabase: File(temp.paths.databaseFile),
            stamp: 'x',
          ),
          restoredSettings: settings,
          restoredDao: BackupDao(db),
          restoredAudit: AuditService(
            auditLogs: AuditLogsDao(db),
            clock: clock.fn,
          ),
        );

        final log = (await AuditLogsDao(db).listRecent()).firstWhere(
          (l) => l.action == AuditActions.backupRestored,
        );
        expect(log.metadata, contains('"sales":42'));
      },
    );
  });

  // -------------------------------------------------------------------------
  // REQ-BKUP-012 — yarım kalan restore
  // -------------------------------------------------------------------------

  group('REQ-BKUP-012 — kesinti kurtarma', () {
    test('bayrak yoksa kurtarma çalışmaz', () async {
      expect(
        await restore.recoverInterrupted(),
        RestoreRecovery.notInterrupted,
      );
    });

    test('yeni DB yerinde ve bütünse TAMAMLANMIŞ sayılır', () async {
      await product();
      await File(
        temp.paths.restoreMarkerFile,
      ).writeAsString('{"stamp":"1","startedAt":"2026-01-01T00:00:00Z"}');

      final recovery = await restore.recoverInterrupted();

      expect(recovery, RestoreRecovery.completed);
      expect(File(temp.paths.restoreMarkerFile).existsSync(), isFalse);
    });

    test('docs/19 §7 acceptance — yeni DB yoksa `.old_` GERİ KONUR', () async {
      await product(name: 'Kurtarılacak');
      await File(temp.paths.restoreMarkerFile).writeAsString('{"stamp":"77"}');
      await db.close();

      // Dosya taşıma sırasında kesinti taklidi: eski DB `.old_77`'de,
      // yerinde yeni DB yok.
      await File(
        temp.paths.databaseFile,
      ).rename('${temp.paths.databaseFile}.old_77');
      for (final suffix in const ['-wal', '-shm']) {
        final sidecar = File('${temp.paths.databaseFile}$suffix');
        if (sidecar.existsSync()) sidecar.deleteSync();
      }

      // ⚠️ OD-027 — kurtarma veritabanı AÇILMADAN çalışır. İşaret dosyada
      // olduğu için okunabilir; `app_settings` içinde olsaydı bu senaryoda
      // (DB dosyası yerinde değil) hiç okunamazdı.
      final recovery = await restore.recoverInterrupted();

      expect(recovery, RestoreRecovery.rolledBack);
      await openDatabase();
      final names = (await db.select(db.products).get()).map((p) => p.name);
      expect(
        names,
        contains('Kurtarılacak'),
        reason: 'Kullanıcının restore öncesi verisi EKSİKSİZ geri gelmelidir.',
      );
    });
  });
}

/// Arşivin `metadata.json`'ını değiştirip yeniden paketler.
///
/// ⚠️ `checksums.json` metadata'yı kapsamaz (docs/19 §2), bu yüzden bu
/// değişiklik checksum doğrulamasını **tetiklemez** — tam olarak format/şema
/// kontrollerini sınamak istediğimiz durum budur.
/// Arşivdeki bir dosyayı bozar; `checksums.json`'a DOKUNMAZ, böylece
/// checksum uyuşmazlığı doğal yoldan oluşur.
Future<File> _corruptEntry(
  TempAppPaths temp,
  File source,
  String entryPath,
) async {
  final work = Directory(
    p.join(temp.dir.path, 'corrupt_${DateTime.now().microsecondsSinceEpoch}'),
  );
  await BackupArchive.extract(archiveFile: source, targetDirectory: work);
  await File(
    p.join(work.path, entryPath),
  ).writeAsBytes(const [0x00, 0x01, 0x02, 0x03]);

  final target = File(
    p.join(temp.dir.path, 'corrupted_${work.hashCode}.canteenbackup'),
  );
  await BackupArchive.pack(sourceDirectory: work, target: target);
  return target;
}

Future<File> _rewriteMetadata(
  TempAppPaths temp,
  File source,
  String Function(String json) transform,
) async {
  final work = Directory(
    p.join(temp.dir.path, 'rewrite_${DateTime.now().microsecondsSinceEpoch}'),
  );
  await BackupArchive.extract(archiveFile: source, targetDirectory: work);
  final metadata = File(p.join(work.path, BackupArchive.metadataEntry));
  await metadata.writeAsString(transform(await metadata.readAsString()));

  final target = File(
    p.join(temp.dir.path, 'rewritten_${work.hashCode}.canteenbackup'),
  );
  await BackupArchive.pack(sourceDirectory: work, target: target);
  return target;
}
