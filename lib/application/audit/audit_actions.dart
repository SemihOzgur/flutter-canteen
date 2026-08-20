/// Denetim kaydı action ve entity adları — **docs/18 §2–§3'ün TEK kod aynası.**
///
/// ## Neden tek dosya
///
/// `audit_logs.action` **kalıcı veridir**: bir ad değişirse geçmiş kayıtlar
/// yeni sorgularla eşleşmez, iki farklı ad kullanılırsa denetim izi ikiye
/// bölünür (bkz. OD-023 — `salePriceOverride` ↔ `salePriceOverridden`).
/// Adlar servislere dağılmışken bu sessizce olur.
///
/// `test/application/audit/audit_actions_test.dart` **docs/18 §3'ü ayrıştırır**
/// ve buradaki listeyle karşılaştırır: dokümanda olup burada olmayan bir action
/// testi kırar. Faz 6 bu boşluktan **18 tanesini** böyle buldu.
///
/// ## Henüz yazılmayanlar
///
/// Bazı action'lar burada tanımlıdır ama onları yazacak kod sonraki fazlara
/// aittir ([futurePhaseActions]). Sabitin burada durması bilinçlidir: doküman
/// ile kod arasındaki fark **görünür** kalır, "unutuldu mu, ertelendi mi"
/// sorusu belirsizleşmez.
library;

abstract final class AuditEntities {
  static const String product = 'product';
  static const String category = 'category';
  static const String supplier = 'supplier';
  static const String vatRate = 'vat_rate';
  static const String sale = 'sale';
  static const String stock = 'stock';
  static const String cart = 'cart';
  static const String user = 'user';

  /// Finansal erişim kilidi olayları — docs/18 §3 "Kullanıcı" tablosu.
  static const String dashboard = 'dashboard';

  static const String system = 'system';
}

abstract final class AuditActions {
  // --- Ürün — docs/18 §3 --------------------------------------------------
  static const String productCreated = 'productCreated';
  static const String productPriceChanged = 'productPriceChanged';
  static const String productCostChanged = 'productCostChanged';
  static const String productCategoryChanged = 'productCategoryChanged';
  static const String productSupplierChanged = 'productSupplierChanged';
  static const String productMinStockChanged = 'productMinStockChanged';
  static const String productDeactivated = 'productDeactivated';
  static const String productActivated = 'productActivated';
  static const String productDeleted = 'productDeleted';
  static const String productImageChanged = 'productImageChanged';
  static const String barcodeAdded = 'barcodeAdded';
  static const String barcodeRemoved = 'barcodeRemoved';

  // --- Satış ---------------------------------------------------------------
  static const String saleCompleted = 'saleCompleted';
  static const String salePriceOverridden = 'salePriceOverridden';
  static const String saleCancelled = 'saleCancelled';
  static const String saleReturned = 'saleReturned';

  // --- Stok ----------------------------------------------------------------
  static const String stockEntryCreated = 'stockEntryCreated';
  static const String stockWasteRecorded = 'stockWasteRecorded';
  static const String stockAdjusted = 'stockAdjusted';

  // --- Kategori / Tedarikçi / KDV -----------------------------------------
  static const String categoryCreated = 'categoryCreated';
  static const String categoryRenamed = 'categoryRenamed';
  static const String categoryDeactivated = 'categoryDeactivated';
  static const String categoryActivated = 'categoryActivated';
  static const String categoryDeleted = 'categoryDeleted';
  static const String categoryProductsMoved = 'categoryProductsMoved';
  static const String supplierCreated = 'supplierCreated';
  static const String supplierUpdated = 'supplierUpdated';
  static const String supplierDeactivated = 'supplierDeactivated';
  static const String supplierActivated = 'supplierActivated';
  static const String vatRateCreated = 'vatRateCreated';
  static const String vatRateChanged = 'vatRateChanged';
  static const String vatRateDeactivated = 'vatRateDeactivated';
  static const String vatRateActivated = 'vatRateActivated';

