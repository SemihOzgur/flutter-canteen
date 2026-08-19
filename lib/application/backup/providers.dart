/// Yedekleme servislerinin provider'ları (OD-002 — Riverpod).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dao/backup_dao.dart';
import '../../data/db/schema_version.dart';
import '../../data/db/providers.dart';
import '../../data/files/providers.dart';
import '../audit/providers.dart';
import '../auth/providers.dart' show appLoggerProvider;
import 'backup_service.dart';
import 'restore_service.dart';

final backupDaoProvider = Provider<BackupDao>(
  (ref) => BackupDao(ref.watch(canteenDatabaseProvider)),
);

/// docs/19 §3 — yedek oluşturma. RSK-005'in tek savunması.
final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    dao: ref.watch(backupDaoProvider),
    schemaVersion: ref.watch(canteenDatabaseProvider).schemaVersion,
    paths: ref.watch(appPathsProvider),
    settings: ref.watch(appSettingsDaoProvider),
    audit: ref.watch(auditServiceProvider),
    logger: ref.watch(appLoggerProvider),
    clock: ref.watch(canteenDatabaseProvider).clock,
  ),
);

/// docs/19 §4 adım 12 — veritabanı bağlantısını kapatan geri çağrı.
///
/// Ekran `data/` katmanını tanımaz (rules/01 §1) ama restore'un bağlantıyı
/// kapatması gerekir. Yetenek burada, application katmanında açığa çıkarılır;
/// ekran yalnızca **ne yapılacağını** bilir, bağlantının kendisini değil.
final closeDatabaseProvider = Provider<Future<void> Function()>(
  (ref) => ref.watch(canteenDatabaseProvider).close,
);

/// docs/19 §4 — geri yükleme. Uygulamanın **en tehlikeli** işlemi.
final restoreServiceProvider = Provider<RestoreService>(
  (ref) => RestoreService(
    paths: ref.watch(appPathsProvider),
    dao: ref.watch(backupDaoProvider),
    backupService: ref.watch(backupServiceProvider),
    supportedSchemaVersion: kSupportedSchemaVersion,
    logger: ref.watch(appLoggerProvider),
    clock: ref.watch(canteenDatabaseProvider).clock,
  ),
);
