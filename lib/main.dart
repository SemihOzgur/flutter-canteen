/// Uygulama giriş noktası ve bootstrap sırası.
///
/// docs/03-architecture.md §6 — bootstrap sırası:
/// ```text
/// 1. Flutter binding init
/// 2. Veri dizinini çöz            [REQ-DATA-008 · REQ-ARCH-007]
/// 3. Loglama başlat               [REQ-SEC-007]
/// 4. Single-instance lock al      [REQ-ARCH-005 · REQ-DATA-005]
/// 5. Veritabanı: kurtarma kontrolü → aç → PRAGMA → migration → seed  [Faz 2]
/// 6. Kurulum kontrolü             [EC-AUTH-008 · REQ-AUTH-016/022]   [Faz 3a]
/// 7. Oturum yükle                 [REQ-AUTH-001/006 · EC-AUTH-003/004]
/// 8. Finansal kilit KAPALI başlar [BR-AUTH-016 · EC-DASH-006]
/// 9. Uygulamayı başlat (Riverpod ProviderScope)
/// ```
///
/// **KRİTİK SIRA (rules/03 §5 · RSK-003):** Veritabanı, single-instance kilidi
/// alındıktan **sonra** açılır. İkinci uygulama örneğinde veritabanı dosyasına
/// hiç dokunulmaz.
///
/// **Adım 8'in kodu yoktur ve olmamalıdır:** `FinancialAccessService` bellekte
/// kilitli doğar ve durumu hiçbir yere yazılmaz (BR-AUTH-016). Doğru davranış,
/// bu dosyada kilidi açan bir çağrının **bulunmamasıdır.**
///
/// **Adım 4b — yarım kalan geri yükleme (REQ-BKUP-012 · OD-027):** veritabanı
/// açılmadan ÖNCE kontrol edilir. Kurtarmanın gerekli olduğu senaryoda yerinde
/// geçerli bir veritabanı yoktur; sonra çalıştırılsaydı bootstrap boş bir
/// veritabanı oluşturur ve kullanıcının verisi `.old_<ts>` dosyalarında
/// unutulurdu.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/l10n/app_strings_tr.dart';
import 'app/startup.dart';
import 'app/theme/app_theme.dart';
import 'application/auth/providers.dart';
import 'application/backup/restore_service.dart';
import 'core/errors/app_exception.dart';
import 'core/logging/app_logger.dart';
import 'core/paths/app_paths.dart';
import 'core/single_instance/instance_lock.dart';
import 'data/db/canteen_database.dart';
import 'data/db/database_bootstrap.dart';
import 'data/db/migrations/migration_coordinator.dart';
import 'data/db/providers.dart';
import 'data/files/providers.dart';
import 'presentation/startup/migration_recovery_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AppPaths paths;
  final AppLogger logger;

  try {
    // 2. Veri dizini — kurulum dizininden bağımsız (BR-DATA-001)
    paths = AppPaths.resolve();
    await paths.ensureDirectories();

    // 4. Loglama
    logger = AppLogger(logsDirPath: paths.logsDir);
    await logger.init();
  } on AppException catch (e) {
    // REQ-SEC-007: teknik detay kullanıcıya gösterilmez.
    runApp(_StartupFailureApp(message: e.userMessage));
    return;
  }

  // Beklenmeyen framework hataları log'a yazılır, kullanıcıya sızdırılmaz.
  FlutterError.onError = (details) {
    logger.error(
      'Flutter hatası',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.error('Yakalanmamış hata', error: error, stackTrace: stack);
    return true;
  };

  // 3. Single-instance lock (BR-GEN-005)
  final lock = InstanceLock(lockFilePath: paths.lockFile);
  if (lock.tryAcquire() == InstanceLockResult.alreadyRunning) {
    logger.warn('İkinci uygulama örneği engellendi.');
    runApp(const AlreadyRunningApp());
    return;
  }

  logger.info('Uygulama başlatıldı. Veri dizini: ${paths.rootPath}');

  // 4b. REQ-BKUP-012 · OD-027 — yarım kalan geri yükleme.
  //
  // ⚠️ Veritabanı AÇILMADAN ÖNCE çalışır ve bu zorunludur: kurtarmanın gerekli
  // olduğu senaryoda yerinde geçerli bir veritabanı **yoktur**. Sonra
  // çalıştırılsaydı bootstrap boş bir veritabanı oluşturur ve kullanıcının
  // verisi `.old_<ts>` dosyalarında unutulurdu.
  final recovery = await RestoreService.recoverAtStartup(
    paths: paths,
    logger: logger,
  );
  if (recovery != RestoreRecovery.notInterrupted) {
    logger.info('Geri yükleme kurtarması: ${recovery.name}');
  }

  // 5. Veritabanı — kilit ALINDIKTAN SONRA açılır (RSK-003).
  final CanteenDatabase database;
  try {
    database = await _openDatabase(paths: paths, logger: logger, lock: lock);
  } on _StartupHandled {
    // Kullanıcıya bir ekran gösterildi (kurtarma veya hata); akış burada
    // biter ve `runApp` ikinci kez çağrılmaz.
    return;
  }

  // Riverpod (OD-002) — bağlantı ve log override ile enjekte edilir; global
  // statik duruma dönüştürülmez.
  //
  // Container `runApp`'ten ÖNCE kurulur: adım 6–7 kararları (kurulum durumu ve
  // oturum) ilk kare çizilmeden önce verilmelidir; aksi hâlde uygulama önce
  // yanlış ekranı gösterip sonra sıçrardı. Aynı container `runApp`'e devredilir
  // ki servisler — özellikle **bellekte** yaşayan finansal erişim kilidi
  // (BR-AUTH-016) — ikinci kez kurulmasın.
  final container = ProviderContainer(
    overrides: [
      canteenDatabaseProvider.overrideWithValue(database),
      appLoggerProvider.overrideWithValue(logger),
      // Veri dizini bootstrap'ta bir kez çözülür; servisler ikinci kez
      // çözmez (BR-DATA-001 · docs/21 §1).
      appPathsProvider.overrideWithValue(paths),
    ],
  );

  // Kapanışta bağlantı düzgün kapatılır — Windows dosya kilidi katıdır
  // (rules/05 §6) ve açık WAL dosyaları yedeklemeyi bozar.
  AppLifecycleListener(
    onExitRequested: () async {
      container.dispose();
      await database.close();
      lock.release();
      logger.info('Uygulama kapatıldı.');
      return AppExitResponse.exit;
    },
  );

  // 6–7. Kurulum durumu ve oturum → açılış rotası (EC-AUTH-008 · REQ-AUTH-006).
  //
  // 8. Finansal erişim kilidi burada **açılmaz**: servis kilitli doğar ve
  // durumu kalıcılaştırılmaz (BR-AUTH-016 · EC-DASH-006).
  final String initialRoute;
  try {
    initialRoute = await resolveInitialRoute(
      setup: container.read(setupServiceProvider),
      session: container.read(sessionServiceProvider),
    );
  } on Object catch (error, stackTrace) {
    // REQ-SEC-007: teknik detay log'a, kullanıcıya sade Türkçe mesaj.
    logger.error(
      'Açılış durumu çözülemedi',
      error: error,
      stackTrace: stackTrace,
    );
    container.dispose();
    await database.close();
    lock.release();
    runApp(
      const _StartupFailureApp(message: AppStringsTr.unexpectedErrorMessage),
    );
    return;
  }

  // 9. Uygulamayı başlat.
  runApp(
    UncontrolledProviderScope(
      container: container,
      child: CanteenApp(initialRoute: initialRoute),
    ),
  );
}

