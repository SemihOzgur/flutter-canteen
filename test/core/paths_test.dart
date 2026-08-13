/// Veri dizini çözümleme testleri.
///
/// BR-DATA-001 / REQ-DATA-008 / REQ-ARCH-007:
///   Kullanıcı verisi kurulum dizininde tutulmaz.
///
/// docs/05-database-architecture.md §1
library;

import 'dart:io';

import 'package:canteen/core/errors/app_exception.dart';
import 'package:canteen/core/paths/app_paths.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('AppPaths.resolve — platform bazlı kök', () {
    test('Windows: %APPDATA%\\CanteenApp', () {
      final paths = AppPaths.resolve(
        environment: {'APPDATA': r'C:\Users\kantin\AppData\Roaming'},
        operatingSystem: 'windows',
      );
      expect(
        paths.rootPath,
        p.join(r'C:\Users\kantin\AppData\Roaming', 'CanteenApp'),
      );
      expect(paths.rootPath, contains('CanteenApp'));
    });

    test('macOS: ~/Library/Application Support/CanteenApp', () {
      final paths = AppPaths.resolve(
        environment: {'HOME': '/Users/kantin'},
        operatingSystem: 'macos',
      );
      expect(
        paths.rootPath,
        p.join('/Users/kantin', 'Library', 'Application Support', 'CanteenApp'),
      );
    });

    test('APPDATA tanımsızsa anlaşılır hata', () {
      expect(
        () =>
            AppPaths.resolve(environment: const {}, operatingSystem: 'windows'),
        throwsA(isA<DataDirectoryException>()),
      );
    });

    test('HOME tanımsızsa anlaşılır hata', () {
      expect(
        () => AppPaths.resolve(environment: const {}, operatingSystem: 'macos'),
        throwsA(isA<DataDirectoryException>()),
      );
    });

    test('desteklenmeyen platform reddedilir (docs/01 §2)', () {
      expect(
        () => AppPaths.resolve(
          environment: const {'HOME': '/home/x'},
          operatingSystem: 'linux',
        ),
        throwsA(isA<UnsupportedPlatformException>()),
      );
    });

    test('hata mesajları kullanıcıya teknik detay sızdırmaz (REQ-SEC-007)', () {
      try {
        AppPaths.resolve(environment: const {}, operatingSystem: 'windows');
        fail('hata bekleniyordu');
      } on DataDirectoryException catch (e) {
        expect(e.userMessage, isNot(contains('APPDATA')));
        expect(e.technicalDetail, contains('APPDATA'));
      }
    });
  });

  group('AppPaths — alt dizinler', () {
    final paths = AppPaths(rootPath: p.join('/tmp', 'CanteenApp'));

    test('tüm alt dizinler kök altındadır', () {
      for (final dir in [
        paths.dataDir,
        paths.imagesDir,
        paths.logsDir,
        paths.backupsDir,
        paths.tempDir,
      ]) {
        expect(p.isWithin(paths.rootPath, dir), isTrue, reason: dir);
      }
    });

    test('veritabanı dosyası data dizinindedir', () {
      expect(paths.databaseFile, p.join(paths.dataDir, 'canteen.sqlite'));
    });

    test('kilit dosyası kök dizindedir', () {
      expect(paths.lockFile, p.join(paths.rootPath, 'app.lock'));
    });
  });

  group('AppPaths.ensureDirectories', () {
    late Directory temp;

    setUp(() => temp = Directory.systemTemp.createTempSync('canteen_paths_'));
    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    test('eksik dizinleri oluşturur, mevcutlara dokunmaz', () async {
      final paths = AppPaths(rootPath: p.join(temp.path, 'CanteenApp'));
      await paths.ensureDirectories();

      expect(Directory(paths.dataDir).existsSync(), isTrue);
      expect(Directory(paths.imagesDir).existsSync(), isTrue);
      expect(Directory(paths.logsDir).existsSync(), isTrue);
      expect(Directory(paths.backupsDir).existsSync(), isTrue);
      expect(Directory(paths.tempDir).existsSync(), isTrue);

      // İkinci çağrı hata vermez
      await paths.ensureDirectories();
      expect(Directory(paths.dataDir).existsSync(), isTrue);
    });
  });
}
