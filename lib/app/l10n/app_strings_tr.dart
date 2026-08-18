/// Merkezî Türkçe arayüz metinleri.
///
/// OD-011: V1 tek dillidir (Türkçe). Çoklu dil altyapısı geliştirilmez.
///         Ancak UI metinleri **widget'ların içine dağınık şekilde hard-code edilmez**;
///         tek bir merkezî kaynakta toplanır.
///
/// rules/05 §4: Metinler merkezî metin dosyasındadır — widget içine dağınık
///              hard-code YASAK.
///
/// İleride `flutter_localizations` + ARB'ye geçiş, metinler zaten toplu olduğu için
/// düşük maliyetlidir.
library;

/// Tüm kullanıcıya görünen metinler.
class AppStringsTr {
  const AppStringsTr._();

  // ── Uygulama ─────────────────────────────────────────────────────────────
  static const String appTitle = 'Kantin Otomasyonu';

  // ── Faz 1 — temel ekran ──────────────────────────────────────────────────
  static const String foundationReady = 'Temel altyapı hazır';
  static const String foundationDescription =
      'Uygulama iskeleti kuruldu. Satış, ürün ve stok ekranları '
      'sonraki fazlarda eklenecek.';

  // ── Single instance (BR-GEN-005) ─────────────────────────────────────────
  static const String alreadyRunningTitle = 'Uygulama zaten çalışıyor';
  static const String alreadyRunningMessage =
      'Kantin Otomasyonu şu anda açık. Aynı anda yalnızca bir pencere '
      'kullanılabilir.';
  static const String close = 'Kapat';

  // ── Faz 3a — kurulum sihirbazı (docs/17 §4) ──────────────────────────────
  static const String setupTitle = 'İlk Kurulum';
  static const String setupDescription =
      'Uygulamayı kullanmaya başlamadan önce üç adım tamamlanmalıdır.';

  /// Sihirbazın kaldığı adım — `SetupState` sırasıyla (docs/17 §4).
  static const String setupStepUser = '1. Kullanıcı hesabı oluşturun';
  static const String setupStepDashboardPassword =
      '2. Dashboard parolası belirleyin';
  static const String setupStepRecoveryCode = '3. Kurtarma kodunu kaydedin';
  static const String setupComplete = 'Kurulum tamamlandı';

  /// Adım göstergesi — sihirbaz üç zorunlu adımdır (docs/17 §4).
  static const String setupStepCounterUser = 'Adım 1 / 3';
  static const String setupStepCounterDashboardPassword = 'Adım 2 / 3';
  static const String setupStepCounterRecoveryCode = 'Adım 3 / 3';

  /// Adım 1 — kullanıcı hesabı.
  static const String setupUserStepDescription =
      'Bu hesapla uygulamaya giriş yapacaksınız. '
      'Kullanıcı adı büyük/küçük harf ayrımı gözetmez.';

  /// Adım 2 — dashboard parolası (docs/17 §4 · REQ-AUTH-016).
  static const String setupDashboardStepDescription =
      'Dashboard ve Raporlar ekranları bu parola ile korunur. '
      'Uygulamaya giriş parolanızdan farklı olabilir.';

  /// Adım 3 — kurtarma kodu (docs/17 §4, §8 · REQ-AUTH-022/024).
  static const String setupRecoveryStepDescription =
      'Dashboard parolanızı unutursanız bu kod ile sıfırlayabilirsiniz.';
  static const String setupRecoveryCodeWarning =
      'Bu kod bir daha gösterilmeyecek. Güvenli bir yere kaydedin.';
  static const String setupRecoveryCodeSavedConfirm = 'Kodu kaydettim';
  static const String setupRecoveryCodeCopy = 'Kopyala';
  static const String setupRecoveryCodeSaveToFile = 'Dosyaya Kaydet';
  static const String setupRecoveryCodeSaveFileName =
      'kantin-kurtarma-kodu.txt';
  static const String setupRecoveryCodeSaved =
      'Kurtarma kodu dosyaya kaydedildi.';

