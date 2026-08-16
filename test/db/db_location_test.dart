/// Veritabanı konumu — **REQ-DB-007 · BR-DATA-001**
///
/// "Kullanıcı verisi ASLA kurulum dizinine yazılmaz." Bu kural
/// [RSK-002](docs/29-risks.md) (güncellemede veri kaybı) savunmasıdır.
library;

import 'dart:io';

import 'package:canteen/core/paths/app_paths.dart';
import 'package:canteen/data/db/database_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../support/test_database.dart';

void main() {
  test('databaseFile → <root>/data/canteen.sqlite', () {
    const paths = AppPaths(rootPath: '/veri/CanteenApp');
    expect(
      paths.databaseFile,
      p.join('/veri/CanteenApp', 'data', 'canteen.sqlite'),
    );
  });

  test('Windows yolu %APPDATA%\\CanteenApp altındadır', () {
    final paths = AppPaths.resolve(
      environment: {'APPDATA': r'C:\Users\Kasa\AppData\Roaming'},
      operatingSystem: 'windows',
    );
    expect(paths.databaseFile, contains('CanteenApp'));
    expect(paths.databaseFile, endsWith('canteen.sqlite'));
    expect(
      paths.databaseFile,
      startsWith(r'C:\Users\Kasa\AppData\Roaming'),
      reason: 'BR-DATA-001: veri kullanıcı profilinde tutulur.',
    );
  });

  test('macOS yolu Application Support altındadır', () {
    final paths = AppPaths.resolve(
      environment: {'HOME': '/Users/kasa'},
      operatingSystem: 'macos',
    );
    expect(
      paths.databaseFile,
      p.join(
        '/Users/kasa',
        'Library',
        'Application Support',
        'CanteenApp',
        'data',
        'canteen.sqlite',
      ),
    );
  });

  test('autoBackupsDir → <root>/backups/auto — docs/06 §3', () {
    const paths = AppPaths(rootPath: '/veri/CanteenApp');
    expect(paths.autoBackupsDir, p.join('/veri/CanteenApp', 'backups', 'auto'));
  });

  test('ensureDirectories backups/auto dizinini de oluşturur', () async {
    final temp = await TempAppPaths.create();
    addTearDown(temp.dispose);

    expect(Directory(temp.paths.autoBackupsDir).existsSync(), isTrue);
    expect(Directory(temp.paths.dataDir).existsSync(), isTrue);
  });

  test('veritabanı dosyası gerçekten veri dizininde oluşur', () async {
    final temp = await TempAppPaths.create();
    addTearDown(temp.dispose);

    final result = await DatabaseBootstrap(paths: temp.paths).open();
    addTearDown(result.database.close);

    final file = File(temp.paths.databaseFile);
    expect(file.existsSync(), isTrue);
    expect(p.dirname(file.path), temp.paths.dataDir);
    expect(p.basename(file.path), 'canteen.sqlite');
  });
}
