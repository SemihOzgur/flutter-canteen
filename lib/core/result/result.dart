/// Beklenen iş hataları için dönüş tipi.
///
/// rules/06 §7: "Beklenen iş hataları `Result`/`Failure` ile döner;
///               exception fırlatılmaz."
///
/// Beklenmeyen teknik hatalar için `AppException` kullanılır.
library;

/// İşlem sonucu: başarı (`Ok`) veya beklenen iş hatası (`Err`).
sealed class Result<T> {
  const Result();

  bool get isOk => this is Ok<T>;
  bool get isErr => this is Err<T>;

  /// Başarılıysa değeri, değilse `null`.
  T? get valueOrNull => switch (this) {
    Ok<T>(:final value) => value,
    Err<T>() => null,
  };

  /// Hata varsa hatayı, yoksa `null`.
  Failure? get failureOrNull => switch (this) {
    Ok<T>() => null,
    Err<T>(:final failure) => failure,
  };
}

class Ok<T> extends Result<T> {
  final T value;
  const Ok(this.value);
}

class Err<T> extends Result<T> {
  final Failure failure;
  const Err(this.failure);
}

/// Beklenen iş hatası.
///
/// [userMessage] kullanıcıya gösterilir ve Türkçedir (REQ-UX-007).
class Failure {
  final String code;
  final String userMessage;

  const Failure({required this.code, required this.userMessage});

  @override
  String toString() => 'Failure($code): $userMessage';
}
