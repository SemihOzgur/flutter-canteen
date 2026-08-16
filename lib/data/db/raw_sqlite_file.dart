/// Bir SQLite dosyası üzerinde **migration çalıştırmadan** ham tanı sorguları.
///
/// Migration protokolü (docs/06 §3), veritabanına dokunmadan önce bazı bilgileri
/// okumak zorundadır:
///
/// - `user_version` — sürüm kapısı (REQ-MIG-005)
/// - `integrity_check` — snapshot doğrulaması (REQ-MIG-002)
///
/// Migration sonrası `foreign_key_check` (docs/06 §3 adım 6) **buraya ait
/// değildir:** o kontrol migration'ı çalıştıran bağlantıda yapılır
/// (`DatabaseBootstrap`), çünkü doğrulanması gereken şey o transaction'ın
/// bıraktığı durumdur.
///
/// Bunlar için tam bir [CanteenDatabase] açmak **yanlış** olurdu: açılış
/// migration + seed tetikler. Bu sınıf `enableMigrations: false` ile bağlanır.
///
/// Tüm sorgular sabit, parametresiz PRAGMA ifadeleridir — kullanıcı girdisi
/// SQL'e gömülmez (REQ-SEC-006).
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../../core/errors/app_exception.dart';
import 'database_opener.dart';

/// Drift, açılış sırasında şema yönetimi için bir [QueryExecutorUser] ister.
/// Migration'lar kapalı olduğundan bu uygulama hiçbir şey yapmaz.
class _InertExecutorUser extends QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}

/// Salt-okuma tanı erişimi.
class RawSqliteFile {
  final String path;

  const RawSqliteFile(this.path);

  Future<T> _withExecutor<T>(
    Future<T> Function(QueryExecutor executor) action,
  ) async {
    // Tanı bağlantısı da yapılandırılır. İki gerekçe:
    //
    // 1. `busy_timeout` varsayılanı `0`'dır; bu sınıf üretimde her açılışta
    //    gerçek veritabanına bağlanır (`DatabaseBootstrap.open`). Kilit tutan
    //    başka biri varsa anında `SQLITE_BUSY` ile düşer ve kullanıcıya
    //    asılsız bir "veritabanı bozuk" hatası gösterilirdi.
    // 2. Bu bağlantı **yazabilir**: WAL modunda son bağlantı kapanırken
    //    checkpoint çalışır. Bu yüzden `synchronous = FULL` de gerekir.
    //
    // `buildDatabaseSetup()` BURAYA BAĞLANAMAZ — gerekçesi
    // [buildDiagnosticSetup] dokümantasyonunda.
    final executor = NativeDatabase(
      File(path),
      enableMigrations: false,
      setup: buildDiagnosticSetup(),
    );
    try {
      await executor.ensureOpen(_InertExecutorUser());
      return await action(executor);
    } finally {
      // `close()` hatası uçuştaki exception'ın YERİNE GEÇMEMELİ. Geçseydi:
      // `isIntegral()`'in "asla fırlatmaz" sözleşmesi (aşağıda) bozulur ve
      // `readUserVersion()`'ın SqliteException → DatabaseException eşlemesi
      // atlanarak ham SQLite metni yukarı sızardı (REQ-SEC-007).
      //
      // Tanı bağlantısı geçicidir ve hiçbir şey commit etmez; kapanışta
      // yapılabilecek bir kurtarma yoktur.
      try {
        await executor.close();
      } on Object {
        // bilinçli olarak yutulur
      }
    }
  }

  /// SQLite dosya başlığındaki sabit alanlar (docs: SQLite File Format §1.3).
  static const List<int> _magic = [
    0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, // "SQLite f"
    0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00, // "ormat 3\0"
  ];
  static const int _headerLength = 100;
  static const int _userVersionOffset = 60;

