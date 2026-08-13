/// Platform bazlı kullanıcı veri dizini çözümlemesi.
///
/// BR-DATA-001 / REQ-DATA-008 / REQ-ARCH-007:
///   Kullanıcı verisi **ASLA kurulum dizinine yazılmaz.**
///   Bu kural, güncellemede veri kaybının (RSK-002) tek savunmasıdır.
///
/// ```text
/// Windows : %APPDATA%\CanteenApp\
/// macOS   : ~/Library/Application Support/CanteenApp/
/// ```
///
/// Yol birleştirme `path` paketi ile yapılır; elle string birleştirme yasaktır
/// (rules/03 §1, rules/05 §6).
///
/// Bkz. docs/05-database-architecture.md §1
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../errors/app_exception.dart';

/// Uygulamanın veri dizini ve alt klasörleri.
class AppPaths {
  /// Veri kökü klasör adı. Her iki platformda da aynıdır.
  static const String appFolderName = 'CanteenApp';

  /// Veri kökü — kurulum dizininden bağımsız.
  final String rootPath;

  const AppPaths({required this.rootPath});

  /// Veritabanı dizini — `<root>/data`
  String get dataDir => p.join(rootPath, 'data');

  /// Ürün görselleri — `<root>/images` (Faz 3'te kullanılır)
  String get imagesDir => p.join(rootPath, 'images');

  /// Log dosyaları — `<root>/logs`
  String get logsDir => p.join(rootPath, 'logs');

  /// Yedekler — `<root>/backups` (Faz 9'da kullanılır)
  String get backupsDir => p.join(rootPath, 'backups');

  /// Geçici dosyalar — `<root>/temp`
  String get tempDir => p.join(rootPath, 'temp');

  /// Veritabanı dosyası — Faz 2'de kullanılır.
  String get databaseFile => p.join(dataDir, 'canteen.sqlite');

  /// Single-instance kilit dosyası (BR-GEN-005).
  String get lockFile => p.join(rootPath, 'app.lock');

  /// Çalışılan platforma göre veri kökünü çözer.
  ///
  /// [environment] ve [operatingSystem] test edilebilirlik için enjekte edilebilir
  /// (rules/06 §7 — determinizm).
  ///
  /// Desteklenmeyen platformda [UnsupportedPlatformException] fırlatır:
  /// production Windows, geliştirme macOS'tur (docs/01 §2).
  factory AppPaths.resolve({
    Map<String, String>? environment,
    String? operatingSystem,
  }) {
    final env = environment ?? Platform.environment;
    final os = operatingSystem ?? Platform.operatingSystem;

    return AppPaths(
      rootPath: _resolveRoot(env: env, os: os),
    );
  }

  static String _resolveRoot({
    required Map<String, String> env,
    required String os,
  }) {
    switch (os) {
      case 'windows':
        final appData = env['APPDATA'];
        if (appData == null || appData.isEmpty) {
          throw const DataDirectoryException(
            userMessage:
                'Uygulama veri klasörü bulunamadı. Windows kullanıcı profiliniz '
                'okunamıyor olabilir.',
            technicalDetail: 'APPDATA ortam değişkeni tanımsız veya boş.',
          );
        }
        return p.join(appData, appFolderName);

      case 'macos':
        final home = env['HOME'];
        if (home == null || home.isEmpty) {
          throw const DataDirectoryException(
            userMessage: 'Uygulama veri klasörü bulunamadı.',
            technicalDetail: 'HOME ortam değişkeni tanımsız veya boş.',
          );
        }
        return p.join(home, 'Library', 'Application Support', appFolderName);

      default:
        throw UnsupportedPlatformException(
          userMessage:
              'Bu uygulama yalnızca Windows üzerinde çalışacak şekilde tasarlanmıştır.',
          technicalDetail: 'Desteklenmeyen platform: $os',
        );
    }
  }

  /// Gerekli tüm alt klasörleri oluşturur (varsa dokunmaz).
  Future<void> ensureDirectories() async {
    for (final dir in [
      rootPath,
      dataDir,
      imagesDir,
      logsDir,
      backupsDir,
      tempDir,
    ]) {
      await Directory(dir).create(recursive: true);
    }
  }

  @override
  String toString() => 'AppPaths($rootPath)';
}
