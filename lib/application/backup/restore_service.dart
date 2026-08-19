/// Geri yükleme — **docs/19 §4–§5 · REQ-BKUP-006…015/018/020**
///
/// > *"Restore, uygulamanın **en tehlikeli işlemidir** — mevcut tüm veriyi
/// > değiştirir."* (docs/19 §4)
///
/// ## İki aşama kesin olarak ayrıdır
///
/// ```text
/// DOĞRULAMA   (adım 1–9)   →  HİÇBİR ŞEY DEĞİŞTİRİLMEZ
///     ▼        kullanıcı karşılaştırmalı özeti görür, YAZARAK onaylar
/// UYGULAMA    (adım 10–22) →  güvenlik yedeği → yeniden adlandır → taşı
/// ```
///
/// [validate] diske **dokunmaz**: bozuk bir yedek, mevcut veri hiç riske
/// girmeden reddedilir (REQ-BKUP-006 acceptance criteria).
///
/// ## Eski veri SİLİNMEZ
///
/// REQ-BKUP-010 · docs/19 §4 adım 13: mevcut dosyalar `.old_<ts>` olarak
/// **yeniden adlandırılır.** Restore beklenmedik şekilde başarısız olsa bile
/// veri diskte durur ve elle kurtarılabilir.
///
/// ## Yarım kalan restore — OD-027
///
/// REQ-BKUP-012: işaret **veritabanının dışında**, `restore_in_progress.json`
/// dosyasında tutulur. docs/19 §4 adım 10 bunu `app_settings` içinde tarif
/// eder ama orada işlemez: restore veritabanı dosyasını değiştirir, dolayısıyla
/// bayrak **tam da tespit etmesi gereken anda** (dosya taşınırken kesinti)
/// veritabanıyla birlikte kaybolur. Dosya, veritabanı hiç açılamadan okunur.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/logging/app_logger.dart';
import '../../core/paths/app_paths.dart';
import '../../core/result/result.dart';
import '../../data/dao/backup_dao.dart';
import '../../data/dao/daos.dart';
import '../../data/db/app_setting_keys.dart';
import '../../data/files/backup_archive.dart';
import '../audit/audit_actions.dart';
import '../audit/audit_service.dart';
import 'backup_failures.dart';
import 'backup_manifest.dart';
import 'backup_service.dart';

/// docs/19 §4 — doğrulama aşamasının sonucu.
///
/// Kullanıcıya gösterilen karşılaştırmalı özet budur (REQ-BKUP-007).
class RestorePreview {
  final File file;
  final BackupMetadata metadata;

  /// Şu anki veritabanının sayıları — "ne kaybolacak" bunun üzerinden anlatılır.
  final BackupCounts current;

  /// docs/19 §4 adım 4 — yedek daha eski şemalı; restore sonrası migration
  /// çalıştırılacak (REQ-BKUP-014). Kullanıcıya bildirilir.
  final bool migrationRequired;

  /// REQ-BKUP-018 — yedekte eksik görsel var; **engelleyici değildir.**
  final int missingImageCount;

  const RestorePreview({
    required this.file,
    required this.metadata,
    required this.current,
    required this.migrationRequired,
    required this.missingImageCount,
  });

  /// docs/19 §4 — "şu anki veri daha fazla kayıt içeriyor" durumu **açıkça
  /// vurgulanır.**
  bool get currentHasMoreSales => current.sales > metadata.counts.sales;

  int get salesAtRisk =>
      currentHasMoreSales ? current.sales - metadata.counts.sales : 0;
}

class RestoreService {
  /// REQ-BKUP-008 — kullanıcı bunu **yazarak** onaylar.
  ///
  /// Geri alınamaz bir işlem için kasıtlı bir sürtünmedir (docs/19 §4).
  static const String confirmationPhrase = 'GERİ YÜKLE';

  /// docs/19 §4 adım 22 — `.old_<ts>` dosyaları bu süre sonunda temizlenir.
  static const Duration retainReplacedData = Duration(days: 7);