  /// `user_version`'ı **veritabanını açmadan**, dosya başlığından okur.
  ///
  /// Başlık bayat olabiliyorsa `null` döner ve çağıran SQLite'a düşer.
  ///
  /// Neden bu yol var: `DatabaseBootstrap.open`, sürüm kapısı devreye girmeden
  /// **önce** bu değeri okumak zorundadır. Bağlantı açmak masum değildir —
  /// WAL modunda son bağlantı kapanırken checkpoint çalışır ve dosyayı
  /// değiştirir. `rules/03 §3` kural 9 ise uygulamanın desteklemediği bir şema
  /// versiyonunu **açmayı reddetmesini** ister. Başlıktan okumak bu çelişkiyi
  /// yan etkisiz çözer.
  int? _readUserVersionFromHeader(File file) {
    // WAL'da çerçeve varsa başlıktaki değer BAYATTIR: ölçüldü — başlık 0
    // gösterirken gerçek değer 7'ydi. `0` "yeni kurulum" anlamına geldiği için
    // bu sessizce mevcut veritabanının üzerine şema kurulmasına yol açardı.
    final wal = File('$path-wal');
    if (wal.existsSync() && wal.lengthSync() > 0) return null;

    final length = file.lengthSync();
    // 0 baytlık dosya SQLite için boş/yeni veritabanıdır.
    if (length == 0) return 0;
    if (length < _headerLength) {
      throw _unreadable('dosya $length bayt — başlık için yetersiz.');
    }

    final handle = file.openSync();
    final List<int> header;
    try {
      header = handle.readSync(_headerLength);
    } finally {
      handle.closeSync();
    }

    for (var i = 0; i < _magic.length; i++) {
      if (header[i] != _magic[i]) {
        throw _unreadable('SQLite başlık imzası eşleşmedi.');
      }
    }

    return (header[_userVersionOffset] << 24) |
        (header[_userVersionOffset + 1] << 16) |
        (header[_userVersionOffset + 2] << 8) |
        header[_userVersionOffset + 3];
  }

  DatabaseException _unreadable(String detail) => DatabaseException(
    userMessage:
        'Veritabanı dosyası okunamadı veya bozuk. '
        'Yedekten geri yükleme gerekebilir.',
    technicalDetail: detail,
  );

  /// `user_version` — dosya yoksa `0`.
  ///
  /// Önce dosya başlığından **yan etkisiz** okunur; yalnızca WAL'da
  /// checkpoint'lenmemiş çerçeve varsa veritabanı açılır
  /// (bkz. [_readUserVersionFromHeader]).
  ///
  /// Dosya okunabilir bir SQLite veritabanı değilse [DatabaseException] fırlatır;
  /// ham SQLite metni kullanıcıya sızdırılmaz (REQ-SEC-007).
  Future<int> readUserVersion() async {
    final file = File(path);
    if (!file.existsSync()) return 0;

    final fromHeader = _readUserVersionFromHeader(file);
    if (fromHeader != null) return fromHeader;

    try {
      return await _withExecutor((executor) async {
        final rows = await executor.runSelect('PRAGMA user_version;', const []);
        if (rows.isEmpty) return 0;
        return rows.first.values.first as int? ?? 0;
      });
    } on SqliteException catch (e) {
      throw DatabaseException(
        userMessage:
            'Veritabanı dosyası okunamadı veya bozuk. '
            'Yedekten geri yükleme gerekebilir.',
        technicalDetail: 'user_version okunamadı (${e.extendedResultCode}).',
      );
    }
  }

  /// `PRAGMA integrity_check` — sağlıklıysa tek satır `'ok'` döner.
  ///
  /// **Bozuk veya SQLite olmayan dosya `false` döner, exception FIRLATMAZ.**
  /// Bu bir doğrulama sorgusudur: "bozuk mu?" sorusunun yanıtı `true`/`false`
  /// olmalıdır. Aksi hâlde bozuk bir snapshot, kurtarma akışını çökertirdi.
  Future<bool> isIntegral() async {
    final file = File(path);
    if (!file.existsSync() || file.lengthSync() == 0) return false;
    try {
      return await _withExecutor((executor) async {
        final rows = await executor.runSelect(
          'PRAGMA integrity_check;',
          const [],
        );
        if (rows.length != 1) return false;
        return rows.first.values.first == 'ok';
      });
    } on SqliteException {
      return false;
    }
  }
}
