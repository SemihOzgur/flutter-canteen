/// Migration çalıştırma protokolü — docs/06-database-migrations.md §3.
///
/// REQ-MIG-002 (snapshot) · REQ-MIG-003 (geri alma) · REQ-MIG-006 (kurtarma)
///
/// ```text
/// 1. (Kullanıcı bilgi ekranı — kurtarma yolunda `MigrationRecoveryScreen`)
/// 2. PRE-MIGRATION SNAPSHOT   → backups/auto/premigration_v<eski>_<ts>.sqlite
/// 3. Snapshot doğrula          → integrity_check + boyut > 0
/// 4. app_settings['migration_in_progress'] = {from, to, startedAt}
/// 5. Migration adımları — tek transaction (Drift onUpgrade)
/// 6. PRAGMA foreign_key_check
/// 7. Doğrulama sorguları
/// 8. user_version güncelle     (Drift)
/// 9. migration_in_progress temizle
/// 10. Audit log                 → Faz 6 (AuditService)
/// ```
///
/// **Kapsam notu:** Bu dosya **mekanizmayı** kurar ve kullanıcıya soru soran
/// hiçbir UI içermez. §3'ün "kullanıcı onayıyla geri yükleme" adımı
/// `presentation/startup/migration_recovery_screen.dart` içindedir ve
/// `main.dart` ikisini birbirine bağlar (REQ-MIG-006).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../core/errors/app_exception.dart';
import '../app_setting_keys.dart';
import '../canteen_database.dart';
import '../raw_sqlite_file.dart';

/// `app_settings['migration_in_progress']` içeriği.
class MigrationFlag {
  final int from;
  final int to;
  final DateTime startedAt;

  const MigrationFlag({
    required this.from,
    required this.to,
    required this.startedAt,
  });

  String toJson() => jsonEncode({
    'from': from,
    'to': to,
    'startedAt': startedAt.toUtc().millisecondsSinceEpoch,
  });

  /// Bozuk JSON `null` döner — uygulama bunun yüzünden çökmez.
  static MigrationFlag? tryParse(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, Object?>) return null;
      final from = decoded['from'];
      final to = decoded['to'];
      final startedAt = decoded['startedAt'];
      if (from is! int || to is! int || startedAt is! int) return null;
      return MigrationFlag(
        from: from,
        to: to,
        startedAt: DateTime.fromMillisecondsSinceEpoch(startedAt, isUtc: true),
      );
    } on FormatException {
      return null;
    }
  }
}

/// Migration protokolünün dosya ve bayrak işlemleri.
class MigrationCoordinator {
  final String databaseFilePath;
  final String autoBackupsDirPath;
  final DateTime Function() clock;

  /// docs/06 §4 — son 5 pre-migration snapshot tutulur.
  final int retainedSnapshots;

  MigrationCoordinator({
    required this.databaseFilePath,
    required this.autoBackupsDirPath,
    DateTime Function()? clock,
    this.retainedSnapshots = 5,
  }) : clock = clock ?? DateTime.now;

  static const String _snapshotPrefix = 'premigration_v';
  static const String _snapshotSuffix = '.sqlite';

  // -------------------------------------------------------------------------
  // Bayrak — REQ-MIG-006
  // -------------------------------------------------------------------------

  Future<MigrationFlag?> readFlag(CanteenDatabase db) async {
    final row =
        await (db.select(db.appSettings)
              ..where((s) => s.key.equals(AppSettingKeys.migrationInProgress))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) return null;
    return MigrationFlag.tryParse(row.value);
  }