  /// rules/04 §7: dosya yolu ve teknik hata kullanıcıya sızdırılmaz.
  static const String setupRecoveryCodeSaveFailed =
      'Kurtarma kodu kaydedilemedi. Farklı bir klasör seçip tekrar deneyin; '
      'kodu kopyalayıp güvenli bir yere de yazabilirsiniz.';

  /// Dosyanın içeriği — kodun ne olduğunu kullanıcıya hatırlatır.
  static String recoveryCodeFileContents(String code) =>
      'Kantin Otomasyonu — Dashboard kurtarma kodu\n'
      '\n'
      '$code\n'
      '\n'
      'Bu kodu Dashboard parolanızı unutursanız kullanacaksınız.\n'
      'Kod TEK KULLANIMLIKTIR; kullanıldığında yerine yenisi üretilir.\n'
      'Bu dosyayı güvenli bir yerde saklayın.\n';
  static const String setupRecoveryCodeCopied =
      'Kurtarma kodu panoya kopyalandı.';
  static const String setupRecoveryCodeUnavailable =
      'Kurtarma kodu üretilemedi. Yeniden deneyin.';
  static const String setupCompleteDescription =
      'Uygulamayı kullanmaya başlayabilirsiniz.';

  // ── Faz 3a — giriş ekranı (docs/17 §3) ───────────────────────────────────
  static const String loginTitle = 'Giriş Yap';
  static const String loginDescription =
      'Devam etmek için kullanıcı adınız ve parolanızla giriş yapın.';

  // ── Faz 3a — form alanları ve eylemleri ──────────────────────────────────
  static const String usernameLabel = 'Kullanıcı adı';
  static const String displayNameLabel = 'Görünen ad';
  static const String passwordLabel = 'Parola';
  static const String passwordConfirmLabel = 'Parola (tekrar)';
  static const String dashboardPasswordLabel = 'Dashboard parolası';
  static const String dashboardPasswordConfirmLabel =
      'Dashboard parolası (tekrar)';

  static const String continueAction = 'Devam';
  static const String retryAction = 'Yeniden dene';

  // ── Faz 3a — form doğrulama mesajları (REQ-UX-007) ───────────────────────
  //
  // Bunlar **form seviyesi** kontrollerdir (boş alan, iki alanın eşitliği);
  // iş kuralı doğrulaması servis katmanındadır ve mesajı `Failure.userMessage`
  // ile gelir (rules/05 §8).
  static const String usernameRequired = 'Kullanıcı adı boş olamaz.';
  static const String displayNameRequired = 'Görünen ad boş olamaz.';
  static const String passwordRequired = 'Parola boş olamaz.';
  static const String dashboardPasswordRequired =
      'Dashboard parolası boş olamaz.';
  static const String passwordMismatch =
      'Parolalar aynı değil. İki alana da aynı parolayı yazın.';

  // ── Faz 3a — ortak eylemler ──────────────────────────────────────────────
  static const String cancelAction = 'Vazgeç';
  static const String saveAction = 'Kaydet';
  static const String okAction = 'Tamam';
  static const String addAction = 'Ekle';
  static const String editAction = 'Düzenle';

  // ── Faz 3a — finansal erişim kilidi (docs/17 §7 · docs/22 F9) ────────────
  static const String financialAccessTitle = 'Finansal Erişim';
  static const String financialAccessDescription =
      'Dashboard ve Raporlar için parola gerekiyor.';
  static const String financialAccessUnlockAction = 'Aç';
  static const String financialAccessForgotAction = 'Şifremi unuttum';

  /// Faz 8 gelene kadar kilidin arkasında gösterilecek yer tutucu.
  static const String dashboardPlaceholderTitle = 'Finansal erişim açıldı';
  static const String dashboardPlaceholderMessage =
      'Dashboard ve Raporlar ekranları sonraki fazda eklenecek. '
      'Kilit bu oturum boyunca açık kalır.';

