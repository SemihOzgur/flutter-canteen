/// Yol güvenliği testleri — **BR-DATA-001 · rules/03 §1 · RSK-002**
///
/// ## Neden bu dosya var
///
/// `docs/27 §8`'in Windows manuel testleri **W6** (veri `%APPDATA%` altında,
/// kurulum dizininde değil) ve **W15** (Türkçe olmayan kullanıcı adı, yolda
/// boşluk) macOS'ta doğrulanamaz. Ancak bu iki testin yakaladığı **hata
/// sınıfının** çoğu platformdan bağımsızdır:
///
/// - elle string birleştirme (`rootPath + '/data'`) → boşlukta/ayırıcıda kırılır
/// - Türkçe veya boşluklu yolun SQLite'a aktarılamaması
/// - türetilmiş bir yolun kök dizinin dışına çıkması
///
/// Bunlar burada otomatik olarak sınanır. **Yakalayamadığı tek şey**
/// `%APPDATA%`'nın Windows'a özgü çözümlenmesi ve 260 karakter yol sınırıdır;
/// onlar W6/W15 olarak elde kalır (bkz. RSK-018).
/// ## Kapsanan requirement'lar (Faz 11 izlenebilirliği)
///
/// - **REQ-COMP-003** — macOS geliştirme desteği: bu testler macOS'ta
///   gerçek dosya sistemiyle çalışır
///
library;

import 'dart:io';

import 'package:canteen/core/paths/app_paths.dart';
import 'package:canteen/core/single_instance/instance_lock.dart';
import 'package:canteen/data/db/canteen_database.dart';
import 'package:canteen/data/db/database_opener.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Gerçek dünyada karşılaşılan zor kök adları.
///
/// `C:\Users\Şule Öztürk\AppData\Roaming\CanteenApp` gibi bir yol Windows'ta
/// tamamen olağandır; boşluk **ve** Türkçe karakter aynı anda bulunur.
const List<String> _hardRootNames = [
  'Şule Öztürk',
  'Ali Veli',
  'çğıöşü ÇĞİÖŞÜ',
  "O'Brien",
  'a.b c.d',
];

