/// Kimlik doğrulamanın ürettiği **beklenen iş hataları**.
///
/// rules/06 §7: beklenen iş hataları `Result`/`Failure` ile döner; exception
/// fırlatılmaz. Desen `data/repositories/failures.dart` ile aynıdır.
///
/// Mesajlar Türkçedir (REQ-UX-007), teknik detay içermez (REQ-SEC-007) ve
/// **parola/kod değeri taşımaz** (BR-SEC-001 · rules/04 §8).
library;

import '../../core/result/result.dart';

abstract final class AuthFailures {
  /// EC-AUTH-001 — hangi alanın yanlış olduğu **söylenmez.**
  ///
  /// Bilinmeyen kullanıcı adı, hatalı parola ve pasif kullanıcı **aynı** hatayı
  /// döndürür; aksi hâlde kullanıcı adı varlığı sızardı.
  static const Failure invalidCredentials = Failure(
    code: 'auth_invalid_credentials',
    userMessage: 'Kullanıcı adı veya parola hatalı.',
  );

  static const Failure usernameRequired = Failure(
    code: 'auth_username_required',
    userMessage: 'Kullanıcı adı boş olamaz.',
  );

  static const Failure passwordRequired = Failure(
    code: 'auth_password_required',
    userMessage: 'Parola boş olamaz.',
  );

  static const Failure displayNameRequired = Failure(
    code: 'auth_display_name_required',
    userMessage: 'Görünen ad boş olamaz.',
  );

  /// `ux_users_username` — kullanıcı adı benzersizdir (docs/17 §11).
  static const Failure usernameExists = Failure(
    code: 'auth_username_exists',
    userMessage: 'Bu kullanıcı adı zaten kullanılıyor. Farklı bir ad deneyin.',
  );

  static const Failure userNotFound = Failure(
    code: 'auth_user_not_found',
    userMessage: 'Kullanıcı bulunamadı.',
  );

  /// docs/17 §11 — parola değiştirmek için mevcut parola gerekir.
  static const Failure currentPasswordWrong = Failure(
    code: 'auth_current_password_wrong',
    userMessage: 'Mevcut parola hatalı.',
  );

  /// BR-AUTH-006 · EC-AUTH-005 — sistemde en az bir aktif kullanıcı kalmalıdır.
  static const Failure lastActiveUser = Failure(
    code: 'auth_last_active_user',
    userMessage:
        'Sistemde en az bir aktif kullanıcı bulunmalıdır. '
        'Bu kullanıcı pasifleştirilemez.',
  );

  /// EC-AUTH-002 / REQ-AUTH-011 — ardışık 5 hatalı denemeden sonra bekleme.
  ///
  /// Kalan süre kullanıcıya saniye olarak bildirilir; belirsiz bir "sonra
  /// deneyin" mesajı kasada işe yaramaz (rules/05 §5).
  static Failure tooManyAttempts(Duration remaining) {
    final seconds = remaining.inSeconds < 1 ? 1 : remaining.inSeconds;
    return Failure(
      code: 'auth_too_many_attempts',
      userMessage:
          'Çok fazla hatalı giriş denemesi yapıldı. '
          '$seconds saniye sonra tekrar deneyin.',
    );
  }
}
