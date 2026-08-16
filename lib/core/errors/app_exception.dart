/// Uygulama hata hiyerarşisi.
///
/// REQ-SEC-007: Teknik hata detayı ve stack trace kullanıcıya gösterilmez;
///              log dosyasına yazılır. Kullanıcıya sade Türkçe mesaj gösterilir.
///
/// Bkz. docs/03-architecture.md §7 · rules/06 §7
library;

/// Beklenmeyen teknik hatalar için temel sınıf.
///
/// **Beklenen iş hataları** için exception fırlatılmaz; `Result`/`Failure` kullanılır
/// (rules/06 §7).
sealed class AppException implements Exception {
  /// Kullanıcıya gösterilebilecek sade Türkçe mesaj.
  final String userMessage;

  /// Yalnızca log dosyasına yazılacak teknik ayrıntı.
  final String? technicalDetail;

  const AppException({required this.userMessage, this.technicalDetail});

  @override
  String toString() => '$runtimeType: $userMessage';
}

/// Uygulamanın çalışamayacağı platform.
class UnsupportedPlatformException extends AppException {
  const UnsupportedPlatformException({
    required super.userMessage,
    super.technicalDetail,
  });
}

/// Veri dizini çözümlenemedi veya oluşturulamadı.
class DataDirectoryException extends AppException {
  const DataDirectoryException({
    required super.userMessage,
    super.technicalDetail,
  });
}

/// Aynı veritabanı üzerinde ikinci uygulama örneği (BR-GEN-005).
class AlreadyRunningException extends AppException {
  const AlreadyRunningException({
    required super.userMessage,
    super.technicalDetail,
  });
}

// ---------------------------------------------------------------------------
// Faz 2 — veritabanı hataları
//
// `AppException` **sealed**'dır: Dart, sealed bir sınıfın tüm doğrudan alt
// tiplerinin aynı library'de tanımlanmasını zorunlu kılar. Bu nedenle
// veritabanı hataları ayrı bir dosyaya konulamaz ve buraya eklenmiştir.
// Bu, Faz 1 davranışını değiştirmeyen bir genişletmedir.
// ---------------------------------------------------------------------------

/// Veritabanı açılamadı, okunamadı veya bozuk.
///
/// REQ-SEC-007: [technicalDetail] yalnızca log dosyasına yazılır.
class DatabaseException extends AppException {
  const DatabaseException({required super.userMessage, super.technicalDetail});
}

/// REQ-MIG-005 — veritabanı, uygulamanın desteklediğinden **daha yeni** bir
/// şema versiyonuyla oluşturulmuş.
///
/// Eski sürüm + yeni veri = veri bozma riski. Uygulama açılmayı reddeder
/// (docs/06 §1).
class SchemaVersionException extends AppException {
  /// Veritabanı dosyasındaki `user_version`.
  final int databaseVersion;

  /// Bu uygulama sürümünün desteklediği şema versiyonu.
  final int supportedVersion;

  const SchemaVersionException({
    required this.databaseVersion,
    required this.supportedVersion,
    required super.userMessage,
    super.technicalDetail,
  });
}

/// REQ-MIG-002/003 — migration sırasında veya migration kurtarması sırasında hata.
class MigrationException extends AppException {
  const MigrationException({required super.userMessage, super.technicalDetail});
}

/// REQ-MIG-006 — açılışta **yarım kalmış migration** tespit edildi.
///
/// docs/06 §3: kullanıcıya durum bildirilir ve onayıyla pre-migration snapshot
/// geri yüklenir. Onaylamazsa uygulama kapanır — yarım şemayla çalışmaya izin
/// verilmez.
///
/// Alanlar bilinçli olarak **ilkel tiplerdir**: `core/` katmanı `data/`
/// katmanına bağımlı olamaz (rules/01 §1).
class MigrationRecoveryRequiredException extends AppException {
  final int fromVersion;
  final int toVersion;
  final DateTime startedAtUtc;

  /// Geri yüklenebilecek en yeni snapshot'ın yolu — yoksa `null`.
  final String? snapshotPath;

  const MigrationRecoveryRequiredException({
    required this.fromVersion,
    required this.toVersion,
    required this.startedAtUtc,
    required this.snapshotPath,
    required super.userMessage,
    super.technicalDetail,
  });
}
