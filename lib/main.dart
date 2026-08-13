/// Uygulama giriş noktası ve bootstrap sırası.
///
/// docs/03-architecture.md §6 — bootstrap sırası (Faz 1 kapsamındaki adımlar):
/// ```text
/// 1. Flutter binding init
/// 2. Veri dizinini çöz            [REQ-DATA-008 · REQ-ARCH-007]
/// 3. Single-instance lock al      [REQ-ARCH-005 · REQ-DATA-005]
/// 4. Loglama başlat               [REQ-SEC-007]
/// 5. Uygulamayı başlat (Riverpod ProviderScope)
/// ```
///
/// Faz 2+ adımları (migration, seed, session, sepet restore) bu fazın
/// kapsamı dışındadır ve **eklenmemiştir.**
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/l10n/app_strings_tr.dart';
import 'app/theme/app_theme.dart';
import 'core/errors/app_exception.dart';
import 'core/logging/app_logger.dart';
import 'core/paths/app_paths.dart';
import 'core/single_instance/instance_lock.dart';

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

  // 5. Riverpod (OD-002)
  runApp(const ProviderScope(child: CanteenApp()));
}

/// Bootstrap başarısız olduğunda gösterilen minimal ekran.
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
