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

  // ── Faz 3d — ürün görseli (docs/21) ──────────────────────────────────────
  static const String productTabImage = 'Görsel';
  static const String productImageDescription =
      'Ürüne bir görsel ekleyebilirsiniz. Görsel kaydedilirken otomatik '
      'olarak küçültülür; orijinal dosya saklanmaz.';
  static const String productImageSelectAction = 'Görsel Seç';
  static const String productImageChangeAction = 'Görseli Değiştir';
  static const String productImageRemoveAction = 'Görseli Kaldır';
  static const String productImageNone = 'Bu ürünün görseli yok.';

  /// Kaydedilmeden önce `temp/` altında bekleyen görsel (docs/21 §2 adım 6).
  static const String productImagePendingNotice =
      'Görsel seçildi. Ürünü kaydettiğinizde uygulanacak.';
  static const String productImageRemovePendingNotice =
      'Görsel kaldırılacak. Ürünü kaydettiğinizde uygulanacak.';

  /// Geri alınamaz sonucu olduğu için onay istenir (rules/05 §5).
  static const String productImageRemoveTitle = 'Görseli kaldır';
  static const String productImageRemoveConfirm =
      'Bu ürünün görseli kaldırılacak. Kaydettiğinizde dosya çöp klasörüne '
      'taşınır ve ürün varsayılan ikonla gösterilir.';
  static const String productImageRemoveConfirmAction = 'Kaldır';

  // ── Faz 3d — favoriler (REQ-PROD-009 · docs/09 §5) ───────────────────────
  static const String productFavoriteAddAction = 'Favorilere ekle';
  static const String productFavoriteRemoveAction = 'Favorilerden çıkar';
  static const String productFavoriteAdded = 'Ürün favorilere eklendi.';
  static const String productFavoriteRemoved = 'Ürün favorilerden çıkarıldı.';

  // ── Faz 3c — ana ekran gezinme ───────────────────────────────────────────
  static const String homeProductsAction = 'Ürünler';

  /// Ürün işlemleri stok hareketi yazabildiği için (`user_id` NOT NULL)
  /// oturumsuz yürütülemez. Normal akışta görülmez: bu ekranlara yalnızca
  /// oturum açıkken ulaşılır (REQ-AUTH-001).
  static const String sessionRequiredMessage =
      'Oturum bulunamadı. Bu işlem için tekrar giriş yapın.';

  // ── Faz 4 — barkod tanılama (REQ-BARC-010 · docs/11) ─────────────────────
  static const String barcodeDiagnosticsTitle = 'Barkod Tanılama';
  static const String barcodeDiagnosticsDescription =
      'Okuyucuyu bu ekranda test edin. Barkod okuttuğunuzda ham girdi '
      'aşağıda görünür. Hiçbir şey görünmüyorsa okuyucu klavye modunda '
      'olmayabilir veya sonuna Enter göndermiyor olabilir.';

  static const String barcodeDiagnosticsLastScan = 'Son okunan';
  static const String barcodeDiagnosticsNoScanYet = 'Henüz okuma yok';
  static const String barcodeDiagnosticsLength = 'Uzunluk';
  static const String barcodeDiagnosticsChecksum = 'Checksum';
  static const String barcodeDiagnosticsChecksumValid = 'Geçerli';
  static const String barcodeDiagnosticsChecksumInvalid =
      'Geçersiz (kayda yine de izin verilir)';
  static const String barcodeDiagnosticsChecksumUnknown =
      'Bu uzunluk için checksum kuralı yok';

  static const String barcodeDiagnosticsBuffer = 'Bekleyen girdi';
  static const String barcodeDiagnosticsBufferEmpty = '(boş)';

  /// OD-021 — zehirli girdi, sonraki Enter'a kadar barkod üretmez.
  static const String barcodeDiagnosticsPoisoned = 'Girdi durumu';
  static const String barcodeDiagnosticsPoisonedYes =
      'Zaman aşımı — bu okuma yok sayılacak, tekrar okutun';
  static const String barcodeDiagnosticsPoisonedNo = 'Normal';

  static String barcodeDiagnosticsThresholds(
    int gapMs,
    int timeoutMs,
    int minLength,
    int maxLength,
  ) =>
      'Eşikler: karakterler arası en fazla $gapMs ms · tampon zaman aşımı '
      '$timeoutMs ms · uzunluk $minLength–$maxLength karakter · sonlandırıcı Enter';

  static const String barcodeDiagnosticsHistory = 'Okuma geçmişi';
  static const String barcodeDiagnosticsClear = 'Geçmişi temizle';
  static const String homeBarcodeDiagnosticsAction = 'Barkod Tanılama';

  // ── Satış ekranı (docs/12 · docs/23) ─────────────────────────────────────
  static const String saleTitle = 'Satış';
  static const String homeSaleAction = 'Satış Ekranı';
  static const String saleSearchHint = 'Barkod okutun veya ürün arayın';
  static const String saleSearchLabel = 'Barkod / Ürün ara';

  /// docs/23 §6 — her liste ekranının eyleme yönlendiren boş durumu vardır.
  static const String saleCartEmptyTitle = 'Sepet boş';
  static const String saleCartEmptyHint =
      'Barkod okutun, ürün arayın veya soldaki listeden seçin.';
  static const String saleProductsEmptyTitle = 'Henüz ürün yok';
  static const String saleProductsEmptyHint =
      'Satış yapabilmek için önce ürün eklemelisiniz.';
  static const String saleProductsEmptyAction = 'Ürün Ekle';
  static const String saleSearchEmpty = 'Aramanıza uyan ürün bulunamadı.';

  static const String saleFavorites = 'Favoriler';
  static const String saleAllCategories = 'Tümü';
  static const String saleCartTitle = 'Sepet';
  static const String saleSubtotal = 'Matrah';
  static const String saleVat = 'KDV';
  static const String saleGrandTotal = 'TOPLAM';
  static const String saleCompleteAction = 'TAMAMLA';
  static const String saleCashAction = 'Nakit';
  static const String saleClearAction = 'Sepeti Temizle';
  static const String saleRemoveLine = 'Satırı sil';
  static const String saleIncrease = 'Miktarı artır';
  static const String saleDecrease = 'Miktarı azalt';

  /// docs/12 §4 — satır rozetleri.
  static const String salePriceOverriddenBadge = 'fiyat değiştirildi';
  static const String salePriceStaleBadge = 'fiyat güncellendi';
  static const String saleInactiveBadge = 'pasif ürün';
  static const String saleOutOfStockBadge = 'stok yok';

  // ── Sepeti temizleme onayı (REQ-UX-009) ──────────────────────────────────
  static const String saleClearTitle = 'Sepeti temizle';
  static const String saleClearMessage =
      'Sepetteki tüm satırlar silinecek. Bu işlem geri alınamaz.';
  static const String saleClearConfirm = 'Temizle';

  // ── Fiyat değiştirme (docs/12 §4) ────────────────────────────────────────
  static String salePriceDialogTitle(String productName) =>
      'Fiyat Değiştir — $productName';
  static String salePriceListLabel(String price) =>
      'Liste fiyatı (KDV dahil): $price';
  static const String salePriceNewLabel = 'Yeni fiyat (KDV dahil)';
  static const String salePriceDialogNotice =
      'Bu değişiklik yalnızca bu satışa uygulanır. Ürünün fiyatı değişmez.';
  static const String salePriceApply = 'Uygula';
  static const String salePriceInvalid = 'Fiyat geçersiz. Örnek: 25,50';

  // ── Nakit hesaplama (docs/12 §5) ─────────────────────────────────────────
  static const String saleCashTitle = 'Nakit Hesaplama';
  static const String saleCashTotal = 'Toplam';
  static const String saleCashReceived = 'Alınan';
  static const String saleCashChange = 'PARA ÜSTÜ';
  static const String saleCashQuick = 'Hızlı';
  static const String saleCashExact = 'Tam tutar';
  static const String saleCashInvalid = 'Tutar geçersiz. Örnek: 200,00';

  /// BR-SALE-008 · EC-SALE-009 — alınan toplamdan azsa tamamlama kapalıdır.
  static const String saleCashInsufficient = 'Alınan tutar toplamdan az.';

  // ── Stok uyarısı (docs/13 §4 · BR-STOCK-006) ─────────────────────────────
  static const String saleStockWarningTitle = 'Stok Uyarısı';
  static String saleStockWarningBody(String productName, int stock) =>
      '$productName\nSistemdeki stok: $stock\n\n'
      'Bu ürünün stoğu tükenmiş görünüyor. Devam ederseniz stok eksiye '
      'düşecek.';
  static const String saleStockWarningContinue = 'Devam Et';

  // ── Bilinmeyen barkod → hızlı ürün (docs/11 §4.2 · REQ-BARC-006/007) ─────
  static const String saleQuickAddTitle = 'Yeni Ürün (Hızlı)';
  static const String saleQuickAddIntro =
      'Bu barkod hiçbir ürüne ait değil. Ürünü şimdi oluşturup sepete '
      'ekleyebilirsiniz.';
  static const String saleQuickAddBarcode = 'Barkod';
  static const String saleQuickAddName = 'Ürün adı';
  static const String saleQuickAddPrice = 'Satış fiyatı (KDV dahil)';
  static const String saleQuickAddSubmit = 'Kaydet ve Sepete Ekle';
  static const String saleQuickAddNameRequired = 'Ürün adı zorunludur.';

  // ── Pasif ürün okutuldu (docs/11 §4.3) ───────────────────────────────────
  static String saleInactiveProductTitle(String productName) =>
      'Bu ürün pasif durumda: $productName';
  static const String saleInactiveProductBody =
      'Pasif ürünler satış ekranında listelenmez. Aktifleştirirseniz ürün '
      'sepete eklenir ve listelerde yeniden görünür.';
  static const String saleInactiveProductActivate =
      'Aktifleştir ve Sepete Ekle';

  // ── Satış tamamlandı (docs/12 §6.3) ──────────────────────────────────────
  static String saleCompletedMessage(String saleNumber, String total) =>
      'Satış tamamlandı — Fiş No: $saleNumber · Toplam $total';
  static String saleCompletedWithChange(
    String saleNumber,
    String total,
    String change,
  ) =>
      'Satış tamamlandı — Fiş No: $saleNumber · Toplam $total · '
      'Para üstü $change';

  /// EC-CART-010 — bozuk satırlar düştü.
  static String saleCartRepaired(int count) =>
      'Sepetteki $count satır açılamadığı için kaldırıldı. Sepetin kalanı '
      'korundu.';

  // ── Kısayollar (REQ-UX-010 · docs/23 §2) ─────────────────────────────────
  static const String saleShortcutsTitle = 'Klavye Kısayolları';
  static const String saleShortcutsClose = 'Kapat';
  static const List<(String, String)> saleShortcuts = [
    ('yazma', 'Odak nerede olursa olsun barkod/arama girişine döner'),
    ('Enter', 'Aramadaki ilk ürünü sepete ekler'),
    ('↑ ↓', 'Sepet satırları arasında gezinir'),
    ('+ / -', 'Seçili satırın miktarını değiştirir'),
    ('Del', 'Seçili satırı siler'),
    ('Alt+1…9', 'Favori ürünü sepete ekler'),
    ('F2', 'Seçili satırın fiyatını değiştirir'),
    ('F3', 'Ürün yönetimini açar'),
    ('F4', 'Nakit hesaplama'),
    ('F12', 'Satışı tamamlar'),
    ('Ctrl+Del', 'Sepeti temizler (onaylı)'),
    ('F1', 'Bu listeyi açar'),
    ('Esc', 'Dialogu kapatır'),
  ];

  // ── Stok (docs/13) ───────────────────────────────────────────────────────
  static const String stockEntryTitle = 'Stok Girişi';
  static const String homeStockAction = 'Stok';
  static const String stockEntrySupplier = 'Tedarikçi';
  static const String stockEntryNoSupplier = 'Tedarikçi seçilmedi';
  static const String stockEntryDocument = 'Belge no (opsiyonel)';
  static const String stockEntrySearchHint = 'Barkod okut veya ürün ara...';
  static const String stockEntryColumnProduct = 'Ürün';
  static const String stockEntryColumnCurrent = 'Mevcut';
  static const String stockEntryColumnQuantity = 'Giriş';
  static const String stockEntryColumnCost = 'Alış Fiyatı';
  static const String stockEntryColumnTotal = 'Tutar';
  static const String stockEntryTotal = 'TOPLAM';
  static const String stockEntrySave = 'Girişi Kaydet';
  static const String stockEntryEmpty =
      'Henüz satır yok. Barkod okutun veya ürün arayın.';
  static const String stockEntrySaved = 'Stok girişi kaydedildi.';

  /// BR-STOCK-009 · REQ-STOCK-008 — kararı kullanıcı verir.
  static const String stockEntryCostChangedTitle = 'Alış fiyatı değişti';
  static String stockEntryCostChangedBody(
    String product,
    String old,
    String updated,
  ) =>
      '$product ürününün alış fiyatı $old idi, bu girişte $updated girdiniz.\n\n'
      'Ürünün alış fiyatı da güncellensin mi? Güncellemezseniz yalnızca bu '
      'giriş bu fiyatla kaydedilir.';
  static const String stockEntryCostUpdateYes = 'Evet, güncelle';
  static const String stockEntryCostUpdateNo = 'Hayır, sadece bu giriş';

  // ── Fire ve düzeltme (docs/13 §6) ────────────────────────────────────────
  static const String stockWasteTitle = 'Fire Kaydı';
  static const String stockWasteQuantity = 'Fire miktarı';
  static const String stockWasteReason = 'Sebep';
  static const String stockWasteSave = 'Fire Kaydet';
  static const String stockWasteSaved = 'Fire kaydedildi.';

  /// docs/13 §6 — öneri listesi.
  static const List<String> stockWasteReasons = [
    'Bozulma',
    'Kırılma',
    'Son kullanma',
    'Çalıntı',
    'Diğer',
  ];

  static const String stockAdjustTitle = 'Stok Düzeltme';
  static const String stockAdjustCurrent = 'Sistemdeki stok';
  static const String stockAdjustNew = 'Sayım sonucu';
  static const String stockAdjustReason = 'Sebep';
  static const String stockAdjustSave = 'Düzeltmeyi Kaydet';
  static const String stockAdjustSaved = 'Stok düzeltmesi kaydedildi.';
  static const String stockReasonRequired = 'Sebep zorunludur.';
  static const String stockQuantityInvalid = 'Miktar geçersiz. Örnek: 12';

  // ── Hareket geçmişi (docs/13 §8) ─────────────────────────────────────────
  static const String stockMovementsTitle = 'Stok Hareketleri';
  static const String stockMovementsEmpty =
      'Bu filtrelerle hareket bulunamadı.';
  static const String stockMovementsAllTypes = 'Tüm hareketler';
  static const String stockMovementsAllProducts = 'Tüm ürünler';
  static const String stockMovementReverse = 'Ters Kayıt Oluştur';
  static const String stockMovementReverseTitle = 'Ters kayıt oluştur';
  static const String stockMovementReverseBody =
      'Hareket kayıtları düzenlenemez ve silinemez. Bunun yerine ters yönde '
      'yeni bir düzeltme hareketi oluşturulur; orijinal kayıt olduğu gibi '
      'kalır.';
  static const String stockMovementReversed = 'Ters kayıt oluşturuldu.';
  static const String stockMovementResulting = 'Sonuç';

  /// docs/13 §2 — hareket tipi adları.
  static const Map<String, String> stockMovementTypeNames = {
    'initial': 'Başlangıç',
    'stockEntry': 'Stok Girişi',
    'sale': 'Satış',
    'saleCancellation': 'Satış İptali',
    'return': 'İade',
    'waste': 'Fire',
    'adjustment': 'Düzeltme',
    'importAdjustment': 'Import Düzeltmesi',
    'restoreBaseline': 'Yedek Geri Yükleme',
  };

  // ── Kritik / negatif stok (docs/13 §7) ───────────────────────────────────
  static const String stockCriticalTitle = 'Kritik Stok';
  static const String stockNegativeTitle = 'Negatif Stok';
  static const String stockCriticalEmpty = 'Kritik stokta ürün yok.';
  static const String stockNegativeEmpty = 'Negatif stoklu ürün yok.';
  static const String stockSearchHint = 'Fire veya düzeltme için ürün ara...';
  static const String stockSearchResults = 'Arama sonuçları';
  static const String stockCriticalBadge = 'kritik';
  static const String stockNegativeBadge = 'negatif';
  static String stockMinimumLabel(int minimum) => 'min. $minimum';

  // ── Bakım · tutarlılık (docs/24 §3.3) ────────────────────────────────────
  static const String maintenanceTitle = 'Bakım';
  static const String consistencyTitle = 'Veri Tutarlılığı Kontrolü';
  static const String consistencyRun = 'Kontrolü Çalıştır';
  static const String consistencyRunning = 'Kontrol ediliyor...';
  static const String consistencyClean =
      'Sapma bulunamadı. Veriler tutarlı görünüyor.';
  static String consistencySummary(int findings, int products, int sales) =>
      '$findings sapma bulundu · $products ürün, $sales satış tarandı';
  static const String consistencyRepair = 'Düzelt';
  static const String consistencyRepaired = 'Sapma kapatıldı.';
  static const String consistencyNotRepairable =
      'Bu sapma otomatik kapatılamaz; kaydı inceleyin.';
  static const String consistencyExpected = 'Olması gereken';
  static const String consistencyActual = 'Bulunan';

  /// docs/24 §3.3 — denetim adları.
  static const Map<String, String> consistencyCheckNames = {
    'stockQuantity': 'Stok miktarı defterle uyuşmuyor',
    'saleTotals': 'Satış toplamı satırlarla uyuşmuyor',
    'saleCounts': 'Satış satır/adet sayacı uyuşmuyor',
    'returnedQuantity': 'İade edilen miktar uyuşmuyor',
    'missingImage': 'Ürün görseli dosyası bulunamadı',
    'foreignKeys': 'Kırık referans',
    'databaseIntegrity': 'Veritabanı bütünlüğü',
  };

  /// REQ-DATA-007 — düzeltme kullanıcı onayı ister.
  static const String consistencyRepairTitle = 'Stok sapmasını kapat';
  static String consistencyRepairBody(
    String label,
    String ledger,
    String cached,
  ) =>
      '$label\n\nDefterdeki toplam: $ledger\nKayıtlı stok: $cached\n\n'
      'Raftaki gerçek miktarı girin. Defterdekiyle aynıysa yalnızca kayıtlı '
      'stok tazelenir; farklıysa bir düzeltme hareketi oluşturulur.';
  static const String consistencyRepairQuantity = 'Gerçek miktar';

  // ── Tedarikçi detayı (REQ-SUP-003) ───────────────────────────────────────
  static const String supplierDetailTitle = 'Tedarikçi Detayı';
  static const String supplierDetailProducts = 'Ürünleri';
  static const String supplierDetailEntries = 'Stok girişleri';
  static const String supplierDetailNoProducts =
      'Bu tedarikçiye bağlı ürün yok.';
  static const String supplierDetailNoEntries =
      'Bu tedarikçiden yapılmış stok girişi yok.';

  // ── Yedekleme (docs/19) ──────────────────────────────────────────────────
  static const String backupTitle = 'Yedekleme';
  static const String homeBackupAction = 'Yedekleme';
  static const String backupCreateAction = 'Yedek Oluştur';
  static const String backupCreating = 'Yedek alınıyor...';
  static const String backupRestoreAction = 'Yedekten Geri Yükle';
  static const String backupListTitle = 'Mevcut yedekler';
  static const String backupListEmpty =
      'Henüz yedek alınmamış. İlk yedeğinizi şimdi alın.';
  static String backupCreated(String fileName, String size) =>
      'Yedek oluşturuldu: $fileName ($size)';
  static const String backupNeverTaken = 'Hiç yedek alınmadı';
  static String backupLastTaken(String when) => 'Son yedek: $when';

  /// docs/19 §3 — otomatik yedek aynı diskte durur.
  static const String backupAutoNotice =
      'Otomatik yedekler aynı bilgisayarda saklanır. Disk arızasına karşı '
      'koruma sağlamazlar — düzenli olarak harici bir diske de yedek alın.';

  // ── Yedek hatırlatması (REQ-BKUP-016) ────────────────────────────────────
  static String backupReminder(int days) =>
      '$days gündür yedek alınmadı. Verilerinizi korumak için yedek alın.';
  static const String backupReminderNever =
      'Henüz hiç yedek alınmadı. Verileriniz korunmasız.';
  static const String backupReminderAction = 'Yedek Al';
  static const String backupReminderDismiss = 'Kapat';

  // ── Geri yükleme (docs/19 §4) ────────────────────────────────────────────
  static const String restoreTitle = 'Yedek Geri Yükleme';
  static const String restoreChooseFile = 'Yedek dosyası seç';
  static const String restoreValidating = 'Yedek doğrulanıyor...';
  static String restoreBackupDate(String when) => 'Yedek tarihi: $when';
  static String restoreBackupAuthor(String who, String version) =>
      'Alan: $who · Sürüm $version';
  static const String restoreColumnBackup = 'YEDEKTEKİ';
  static const String restoreColumnCurrent = 'ŞU ANKİ';
  static const String restoreRowProducts = 'Ürün';
  static const String restoreRowSales = 'Satış';
  static const String restoreRowStockMovements = 'Stok hareketi';
  static const String restoreRowImages = 'Görsel';

  /// docs/19 §4 — "şu anki veri daha fazla kayıt içeriyor" AÇIKÇA vurgulanır.
  static String restoreSalesAtRisk(int count) => '⚠ $count satış kaybolacak';

  static const String restoreWarning =
      '⚠ Mevcut verileriniz bu yedekle DEĞİŞTİRİLECEK.\n'
      'İşlem öncesi otomatik güvenlik yedeği alınacak.';

  /// REQ-BKUP-020 — parolalar da değişir.
  static const String restorePasswordWarning =
      'Kullanıcı parolaları ve dashboard parolası yedekteki değerlerle '
      'değişecek. Oturumunuz sonlandırılacak ve giriş ekranına döneceksiniz.';

  /// REQ-BKUP-014 — daha eski şema.
  static const String restoreMigrationNotice =
      'Bu yedek daha eski bir veritabanı sürümüne ait. Geri yükleme sonrası '
      'otomatik olarak güncellenecek.';

  /// REQ-BKUP-018 — eksik görsel engellemez.
  static String restoreMissingImages(int count) =>
      '$count görsel yedekte bulunamadı. Geri yükleme yapılabilir; bu ürünler '
      'varsayılan ikonla gösterilir.';

  static String restoreConfirmPrompt(String phrase) =>
      'Onaylamak için "$phrase" yazın:';
  static const String restoreConfirmAction = 'Geri Yükle';
  static const String restoreRunning = 'Geri yükleniyor...';
  static const String restoreSucceeded =
      'Geri yükleme tamamlandı. Uygulamayı yeniden başlatın.';

  // ── Kesinti kurtarma (REQ-BKUP-012) ──────────────────────────────────────
  static const String restoreInterruptedTitle = 'Geri yükleme yarım kaldı';
  static const String restoreRecoveredCompleted =
      'Geri yükleme tamamlanmış görünüyor; verileriniz doğrulandı.';
  static const String restoreRecoveredRolledBack =
      'Geri yükleme tamamlanamadı. Önceki verileriniz geri yüklendi.';
  static const String restoreRecoveredFailed =
      'Geri yükleme kurtarılamadı. Güvenlik yedeği veri klasörünüzdeki '
      'backups/auto altındadır.';

  // ── Satış geçmişi (docs/12 §7 · REQ-SALE-010) ────────────────────────────
  static const String saleHistoryTitle = 'Satış Geçmişi';
  static const String homeSaleHistoryAction = 'Satış Geçmişi';
  static const String saleHistorySearchHint = 'Fiş numarası ara...';
  static const String saleHistoryEmpty = 'Bu filtrelerle satış bulunamadı.';
  static const String saleHistoryAllStatuses = 'Tüm durumlar';
  static const String saleHistoryDetailTitle = 'Satış Detayı';
  static const String saleHistoryItems = 'Satırlar';
  static const String saleHistoryReturns = 'İadeler';
  static const String saleHistoryNoReturns = 'Bu satışta iade yok.';
  static const String saleHistoryCost = 'Maliyet';
  static const String saleHistoryProfit = 'Kâr';
  static const String saleHistoryCash = 'Alınan';
  static const String saleHistoryChange = 'Para üstü';
  static const String saleHistoryReturnedBadge = 'iade edildi';

  /// docs/14 §2 — satış durumu adları.
  static const Map<String, String> saleStatusNames = {
    'completed': 'Tamamlandı',
    'cancelled': 'İptal edildi',
    'partiallyReturned': 'Kısmen iade edildi',
    'returned': 'İade edildi',
  };

  // ── Satış iptali (docs/14 §3) ────────────────────────────────────────────
  static const String saleCancelAction = 'Satışı İptal Et';
  static String saleCancelTitle(String saleNumber) =>
      'Satışı İptal Et — $saleNumber';
  static String saleCancelSummary(String total, int itemCount) =>
      'Tutar: $total · $itemCount ürün';
  static const String saleCancelWarning =
      'Bu işlem geri alınamaz. Tüm ürünlerin stoğu geri eklenecek. Satış '
      'kaydı silinmez, iptal olarak işaretlenir ve raporlarda görünmeye '
      'devam eder.';
  static const String saleCancelReason = 'İptal sebebi';
  static const String saleCancelConfirm = 'İptal Et';
  static const String saleCancelled = 'Satış iptal edildi.';

  /// BR-RET-001 — iade yapılmış satış iptal edilemez.
  static const String saleCancelUnavailable = 'Bu satış iptal edilemez.';

  // ── İade (docs/14 §4) ────────────────────────────────────────────────────
  static const String saleReturnAction = 'İade Oluştur';
  static String saleReturnTitle(String saleNumber) =>
      'İADE — Satış $saleNumber';
  static const String saleReturnColumnSold = 'Satılan';
  static const String saleReturnColumnReturned = 'Önceki iade';
  static const String saleReturnColumnQuantity = 'İade edilecek';
  static const String saleReturnTotal = 'İade tutarı';
  static const String saleReturnPriceNote =
      '(satış anındaki fiyatlar üzerinden)';
  static const String saleReturnReason = 'Sebep';
  static const String saleReturnSave = 'İadeyi Kaydet';
  static const String saleReturnSaved = 'İade kaydedildi.';
  static String saleReturnMax(int max) => 'maks $max';

  // ── Dashboard (docs/15) ──────────────────────────────────────────────────
  static const String dashboardTitle = 'Dashboard';
  static const String dashboardNetRevenue = 'Net Ciro';
  static const String dashboardNetProfit = 'Net Kâr';
  static const String dashboardSaleCount = 'Satış Adedi';
  static const String dashboardUnitCount = 'Satılan Ürün';
  static const String dashboardCriticalStock = 'Kritik Stok';
  static const String dashboardNegativeStock = 'Negatif Stok';
  static const String dashboardAverageSale = 'Ortalama fiş';
  static const String dashboardMargin = 'Kâr marjı';

  /// docs/15 §3.1 — kritik/negatif kartlar tarih aralığından bağımsızdır.
  static const String dashboardNowSuffix = 'şu an';

  static const String dashboardRevenueTrend = 'Ciro Trendi';
  static const String dashboardHourlyDensity = 'Saatlik Yoğunluk';
  static const String dashboardTopProducts = 'En Çok Satan Ürünler';
  static const String dashboardCategories = 'Kategori Dağılımı';
  static const String dashboardRecentSales = 'Son Satışlar';
  static const String dashboardNoData = 'Bu dönemde veri yok.';
  static const String dashboardOtherCategories = 'Diğer';

  /// docs/15 §5 — brüt/iptal/iade ayrıntısı ayrı bölümde.
  static const String dashboardBreakdownTitle = 'İptal ve İadeler';
  static const String dashboardGrossRevenue = 'Brüt ciro';
  static const String dashboardCancelled = 'İptal';
  static const String dashboardReturned = 'İade';
  static const String dashboardWasteCost = 'Fire maliyeti';

  /// docs/15 §2 — dönem seçici.
  static const Map<String, String> dashboardPeriodNames = {
    'today': 'Bugün',
    'yesterday': 'Dün',
    'thisWeek': 'Bu Hafta',
    'thisMonth': 'Bu Ay',
    'last7Days': 'Son 7 Gün',
    'last30Days': 'Son 30 Gün',
    'custom': 'Özel',
  };

  /// docs/15 §2 — karşılaştırma; önceki dönem boşsa gösterilmez.
  static String dashboardChange(int bp) {
    final sign = bp >= 0 ? '▲' : '▼';
    final value = (bp.abs() / 100).toStringAsFixed(1).replaceAll('.', ',');
    return '$sign%$value önceki döneme göre';
  }

  static const String dashboardNoComparison = 'önceki dönemde veri yok';

  // ── Genel hata (REQ-UX-007, REQ-SEC-007) ─────────────────────────────────
  static const String unexpectedErrorTitle = 'Beklenmeyen bir hata oluştu';
  static const String unexpectedErrorMessage =
      'İşlem tamamlanamadı. Sorun devam ederse uygulamayı yeniden başlatın.';
  static const String startupFailedTitle = 'Uygulama başlatılamadı';
}
