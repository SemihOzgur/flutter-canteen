/// Ana ekran — **OD-030 · BR-AUTH-013/014/018 · REQ-AUTH-029/031/032 ·
/// REQ-UX-015/016**
///
/// ## Ekranın iki hâli vardır
///
/// ```text
/// KİLİT KAPALI (harici kullanıcı)     KİLİT AÇIK (yönetici parolası girilmiş)
/// ────────────────────────────────    ──────────────────────────────────────
/// 🛒 Satış                            🛒 Satış
/// 🔁 Satış Geçmişi                    🔁 Satış Geçmişi · 📦 Stok
/// 📦 Stok                             📦 Ürünler · Kategoriler · Tedarikçiler
/// 🔒 Yönetici Erişimi                    KDV · Kullanıcılar
///                                     💾 Yedekleme · İçe/Dışa · Tutarlılık
///                                        Barkod Tanılama
///                                     📊 Dashboard · Raporlar · Erişim Ayarları
///                                     🔓 Erişimi Kapat
/// ```
///
/// Kilitli ekranlar **hiç listelenmez** (BR-AUTH-018). Pasif/gri kutu olarak da
/// durmaz ve "yetkiniz yok" **denmez**: bu projede yetki kavramı yoktur
/// (`rules/04 §2`), yalnızca parolayı bilip bilmemek vardır.
///
/// ## Kutu gizlemek TEK BAŞINA bir koruma değildir
///
/// Asıl kapı rota tanımının içindedir (`AppRoutes.routes` → `AdminGate`):
/// kilitli bir rota kısayolla veya doğrudan `pushNamed` ile açılmaya
/// çalışılırsa ekran **kurulmaz** (REQ-AUTH-030). Buradaki gizleme bir
/// görünürlük kararıdır, güvencenin kendisi değildir.
///
/// ## Kilit durumu neden `setState` ile tazeleniyor
///
/// Kilit `FinancialAccessService` içinde **bellekte** yaşar (BR-AUTH-016) ve
/// dinlenebilir bir durum değildir. Kilit bu ekranın dışında da açılabilir
/// (satış ekranında `F3` → `AdminGate`), bu yüzden her `pushNamed` dönüşünde
/// durum yeniden okunur — `stock_overview_screen`'deki `.then((_) => _load())`
/// deseninin aynısı. Kilidi ikinci bir yerde (provider) tutmak iki doğruluk
/// kaynağı yaratırdı.
///
/// ## Bu ekranda sorgu yoktur
///
/// `rules/05 §8`: burada veri kaynağı, hesaplama veya iş kuralı bulunmaz.
/// Tek istisna çıkış akışının **okuma** çağrısıdır (`CartService.activeSummary`,
/// docs/17 §10) — kullanıcıya sepetinin korunacağını söyleyebilmek için.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../app/router.dart';
import '../../app/theme/app_palette.dart';
import '../../application/auth/providers.dart';
import '../../application/sales/providers.dart';
import '../../core/version/app_version.dart';
import '../auth/financial_access_dialog.dart';

/// docs/17 §10 — çıkış onayında kullanıcının üç seçeneği vardır.
enum _LogoutChoice { cancel, keepCart, clearCart }

class HomeScreen extends ConsumerStatefulWidget {
  /// Test için sabit anahtarlar.
  static const Key usersButtonKey = Key('home_users_button');
  static const Key financialAccessSettingsButtonKey = Key(
    'home_financial_access_button',
  );
  static const Key dashboardButtonKey = Key('home_dashboard_button');
  static const Key reportsButtonKey = Key('home_reports_button');
  static const Key salesButtonKey = Key('home_sales_button');
  static const Key stockButtonKey = Key('home_stock_button');
  static const Key saleHistoryButtonKey = Key('home_sale_history_button');
  static const Key consistencyButtonKey = Key('home_consistency_button');
  static const Key importExportButtonKey = Key('home_import_export_button');
  static const Key backupButtonKey = Key('home_backup_button');
  static const Key productsButtonKey = Key('home_products_button');
  static const Key barcodeDiagnosticsButtonKey = Key(
    'home_barcode_diagnostics_button',
  );
  static const Key categoriesButtonKey = Key('home_categories_button');
  static const Key suppliersButtonKey = Key('home_suppliers_button');
  static const Key vatRatesButtonKey = Key('home_vat_rates_button');