  final AppPaths _paths;
  final BackupDao _dao;
  final BackupService _backupService;
  final int _supportedSchemaVersion;
  final AppLogger? _logger;
  final DateTime Function() _clock;

  RestoreService({
    required AppPaths paths,
    required BackupDao dao,
    required BackupService backupService,
    required int supportedSchemaVersion,
    required DateTime Function() clock,
    AppLogger? logger,
  }) : _paths = paths,
       _dao = dao,
       _backupService = backupService,
       _supportedSchemaVersion = supportedSchemaVersion,
       _logger = logger,
       _clock = clock;

  // -------------------------------------------------------------------------
  // DOĞRULAMA — docs/19 §4 adım 1–9. HİÇBİR ŞEY DEĞİŞTİRİLMEZ.
  // -------------------------------------------------------------------------

  Future<Result<RestorePreview>> validate(File file) async {
    if (!file.existsSync()) return const Err(BackupFailures.notReadable);

    // Adım 1–2 — geçerli ZIP mi, metadata okunabiliyor mu?
    final String? metadataSource;
    try {
      metadataSource = await BackupArchive.readEntryAsString(
        file,
        BackupArchive.metadataEntry,
      );
    } on Object catch (error, stackTrace) {
      _logger?.error('Yedek açılamadı.', error: error, stackTrace: stackTrace);
      return const Err(BackupFailures.invalidArchive);
    }
    if (metadataSource == null) return const Err(BackupFailures.invalidArchive);

    final metadata = BackupMetadata.tryDecode(metadataSource);
    if (metadata == null) return const Err(BackupFailures.metadataInvalid);

    // Adım 3 — REQ-BKUP-013.
    if (metadata.backupFormatVersion > BackupMetadata.currentFormatVersion) {
      return const Err(BackupFailures.formatTooNew);
    }
    // Adım 4 — daha yeni şema reddedilir; daha eskisi migration'a gider.
    if (metadata.schemaVersion > _supportedSchemaVersion) {
      return const Err(BackupFailures.schemaTooNew);
    }

    // Adım 5–6 — checksum'lar. Arşiv geçici bir yere çıkarılır; **veri
    // dizinine dokunulmaz.**
    final inspectDir = Directory(
      p.join(_paths.tempDir, 'restore_check_${_stamp()}'),
    );
    try {
      await BackupArchive.extract(
        archiveFile: file,
        targetDirectory: inspectDir,
      );

      final checksumsFile = File(
        p.join(inspectDir.path, BackupArchive.checksumsEntry),
      );
      final databaseFile = File(
        p.join(inspectDir.path, BackupArchive.databaseEntry),
      );
      if (!checksumsFile.existsSync() || !databaseFile.existsSync()) {
        return const Err(BackupFailures.invalidArchive);
      }

      final checksums = BackupChecksums.tryDecode(
        await checksumsFile.readAsString(),
      );
      if (checksums == null) return const Err(BackupFailures.metadataInvalid);

      var missingImages = 0;
      for (final entry in checksums.entries) {
        final target = File(p.join(inspectDir.path, entry.key));
        if (!target.existsSync()) {
          // REQ-BKUP-018 — eksik GÖRSEL engellemez; eksik veritabanı engeller.
          if (entry.key.startsWith(BackupArchive.imagesPrefix)) {
            missingImages++;
            continue;
          }
          return const Err(BackupFailures.checksumMismatch);
        }
        if (await BackupArchive.sha256OfFile(target) != entry.value) {
          return const Err(BackupFailures.checksumMismatch);
        }
      }

      // Adım 7 — integrity_check.
      if (!await BackupDao.isFileIntegral(databaseFile.path)) {
        return const Err(BackupFailures.databaseCorrupt);
      }

      return Ok(
        RestorePreview(
          file: file,
          metadata: metadata,
          current: await _currentCounts(),
          migrationRequired: metadata.schemaVersion < _supportedSchemaVersion,
          missingImageCount: missingImages,
        ),
      );
    } on BackupArchiveException catch (error) {
      // Zip-slip / zip bomb — rules/03 §7.
      _logger?.error('Yedek reddedildi: ${error.message}');
      return const Err(BackupFailures.invalidArchive);
    } on Object catch (error, stackTrace) {
      _logger?.error(
        'Yedek doğrulanamadı.',
        error: error,
        stackTrace: stackTrace,
      );
      return const Err(BackupFailures.invalidArchive);
    } finally {
      _deleteQuietly(inspectDir);
    }
  }

