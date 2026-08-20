/// Yedek oluşturma — **docs/19 §3 · REQ-BKUP-001…005/016/017/019**
///
/// > *"Backup bu projede bir özellik değil, **varoluşsal bir gerekliliktir**."*
/// > (docs/19 §1)
///
/// Backend yok, cloud yok: tek kopya veri, tek diskte. Bu servis
/// [RSK-005](../../../docs/29-risks.md)'in tek savunmasıdır.
///
/// ## docs/19 §3'ün 12 adımı
///
/// ```text
///  2. temp/backup_<ts>/ oluştur
///  3. VACUUM INTO database.sqlite      ← uygulamayı DURDURMADAN tutarlı kopya
///  4. images/ kopyala (yalnızca DB'de referansı olanlar)
///  5. SHA-256 → checksums.json
///  6. metadata.json (counts sorgularla)
///  7. ZIP → hedef klasöre `.tmp` olarak
///  8. ZIP'i TEKRAR AÇ ve doğrula
///  9. .tmp → .canteenbackup                ← ATOMİK ADIM
/// 10. temp temizle
/// 11. audit: backupCreated
/// 12. app_settings['last_backup_at']
/// ```
///
/// **Adım 9 kritiktir** (REQ-BKUP-004): dosya ancak tamamen yazılıp
/// doğrulandığında nihai adını alır. Yedekleme sırasında elektrik keserse
/// geriye yalnızca bir `.tmp` kalır ve kullanıcı onu geçerli bir yedek sanmaz.
///
/// ## Parola sızmaz — REQ-BKUP-019
///
/// Yedek düz metin parola **içermez**: veritabanında zaten yalnızca salt'lı
/// hash vardır (BR-SEC-001) ve `metadata.json` parola alanı taşımaz. Bu iddia
/// `test/application/backup/` içinde ham bayt taramasıyla doğrulanır.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../core/paths/app_paths.dart';
import '../../core/result/result.dart';
import '../../core/version/app_version.dart' as app;
import '../../data/dao/backup_dao.dart';
import '../../data/dao/daos.dart';
import '../../data/db/app_setting_keys.dart';
import '../../data/files/backup_archive.dart';
import '../audit/audit_actions.dart';
import '../audit/audit_service.dart';
import 'backup_failures.dart';
import 'backup_manifest.dart';

/// Oluşturulan yedeğin özeti.
class BackupResult {
  final File file;
  final BackupMetadata metadata;

  const BackupResult({required this.file, required this.metadata});

  int get sizeBytes => file.existsSync() ? file.lengthSync() : 0;
}

class BackupService {
  /// REQ-BKUP-016 — bu süreden uzun süredir yedek alınmadıysa uyarılır.
  static const Duration reminderThreshold = Duration(days: 7);

  /// docs/19 §3 — 30 günü geçince uyarı kırmızıya döner.
  static const Duration urgentReminderThreshold = Duration(days: 30);

  /// docs/19 §3 — otomatik yedeklerde saklanan kopya sayısı.
  static const int retainedAutoBackups = 7;

  final BackupDao _dao;
  final int _schemaVersion;
  final AppPaths _paths;
  final AppSettingsDao _settings;
  final AuditService? _audit;
  final AppLogger? _logger;
  final String _appVersion;
  final DateTime Function() _clock;

  BackupService({
    required BackupDao dao,
    required int schemaVersion,
    required AppPaths paths,
    required AppSettingsDao settings,
    required DateTime Function() clock,
    AuditService? audit,
    AppLogger? logger,
    String appVersion = app.appVersion,
  }) : _dao = dao,
       _schemaVersion = schemaVersion,
       _paths = paths,
       _settings = settings,
       _audit = audit,
       _logger = logger,
       _appVersion = appVersion,
       _clock = clock;

