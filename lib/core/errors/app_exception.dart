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