  // -------------------------------------------------------------------------
  // UYGULAMA — docs/19 §4 adım 10–22.
  // -------------------------------------------------------------------------

  /// [confirmation] tam olarak [confirmationPhrase] olmalıdır (REQ-BKUP-008).
  ///
  /// [closeDatabase] docs/19 §4 **adım 12**'dir ve çağıran tarafından
  /// verilir: bağlantı yaşam döngüsü bu servise ait değildir (docs/03 §6).
  /// Ama **sırası** aittir — güvenlik yedeği (adım 11) bağlantı açıkken
  /// alınmalı, dosya taşıma (adım 13) ise kapalıyken yapılmalıdır. Windows'ta
  /// açık bir bağlantı dosyanın taşınmasını engeller (rules/05 §6).
  Future<Result<RestoreOutcome>> apply({
    required RestorePreview preview,
    required String confirmation,
    required Future<void> Function() closeDatabase,
    String? createdBy,
  }) async {
    if (confirmation.trim() != confirmationPhrase) {
      return const Err(BackupFailures.notConfirmed);
    }

    final now = _clock().toUtc();
    final stamp = _stamp();
    final before = preview.current;

    // Adım 10 — kesinti tespiti için işaret DOSYASI (OD-027).
    await File(_paths.restoreMarkerFile).writeAsString(
      jsonEncode({
        'startedAt': now.toIso8601String(),
        'sourceFile': preview.file.path,
        'stamp': stamp,
      }),
    );

    // Adım 11 — GÜVENLİK YEDEĞİ. Başarısızsa restore HİÇ başlamaz.
    final safety = await _backupService.create(
      targetDirectory: _paths.autoBackupsDir,
      createdBy: createdBy,
      fileNamePrefix: 'pre_restore',
    );
    if (safety.isErr) {
      await _clearMarker();
      return const Err(BackupFailures.safetyBackupFailed);
    }

    // Adım 12 — bağlantı kapatılır. Güvenlik yedeğinden SONRA, dosya
    // taşımadan ÖNCE: sıra bu servisin sorumluluğudur.
    await closeDatabase();

    final extractDir = Directory(p.join(_paths.tempDir, 'restore_$stamp'));
    final databaseFile = File(_paths.databaseFile);
    final imagesDir = Directory(_paths.imagesDir);
    final replacedDatabase = File('${_paths.databaseFile}.old_$stamp');
    final replacedImages = Directory('${_paths.imagesDir}.old_$stamp');

    try {
      await BackupArchive.extract(
        archiveFile: preview.file,
        targetDirectory: extractDir,
      );

      // Adım 13 — SİLME DEĞİL, yeniden adlandırma (REQ-BKUP-010).
      if (databaseFile.existsSync()) {
        await databaseFile.rename(replacedDatabase.path);
      }
      // WAL yan dosyaları da taşınmalıdır; kalırlarsa yeni veritabanının
      // başlığıyla uyuşmayan bir WAL bulunur ve açılış bozulur.
      for (final suffix in const ['-wal', '-shm']) {
        final sidecar = File('${_paths.databaseFile}$suffix');
        if (sidecar.existsSync()) {
          await sidecar.rename('${replacedDatabase.path}$suffix');
        }
      }
      if (imagesDir.existsSync()) {
        await imagesDir.rename(replacedImages.path);
      }

      // Adım 14 — yedekten çıkanları yerine taşı.
      await Directory(_paths.dataDir).create(recursive: true);
      await File(
        p.join(extractDir.path, BackupArchive.databaseEntry),
      ).copy(_paths.databaseFile);

      await imagesDir.create(recursive: true);
      final extractedImages = Directory(p.join(extractDir.path, 'images'));
      if (extractedImages.existsSync()) {
        for (final image in extractedImages.listSync().whereType<File>()) {
          await image.copy(p.join(imagesDir.path, p.basename(image.path)));
        }
      }

      // Adım 15 — integrity_check.
      if (!await BackupDao.isFileIntegral(_paths.databaseFile)) {
        await _rollback(replacedDatabase, replacedImages, stamp);
        return const Err(BackupFailures.verificationRolledBack);
      }

      return Ok(
        RestoreOutcome(
          countsBefore: before,
          countsAfter: preview.metadata.counts,
          migrationRequired: preview.migrationRequired,
          safetyBackup: safety.valueOrNull!.file,
          replacedDatabase: replacedDatabase,
          stamp: stamp,
        ),
      );
    } on Object catch (error, stackTrace) {
      _logger?.error(
        'Geri yükleme başarısız; önceki veri geri konuyor.',
        error: error,
        stackTrace: stackTrace,
      );
      await _rollback(replacedDatabase, replacedImages, stamp);
      return const Err(BackupFailures.verificationRolledBack);
    } finally {
      _deleteQuietly(extractDir);
    }
  }

