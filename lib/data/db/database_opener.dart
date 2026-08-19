/// Veritabanı bağlantısı açma ve SQLite yapılandırması.
///
/// docs/05-database-architecture.md §1 — REQ-DB-001 · REQ-DATA-002
///
/// | Ayar | Değer | Gerekçe |
/// |---|---|---|
/// | `journal_mode` | **WAL** | Elektrik kesintisi dayanıklılığı |
/// | `synchronous` | **FULL** | Satış kaybı kabul edilemez |
/// | `foreign_keys` | **ON** | Referans bütünlüğü |
/// | `busy_timeout` | 5000 ms | |
/// | `temp_store` | **MEMORY** | Rapor aggregation hızı |
///
/// Ayrıca **REQ-MIG-005 sürüm kapısı** burada uygulanır: bağlantı açılır açılmaz,
/// Drift herhangi bir migration çalıştırma fırsatı bulmadan `user_version`
/// kontrol edilir.
library;

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import '../../core/errors/app_exception.dart';
import '../../domain/services/turkish_text.dart';
import 'schema_version.dart';

/// SQLite PRAGMA değerleri — testler bu sabitleri doğrular.
abstract final class SqlitePragmas {
  static const String journalModeWal = 'wal';

  /// `PRAGMA synchronous` FULL karşılığı.
  static const int synchronousFull = 2;

  /// `PRAGMA temp_store` MEMORY karşılığı.
  static const int tempStoreMemory = 2;

  static const int busyTimeoutMs = 5000;
}

/// **Her** bağlantıda uygulanan PRAGMA'lar — tanı bağlantısı dâhil.
///
/// `synchronous` buraya aittir, çünkü **"yalnızca PRAGMA okuyan" bir bağlantı
/// da diske yazabilir:** WAL modunda son bağlantı kapanırken checkpoint
/// çalışır ve WAL çerçevelerini ana dosyaya taşır. Çökme sonrası açılışta
/// (`DatabaseBootstrap.open` → `RawSqliteFile.readUserVersion`) tam olarak bu
/// olur. Ölçüm: 4 KB'lik ana dosya, hiçbir DML çalıştırılmadan 52 KB'ye çıkar.
///
/// Ayrıca `synchronous` varsayılanı sabit değildir — WAL dosyasında `NORMAL`
/// (1), rollback-journal dosyasında `FULL` (2) ölçülür. Açıkça yazılmazsa
/// üretim veritabanı `docs/05 §1`'in gerektirdiği `FULL`'de **olmaz**.
/// **SIRA KRİTİKTİR — `busy_timeout` daima ilk sıradadır.**
///
/// Bağlantının ilk ifadesi veritabanı başlığını okumak için paylaşımlı kilit
/// ister. Başka biri kilidi tutuyorsa, `busy_timeout` o ana kadar
/// uygulanmadıysa SQLite bekleme yapmadan `SQLITE_BUSY` döner. Ölçüldü:
/// `synchronous` başa alındığında kilitli veritabanında açılış **4 ms**'de
/// düşüyor; `busy_timeout` başa alındığında beklemeye geçiyor.
const List<String> _sharedPragmas = [
  'PRAGMA busy_timeout = ${SqlitePragmas.busyTimeoutMs};',
  'PRAGMA synchronous = FULL;',
  'PRAGMA temp_store = MEMORY;',
];

/// Yalnızca **yazan** bağlantılarda anlamlı olan PRAGMA'lar.
///
/// `foreign_key_check` bu ayardan bağımsız çalışır (ölçüldü: `foreign_keys=0`
/// iken de ihlalleri raporlar), bu yüzden tanı bağlantısına uygulanmaz.
const List<String> _writeConnectionPragmas = ['PRAGMA foreign_keys = ON;'];

/// Uygulama tarafından tanımlanan SQL fonksiyonları.
///
/// **REQ-PROD-010 · docs/09 §6** — ürün araması Türkçe karakter ve büyük/küçük
/// harf duyarsızdır.
///
/// ## Neden normalize edilmiş bir kolon değil
///
/// Şema **FİNAL**'dir (rules/03 §1): `products` tablosuna katlanmış bir arama
/// kolonu eklemek bir şema kararıdır ve dokümanda yoktur. Bunun yerine
/// karşılaştırma anında çalışan **deterministik bir skaler fonksiyon**
/// kaydedilir; sorgu `WHERE canteen_fold(name) LIKE ?` yazabilir.
///
/// Katlama mantığı Dart tarafında **tek yerde** yaşar
/// ([TurkishText.fold]) — sorgunun iki yakası aynı kuralı kullanır.
///
/// Tam tarama bilinçli bir tercihtir: rules/01 §8 FTS5/rollup/önbelleği
/// "yalnızca ölçülerek eşik aşıldığında" serbest bırakır.
abstract final class SqliteFunctions {
  /// Türkçe arama katlaması — [TurkishText.fold].
  static const String fold = 'canteen_fold';
}