  Future<void> writeFlag(CanteenDatabase db, MigrationFlag flag) async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: AppSettingKeys.migrationInProgress,
            value: flag.toJson(),
            updatedAt: clock().toUtc(),
          ),
        );
  }

  Future<void> clearFlag(CanteenDatabase db) async {
    await (db.delete(
      db.appSettings,
    )..where((s) => s.key.equals(AppSettingKeys.migrationInProgress))).go();
  }

  // -------------------------------------------------------------------------
  // Snapshot — REQ-MIG-002
  // -------------------------------------------------------------------------

  /// docs/06 §3 adım 2 — `VACUUM INTO` ile bütünlüklü kopya.
  ///
  /// `VACUUM INTO` bir transaction içinde çalıştırılamaz ve hedef dosya
  /// **var olmamalıdır.**
  Future<File> createSnapshot(
    CanteenDatabase db, {
    required int fromVersion,
  }) async {
    await Directory(autoBackupsDirPath).create(recursive: true);

    final stamp = clock().toUtc().millisecondsSinceEpoch;
    final target = File(
      p.join(
        autoBackupsDirPath,
        '$_snapshotPrefix${fromVersion}_$stamp$_snapshotSuffix',
      ),
    );
    if (target.existsSync()) await target.delete();

    // Parametreli — yol SQL'e gömülmez (REQ-SEC-006).
    await db.customStatement('VACUUM INTO ?;', [target.path]);
    return target;
  }

  /// docs/06 §3 adım 3 — boyut > 0 **ve** `integrity_check` = ok.
  Future<bool> verifySnapshot(File snapshot) async {
    if (!snapshot.existsSync() || snapshot.lengthSync() == 0) return false;
    return RawSqliteFile(snapshot.path).isIntegral();
  }

  /// docs/06 §4 — en yeni [retainedSnapshots] tanesi tutulur.
  Future<void> pruneSnapshots() async {
    final dir = Directory(autoBackupsDirPath);
    if (!dir.existsSync()) return;

    final snapshots =
        dir
            .listSync()
            .whereType<File>()
            .where(
              (f) =>
                  p.basename(f.path).startsWith(_snapshotPrefix) &&
                  f.path.endsWith(_snapshotSuffix),
            )
            .toList()
          ..sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );

    for (final stale in snapshots.skip(retainedSnapshots)) {
      await stale.delete();
    }
  }

  /// En yeni geçerli snapshot — kurtarma için.
  File? latestSnapshot() {
    final dir = Directory(autoBackupsDirPath);
    if (!dir.existsSync()) return null;

    final snapshots =
        dir
            .listSync()
            .whereType<File>()
            .where(
              (f) =>
                  p.basename(f.path).startsWith(_snapshotPrefix) &&
                  f.path.endsWith(_snapshotSuffix),
            )
            .toList()
          ..sort(
            (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
          );

    return snapshots.isEmpty ? null : snapshots.first;
  }

  // -------------------------------------------------------------------------
  // Kurtarma — REQ-MIG-003 / REQ-MIG-006
  // -------------------------------------------------------------------------

  /// docs/06 §3 "Başarısızlık durumunda":
  ///
  /// ```text
  /// canteen.sqlite         →  canteen.corrupt_<ts>.sqlite   (TAŞINIR, silinmez)
  /// premigration snapshot  →  canteen.sqlite                (geri yüklenir)
  /// ```
  ///
  /// **Mevcut veritabanı hiçbir koşulda silinmez.**
  Future<void> restoreFromSnapshot(File snapshot) async {
    if (!await verifySnapshot(snapshot)) {
      throw MigrationException(
        userMessage:
            'Güncelleme öncesi yedek doğrulanamadı. Verileriniz değiştirilmedi.',
        technicalDetail: 'Snapshot doğrulaması başarısız: ${snapshot.path}',
      );
    }

    final live = File(databaseFilePath);
    if (live.existsSync()) {
      final stamp = clock().toUtc().millisecondsSinceEpoch;
      final dir = p.dirname(databaseFilePath);
      final base = p.basenameWithoutExtension(databaseFilePath);
      await live.rename(p.join(dir, '$base.corrupt_$stamp.sqlite'));
    }

    // WAL/SHM yan dosyaları eski veritabanına aittir; bırakılırsa geri yüklenen
    // dosyayla tutarsız olur.
    for (final suffix in const ['-wal', '-shm']) {
      final sidecar = File('$databaseFilePath$suffix');
      if (sidecar.existsSync()) await sidecar.delete();
    }

    await snapshot.copy(databaseFilePath);
  }
}