  /// OD-030 — kilidi açan / kapatan ve oturumu kapatan eylemler.
  static const Key adminUnlockButtonKey = Key('home_admin_unlock_button');
  static const Key adminLockButtonKey = Key('home_admin_lock_button');
  static const Key logoutButtonKey = Key('home_logout_button');
  static const Key logoutConfirmButtonKey = Key('home_logout_confirm');
  static const Key logoutClearCartButtonKey = Key('home_logout_clear_cart');

  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// BR-AUTH-016 — tek doğruluk kaynağı servisin bellekteki bayrağıdır.
  bool get _unlocked => ref.read(financialAccessProvider).isUnlocked;

  /// Kilit dışı bir ekrana gider ve dönüşte kilit durumunu yeniden okur.
  Future<void> _open(String route) async {
    await Navigator.of(context).pushNamed(route);
    if (!mounted) return;
    // Kilit başka bir ekranda açılmış olabilir (örn. satışta `F3`).
    setState(() {});
  }

  /// Kilit arkasındaki bir ekrana gider — docs/22 F9.
  ///
  /// Parola **ekran açılmadan önce** sorulur: kullanıcı vazgeçerse rota hiç
  /// push edilmez (EC-DASH-003 — "ekran hiç açılmaz"). Rotanın kendi kapısı
  /// (`AdminGate`) yine yerindedir; bu, akışı kesmeden aynı sonucu verir.
  Future<void> _openAdmin(String route) async {
    assert(
      AppRoutes.adminOnly.contains(route),
      'Kilit dışı rota için _openAdmin kullanılmaz: $route',
    );
    if (!await ensureFinancialAccess(context, ref)) {
      if (mounted) setState(() {});
      return;
    }
    if (!mounted) return;
    await _open(route);
  }

  /// REQ-AUTH-029 — kilidi açar; ana ekran yönetim kutularını gösterir.
  Future<void> _unlockAdmin() async {
    final unlocked = await ensureFinancialAccess(context, ref);
    if (!mounted) return;
    setState(() {});
    if (unlocked) _notify(AppStringsTr.adminAccessUnlocked);
  }

  /// REQ-AUTH-031 — kilidi **logout etmeden** kapatır.
  ///
  /// Oturum ve aktif sepet korunur; yalnızca bellekteki bayrak düşer
  /// (BR-AUTH-016). Yönetici makineyi kasadaki kişiye bu şekilde bırakır.
  void _lockAdmin() {
    ref.read(financialAccessProvider).lock();
    setState(() {});
    _notify(AppStringsTr.adminAccessLocked);
  }

  /// docs/17 §10 · REQ-AUTH-032 — çıkış.
  ///
  /// **BR-AUTH-005: aktif sepet SİLİNMEZ.** Sepette ürün varsa kullanıcıya bu
  /// açıkça söylenir; "Sepeti Temizle ve Çık" onun **açık** tercihidir. Sepet
  /// boşsa onay sorulmaz (docs/17 §10 — "Hayır → doğrudan"): geri alınabilir
  /// bir işlem için gereksiz onay istenmez (`rules/05 §5`).
  Future<void> _logout() async {
    final cart = await ref.read(cartServiceProvider).activeSummary();
    if (!mounted) return;

    final lineCount = cart?.lineCount ?? 0;
    final choice = lineCount == 0
        ? _LogoutChoice.keepCart
        : await _askLogout(lineCount);
    if (!mounted || choice == null || choice == _LogoutChoice.cancel) return;

    if (choice == _LogoutChoice.clearCart && cart != null) {
      await ref
          .read(cartServiceProvider)
          .clear(cartId: cart.id, userId: cart.userId);
      if (!mounted) return;
    }

    // REQ-AUTH-004: oturum temizlenir **ve** yönetici erişim kilidi kapanır.
    await ref.read(authServiceProvider).logout();
    if (!mounted) return;

    await Navigator.of(
      context,
    ).pushNamedAndRemoveUntil(AppRoutes.login, (_) => false);
  }

