/// Temel navigasyon.
///
/// rules/01 §3 (over-engineering yasağı) ve Faz 1 kapsamı gereği `go_router`
/// **kullanılmaz** — Flutter'ın yerleşik `Navigator`'ı yeterlidir.
/// Ekran sayısı arttığında yeniden değerlendirilir.
///
/// Açılış rotası sabit değildir; bootstrap tarafından çözülür
/// (`startup.dart` · docs/03 §6 adım 7/9).
library;

import 'package:flutter/material.dart';

import '../presentation/auth/login_screen.dart';
import '../presentation/auth/setup_wizard_screen.dart';
import '../presentation/home/home_screen.dart';
import '../presentation/settings/category_management_screen.dart';
import '../presentation/settings/financial_access_settings_screen.dart';
import '../presentation/settings/supplier_management_screen.dart';
import '../presentation/settings/user_management_screen.dart';
import '../presentation/barcode/barcode_diagnostics_screen.dart';
import '../presentation/products/product_list_screen.dart';
import '../presentation/backup/backup_screen.dart';
import '../presentation/dashboard/dashboard_screen.dart';
import '../presentation/history/sale_history_screen.dart';
import '../presentation/maintenance/consistency_screen.dart';
import '../presentation/sales/sale_screen.dart';
import '../presentation/stock/stock_entry_screen.dart';
import '../presentation/stock/stock_movements_screen.dart';
import '../presentation/stock/stock_overview_screen.dart';
import '../presentation/settings/vat_rate_management_screen.dart';

class AppRoutes {
  const AppRoutes._();

  /// İlk kurulum sihirbazı — hiç kullanıcı yoksa veya kurulum yarım kaldıysa
  /// (EC-AUTH-008 · REQ-AUTH-016/022).
  static const String setup = '/setup';

  /// Kullanıcı girişi (docs/17 §3).
  static const String login = '/login';

  /// Ana ekran — geçerli oturum varsa (REQ-AUTH-001).
  static const String home = '/';

  /// Kullanıcı yönetimi (docs/17 §11 · REQ-AUTH-008).
  static const String users = '/users';

  /// Ayarlar → Finansal Erişim (docs/17 §8, §9).
  ///
  /// ⚠️ Bu ekran finansal erişim kilidinin **arkasında değildir**
  /// (BR-AUTH-014 · EC-DASH-014); içindeki işlemler mevcut dashboard
  /// parolasını ister (BR-AUTH-010).
  static const String financialAccessSettings = '/financial-access';

  /// Kategori yönetimi (docs/10 §1 · REQ-CAT-001).
  ///
  /// ⚠️ Bu üç referans veri ekranı da finansal erişim kilidinin **dışındadır**
  /// (BR-AUTH-013 · rules/04 §4 — kilit yalnızca Dashboard ve Raporlar için).
  static const String categories = '/categories';

  /// Tedarikçi yönetimi (docs/10 §2 · REQ-SUP-001).
  static const String suppliers = '/suppliers';

  /// KDV oranı yönetimi (docs/08 §4 · REQ-VAT-001).
  static const String vatRates = '/vat-rates';

  /// Ürün yönetimi (docs/09 · REQ-PROD-001). Kilit dışındadır.
  static const String products = '/products';

  /// Barkod tanılama (REQ-BARC-010). Finansal veri içermez, kilit dışındadır.
  static const String barcodeDiagnostics = '/barcode-diagnostics';

  /// Dashboard (docs/15). **Finansal erişim kilidinin ARKASINDADIR**
  /// (BR-AUTH-013). Rota koruması `HomeScreen._openDashboard` içindedir;
  /// asıl güvence `DashboardService`'in kapısıdır (BR-AUTH-012).
  static const String dashboard = '/dashboard';

  /// Satış geçmişi (docs/12 §7 · docs/14). **Kilit dışındadır** —
  /// iade ve iptal günlük kasa işidir, finansal rapor değildir (rules/04 §4).
  static const String saleHistory = '/sales/history';

  /// Stok yönetimi (docs/13). Kilit dışındadır (rules/04 §4).
  static const String stock = '/stock';

  /// Mal kabul (docs/13 §5).
  static const String stockEntry = '/stock/entry';

  /// Hareket geçmişi (docs/13 §8 · REQ-STOCK-010).
  static const String stockMovements = '/stock/movements';

  /// Ayarlar → Yedekleme (docs/19). Kilit dışındadır (rules/04 §4).
  ///
  /// ⚠️ Bu rotanın yolu `BackupReminderBanner` içinde de geçer; ikisi birlikte
  /// değiştirilmelidir.
  static const String backup = '/backup';

  /// Ayarlar → Bakım → Veri Tutarlılığı Kontrolü (docs/24 §3.3).
  static const String consistency = '/maintenance/consistency';

  /// Satış ekranı (docs/12 · REQ-UX-001). **Kilit dışındadır** — satış
  /// finansal bir ekran değil, uygulamanın asıl işidir (rules/04 §4).
  static const String sales = '/sales';

  static Map<String, WidgetBuilder> routes() => {
    setup: (_) => const SetupWizardScreen(),
    login: (_) => const LoginScreen(),
    home: (_) => const HomeScreen(),
    users: (_) => const UserManagementScreen(),
    financialAccessSettings: (_) => const FinancialAccessSettingsScreen(),
    categories: (_) => const CategoryManagementScreen(),
    suppliers: (_) => const SupplierManagementScreen(),
    vatRates: (_) => const VatRateManagementScreen(),
    products: (_) => const ProductListScreen(),
    barcodeDiagnostics: (_) => const BarcodeDiagnosticsScreen(),
    sales: (_) => const SaleScreen(),
    saleHistory: (_) => const SaleHistoryScreen(),
    dashboard: (_) => const DashboardScreen(),
    stock: (_) => const StockOverviewScreen(),
    stockEntry: (_) => const StockEntryScreen(),
    stockMovements: (_) => const StockMovementsScreen(),
    consistency: (_) => const ConsistencyScreen(),
    backup: (_) => const BackupScreen(),
  };
}