void main() {
  late Directory sandbox;

  setUp(() {
    sandbox = Directory.systemTemp.createTempSync('canteen_paths_');
  });

  tearDown(() {
    if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
  });

  AppPaths pathsUnder(String rootName) =>
      AppPaths(rootPath: p.join(sandbox.path, rootName));

  group('W15 — boşluklu ve Türkçe karakterli yollar', () {
    for (final rootName in _hardRootNames) {
      test('"$rootName" altında tüm dizinler oluşturulur', () async {
        final paths = pathsUnder(rootName);

        await paths.ensureDirectories();

        for (final dir in [
          paths.dataDir,
          paths.imagesDir,
          paths.logsDir,
          paths.backupsDir,
          paths.autoBackupsDir,
          paths.tempDir,
        ]) {
          expect(
            Directory(dir).existsSync(),
            isTrue,
            reason: '"$rootName" içinde $dir oluşturulamadı.',
          );
        }
      });

      test('"$rootName" altında veritabanı AÇILIP yazılabilir', () async {
        // Asıl risk budur: yol SQLite'a doğru aktarılmazsa uygulama hiç
        // açılmaz. Elle string birleştirme burada patlar.
        final paths = pathsUnder(rootName);
        await paths.ensureDirectories();

        final db = CanteenDatabase(openDatabaseFile(paths.databaseFile));
        addTearDown(db.close);

        await db.customStatement('CREATE TABLE probe (id INTEGER PRIMARY KEY)');
        await db.customStatement('INSERT INTO probe (id) VALUES (1)');
        final rows = await db.customSelect('SELECT id FROM probe').get();

        expect(rows, hasLength(1));
        expect(File(paths.databaseFile).existsSync(), isTrue);
      });
    }
  });

  group('W6 — veri KÖK dizinin altında kalır', () {
    test('türetilmiş yolların hepsi kökün içindedir', () {
      final paths = pathsUnder('Şule Öztürk');

      for (final path in [
        paths.dataDir,
        paths.imagesDir,
        paths.logsDir,
        paths.backupsDir,
        paths.autoBackupsDir,
        paths.tempDir,
        paths.databaseFile,
        paths.lockFile,
      ]) {
        expect(
          p.isWithin(paths.rootPath, path),
          isTrue,
          reason:
              'BR-DATA-001: kullanıcı verisi veri dizininin dışına — özellikle '
              'kurulum dizinine — yazılamaz (RSK-002).',
        );
      }
    });

    test('yollar elle birleştirilmez — ayırıcı platformun kendisidir', () {
      final paths = pathsUnder('Ali Veli');

      expect(
        paths.dataDir,
        p.join(paths.rootPath, 'data'),
        reason:
            'rules/03 §1: yol işlemlerinde `path` paketi kullanılır; elle '
            'string birleştirme Windows\'ta ters ayırıcı yüzünden kırılır.',
      );
      expect(paths.databaseFile, p.join(paths.dataDir, 'canteen.sqlite'));
    });

    test('kök yolu mutlaktır', () async {
      final paths = pathsUnder('Şule Öztürk');
      await paths.ensureDirectories();

      expect(
        p.isAbsolute(paths.rootPath),
        isTrue,
        reason:
            'Göreli kök, çalışma dizini değiştiğinde veriyi başka yere yazardı.',
      );
    });
  });

  group('W11 — aynı veriye ikinci örnek (BR-GEN-005 · RSK-003)', () {
    // ⚠️ "İkinci ÖRNEK reddedilir" iddiası burada kanıtlanamaz.
    //
    // POSIX'te `flock` **süreç** bazlıdır: aynı süreçten alınan ikinci kilit
    // başarılı olur. Windows'ta `LockFile` **handle** bazlıdır ve reddeder.
    // Üretim anlamı (iki AYRI süreç) her iki platformda da doğrudur, ama
    // tek süreçli bir testte doğrulanamaz — bu tam olarak W11'in var olma
    // sebebidir (docs/27 §8 · RSK-018).
    test('kilit alınır ve dosyaya PID yazılır', () async {
      final paths = pathsUnder('Şule Öztürk');
      await paths.ensureDirectories();

      final lock = InstanceLock(
        lockFilePath: paths.lockFile,
        pidProvider: () => 4242,
      );
      addTearDown(lock.release);

      expect(lock.tryAcquire(), InstanceLockResult.acquired);
      expect(lock.isHeld, isTrue);
      expect(
        File(paths.lockFile).readAsStringSync(),
        '4242',
        reason:
            'Çökme sonrası kalan kilidin PID kontrolüyle temizlenebilmesi '
            'için dosyada PID bulunmalıdır (rules/03 §5).',
      );
    });

    test('kilit bırakılınca ikinci örnek alabilir', () async {
      final paths = pathsUnder('Ali Veli');
      await paths.ensureDirectories();

      final first = InstanceLock(lockFilePath: paths.lockFile);
      expect(first.tryAcquire(), InstanceLockResult.acquired);
      first.release();

      final second = InstanceLock(lockFilePath: paths.lockFile);
      addTearDown(second.release);
      expect(
        second.tryAcquire(),
        InstanceLockResult.acquired,
        reason:
            'Çökme sonrası kalan kilit uygulamayı kalıcı olarak açılmaz '
            'hale getirmemelidir.',
      );
    });

    test('boşluklu/Türkçe yolda da kilit çalışır', () async {
      final paths = pathsUnder('çğıöşü ÇĞİÖŞÜ');
      await paths.ensureDirectories();

      final lock = InstanceLock(lockFilePath: paths.lockFile);
      addTearDown(lock.release);

      expect(lock.tryAcquire(), InstanceLockResult.acquired);
      expect(File(paths.lockFile).existsSync(), isTrue);
    });
  });
}