/// Bootstrap başarısız olduğunda gösterilen minimal ekran.
/// Açılış, kullanıcıya bir ekran göstererek sonlandı.
///
/// `main` içindeki akışı erken bitirmek için kullanılır; `runApp` çağrısı
/// zaten yapılmıştır.
class _StartupHandled implements Exception {
  const _StartupHandled();
}

/// Veritabanını açar; yarım kalmış migration bulursa **kurtarma ekranını**
/// gösterir (docs/06 §3 · REQ-MIG-006).
///
/// docs/06 §3 kurtarmayı dört adımda tanımlar ve üçüncüsü *"kullanıcı
/// onaylarsa snapshot geri yüklenir ve migration yeniden denenir"* der —
/// bu yüzden geri yükleme sonrası açılış **yeniden** denenir, uygulama
/// kapanıp açılmayı beklemez.
///
/// Yeniden deneme **bir kez** yapılır: ikinci kez yarım kalan bir migration,
/// düzelmeyen bir sorunun işaretidir ve döngüye girmek kullanıcıyı hiçbir
/// yere götürmez.
Future<CanteenDatabase> _openDatabase({
  required AppPaths paths,
  required AppLogger logger,
  required InstanceLock lock,
  bool retrying = false,
}) async {
  try {
    final result = await DatabaseBootstrap(paths: paths, logger: logger).open();
    logger.info('Veritabanı hazır (${result.kind.name}).');
    return result.database;
  } on MigrationRecoveryRequiredException catch (e) {
    logger.error(
      'Yarım kalmış migration',
      error: e.technicalDetail ?? e.userMessage,
    );
    if (retrying) {
      lock.release();
      runApp(_StartupFailureApp(message: e.userMessage));
      throw const _StartupHandled();
    }

    final completer = Completer<CanteenDatabase>();
    runApp(
      _MigrationRecoveryApp(
        snapshotPath: e.snapshotPath,
        onRestore: () async {
          try {
            // Snapshot adım 2'de, bayrak adım 4'te yazılır: geri yüklenen
            // kopya bayrağı TAŞIMAZ ve migration temiz bir zeminde
            // yeniden denenir.
            await MigrationCoordinator(
              databaseFilePath: paths.databaseFile,
              autoBackupsDirPath: paths.autoBackupsDir,
            ).restoreFromSnapshot(File(e.snapshotPath!));
            logger.info('Snapshot geri yüklendi; migration yeniden denenecek.');

            completer.complete(
              await _openDatabase(
                paths: paths,
                logger: logger,
                lock: lock,
                retrying: true,
              ),
            );
            return true;
          } on Object catch (error) {
            logger.error('Snapshot geri yüklenemedi', error: error);
            return false;
          }
        },
        // docs/06 §3 adım 4 — onaylamazsa uygulama kapanır; yarım şemayla
        // çalışmaya izin verilmez.
        onQuit: () {
          lock.release();
          exit(0);
        },
      ),
    );

    return completer.future;
  } on AppException catch (e) {
    // REQ-SEC-007: teknik detay log'a, kullanıcıya sade Türkçe mesaj.
    logger.error('Veritabanı açılamadı', error: e.technicalDetail ?? e);
    lock.release();
    runApp(_StartupFailureApp(message: e.userMessage));
    throw const _StartupHandled();
  }
}

/// Kurtarma ekranını taşıyan minimal uygulama.
class _MigrationRecoveryApp extends StatelessWidget {
  final String? snapshotPath;
  final Future<bool> Function() onRestore;
  final VoidCallback onQuit;

  const _MigrationRecoveryApp({
    required this.snapshotPath,
    required this.onRestore,
    required this.onQuit,
  });

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: AppStringsTr.appTitle,
    debugShowCheckedModeBanner: false,
    theme: AppTheme.light(),
    home: MigrationRecoveryScreen(
      snapshotPath: snapshotPath,
      onRestore: onRestore,
      onQuit: onQuit,
    ),
  );
}

class _StartupFailureApp extends StatelessWidget {
  final String message;

  const _StartupFailureApp({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStringsTr.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 16),
                  Text(
                    AppStringsTr.startupFailedTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(message, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