  /// docs/19 §3 — yedek oluşturur.
  ///
  /// [targetDirectory] verilmezse `<veri dizini>/backups/` kullanılır.
  /// [fileNamePrefix] otomatik yedeklerde `pre_restore` gibi bir ad verir.
  Future<Result<BackupResult>> create({
    String? targetDirectory,
    String? createdBy,
    String fileNamePrefix = 'canteen_backup',
  }) async {
    final now = _clock().toUtc();
    final stamp = _stamp(now);
    final workDir = Directory(p.join(_paths.tempDir, 'backup_$stamp'));
    final targetDir = Directory(targetDirectory ?? _paths.backupsDir);

    try {
      // Adım 2 — geçici çalışma klasörü.
      if (workDir.existsSync()) workDir.deleteSync(recursive: true);
      await workDir.create(recursive: true);
      await targetDir.create(recursive: true);

      // Adım 3 — VACUUM INTO. Uygulamayı durdurmaz ve WAL'daki tamamlanmış
      // işlemleri de içerir (REQ-BKUP-003).
      final databaseCopy = File(
        p.join(workDir.path, BackupArchive.databaseEntry),
      );
      await _dao.snapshotInto(databaseCopy.path);
      if (!databaseCopy.existsSync() || databaseCopy.lengthSync() == 0) {
        return const Err(BackupFailures.snapshotFailed);
      }

      // Adım 4 — yalnızca DB'de **referansı olan** görseller.
      //
      // Orphan dosyaları da kopyalamak yedeği gereksiz büyütür ve bir sonraki
      // restore'da onları geri getirirdi (docs/19 §5 — orphan taraması).
      final referenced = await _dao.referencedImagePaths();
      final imagesBytes = await _copyImages(referenced, workDir);

      // Adım 5 — checksum'lar.
      final checksums = <String, String>{};
      for (final entity in workDir.listSync(recursive: true)) {
        if (entity is! File) continue;
        final relative = p
            .relative(entity.path, from: workDir.path)
            .replaceAll(r'\', '/');
        checksums[relative] = await BackupArchive.sha256OfFile(entity);
      }
      await File(
        p.join(workDir.path, BackupArchive.checksumsEntry),
      ).writeAsString(BackupChecksums.encode(checksums));

      // Adım 6 — metadata.
      final metadata = BackupMetadata(
        backupFormatVersion: BackupMetadata.currentFormatVersion,
        schemaVersion: _schemaVersion,
        appVersion: _appVersion,
        createdAtUtc: now,
        createdBy: createdBy,
        platform: Platform.operatingSystem,
        counts: BackupCounts.fromJson({
          ...await _dao.tableCounts(),
          'images': referenced.length,
        }),
        databaseBytes: databaseCopy.lengthSync(),
        imagesBytes: imagesBytes,
      );
      await File(
        p.join(workDir.path, BackupArchive.metadataEntry),
      ).writeAsString(metadata.encode());

      // Adım 7 — ZIP, önce `.tmp`.
      final finalFile = File(
        p.join(
          targetDir.path,
          '${fileNamePrefix}_$stamp${BackupArchive.extension}',
        ),
      );
      final tempFile = File(
        '${finalFile.path}${BackupArchive.temporaryExtension}',
      );
      if (tempFile.existsSync()) await tempFile.delete();
      await BackupArchive.pack(sourceDirectory: workDir, target: tempFile);

      // Adım 8 — TEKRAR AÇ ve doğrula (REQ-BKUP-005).
      //
      // Yazdığımız arşivi okumadan "yedek alındı" demek, kullanıcıya
      // olmayan bir güvence vermektir.
      if (!await verifyArchive(tempFile, checksums)) {
        await tempFile.delete();
        return const Err(BackupFailures.verificationFailed);
      }

      // Adım 9 — ATOMİK: dosya ancak şimdi nihai adını alır.
      if (finalFile.existsSync()) await finalFile.delete();
      await tempFile.rename(finalFile.path);

      // Adım 11–12.
      await _audit?.record(
        action: AuditActions.backupCreated,
        entityType: AuditEntities.system,
        at: now,
        // docs/18 §3 — dosya adı, boyut, kayıt sayıları.
        metadata: {
          'file_name': p.basename(finalFile.path),
          'size_bytes': finalFile.lengthSync(),
          'counts': metadata.counts.toJson(),
        },
      );
      await _settings.write(
        AppSettingKeys.lastBackupAt,
        '${now.millisecondsSinceEpoch}',
      );

      return Ok(BackupResult(file: finalFile, metadata: metadata));
    } on Object catch (error, stackTrace) {
      _logger?.error(
        'Yedek oluşturulamadı.',
        error: error,
        stackTrace: stackTrace,
      );
      return const Err(BackupFailures.targetNotWritable);
    } finally {
      // Adım 10 — geçici klasör her koşulda temizlenir.
      if (workDir.existsSync()) {
        try {
          workDir.deleteSync(recursive: true);
        } on Object {
          // Temizlik hatası yedeği geçersiz kılmaz.
        }
      }
    }
  }

  /// docs/19 §3 — günlük otomatik yedek.
  ///
  /// ⚠️ **Aynı diskte tutulur**; disk arızasına karşı koruma sağlamaz.
  /// Kullanıcıya bu açıkça belirtilir ve harici ortama manuel yedek alması
  /// önerilir (docs/19 §3).
  Future<Result<BackupResult>> createAutomatic({String? createdBy}) async {
    final result = await create(
      targetDirectory: _paths.autoBackupsDir,
      createdBy: createdBy,
      fileNamePrefix: 'auto',
    );
    if (result.isOk) await pruneAutoBackups();
    return result;
  }

  /// docs/19 §3 — son [retainedAutoBackups] otomatik yedek tutulur.
  Future<void> pruneAutoBackups() async {
    final dir = Directory(_paths.autoBackupsDir);
    if (!dir.existsSync()) return;

    final backups =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith(BackupArchive.extension))
            .toList()
          ..sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );

