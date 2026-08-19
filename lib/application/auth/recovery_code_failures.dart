/// Recovery code akışının ürettiği **beklenen iş hataları**.
///
/// rules/06 §7: beklenen iş hataları `Result`/`Failure` ile döner; exception
/// fırlatılmaz. Desen `financial_access_failures.dart` ile aynıdır.
///
/// Mesajlar Türkçedir (REQ-UX-007), teknik detay içermez (REQ-SEC-007) ve
/// **kod/parola/hash/salt değeri taşımaz** (BR-SEC-001 · rules/04 §8).
library;

import '../../core/result/result.dart';

abstract final class RecoveryCodeFailures {
  /// Yanlış **veya biçimi geçersiz** kod — docs/17 §8.
  ///
  /// İkisi bilinçli olarak **aynı** mesajı alır: biçim kontrolü ayrı bir hata
  /// döndürseydi, saldırgan için "bu kod doğru biçimde ama yanlış" bilgisi
  /// veren bir oracle olurdu (EC-AUTH-001 ile aynı gerekçe).
  static const Failure invalidCode = Failure(
    code: 'recovery_code_invalid',
    userMessage:
        'Kurtarma kodu hatalı. '
        'Kurulumda size verilen XXXX-XXXX-XXXX-XXXX biçimindeki kodu girin.',
  );

  /// EC-REC-002 — kullanılmış kod **ayırt edici** mesaj alır.
  ///
  /// docs/17 §8 akış diyagramı bu dalı yanlış koddan ayrı gösterir: kod tek
  /// kullanımlık olduğu için kullanıcının "kod yanlış mı, tükenmiş mi?"
  /// sorusunu ayırt edebilmesi gerekir. Bu bilgi bir sır değildir — kodu
  /// zaten doğru bilen kişiye verilir.
  static const Failure alreadyUsed = Failure(
    code: 'recovery_code_already_used',
    userMessage:
        'Bu kurtarma kodu daha önce kullanılmış. '
        'Kurtarma sırasında size verilen yeni kodu kullanın.',
  );

  /// EC-REC-012 — veritabanında recovery kaydı hiç yok.
  ///
  /// Bu durumda "Şifremi unuttum" seçeneği kullanıcıya **gösterilmez**
  /// (`RecoveryCodeService.isAvailable`); yine de servis çağrılırsa akış sessiz
  /// başarısızlıkla değil bu hatayla biter. Parola değiştirme yolu açık kalır.
  static const Failure notConfigured = Failure(
    code: 'recovery_code_not_configured',
    userMessage:
        'Bu kurulumda kurtarma kodu tanımlı değil. '
        'Dashboard parolasını Ayarlar bölümünden değiştirebilirsiniz.',
  );

  /// Kurulum sihirbazı Adım 3 bir kez çalışır; sonrası yenileme akışıdır
  /// (docs/17 §8 — "Recovery code yeniden görüntüleme / yenileme").
  static const Failure alreadyConfigured = Failure(
    code: 'recovery_code_already_configured',
    userMessage:
        'Kurtarma kodu zaten üretilmiş. '
        'Yeni bir kod için Ayarlar bölümünden dashboard parolanızı girin.',
  );

  /// EC-REC-003 — ardışık 5 hatalı denemeden sonra 30 saniye bekleme.
  static Failure tooManyAttempts(Duration remaining) {
    final seconds = remaining.inSeconds < 1 ? 1 : remaining.inSeconds;
    return Failure(
      code: 'recovery_code_too_many_attempts',
      userMessage:
          'Çok fazla hatalı kurtarma kodu denemesi yapıldı. '
          '$seconds saniye sonra tekrar deneyin.',
    );
  }
}