  // ── Faz 3a — kurtarma akışı (docs/17 §8 · docs/22 F10) ───────────────────
  static const String recoveryTitle = 'Kurtarma Kodu';
  static const String recoveryStepCounterCode = 'Adım 1 / 3';
  static const String recoveryStepCounterPassword = 'Adım 2 / 3';
  static const String recoveryStepCounterNewCode = 'Adım 3 / 3';
  static const String recoveryCodeStepTitle = 'Kurtarma kodunu girin';
  static const String recoveryCodeStepDescription =
      'Kurulumda size verilen kurtarma kodunu girin. '
      'Büyük/küçük harf ve tire farkı önemli değildir.';
  static const String recoveryCodeLabel = 'Kurtarma kodu';
  static const String recoveryCodeHint = 'XXXX-XXXX-XXXX-XXXX';
  static const String recoveryCodeRequired = 'Kurtarma kodu boş olamaz.';
  static const String recoveryPasswordStepTitle = 'Yeni dashboard parolası';
  static const String recoveryPasswordStepDescription =
      'Kurtarma kodu bu adımda doğrulanır. Doğruysa dashboard parolanız '
      'yenisiyle değiştirilir ve size yeni bir kurtarma kodu verilir.';
  static const String newDashboardPasswordLabel = 'Yeni dashboard parolası';
  static const String newDashboardPasswordConfirmLabel =
      'Yeni dashboard parolası (tekrar)';
  static const String recoveryNewCodeStepTitle =
      'Dashboard parolanız değiştirildi';
  static const String recoveryNewCodeStepDescription =
      'Eski kurtarma kodunuz artık geçersiz. Aşağıdaki YENİ kodu saklayın.';

  // ── Faz 3a — Ayarlar → Finansal Erişim (docs/17 §8, §9) ──────────────────
  static const String financialAccessSettingsDescription =
      'Dashboard parolanızı değiştirebilir veya yeni bir kurtarma kodu '
      'üretebilirsiniz.';
  static const String changeDashboardPasswordTitle =
      'Dashboard parolasını değiştir';
  static const String currentDashboardPasswordLabel =
      'Mevcut dashboard parolası';
  static const String changeDashboardPasswordAction = 'Parolayı Değiştir';
  static const String dashboardPasswordChanged =
      'Dashboard parolası değiştirildi.';
  static const String regenerateRecoveryCodeTitle = 'Yeni kurtarma kodu üret';
  static const String regenerateRecoveryCodeDescription =
      'Mevcut kodunuz bir daha gösterilemez. Yeni kod ürettiğinizde eski kod '
      'geçersizleşir.';
  static const String regenerateRecoveryCodeAction = 'Yeni Kurtarma Kodu Üret';

  // ── Faz 3a — kullanıcı yönetimi (docs/17 §11 · REQ-AUTH-008/009) ─────────
  static const String usersTitle = 'Kullanıcı Yönetimi';
  static const String usersDescription =
      'Tüm kullanıcılar aynı yetkilere sahiptir. Kullanıcılar silinemez; '
      'yalnızca pasifleştirilir.';
  static const String usersEmpty =
      'Henüz kullanıcı yok. Yeni bir kullanıcı ekleyin.';
  static const String userAddTitle = 'Yeni kullanıcı';
  static const String userAddAction = 'Kullanıcı Ekle';
  static const String userEditDisplayNameTitle = 'Görünen adı değiştir';
  static const String userActive = 'Aktif';
  static const String userInactive = 'Pasif';
  static const String userCreated = 'Kullanıcı eklendi.';
  static const String userUpdated = 'Kullanıcı güncellendi.';

  // ── Faz 3a — ana ekran gezinme ───────────────────────────────────────────
  static const String homeUsersAction = 'Kullanıcı Yönetimi';
  static const String homeFinancialAccessAction = 'Finansal Erişim';
  static const String homeDashboardAction = 'Dashboard';

  // ── Genel hata (REQ-UX-007, REQ-SEC-007) ─────────────────────────────────
  static const String unexpectedErrorTitle = 'Beklenmeyen bir hata oluştu';
  static const String unexpectedErrorMessage =
      'İşlem tamamlanamadı. Sorun devam ederse uygulamayı yeniden başlatın.';
  static const String startupFailedTitle = 'Uygulama başlatılamadı';
}
