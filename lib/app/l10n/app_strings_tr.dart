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

  // ── Faz 3b — ortak durum ve eylemler (docs/10 · docs/08 §4) ──────────────
  //
  // Üç referans veri ekranı da (kategori, tedarikçi, KDV oranı) aynı
  // pasifleştirme/aktifleştirme sözlüğünü kullanır; metin tek yerde yaşar.
  static const String statusActive = 'Aktif';
  static const String statusInactive = 'Pasif';
  static const String deactivateAction = 'Pasife Al';
  static const String activateAction = 'Yeniden Aktifleştir';
  static const String deleteAction = 'Sil';
  static const String changeAction = 'Değiştir';

  // ── Faz 3b — kategoriler (docs/10 §1 · REQ-CAT-001…007) ──────────────────
  static const String categoriesTitle = 'Kategoriler';
  static const String categoriesDescription =
      'Kategoriler satış ekranındaki sıra numarasına göre listelenir. '
      'Kullanılmış bir kategori silinemez; pasife alınır ve ürünleri '
      'etkilenmez.';
  static const String categoryAddTitle = 'Yeni kategori';
  static const String categoryAddAction = 'Kategori Ekle';
  static const String categoryNameLabel = 'Kategori adı';
  static const String categoryNameRequired = 'Kategori adı boş olamaz.';
  static const String categoryRenameTitle = 'Kategori adını değiştir';
  static const String categorySortOrderTitle = 'Sıralamayı değiştir';
  static const String categorySortOrderLabel = 'Sıra numarası';
  static const String categorySortOrderInvalid =
      'Sıra numarası tam sayı olmalı. Örnek: 10';

  /// Liste satırındaki sıra bilgisi.
  static String categorySortOrderValue(int sortOrder) => 'Sıra $sortOrder';

  /// BR-CAT-004 · EC-CAT-001 — sebep açıklanır; eylem gizlenmez, devre dışıdır.
  static const String categorySystemBadge = 'Sistem kategorisi';
  static const String categorySystemHint =
      '"Genel" sistem kategorisidir: adı değiştirilemez, pasife alınamaz ve '
      'silinemez. Ürüne kategori seçilmediğinde bu kategori kullanılır.';

  static const String categoryCreated = 'Kategori eklendi.';
  static const String categoryRenamed = 'Kategori adı güncellendi.';
  static const String categorySortOrderUpdated = 'Sıralama güncellendi.';
  static const String categoryDeactivated = 'Kategori pasife alındı.';
  static const String categoryActivated = 'Kategori yeniden aktifleştirildi.';
  static const String categoryDeleted = 'Kategori silindi.';

  /// REQ-CAT-006 — kalıcı silme geri alınamaz; onay metni bunu söyler.
  static const String categoryDeleteTitle = 'Kategoriyi sil';
  static String categoryDeleteConfirm(String name) =>
      '"$name" kategorisi kalıcı olarak silinecek. Bu işlem geri alınamaz.';

  /// docs/10 §1.3 — pasifleştirme öncesi bilgi: ürün sayısı gösterilir.
  static const String categoryDeactivateTitle = 'Kategoriyi pasife al';
  static String categoryDeactivateMessage(String name, int productCount) =>
      productCount > 0
      ? '"$name" kategorisi pasife alınacak. Bu kategoride $productCount ürün '
            'var. Ürünler etkilenmeyecek, satılmaya devam edecek. Yalnızca '
            'yeni ürünlere bu kategori atanamayacak.'
      : '"$name" kategorisi pasife alınacak. Bu kategoride ürün yok. '
            'Yalnızca yeni ürünlere bu kategori atanamayacak.';

  /// REQ-CAT-004 — docs/10 §1.4 toplu taşıma.
  static const String categoryMoveProductsAction =
      'Ürünleri başka kategoriye taşı';
  static const String categoryMoveTargetTitle = 'Hedef kategoriyi seçin';
  static const String categoryMoveTargetDescription =
      'Ürünler seçtiğiniz kategoriye taşınır. Geçmiş satışların kategori '
      'raporu değişmez. Yalnızca aktif kategoriler listelenir.';
  static const String categoryMoveNoTarget =
      'Taşınabilecek başka aktif kategori yok. Önce yeni bir kategori ekleyin.';
  static String categoryProductsMoved(int count, String targetName) =>
      '$count ürün "$targetName" kategorisine taşındı.';

  // ── Faz 3b — tedarikçiler (docs/10 §2 · REQ-SUP-001/002/006) ─────────────
  static const String suppliersTitle = 'Tedarikçiler';
  static const String suppliersDescription =
      'Tedarikçi silinemez; yalnızca pasife alınır. Bağlı ürünler ve geçmiş '
      'stok girişleri korunur.';
  static const String suppliersEmpty =
      'Henüz tedarikçi yok. Yeni bir tedarikçi ekleyin.';
  static const String supplierAddTitle = 'Yeni tedarikçi';
  static const String supplierAddAction = 'Tedarikçi Ekle';
  static const String supplierEditTitle = 'Tedarikçiyi düzenle';

  /// REQ-SUP-001 — yalnızca ad zorunludur; etiketler bunu görünür kılar.
  static const String supplierNameLabel = 'Tedarikçi adı';
  static const String supplierNameRequired = 'Tedarikçi adı boş olamaz.';
  static const String supplierContactNameLabel = 'Yetkili kişi (opsiyonel)';
  static const String supplierPhoneLabel = 'Telefon (opsiyonel)';
  static const String supplierEmailLabel = 'E-posta (opsiyonel)';
  static const String supplierAddressLabel = 'Adres (opsiyonel)';
  static const String supplierNoteLabel = 'Not (opsiyonel)';
  static const String supplierCreated = 'Tedarikçi eklendi.';
  static const String supplierUpdated = 'Tedarikçi güncellendi.';
  static const String supplierDeactivated = 'Tedarikçi pasife alındı.';
  static const String supplierActivated = 'Tedarikçi yeniden aktifleştirildi.';

  // ── Faz 3b — KDV oranları (docs/08 §4 · REQ-VAT-001/010/011) ─────────────
  static const String vatRatesTitle = 'KDV Oranları';
  static const String vatRatesDescription =
      'Satış fiyatları KDV dahildir. Oran kaydı silinemez; yalnızca pasife '
      'alınır. Oran değişikliği geçmiş satışların KDV tutarını değiştirmez.';
  static const String vatRateAddTitle = 'Yeni KDV oranı';
  static const String vatRateAddAction = 'KDV Oranı Ekle';
  static const String vatRateEditTitle = 'KDV oranını düzenle';
  static const String vatRateNameLabel = 'Oran adı';
  static const String vatRateNameRequired = 'KDV oranı adı boş olamaz.';
  static const String vatRateValueLabel = 'Oran';
  static const String vatRateValueHint = 'Örnek: 20 veya 0,5';
  static const String vatRateValueRequired = 'KDV oranı boş olamaz.';
  static const String vatRateDefaultBadge = 'Varsayılan';

  /// BR-VAT-006 · EC-VAT-001 — pasif satırda bu eylem sunulmaz.
  static const String vatRateSetDefaultAction = 'Varsayılan yap';
  static const String vatRateCreated = 'KDV oranı eklendi.';
  static const String vatRateUpdated = 'KDV oranı güncellendi.';
  static const String vatRateDefaultUpdated =
      'Varsayılan KDV oranı güncellendi.';
  static const String vatRateDeactivated = 'KDV oranı pasife alındı.';
  static const String vatRateActivated = 'KDV oranı yeniden aktifleştirildi.';

  /// docs/08 §4 — oran DEĞERİ değişiyorsa kaydetmeden önce gösterilir.
  static const String vatRateChangeWarningTitle = 'Oran değişikliği';
  static String vatRateChangeWarning(int productCount) =>
      'Bu oran $productCount üründe kullanılıyor. Değişiklik yalnızca bundan '
      'sonraki satışları etkiler. Geçmiş satışların KDV tutarları değişmez.';

  // ── Faz 3b — ana ekran gezinme ───────────────────────────────────────────
  static const String homeCategoriesAction = 'Kategoriler';
  static const String homeSuppliersAction = 'Tedarikçiler';
  static const String homeVatRatesAction = 'KDV Oranları';

  // ── Faz 3c — ürünler (docs/09 · REQ-PROD-001…015) ────────────────────────
  static const String productsTitle = 'Ürünler';
  static const String productsDescription =
      'Satış fiyatları KDV dahildir. Satılmış veya stok hareketi olan ürün '
      'silinemez; pasife alınır ve raporlarda görünmeye devam eder.';

  /// docs/23 §7 — boş durum eyleme yönlendirir.
  ///
  /// Doküman burada "[Excel'den İçe Aktar]" eylemini de sayar; import **Faz
  /// 10** kapsamındadır (docs/25) ve var olmayan bir ekrana buton konmaz.
  static const String productsEmpty =
      'Henüz ürün eklemediniz. İlk ürününüzü ekleyin.';
  static String productsSearchEmpty(String query) =>
      '"$query" için ürün bulunamadı. Farklı bir ad veya marka deneyin.';

  static const String productSearchLabel = 'Ürün adı veya marka ara';
  static const String productShowInactiveLabel = 'Pasifleri göster';

  static const String productAddAction = 'Ürün Ekle';
  static const String productAddTitle = 'Yeni ürün';
  static const String productEditTitle = 'Ürünü düzenle';
  static const String productCreated = 'Ürün eklendi.';
  static const String productUpdated = 'Ürün güncellendi.';
  static const String productDeleted = 'Ürün silindi.';
  static const String productDeactivated = 'Ürün pasife alındı.';
  static const String productActivated = 'Ürün yeniden aktifleştirildi.';

  /// REQ-PERF-006 — liste sayfalanır; sayfa göstergesi bunu görünür kılar.
  static String productPageIndicator(int page, int pageCount) =>
      'Sayfa $page / $pageCount';
  static String productTotalCount(int total) => 'Toplam $total ürün';
  static const String previousPageAction = 'Önceki';
  static const String nextPageAction = 'Sonraki';

  /// Liste satırı — stok negatif olabilir (BR-STOCK-006).
  static String productStockValue(int quantity) => 'Stok: $quantity';

  /// BR-VAT-003 — listede gösterilen fiyat KDV dahildir.
  static const String productPriceVatIncludedSuffix = 'KDV dahil';

  /// EC-PROD-005 · EC-PROD-006 · EC-VAT-002 — pasif referans kaydı seçili
  /// kalabilir; etiketle işaretlenir (rules/05 §5 — renk tek başına yetmez).
  static String inactiveOptionLabel(String name) => '$name (pasif)';

  // ── Faz 3c — ürün formu (docs/09 §1, §2.2) ───────────────────────────────
  static const String productTabGeneral = 'Genel';
  static const String productTabPricing = 'Fiyat & KDV';
  static const String productTabStock = 'Stok';
  static const String productTabBarcodes = 'Barkodlar';

  static const String productNameLabel = 'Ürün adı';
  static const String productNameRequired = 'Ürün adı boş olamaz.';
  static const String productDescriptionLabel = 'Açıklama (opsiyonel)';
  static const String productCategoryLabel = 'Kategori';
  static const String productCategoryDefaultHint =
      'Seçilmezse "Genel" kategorisi kullanılır.';
  static const String productCategoryDefaultOption = 'Genel (varsayılan)';
  static const String productBrandLabel = 'Marka (opsiyonel)';
  static const String productSalesUnitLabel = 'Satış birimi (opsiyonel)';
  static const String productSalesUnitHint =
      'Nasıl satıldığını anlatır; miktar daima tam sayıdır.';
  static const String productNetWeightValueLabel = 'Net ağırlık (opsiyonel)';
  static const String productNetWeightUnitLabel = 'Ağırlık birimi';
  static const String productNetWeightHint =
      'Örnek: 150 g. Yalnızca açıklayıcıdır; fiyat ve stok hesabına girmez.';
  static const String productNetWeightInvalid =
      'Net ağırlık sayı olmalı. Örnek: 150 veya 1,5';
  static const String productShelfLocationLabel = 'Raf konumu (opsiyonel)';
  static const String productSupplierLabel = 'Tedarikçi (opsiyonel)';
  static const String productSupplierNone = 'Tedarikçi seçilmedi';
  static const String suggestionsTooltip = 'Önerilenler';

  /// **REQ-PROD-014 — bu etiket bir gereksinimdir, tercih değildir.**
  ///
  /// docs/09 §1: girilen tutar müşteriden alınan tutardır; KDV bu tutarın
  /// **içinden** çıkarılır, üzerine eklenmez (BR-VAT-003).
  static const String productSalePriceLabel = 'Satış Fiyatı (KDV Dahil)';
  static const String productSalePriceHint =
      'Müşteriden alınan tutar. KDV bu tutarın içinden çıkarılır. '
      'Örnek: 25,50';
  static const String productPurchasePriceLabel = 'Alış fiyatı';
  static const String productPurchasePriceHint =
      'Boş bırakılırsa ₺0,00 kaydedilir.';

  /// REQ-FIN-006 — hem `,` hem `.` kabul edilir; mesaj örnekle biter
  /// (rules/05 §5: "ne oldu + ne yapmalıyım").
  static const String productSalePriceInvalid =
      'Fiyat geçersiz. Örnek: 25,50 veya 25.50';
  static const String productVatRateLabel = 'KDV oranı';
  static const String productVatRateDefaultOption = 'Varsayılan oran';

  /// docs/08 §3 — hiç aktif oran yoksa KDV alanları gizlenir (BR-VAT-005).
  static const String productVatDisabledNotice =
      'KDV takibi kapalı: tanımlı bir KDV oranı yok. Satış fiyatının tamamı '
      'matrah kabul edilir. Ayarlar → KDV Oranları\'ndan oran ekleyebilirsiniz.';

  static const String productMinimumStockLabel = 'Minimum stok';
  static const String productMinimumStockHint =
      '0 ise kritik stok uyarısı verilmez.';
  static const String productInitialStockLabel = 'Başlangıç stoğu';

  /// REQ-PROD-007 — değer doğrudan yazılmaz, `initial` stok hareketi üretir.
  static const String productInitialStockHint =
      'Girilen miktar bir stok hareketi olarak kaydedilir; stok geçmişinde '
      'görünür.';
  static const String productStockLabel = 'Stok';

  /// docs/09 §1 — "Stok alanı düzenlenebilir değildir."
  static const String productStockReadOnlyHint =
      'Stok elle düzenlenemez. Yalnızca stok hareketleriyle değişir.';
  static const String productIntegerInvalid =
      'Miktar tam sayı olmalı. Örnek: 0, 1, 12';

  // ── Faz 3c — barkodlar (docs/09 §1 · EC-PROD-001/002/003/016) ────────────
  static const String productBarcodesDescription =
      'Ürün barkodsuz olabilir; arama ve favorilerle satılır. Bir ürüne '
      'birden fazla barkod eklenebilir.';
  static const String productBarcodesEmpty =
      'Bu ürünün barkodu yok. Barkod eklemek zorunlu değildir.';
  static const String productBarcodeLabel = 'Barkod';
  static const String productBarcodeAddAction = 'Barkod Ekle';
  static const String productBarcodeRemoveAction = 'Barkodu sil';
  static const String productBarcodeAdded = 'Barkod eklendi.';
  static const String productBarcodeRemoved = 'Barkod silindi.';

  /// REQ-PROD-005 · EC-PROD-001 — sahip ürüne gitme seçeneği sunulur.
  static const String productBarcodeGoToOwnerAction = 'Ürüne Git';

  /// Kaydedilmemiş ürüne eklenen barkodlar ürünle **birlikte** yazılır.
  static const String productBarcodePendingNotice =
      'Barkodlar ürünle birlikte kaydedilir.';

  // ── Faz 3c — silme / pasifleştirme (docs/09 §4 · EC-PROD-019/020/021) ────
  static const String productDeleteTitle = 'Ürünü sil';
  static const String productDeactivateAction = 'Pasife Al';
  static const String productDeletePermanentAction = 'Kalıcı Olarak Sil';

  /// BR-PROD-014 · EC-PROD-019 — geri alınamaz; onay zorunludur.
  static String productDeleteConfirm(String name) =>
      '"$name" ürünü hiç satılmamış ve hiç stok hareketi yok. Kalıcı olarak '
      'silinecek. Bu işlem geri alınamaz.';

  /// BR-PROD-009 · EC-PROD-020/021 — kalıcı silme **sunulmaz**.
  ///
  /// Sayılar `ProductUsage`'dan gelir; silinip silinemeyeceğine karar veren
  /// **servistir** (`ProductUsage.canDeletePermanently`), bu metin değil.
  static const String productDeleteBlockedTitle = 'Ürün silinemez';
  static String productDeleteBlockedMessage(
    String name,
    int saleItemCount,
    int stockMovementCount,
  ) {
    final reasons = <String>[
      if (saleItemCount > 0) '$saleItemCount satışta kullanılmış',
      if (stockMovementCount > 0)
        '$stockMovementCount stok hareketi kayıtlı (başlangıç stoğu dâhil)',
    ];
    return '"$name" ürünü ${reasons.join(' ve ')}. Geçmiş kayıtların '
        'bozulmaması için ürün silinmez, pasife alınır. Pasif ürünler satış '
        'ekranında görünmez, raporlarda görünmeye devam eder.';
  }

  /// REQ-PROD-012 — %50'den fazla fiyat değişikliğinde onay istenir.
  /// Uyarı metni servisten gelir (`ProductWarnings.largePriceChange`).
  static const String productPriceChangeTitle = 'Fiyat değişikliği';
  static const String productPriceChangeConfirmAction = 'Devam Et';

  // ── Faz 3c — ana ekran gezinme ───────────────────────────────────────────
  static const String homeProductsAction = 'Ürünler';

  /// Ürün işlemleri stok hareketi yazabildiği için (`user_id` NOT NULL)
  /// oturumsuz yürütülemez. Normal akışta görülmez: bu ekranlara yalnızca
  /// oturum açıkken ulaşılır (REQ-AUTH-001).
  static const String sessionRequiredMessage =
      'Oturum bulunamadı. Bu işlem için tekrar giriş yapın.';

  // ── Genel hata (REQ-UX-007, REQ-SEC-007) ─────────────────────────────────
  static const String unexpectedErrorTitle = 'Beklenmeyen bir hata oluştu';
  static const String unexpectedErrorMessage =
      'İşlem tamamlanamadı. Sorun devam ederse uygulamayı yeniden başlatın.';
  static const String startupFailedTitle = 'Uygulama başlatılamadı';
}
