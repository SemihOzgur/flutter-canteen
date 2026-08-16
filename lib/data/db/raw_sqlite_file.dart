/// Bir SQLite dosyası üzerinde **migration çalıştırmadan** ham tanı sorguları.
///
/// Migration protokolü (docs/06 §3), veritabanına dokunmadan önce bazı bilgileri
/// okumak zorundadır:
///
/// - `user_version` — sürüm kapısı (REQ-MIG-005)
/// - `integrity_check` — snapshot doğrulaması (REQ-MIG-002)
/// - `foreign_key_check` — migration sonrası doğrulama (docs/06 §3 adım 6)
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
      await executor.close();
    }
  }

  /// `PRAGMA user_version` — dosya yoksa `0`.
  ///
  /// Dosya okunabilir bir SQLite veritabanı değilse [DatabaseException] fırlatır;
  /// ham SQLite metni kullanıcıya sızdırılmaz (REQ-SEC-007).
  Future<int> readUserVersion() async {
    if (!File(path).existsSync()) return 0;
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

  /// `PRAGMA foreign_key_check` — ihlal yoksa **boş** dönmelidir (docs/06 §6).
  Future<List<Map<String, Object?>>> foreignKeyViolations() {
    return _withExecutor((executor) async {
      return executor.runSelect('PRAGMA foreign_key_check;', const []);
    });
  }
}