  Future<_LogoutChoice?> _askLogout(int lineCount) => showDialog<_LogoutChoice>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text(AppStringsTr.logoutTitle),
      content: Text(AppStringsTr.logoutDescriptionWithCart(lineCount)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(_LogoutChoice.cancel),
          child: const Text(AppStringsTr.cancelAction),
        ),
        TextButton(
          key: HomeScreen.logoutClearCartButtonKey,
          onPressed: () => Navigator.of(context).pop(_LogoutChoice.clearCart),
          child: const Text(AppStringsTr.logoutClearCartAction),
        ),
        FilledButton(
          key: HomeScreen.logoutConfirmButtonKey,
          onPressed: () => Navigator.of(context).pop(_LogoutChoice.keepCart),
          child: const Text(AppStringsTr.logoutConfirmAction),
        ),
      ],
    ),
  );

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 3)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // REQ-AUTH-029 — ekranın iki hâlini belirleyen tek koşul.
    final unlocked = _unlocked;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStringsTr.appTitle),
        actions: [
          // REQ-UX-016 — çıkış her iki hâlde de erişilebilirdir.
          Tooltip(
            message: AppStringsTr.homeHintLogout,
            child: TextButton.icon(
              key: HomeScreen.logoutButtonKey,
              onPressed: () => unawaited(_logout()),
              icon: const Icon(Icons.logout),
              label: const Text(AppStringsTr.homeLogoutAction),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 16),
            child: Center(
              child: Text(
                appVersionLabel,
                key: const Key('home_app_version'),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
            children: [
              Text(
                AppStringsTr.homeWelcome,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                AppStringsTr.homeDescription,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),

              // Satış uygulamanın asıl işidir; kendi başına ve büyük durur
              // (docs/12 · docs/22). Diğer kutularla aynı boyutta olsaydı
              // kasadaki kişi her açılışta onu arardı.
              _PrimaryTile(
                tileKey: HomeScreen.salesButtonKey,
                icon: Icons.point_of_sale,
                label: AppStringsTr.homeSaleAction,
                hint: AppStringsTr.homeHintSale,
                onTap: () => unawaited(_open(AppRoutes.sales)),
              ),
              const SizedBox(height: 28),

              // BR-AUTH-014 — kilit dışı üçlü. Kilit kapalıyken ana ekranda
              // görünen tek grup budur.
              _Section(
                title: AppStringsTr.homeSectionDaily,
                tiles: [
                  _Tile(
                    tileKey: HomeScreen.saleHistoryButtonKey,
                    icon: Icons.receipt_long_outlined,
                    label: AppStringsTr.homeSaleHistoryAction,
                    hint: AppStringsTr.homeHintSaleHistory,
                    accent: AppPalette.tiles[0],
                    onTap: () => unawaited(_open(AppRoutes.saleHistory)),
                  ),
                  _Tile(
                    tileKey: HomeScreen.stockButtonKey,
                    icon: Icons.inventory_outlined,
                    label: AppStringsTr.homeStockAction,
                    hint: AppStringsTr.homeHintStock,
                    accent: AppPalette.tiles[1],
                    onTap: () => unawaited(_open(AppRoutes.stock)),
                  ),
                ],
              ),

              // BR-AUTH-018 — kilitliyken yönetim kutuları AĞAÇTA BULUNMAZ.
              // `Visibility`/`Opacity` ile gizlemek yetmezdi: kutu ağaçta
              // kalsaydı `Tab` ile odaklanılabilir ve testte "görünüyor"
              // sayılırdı.
              if (!unlocked)
                _Section(
                  title: AppStringsTr.homeAdminSectionTitle,
                  tiles: [
                    _Tile(
                      tileKey: HomeScreen.adminUnlockButtonKey,
                      // Kutunun kendi simgesi kilit rozetiyle aynı olamaz:
                      // rozet (`locked: true`) sağ üstte ayrıca durur.
                      icon: Icons.admin_panel_settings_outlined,
                      label: AppStringsTr.homeAdminUnlockAction,
                      hint: AppStringsTr.homeHintAdminUnlock,
                      accent: AppPalette.tiles[3],
                      locked: true,
                      onTap: () => unawaited(_unlockAdmin()),
                    ),
                  ],
                ),

              if (unlocked) ...[
                _Section(
                  title: AppStringsTr.homeSectionCatalog,
                  tiles: [
                    _Tile(
                      tileKey: HomeScreen.productsButtonKey,
                      icon: Icons.inventory_2_outlined,
                      label: AppStringsTr.homeProductsAction,
                      hint: AppStringsTr.homeHintProducts,
                      accent: AppPalette.tiles[2],
                      onTap: () => unawaited(_openAdmin(AppRoutes.products)),
                    ),
                    _Tile(
                      tileKey: HomeScreen.categoriesButtonKey,
                      icon: Icons.folder_outlined,
                      label: AppStringsTr.homeCategoriesAction,
                      hint: AppStringsTr.homeHintCategories,
                      accent: AppPalette.tiles[3],
                      onTap: () => unawaited(_openAdmin(AppRoutes.categories)),
                    ),
                    _Tile(
                      tileKey: HomeScreen.suppliersButtonKey,
                      icon: Icons.local_shipping_outlined,
                      label: AppStringsTr.homeSuppliersAction,
                      hint: AppStringsTr.homeHintSuppliers,
                      accent: AppPalette.tiles[4],
                      onTap: () => unawaited(_openAdmin(AppRoutes.suppliers)),
                    ),
                    _Tile(
                      tileKey: HomeScreen.vatRatesButtonKey,
                      icon: Icons.percent_outlined,
                      label: AppStringsTr.homeVatRatesAction,
                      hint: AppStringsTr.homeHintVatRates,
                      accent: AppPalette.tiles[6],
                      onTap: () => unawaited(_openAdmin(AppRoutes.vatRates)),
                    ),
                    _Tile(
                      tileKey: HomeScreen.usersButtonKey,
                      icon: Icons.group_outlined,
                      label: AppStringsTr.homeUsersAction,
                      hint: AppStringsTr.homeHintUsers,
                      accent: AppPalette.tiles[7],
                      onTap: () => unawaited(_openAdmin(AppRoutes.users)),
                    ),
                  ],
                ),

                _Section(
                  title: AppStringsTr.homeSectionData,
                  tiles: [
                    _Tile(
                      tileKey: HomeScreen.backupButtonKey,
                      icon: Icons.save_outlined,
                      label: AppStringsTr.homeBackupAction,
                      hint: AppStringsTr.homeHintBackup,
                      accent: AppPalette.tiles[1],
                      onTap: () => unawaited(_openAdmin(AppRoutes.backup)),
                    ),
                    _Tile(
                      tileKey: HomeScreen.importExportButtonKey,
                      icon: Icons.swap_vert,
                      label: AppStringsTr.homeImportExportAction,
                      hint: AppStringsTr.homeHintImportExport,
                      accent: AppPalette.tiles[4],
                      onTap: () =>
                          unawaited(_openAdmin(AppRoutes.importExport)),
                    ),
                    _Tile(
                      tileKey: HomeScreen.consistencyButtonKey,
                      icon: Icons.fact_check_outlined,
                      label: AppStringsTr.consistencyTitle,
                      hint: AppStringsTr.homeHintConsistency,
                      accent: AppPalette.tiles[2],
                      onTap: () => unawaited(_openAdmin(AppRoutes.consistency)),
                    ),
                    _Tile(
                      tileKey: HomeScreen.barcodeDiagnosticsButtonKey,
                      icon: Icons.qr_code_scanner_outlined,
                      label: AppStringsTr.homeBarcodeDiagnosticsAction,
                      hint: AppStringsTr.homeHintBarcodeDiagnostics,
                      accent: AppPalette.tiles[0],
                      onTap: () =>
                          unawaited(_openAdmin(AppRoutes.barcodeDiagnostics)),
                    ),
                  ],
                ),

                // BR-AUTH-012 — bu üçlü kilit AÇIKKEN bile ayrı durur: finansal
                // sorgular ayrıca servis kapısından geçer (Katman 1).
                _Section(
                  title: AppStringsTr.homeSectionFinancial,
                  tiles: [
                    _Tile(
                      tileKey: HomeScreen.dashboardButtonKey,
                      icon: Icons.dashboard_outlined,
                      label: AppStringsTr.homeDashboardAction,
                      hint: AppStringsTr.homeHintDashboard,
                      accent: AppPalette.tiles[3],
                      locked: true,
                      onTap: () => unawaited(_openAdmin(AppRoutes.dashboard)),
                    ),
                    _Tile(
                      tileKey: HomeScreen.reportsButtonKey,
                      icon: Icons.assessment_outlined,
                      label: AppStringsTr.reportsTitle,
                      hint: AppStringsTr.homeHintReports,
                      accent: AppPalette.tiles[5],
                      locked: true,
                      onTap: () => unawaited(_openAdmin(AppRoutes.reports)),
                    ),
                    _Tile(
                      tileKey: HomeScreen.financialAccessSettingsButtonKey,
                      icon: Icons.tune_outlined,
                      label: AppStringsTr.homeFinancialAccessAction,
                      hint: AppStringsTr.homeHintFinancialAccess,
                      accent: AppPalette.tiles[7],
                      onTap: () => unawaited(
                        _openAdmin(AppRoutes.financialAccessSettings),
                      ),
                    ),
                  ],
                ),

                // REQ-AUTH-031 — yönetici makineyi bırakırken kilidi geri
                // kapatır; oturumu kapatmak zorunda değildir.
                _Section(
                  title: AppStringsTr.homeAdminSectionTitle,
                  tiles: [
                    _Tile(
                      tileKey: HomeScreen.adminLockButtonKey,
                      icon: Icons.lock_open_outlined,
                      label: AppStringsTr.homeAdminLockAction,
                      hint: AppStringsTr.homeHintAdminLock,
                      accent: AppPalette.tiles[5],
                      onTap: _lockAdmin,
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Başlıklı kutu grubu.
class _Section extends StatelessWidget {
  final String title;
  final List<Widget> tiles;

  const _Section({required this.title, required this.tiles});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: tiles),
        ],
      ),
    );
  }
}

/// Satış kutusu — ana ekranın birincil eylemi.
class _PrimaryTile extends StatelessWidget {
  final Key tileKey;
  final IconData icon;
  final String label;
  final String hint;
  final VoidCallback onTap;

  const _PrimaryTile({
    required this.tileKey,
    required this.icon,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: hint,
      waitDuration: _tileTooltipDelay,
      child: DecoratedBox(
        // Düz renk yerine degrade: bu kutu ana ekranın birincil eylemi ve
        // yanındaki 14 doygun kutunun arasında kaybolmamalı.
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
          ),
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            key: tileKey,
            onTap: onTap,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
              child: Row(
                children: [
                  Icon(icon, size: 44, color: Colors.white),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          hint,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward,
                    size: 28,
                    color: Colors.white,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Üzerine gelince açıklama gösteren renkli eylem kutusu.
///
/// Etiket ne olduğunu söyler; **ne işe yaradığı** [hint] ile üzerine
/// gelindiğinde çıkar. İkisi birden kutuya sığsaydı ızgara okunmaz olurdu.
class _Tile extends StatelessWidget {
  final Key tileKey;
  final IconData icon;
  final String label;
  final String hint;
  final AccentColor accent;
  final bool locked;
  final VoidCallback onTap;

  const _Tile({
    required this.tileKey,
    required this.icon,
    required this.label,
    required this.hint,
    required this.accent,
    required this.onTap,
    this.locked = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Tooltip(
      message: hint,
      waitDuration: _tileTooltipDelay,
      child: SizedBox(
        width: 168,
        height: 124,
        child: Material(
          color: accent.background,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: tileKey,
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 30, color: accent.foreground),
                      const Spacer(),
                      // rules/05 §5 — kilit renkle değil, SİMGEYLE anlatılır.
                      if (locked)
                        Icon(
                          Icons.lock_outline,
                          size: 18,
                          color: accent.foreground.withValues(alpha: 0.85),
                        ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    label,
                    // Uzun etiketler ("Barkod Tanılama") iki satıra iner;
                    // üçüncü satır kutuyu taşırır.
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: accent.foreground,
                      fontWeight: FontWeight.w600,
                      height: 1.15,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fare kutunun üzerinde bu kadar durunca açıklama çıkar.
///
/// rules/05 §2 animasyon bütçesiyle uyumlu: ekranda gezinirken art arda
/// balon açılmaz, ama bilgi isteyen kullanıcı beklemez.
const Duration _tileTooltipDelay = Duration(milliseconds: 400);
