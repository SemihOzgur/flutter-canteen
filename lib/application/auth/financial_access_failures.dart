/// Finansal erişim kilidinin ürettiği **beklenen iş hataları**.
///
/// rules/06 §7: beklenen iş hataları `Result`/`Failure` ile döner; exception
/// fırlatılmaz. Desen `auth_failures.dart` ile aynıdır.
///
/// Kullanıcı parolası hataları [AuthFailures] içinde kalır: dashboard parolası
/// **ayrı bir koruma katmanıdır** (docs/17 §1) ve mesajları da ayrıdır —
/// kasadaki kullanıcı hangi parolanın istendiğini karıştırmamalıdır.
///
/// Mesajlar Türkçedir (REQ-UX-007), teknik detay içermez (REQ-SEC-007) ve
/// **parola/hash/salt değeri taşımaz** (BR-SEC-001 · rules/04 §8).
library;

import '../../core/result/result.dart';

abstract final class FinancialAccessFailures {
  /// BR-AUTH-012 · REQ-AUTH-019 — kilit kapalıyken finansal sorgu çalıştırılmaz.
  ///
  /// Bu hata `guard` tarafından, sorgu **hiç çağrılmadan** döndürülür.
  static const Failure locked = Failure(
    code: 'financial_access_locked',
    userMessage:
        'Dashboard ve Raporlar için finansal erişim parolası gerekiyor.',
  );

  /// Dashboard parolası henüz belirlenmemiş.
  ///
  /// Normal akışta oluşmaz: kurulum sihirbazı Adım 2 bunu zorunlu kılar
  /// (REQ-AUTH-016 · EC-DASH-011).
  static const Failure notConfigured = Failure(
    code: 'financial_access_not_configured',
    userMessage:
        'Dashboard parolası belirlenmemiş. '
        'Ayarlar bölümünden bir parola belirleyin.',
  );

  /// Kurulum yalnızca bir kez yapılır; sonrası [changePassword] akışıdır
  /// (docs/17 §9 · BR-AUTH-010).
  static const Failure alreadyConfigured = Failure(
    code: 'financial_access_already_configured',
    userMessage:
        'Dashboard parolası zaten belirlenmiş. '
        'Değiştirmek için mevcut parolayı girin.',
  );

  /// EC-DASH-011 / REQ-AUTH-016 — parola zorunlu alandır.
  static const Failure passwordRequired = Failure(
    code: 'financial_access_password_required',
    userMessage: 'Dashboard parolası boş olamaz.',
  );

  /// docs/17 §7 — yanlış dashboard parolası.
  static const Failure wrongPassword = Failure(
    code: 'financial_access_wrong_password',
    userMessage: 'Dashboard parolası hatalı.',
  );

  /// EC-DASH-008 · BR-AUTH-010 — mevcut parola doğrulanmadan değişiklik yapılmaz.
  static const Failure currentPasswordWrong = Failure(
    code: 'financial_access_current_password_wrong',
    userMessage: 'Mevcut dashboard parolası hatalı.',
  );

  /// EC-DASH-002 — ardışık 5 hatalı denemeden sonra 30 saniye bekleme.
  ///
  /// Kalan süre saniye olarak bildirilir; belirsiz bir "sonra deneyin" mesajı
  /// kasada işe yaramaz (rules/05 §5).
  static Failure tooManyAttempts(Duration remaining) {
    final seconds = remaining.inSeconds < 1 ? 1 : remaining.inSeconds;
    return Failure(
      code: 'financial_access_too_many_attempts',
      userMessage:
          'Çok fazla hatalı parola denemesi yapıldı. '
          '$seconds saniye sonra tekrar deneyin.',
    );
  }
}