  // --- Sistem / Veri -------------------------------------------------------
  static const String backupCreated = 'backupCreated';
  static const String backupRestored = 'backupRestored';
  static const String dataImported = 'dataImported';
  static const String dataExported = 'dataExported';
  static const String migrationApplied = 'migrationApplied';
  static const String consistencyCheckRun = 'consistencyCheckRun';

  // --- Kullanıcı -----------------------------------------------------------
  static const String userLoggedIn = 'userLoggedIn';
  static const String userLoggedOut = 'userLoggedOut';
  static const String userCreated = 'userCreated';
  static const String userDeactivated = 'userDeactivated';
  static const String userRenamed = 'userRenamed';

  /// ⚠️ Parola, hash ve salt değerleri **asla** yazılmaz (BR-SEC-001).
  static const String passwordChanged = 'passwordChanged';

  static const String dashboardUnlocked = 'dashboardUnlocked';
  static const String dashboardUnlockFailed = 'dashboardUnlockFailed';
  static const String dashboardPasswordChanged = 'dashboardPasswordChanged';
  static const String dashboardRecoveryUsed = 'dashboardRecoveryUsed';
  static const String dashboardRecoveryFailed = 'dashboardRecoveryFailed';
  static const String dashboardRecoveryRegenerated =
      'dashboardRecoveryRegenerated';

  static const String cartTakenOver = 'cartTakenOver';

  /// docs/18 §3'te tanımlı **tüm** action'lar.
  static const Set<String> all = {
    productCreated,
    productPriceChanged,
    productCostChanged,
    productCategoryChanged,
    productSupplierChanged,
    productMinStockChanged,
    productDeactivated,
    productActivated,
    productDeleted,
    productImageChanged,
    barcodeAdded,
    barcodeRemoved,
    saleCompleted,
    salePriceOverridden,
    saleCancelled,
    saleReturned,
    stockEntryCreated,
    stockWasteRecorded,
    stockAdjusted,
    categoryCreated,
    categoryRenamed,
    categoryDeactivated,
    categoryActivated,
    categoryDeleted,
    categoryProductsMoved,
    supplierCreated,
    supplierUpdated,
    supplierDeactivated,
    supplierActivated,
    vatRateCreated,
    vatRateChanged,
    vatRateDeactivated,
    vatRateActivated,
    backupCreated,
    backupRestored,
    dataImported,
    dataExported,
    migrationApplied,
    consistencyCheckRun,
    userLoggedIn,
    userLoggedOut,
    userCreated,
    userDeactivated,
    userRenamed,
    passwordChanged,
    dashboardUnlocked,
    dashboardUnlockFailed,
    dashboardPasswordChanged,
    dashboardRecoveryUsed,
    dashboardRecoveryFailed,
    dashboardRecoveryRegenerated,
    cartTakenOver,
  };

  /// Tanımlı ama **henüz yazılmayan** action'lar ve ait oldukları faz.
  ///
  /// Bu harita bir *yapılacaklar listesi* değil, bir **sözleşmedir**: ilgili
  /// faz geldiğinde action buradan çıkarılır ve yazım noktası eklenir. Test
  /// bu haritayı kullanarak "dokümanda var, kodda yok" farkını beklenen
  /// boşluklarla sınırlar — beklenmeyen bir boşluk testi kırar.
  static const Map<String, String> futurePhaseActions = {
    dataImported: 'Faz 10 — import',
    dataExported: 'Faz 10 — export',
    // Şema v1'den başka sürüm yok; migration adımı hiç çalışmıyor. Yazım
    // noktası ilk v2 adımıyla birlikte eklenir — bugün eklenirse asla
    // tetiklenmeyen ölü kod olur (rules/06 §7).
    migrationApplied: 'İlk v2 migration adımı',
    // REQ-AUTH-010 (🟢 Could) — aktif sepet varken farklı kullanıcı girişi.
    cartTakenOver: 'REQ-AUTH-010 — kapsama alınırsa',
  };
}