  /// docs/19 §4 adım 17–21 — veritabanı **yeniden açıldıktan sonra** çalışır.
  ///
  /// Ayrı bir metottur çünkü aradaki adımlar (bağlantıyı aç, gerekiyorsa
  /// migration) bu servisin dışındadır: bağlantı yaşam döngüsü uygulamanın
  /// bootstrap'ine aittir (docs/03 §6).
  ///
  /// ⚠️ [restoredSettings], [restoredDao] ve [restoredAudit] **yeni**
  /// veritabanına bağlı olmalıdır. Bu servisin kendi bağımlılıkları eski
  /// veritabanını gösterir; oraya yazılan bir denetim kaydı restore ile
  /// birlikte zaten kaybolurdu.
  Future<void> finalize({
    required RestoreOutcome outcome,
    required AppSettingsDao restoredSettings,
    required BackupDao restoredDao,
    required AuditService? restoredAudit,
  }) async {
    final now = _clock().toUtc();

    // Adım 18 — satış numarası sayacı (REQ-BKUP-015 · EC-SALE-012).
    await _repairSaleCounter(restoredSettings, restoredDao);

    // Adım 19–20 — oturum sonlandırılır, işaret temizlenir.
    //
    // REQ-BKUP-020: dashboard kilidi zaten yalnızca bellektedir ve uygulama
    // yeniden başladığında kapalı gelir; oturumun düşmesi login'e döndürür.
    await restoredSettings.remove(AppSettingKeys.session);
    await _clearMarker();

    // Adım 21 — audit, restore ÖNCESİ sayılarla birlikte.
    await restoredAudit?.record(
      action: AuditActions.backupRestored,
      entityType: AuditEntities.system,
      at: now,
      // docs/18 §3 — kaynak dosya, yedek tarihi, şema versiyonu ve
      // **restore öncesi kayıt sayıları**.
      metadata: {
        'counts_before': outcome.countsBefore.toJson(),
        'counts_after': outcome.countsAfter.toJson(),
        'migration_required': outcome.migrationRequired,
        'safety_backup': p.basename(outcome.safetyBackup.path),
      },
    );

    // Adım 22 — süresi dolmuş `.old_<ts>` dosyaları.
    await pruneReplacedData();
  }

  /// docs/19 §4 adım 18 · REQ-BKUP-015 — sayaç `MAX(sale_number)`'a çekilir.
  ///
  /// Aksi hâlde eski sayaç yerinde kalır ve `ux_sales_number` çakışması
  /// yüzünden **hiçbir satış tamamlanamaz.**
  Future<void> _repairSaleCounter(
    AppSettingsDao settings,
    BackupDao dao,
  ) async {
    final maxNumber = await dao.maxSaleNumber();
    if (maxNumber == null) return;

    // `YYYY-NNNNNN` — yıl ve sıra ayrıştırılır.
    final separator = maxNumber.indexOf('-');
    if (separator <= 0) return;
    final year = int.tryParse(maxNumber.substring(0, separator));
    final sequence = int.tryParse(maxNumber.substring(separator + 1));
    if (year == null || sequence == null) return;

    await settings.write('sale_counter_$year', '$sequence');
  }