    for (final stale in backups.skip(retainedAutoBackups)) {
      try {
        stale.deleteSync();
      } on Object {
        // Silinemeyen eski yedek bir hata değildir.
      }
    }
  }

  /// REQ-BKUP-016 — son yedeğin üzerinden geçen süre; hiç yedek yoksa `null`.
  Future<Duration?> timeSinceLastBackup() async {
    final raw = await _settings.read(AppSettingKeys.lastBackupAt);
    final millis = int.tryParse(raw ?? '');
    if (millis == null) return null;
    return _clock().toUtc().difference(
      DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true),
    );
  }

  /// Hiç yedek alınmamışsa da **uyarılır**: "hiç yedek yok" en kötü durumdur.
  Future<bool> needsBackupReminder() async {
    final elapsed = await timeSinceLastBackup();
    return elapsed == null || elapsed >= reminderThreshold;
  }

  Future<bool> isBackupOverdue() async {
    final elapsed = await timeSinceLastBackup();
    return elapsed != null && elapsed >= urgentReminderThreshold;
  }

  /// Geri yükleme ekranında listelenebilecek yedekler.
  ///
  /// REQ-BKUP-004 acceptance criteria: yarım kalmış `.tmp` dosyaları
  /// **listelenmez** — kullanıcı onları geçerli bir yedek sanmamalıdır.
  List<File> listBackups({String? directory}) {
    final dir = Directory(directory ?? _paths.backupsDir);
    if (!dir.existsSync()) return const [];
    return dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith(BackupArchive.extension))
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
  }

  // --- Yardımcılar ---------------------------------------------------------

  Future<int> _copyImages(List<String> relativePaths, Directory workDir) async {
    if (relativePaths.isEmpty) return 0;
    final imagesDir = Directory(p.join(workDir.path, 'images'));
    await imagesDir.create(recursive: true);

    var bytes = 0;
    for (final relative in relativePaths) {
      final source = File(p.join(_paths.imagesDir, p.basename(relative)));
      // REQ-BKUP-018: eksik görsel yedeklemeyi **engellemez**.
      if (!source.existsSync()) continue;
      final target = File(p.join(imagesDir.path, p.basename(relative)));
      await source.copy(target.path);
      bytes += target.lengthSync();
    }
    return bytes;
  }

  /// Adım 8 — arşivi geçici bir yere çıkarıp checksum'ları yeniden hesaplar.
  ///
  /// **REQ-BKUP-005'in tamamı budur:** yazdığımız arşivi okumadan "yedek
  /// alındı" demek, kullanıcıya olmayan bir güvence vermektir.
  ///
  /// **Ezilebilir olması bilinçlidir:** testler alt sınıf yazıp hata enjekte
  /// eder (Faz 5'teki `_FailingSaleRepository` deseni). Üretim API'sine test
  /// için parametre eklenmez.
  ///
  /// `@protected` kullanılmadı: o anotasyon `package:flutter/foundation`'dan
  /// gelir ve `rules/01 §1` application katmanında Flutter import'unu
  /// yasaklar — kural bir anotasyon rahatlığı için esnetilmez.
  Future<bool> verifyArchive(File archive, Map<String, String> expected) async {
    final verifyDir = Directory(
      p.join(_paths.tempDir, 'verify_${_stamp(_clock().toUtc())}'),
    );
    try {
      await BackupArchive.extract(
        archiveFile: archive,
        targetDirectory: verifyDir,
      );
      for (final entry in expected.entries) {
        final file = File(p.join(verifyDir.path, entry.key));
        if (!file.existsSync()) return false;
        if (await BackupArchive.sha256OfFile(file) != entry.value) return false;
      }
      // Veritabanı gerçekten açılabiliyor mu?
      return await BackupDao.isFileIntegral(
        p.join(verifyDir.path, BackupArchive.databaseEntry),
      );
    } on Object catch (error, stackTrace) {
      _logger?.error(
        'Yedek doğrulanamadı.',
        error: error,
        stackTrace: stackTrace,
      );
      return false;
    } finally {
      if (verifyDir.existsSync()) {
        try {
          verifyDir.deleteSync(recursive: true);
        } on Object {
          // yok say
        }
      }
    }
  }

  /// `20260813_1502` — dosya adında sıralanabilir ve okunabilir.
  static String _stamp(DateTime utc) {
    final local = utc.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.year}${two(local.month)}${two(local.day)}_'
        '${two(local.hour)}${two(local.minute)}${two(local.second)}';
  }
}
