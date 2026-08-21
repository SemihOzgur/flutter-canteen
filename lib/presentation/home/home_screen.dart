/// Ana ekran (Faz 1 iskeleti + Faz 3a gezinme bağlantıları).
///
/// Satış ekranı Faz 5'te, Dashboard ve Raporlar Faz 8'de gelir. Bu ekran
/// bugün yalnızca Faz 3a'da yazılan ekranlara giriş noktası sağlar:
///
/// | Bağlantı | Kilit | Kaynak |
/// |---|---|---|
/// | Kullanıcı Yönetimi | 🔓 kilit dışında | BR-AUTH-014 · docs/17 §11 |
/// | Finansal Erişim (Ayarlar) | 🔓 kilit dışında | BR-AUTH-014 · EC-DASH-014 |
/// | Kategoriler | 🔓 kilit dışında | rules/04 §4 · docs/10 §1 |
/// | Tedarikçiler | 🔓 kilit dışında | rules/04 §4 · docs/10 §2 |
/// | KDV Oranları | 🔓 kilit dışında | rules/04 §4 · docs/08 §4 |
/// | Satış geçmişi | 🔓 kilit dışında | rules/04 §4 |
/// | Stok | 🔓 kilit dışında | rules/04 §4 |
/// | Yedekleme | 🔓 kilit dışında | rules/04 §4 |
/// | Dashboard | 🔒 **kilit arkasında** | BR-AUTH-013 · docs/22 F9 |
///
/// ## Dashboard kapısı
///
/// docs/22 F9: kilit **ekran açılmadan önce** sorulur. Kullanıcı vazgeçerse
/// Dashboard hiç kurulmaz ve tek sorgu çalışmaz.
///
/// **BR-AUTH-012:** kilit açılmadan hiçbir finansal sorgu çalıştırılmaz —
/// bu ekranda zaten hiçbir sorgu, hesaplama veya veri kaynağı yoktur
/// (rules/05 §8).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../app/router.dart';
import '../../app/theme/app_palette.dart';
import '../../core/version/app_version.dart';
import '../auth/financial_access_dialog.dart';

class HomeScreen extends ConsumerWidget {
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

  const HomeScreen({super.key});

  /// docs/22 F9 — Dashboard açılmadan önce kilit sorulur.
  ///
  /// EC-DASH-003: kullanıcı vazgeçerse hiçbir şey açılmaz ve kilit kapalı
  /// kalır.
  Future<void> _openDashboard(BuildContext context, WidgetRef ref) async {
    if (!await ensureFinancialAccess(context, ref)) return;
    if (!context.mounted) return;

    // Faz 8 — kapı açıldı, ekran geldi. Kilit yine de ekranın İÇİNDE de
    // duruyor: rota koruması bir gezinme ayrıntısıdır ve unutulabilir,
    // `DashboardService`'in kapısı unutulamaz (BR-AUTH-012).
    await Navigator.of(context).pushNamed(AppRoutes.dashboard);
  }

