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
import '../auth/financial_access_dialog.dart';

class HomeScreen extends ConsumerWidget {
  /// Test için sabit anahtarlar.
  static const Key usersButtonKey = Key('home_users_button');
  static const Key financialAccessSettingsButtonKey = Key(
    'home_financial_access_button',
  );
  static const Key dashboardButtonKey = Key('home_dashboard_button');
  static const Key salesButtonKey = Key('home_sales_button');
  static const Key stockButtonKey = Key('home_stock_button');
  static const Key saleHistoryButtonKey = Key('home_sale_history_button');
  static const Key consistencyButtonKey = Key('home_consistency_button');
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStringsTr.appTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.storefront_outlined,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  AppStringsTr.foundationReady,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  AppStringsTr.foundationDescription,
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      key: HomeScreen.usersButtonKey,
                      onPressed: () =>
                          Navigator.of(context).pushNamed(AppRoutes.users),
                      icon: const Icon(Icons.group_outlined),
                      label: const Text(AppStringsTr.homeUsersAction),
                    ),
                    OutlinedButton.icon(
                      key: HomeScreen.financialAccessSettingsButtonKey,
                      onPressed: () => Navigator.of(
                        context,
                      ).pushNamed(AppRoutes.financialAccessSettings),
                      icon: const Icon(Icons.tune_outlined),
                      label: const Text(AppStringsTr.homeFinancialAccessAction),
                    ),
                    // Satış ekranı uygulamanın asıl işidir; ana ekranda
                    // birincil eylem olarak durur (docs/22 · docs/12).
                    FilledButton.icon(
                      key: HomeScreen.salesButtonKey,
                      onPressed: () =>
                          Navigator.of(context).pushNamed(AppRoutes.sales),
                      icon: const Icon(Icons.point_of_sale),
                      label: const Text(AppStringsTr.homeSaleAction),
                    ),
                    OutlinedButton.icon(
                      key: HomeScreen.saleHistoryButtonKey,
                      onPressed: () => Navigator.of(
                        context,
                      ).pushNamed(AppRoutes.saleHistory),
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text(AppStringsTr.homeSaleHistoryAction),
                    ),
                    OutlinedButton.icon(
                      key: HomeScreen.stockButtonKey,
                      onPressed: () =>
                          Navigator.of(context).pushNamed(AppRoutes.stock),
                      icon: const Icon(Icons.inventory_outlined),
                      label: const Text(AppStringsTr.homeStockAction),
                    ),
                    OutlinedButton.icon(
                      key: HomeScreen.productsButtonKey,
                      onPressed: () =>
                          Navigator.of(context).pushNamed(AppRoutes.products),
                      icon: const Icon(Icons.inventory_2_outlined),
                      label: const Text(AppStringsTr.homeProductsAction),
                    ),
                    OutlinedButton.icon(
                      key: HomeScreen.categoriesButtonKey,
                      onPressed: () =>
                          Navigator.of(context).pushNamed(AppRoutes.categories),
                      icon: const Icon(Icons.folder_outlined),
                      label: const Text(AppStringsTr.homeCategoriesAction),
                    ),
                    OutlinedButton.icon(
                      key: HomeScreen.suppliersButtonKey,
                      onPressed: () =>
                          Navigator.of(context).pushNamed(AppRoutes.suppliers),
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: const Text(AppStringsTr.homeSuppliersAction),
                    ),
                    OutlinedButton.icon(
                      key: HomeScreen.vatRatesButtonKey,
                      onPressed: () =>
                          Navigator.of(context).pushNamed(AppRoutes.vatRates),
                      icon: const Icon(Icons.percent_outlined),
                      label: const Text(AppStringsTr.homeVatRatesAction),
                    ),
                    OutlinedButton.icon(
                      key: HomeScreen.backupButtonKey,
                      onPressed: () =>
                          Navigator.of(context).pushNamed(AppRoutes.backup),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text(AppStringsTr.homeBackupAction),
                    ),
                    OutlinedButton.icon(
                      key: HomeScreen.consistencyButtonKey,
                      onPressed: () => Navigator.of(
                        context,
                      ).pushNamed(AppRoutes.consistency),
                      icon: const Icon(Icons.fact_check_outlined),
                      label: const Text(AppStringsTr.consistencyTitle),
                    ),
                    OutlinedButton.icon(
                      key: HomeScreen.barcodeDiagnosticsButtonKey,
                      onPressed: () => Navigator.of(
                        context,
                      ).pushNamed(AppRoutes.barcodeDiagnostics),
                      icon: const Icon(Icons.qr_code_scanner_outlined),
                      label: const Text(
                        AppStringsTr.homeBarcodeDiagnosticsAction,
                      ),
                    ),
                    OutlinedButton.icon(
                      key: HomeScreen.dashboardButtonKey,
                      onPressed: () => _openDashboard(context, ref),
                      icon: const Icon(Icons.lock_outline),
                      label: const Text(AppStringsTr.homeDashboardAction),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