  /// docs/19 §4 — `.old_<ts>` dosyalarını geri koyar.
  Future<void> _rollback(
    File replacedDatabase,
    Directory replacedImages,
    String stamp,
  ) async {
    try {
      final current = File(_paths.databaseFile);
      if (current.existsSync()) await current.delete();
      if (replacedDatabase.existsSync()) {
        await replacedDatabase.rename(_paths.databaseFile);
      }
      for (final suffix in const ['-wal', '-shm']) {
        final saved = File('${replacedDatabase.path}$suffix');
        if (saved.existsSync()) {
          await saved.rename('${_paths.databaseFile}$suffix');
        }
      }

      final images = Directory(_paths.imagesDir);
      if (images.existsSync()) images.deleteSync(recursive: true);
      if (replacedImages.existsSync()) {
        await replacedImages.rename(_paths.imagesDir);
      }
      await _clearMarker();
    } on Object catch (error, stackTrace) {
      _logger?.error(
        'Geri alma başarısız — veri .old_$stamp dosyalarında duruyor.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  // -------------------------------------------------------------------------
  // Yarım kalan restore — REQ-BKUP-012 · docs/19 §4
  // -------------------------------------------------------------------------

  /// Açılışta `restore_in_progress` bulunursa durumu inceler ve kurtarır.
  ///
  /// ```text
  /// Yeni DB yerinde ve bütün        → restore tamamlanmış say
  /// Yeni DB yok/bozuk, .old_ var    → .old_'u geri koy
  /// İkisi de yok                    → kurtarılamadı, kullanıcı bilgilendirilir
  /// ```
  Future<RestoreRecovery> recoverInterrupted() async {
    final marker = File(_paths.restoreMarkerFile);
    if (!marker.existsSync()) return RestoreRecovery.notInterrupted;
    final raw = await marker.readAsString();

    String? stamp;
    try {
      final json = jsonDecode(raw);
      if (json is Map<String, Object?>) stamp = json['stamp'] as String?;
    } on Object {
      // Bozuk bayrak: yine de kurtarmayı deneriz.
    }

    final database = File(_paths.databaseFile);
    if (database.existsSync() &&
        database.lengthSync() > 0 &&
        await BackupDao.isFileIntegral(_paths.databaseFile)) {
      await _clearMarker();
      return RestoreRecovery.completed;
    }

    // Yeni DB yok veya bozuk — `.old_<ts>` geri konur.
    final replaced = stamp == null
        ? _findMostRecentReplacedDatabase()
        : File('${_paths.databaseFile}.old_$stamp');
    if (replaced != null && replaced.existsSync()) {
      if (database.existsSync()) await database.delete();
      await replaced.rename(_paths.databaseFile);
      await _clearMarker();
      _logger?.error(
        'Yarım kalan geri yükleme tespit edildi; önceki veri geri kondu.',
      );
      return RestoreRecovery.rolledBack;
    }

    _logger?.error(
      'Yarım kalan geri yükleme kurtarılamadı; güvenlik yedeği '
      '${_paths.autoBackupsDir} altındadır.',
    );
    return RestoreRecovery.unrecoverable;
  }

  File? _findMostRecentReplacedDatabase() {
    final dir = Directory(_paths.dataDir);
    if (!dir.existsSync()) return null;
    final candidates =
        dir
            .listSync()
            .whereType<File>()
            .where((f) => p.basename(f.path).contains('.old_'))
            .where((f) => f.path.endsWith('.sqlite'))
            .toList()
          ..sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );
    return candidates.isEmpty ? null : candidates.first;
  }

  /// Açılışta, **veritabanı açılmadan önce** çalışan kurtarma girişi.
  ///
  /// Statiktir çünkü tam olarak veritabanına ihtiyaç duymayan yolu temsil
  /// eder: `RestoreService`'in diğer bağımlılıkları (DAO, yedek servisi) bir
  /// bağlantı ister ve o bağlantı bu noktada henüz yoktur — hatta açılamıyor
  /// olabilir. İşaret dosyada olduğu için okunabilir (OD-027).
  static Future<RestoreRecovery> recoverAtStartup({
    required AppPaths paths,
    AppLogger? logger,
  }) {
    return RestoreService(
      paths: paths,
      dao: _UnavailableBackupDao(),
      backupService: _UnavailableBackupService(),
      supportedSchemaVersion: 0,
      clock: DateTime.now,
      logger: logger,
    ).recoverInterrupted();
  }

  /// docs/19 §4 adım 22 — 7 günden eski `.old_<ts>` verileri temizlenir.
  Future<void> pruneReplacedData() async {
    final cutoff = _clock().toUtc().subtract(retainReplacedData);
    for (final dir in [Directory(_paths.dataDir), Directory(_paths.rootPath)]) {
      if (!dir.existsSync()) continue;
      for (final entity in dir.listSync()) {
        if (!p.basename(entity.path).contains('.old_')) continue;
        if (entity.statSync().modified.toUtc().isAfter(cutoff)) continue;
        try {
          entity.deleteSync(recursive: true);
        } on Object {
          // Silinemeyen eski veri bir hata değildir.
        }
      }
    }
  }

  Future<void> _clearMarker() async {
    final marker = File(_paths.restoreMarkerFile);
    if (marker.existsSync()) await marker.delete();
  }

  Future<BackupCounts> _currentCounts() async => BackupCounts.fromJson({
    ...await _dao.tableCounts(),
    'images': (await _dao.referencedImagePaths()).length,
  });

  void _deleteQuietly(Directory dir) {
    if (!dir.existsSync()) return;
    try {
      dir.deleteSync(recursive: true);
    } on Object {
      // yok say
    }
  }

  String _stamp() => '${_clock().toUtc().millisecondsSinceEpoch}';
}

/// Uygulama aşamasının sonucu — `finalize` bunu bekler.
class RestoreOutcome {
  final BackupCounts countsBefore;
  final BackupCounts countsAfter;
  final bool migrationRequired;
  final File safetyBackup;
  final File replacedDatabase;
  final String stamp;

  const RestoreOutcome({
    required this.countsBefore,
    required this.countsAfter,
    required this.migrationRequired,
    required this.safetyBackup,
    required this.replacedDatabase,
    required this.stamp,
  });
}

/// REQ-BKUP-012 — açılıştaki kurtarma sonucu.
enum RestoreRecovery {
  /// Yarım kalmış restore yok.
  notInterrupted,

  /// Yeni veritabanı yerindeydi ve bütündü; restore tamamlanmış sayıldı.
  completed,

  /// `.old_<ts>` geri kondu; kullanıcının restore öncesi verisi geri geldi.
  rolledBack,

  /// Ne yeni ne eski veritabanı kurtarılabildi; güvenlik yedeğinden elle
  /// geri yükleme gerekir.
  unrecoverable,
}

/// [RestoreService.recoverAtStartup] için yer tutucular.
///
/// Açılış kurtarması yalnızca dosya sistemine bakar; veritabanına dayanan
/// hiçbir yolu çalıştırmaz. Bu tipler o sözleşmeyi **zorlar**: yanlışlıkla
/// veritabanı gerektiren bir yol eklenirse test değil, çalışma zamanı
/// gürültülü biçimde patlar.
class _UnavailableBackupDao implements BackupDao {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Açılış kurtarması veritabanına erişemez (OD-027): '
    '${invocation.memberName}',
  );
}

class _UnavailableBackupService implements BackupService {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw StateError(
    'Açılış kurtarması yedek alamaz: ${invocation.memberName}',
  );
}