  /// docs/22 F9 — Raporlar **aynı** kilidin arkasındadır (BR-AUTH-013).
  ///
  /// Kilit oturum kapsamlı olduğu için Dashboard açılmışsa parola tekrar
  /// sorulmaz (BR-AUTH-016).
  Future<void> _openReports(BuildContext context, WidgetRef ref) async {
    if (!await ensureFinancialAccess(context, ref)) return;
    if (!context.mounted) return;
    await Navigator.of(context).pushNamed(AppRoutes.reports);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStringsTr.appTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
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
              // (docs/12 · docs/22). Diğer 14 eylemle aynı boyutta olsaydı
              // kasadaki kişi her açılışta onu arardı.
              _PrimaryTile(
                tileKey: HomeScreen.salesButtonKey,
                icon: Icons.point_of_sale,
                label: AppStringsTr.homeSaleAction,
                hint: AppStringsTr.homeHintSale,
                onTap: () => Navigator.of(context).pushNamed(AppRoutes.sales),
              ),
              const SizedBox(height: 28),

              _Section(
                title: AppStringsTr.homeSectionDaily,
                tiles: [
                  _Tile(
                    tileKey: HomeScreen.saleHistoryButtonKey,
                    icon: Icons.receipt_long_outlined,
                    label: AppStringsTr.homeSaleHistoryAction,
                    hint: AppStringsTr.homeHintSaleHistory,
                    accent: AppPalette.tiles[0],
                    onTap: () =>
                        Navigator.of(context).pushNamed(AppRoutes.saleHistory),
                  ),
                  _Tile(
                    tileKey: HomeScreen.stockButtonKey,
                    icon: Icons.inventory_outlined,
                    label: AppStringsTr.homeStockAction,
                    hint: AppStringsTr.homeHintStock,
                    accent: AppPalette.tiles[1],
                    onTap: () =>
                        Navigator.of(context).pushNamed(AppRoutes.stock),
                  ),
                ],
              ),

              _Section(
                title: AppStringsTr.homeSectionCatalog,
                tiles: [
                  _Tile(
                    tileKey: HomeScreen.productsButtonKey,
                    icon: Icons.inventory_2_outlined,
                    label: AppStringsTr.homeProductsAction,
                    hint: AppStringsTr.homeHintProducts,
                    accent: AppPalette.tiles[2],
                    onTap: () =>
                        Navigator.of(context).pushNamed(AppRoutes.products),
                  ),
                  _Tile(
                    tileKey: HomeScreen.categoriesButtonKey,
                    icon: Icons.folder_outlined,
                    label: AppStringsTr.homeCategoriesAction,
                    hint: AppStringsTr.homeHintCategories,
                    accent: AppPalette.tiles[3],
                    onTap: () =>
                        Navigator.of(context).pushNamed(AppRoutes.categories),
                  ),
                  _Tile(
                    tileKey: HomeScreen.suppliersButtonKey,
                    icon: Icons.local_shipping_outlined,
                    label: AppStringsTr.homeSuppliersAction,
                    hint: AppStringsTr.homeHintSuppliers,
                    accent: AppPalette.tiles[4],
                    onTap: () =>
                        Navigator.of(context).pushNamed(AppRoutes.suppliers),
                  ),
                  _Tile(
                    tileKey: HomeScreen.vatRatesButtonKey,
                    icon: Icons.percent_outlined,
                    label: AppStringsTr.homeVatRatesAction,
                    hint: AppStringsTr.homeHintVatRates,
                    accent: AppPalette.tiles[6],
                    onTap: () =>
                        Navigator.of(context).pushNamed(AppRoutes.vatRates),
                  ),
                  _Tile(
                    tileKey: HomeScreen.usersButtonKey,
                    icon: Icons.group_outlined,
                    label: AppStringsTr.homeUsersAction,
                    hint: AppStringsTr.homeHintUsers,
                    accent: AppPalette.tiles[7],
                    onTap: () =>
                        Navigator.of(context).pushNamed(AppRoutes.users),
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
                    onTap: () =>
                        Navigator.of(context).pushNamed(AppRoutes.backup),
                  ),
                  _Tile(
                    tileKey: HomeScreen.importExportButtonKey,
                    icon: Icons.swap_vert,
                    label: AppStringsTr.homeImportExportAction,
                    hint: AppStringsTr.homeHintImportExport,
                    accent: AppPalette.tiles[4],
                    onTap: () =>
                        Navigator.of(context).pushNamed(AppRoutes.importExport),
                  ),
                  _Tile(
                    tileKey: HomeScreen.consistencyButtonKey,
                    icon: Icons.fact_check_outlined,
                    label: AppStringsTr.consistencyTitle,
                    hint: AppStringsTr.homeHintConsistency,
                    accent: AppPalette.tiles[2],
                    onTap: () =>
                        Navigator.of(context).pushNamed(AppRoutes.consistency),
                  ),
                  _Tile(
                    tileKey: HomeScreen.barcodeDiagnosticsButtonKey,
                    icon: Icons.qr_code_scanner_outlined,
                    label: AppStringsTr.homeBarcodeDiagnosticsAction,
                    hint: AppStringsTr.homeHintBarcodeDiagnostics,
                    accent: AppPalette.tiles[0],
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed(AppRoutes.barcodeDiagnostics),
                  ),
                ],
              ),

              // BR-AUTH-013 — bu üçlü ayrı bir bölümdedir ve kilit simgesi
              // taşır. Kullanıcı parolanın neden sorulduğunu tıklamadan
              // ÖNCE anlamalıdır.
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
                    onTap: () => _openDashboard(context, ref),
                  ),
                  _Tile(
                    tileKey: HomeScreen.reportsButtonKey,
                    icon: Icons.assessment_outlined,
                    label: AppStringsTr.reportsTitle,
                    hint: AppStringsTr.homeHintReports,
                    accent: AppPalette.tiles[5],
                    locked: true,
                    onTap: () => _openReports(context, ref),
                  ),
                  _Tile(
                    tileKey: HomeScreen.financialAccessSettingsButtonKey,
                    icon: Icons.tune_outlined,
                    label: AppStringsTr.homeFinancialAccessAction,
                    hint: AppStringsTr.homeHintFinancialAccess,
                    accent: AppPalette.tiles[7],
                    onTap: () => Navigator.of(
                      context,
                    ).pushNamed(AppRoutes.financialAccessSettings),
                  ),
                ],
              ),
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