/// Bağlantı kurulum adımlarını üretir.
///
/// [useWal] yalnızca dosya tabanlı veritabanları için anlamlıdır; in-memory
/// veritabanı WAL moduna geçemez.
DatabaseSetup buildDatabaseSetup({
  required bool useWal,
  int supportedSchemaVersion = kSupportedSchemaVersion,
}) {
  return (rawDb) {
    // Ortak PRAGMA'lar ÖNCE — `busy_timeout` başta olmalı, çünkü hemen
    // ardından gelen `journal_mode = WAL` kilit bekleyebilir.
    for (final pragma in _sharedPragmas) {
      rawDb.execute(pragma);
    }
    if (useWal) {
      rawDb.execute('PRAGMA journal_mode = WAL;');
    }
    for (final pragma in _writeConnectionPragmas) {
      rawDb.execute(pragma);
    }

    // [SqliteFunctions.fold] — PRAGMA'ların tamamının ARDINDAN kaydedilir.
    // Fonksiyon kaydı veritabanına hiç dokunmaz (SQL çalıştırmaz), yine de
    // `busy_timeout`'un ilk ifade olması kuralı (bkz. [_sharedPragmas])
    // hiçbir koşulda esnetilmez.
    //
    // `deterministic: true`: aynı girdi daima aynı çıktıyı verir; sorgu
    // planlayıcı çağrıyı iç döngülerden çıkarabilir.
    // `directOnly` varsayılanı (`true`) korunur: fonksiyon yalnızca üst düzey
    // SQL'den çağrılabilir, VIEW/TRIGGER veya şema ifadelerinden çağrılamaz —
    // sqlite3 bunu tüm uygulama fonksiyonları için önerir.
    //
    // Kayıt burada **satır içidir**, çünkü `rawDb`'nin tipi [DatabaseSetup]'tan
    // çıkarılır; ayrı bir yardımcı fonksiyon `package:sqlite3` import etmeyi
    // gerektirirdi ve o paket drift'in **geçişli** bağımlılığıdır.
    rawDb.createFunction(
      functionName: SqliteFunctions.fold,
      deterministic: true,
      function: (args) {
        if (args.isEmpty) return null;
        final value = args.first;
        // NULL girdi NULL döner — SQL fonksiyonlarının beklenen davranışı;
        // `brand` gibi nullable kolonlar bu yoldan geçer.
        return value is String ? TurkishText.fold(value) : null;
      },
    );

    // REQ-MIG-005 — kendi desteklediğinden yeni bir şemayı açmayı reddet.
    final rows = rawDb.select('PRAGMA user_version;');
    final version = rows.isEmpty ? 0 : rows.first.values.first as int? ?? 0;
    if (version > supportedSchemaVersion) {
      throw SchemaVersionException(
        databaseVersion: version,
        supportedVersion: supportedSchemaVersion,
        userMessage:
            'Bu veritabanı daha yeni bir sürümle oluşturulmuş. '
            'Lütfen uygulamayı güncelleyin.',
        technicalDetail:
            'user_version=$version > supported=$supportedSchemaVersion',
      );
    }
  };
}

/// **Tanı** bağlantısı için kurulum — `RawSqliteFile`.
///
/// Bu bağlantı yalnızca `user_version`, `integrity_check` ve
/// `foreign_key_check` çalıştırır — ama bu onu *salt-okuma* yapmaz: WAL
/// checkpoint'i nedeniyle ana dosyayı yine de değiştirebilir
/// (bkz. [_sharedPragmas]). Bu yüzden `synchronous` dâhil ortak PRAGMA'ların
/// tamamını alır.
///
/// [buildDatabaseSetup]'ın kalan iki parçası ise **bilinçli olarak** dışarıda
/// bırakılır:
///
/// | Uygulanmayan | Neden |
/// |---|---|
/// | `journal_mode = WAL` | WAL, dosya **başlığına yazılır** ve `-wal`/`-shm` yan dosyaları üretir. Bu bağlantı `VACUUM INTO` snapshot'larını **doğrulamak** için kullanılıyor (`MigrationCoordinator.verifySnapshot`); doğruladığı dosyayı WAL'a çeviremez. |
/// | REQ-MIG-005 sürüm kapısı | `readUserVersion()` "çok yeni şema"yı tam olarak **saptamak** için var. Kapı burada da uygulansaydı, saptaması gereken durumda exception fırlatır ve `DatabaseBootstrap`'in açık kontrolünü imkânsız kılardı. |
DatabaseSetup buildDiagnosticSetup() {
  return (rawDb) {
    for (final pragma in _sharedPragmas) {
      rawDb.execute(pragma);
    }
  };
}

/// Dosya tabanlı veritabanı bağlantısı (production).
QueryExecutor openDatabaseFile(
  String path, {
  int supportedSchemaVersion = kSupportedSchemaVersion,
  bool logStatements = false,
}) {
  return NativeDatabase(
    File(path),
    logStatements: logStatements,
    setup: buildDatabaseSetup(
      useWal: true,
      supportedSchemaVersion: supportedSchemaVersion,
    ),
  );
}

/// In-memory bağlantı (testler — docs/27 §4).
///
/// WAL uygulanmaz: in-memory veritabanları `journal_mode = memory` kullanır.
/// WAL'ın gerçekten etkin olduğu **dosya tabanlı** bir test ile doğrulanır.
QueryExecutor openDatabaseInMemory({
  int supportedSchemaVersion = kSupportedSchemaVersion,
  bool logStatements = false,
}) {
  return NativeDatabase.memory(
    logStatements: logStatements,
    setup: buildDatabaseSetup(
      useWal: false,
      supportedSchemaVersion: supportedSchemaVersion,
    ),
  );
}
