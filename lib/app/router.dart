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

import '../presentation/auth/admin_gate.dart';
import '../presentation/auth/login_screen.dart';
import '../presentation/auth/setup_wizard_screen.dart';
import '../presentation/home/home_screen.dart';
import '../presentation/settings/category_management_screen.dart';
import '../presentation/settings/financial_access_settings_screen.dart';
import '../presentation/settings/supplier_management_screen.dart';
import '../presentation/settings/user_management_screen.dart';
import '../presentation/barcode/barcode_diagnostics_screen.dart';
import '../presentation/products/product_list_screen.dart';
import '../presentation/reports/reports_screen.dart';
import '../presentation/backup/backup_screen.dart';
import '../presentation/dashboard/dashboard_screen.dart';
import '../presentation/history/sale_history_screen.dart';
import '../presentation/import/import_export_screen.dart';
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

  /// Ayarlar → Yönetici Erişimi (docs/17 §8, §9).
  ///
  /// **OD-030 ile kilidin ARKASINA alındı.** Kullanıcıyı kilitlemez: parolayı
  /// unutan kişi kurtarma akışına kilit **dialogundaki** "Şifremi unuttum"
  /// bağlantısından ulaşır (docs/17 §8), bu ekrandan geçmesi gerekmez.
  /// İçindeki işlemler ayrıca mevcut parolayı ister (BR-AUTH-010).
  static const String financialAccessSettings = '/financial-access';

  /// Kategori yönetimi (docs/10 §1 · REQ-CAT-001).
  ///
  /// 🔒 Bu üç referans veri ekranı **OD-030 ile kilidin arkasına alındı**
  /// (BR-AUTH-013 · rules/04 §4).
  static const String categories = '/categories';

  /// Tedarikçi yönetimi (docs/10 §2 · REQ-SUP-001).
  static const String suppliers = '/suppliers';

  /// KDV oranı yönetimi (docs/08 §4 · REQ-VAT-001).
  static const String vatRates = '/vat-rates';

  /// Ürün yönetimi (docs/09 · REQ-PROD-001). 🔒 Kilit arkasındadır (OD-030).
  ///
  /// **BR-AUTH-019:** satış ekranındaki *bilinmeyen barkod → hızlı ürün ekleme*
  /// akışı bu rotadan geçmez ve kilitten etkilenmez (docs/11 §4.2).
  static const String products = '/products';

  /// Barkod tanılama (REQ-BARC-010). 🔒 Kilit arkasındadır (OD-030) — bir
  /// kurulum/tanılama aracıdır, günlük kasa işi değildir.
  static const String barcodeDiagnostics = '/barcode-diagnostics';

  /// Dashboard (docs/15). 🔒 **Yönetici erişim kilidinin ARKASINDADIR**
  /// (BR-AUTH-013). Rota koruması [adminOnly] + `AdminGate`'tir; asıl güvence
  /// ise `DashboardService`'in kapısıdır (BR-AUTH-012) — kilit açıldıktan
  /// sonra bile her finansal sorgu oradan geçer.
  static const String dashboard = '/dashboard';

  /// Raporlar (docs/16). Dashboard ile **aynı kilidin arkasındadır**
  /// (BR-AUTH-013); kilit oturum kapsamlı olduğu için parola tekrar sorulmaz.
  static const String reports = '/reports';

  /// Satış geçmişi (docs/12 §7 · docs/14). **Kilit dışındadır** — iade ve iptal
  /// günlük kasa işidir, finansal rapor değildir (BR-AUTH-014 · OD-030 alt
  /// karar 1).
  static const String saleHistory = '/sales/history';

  /// İçe / dışa aktarma (docs/20). 🔒 **OD-030 ile kilidin arkasına alındı:**
  /// toplu veri değiştiren bir yönetim işidir.
  static const String importExport = '/import-export';

  /// Stok yönetimi (docs/13). **Kilit dışındadır** (BR-AUTH-014) — mal kabul,
  /// fire ve sayım günlük kasa işidir.
  static const String stock = '/stock';

  /// Mal kabul (docs/13 §5).
  static const String stockEntry = '/stock/entry';

  /// Hareket geçmişi (docs/13 §8 · REQ-STOCK-010).
  static const String stockMovements = '/stock/movements';

  /// Ayarlar → Yedekleme (docs/19). 🔒 **OD-030 ile kilidin arkasına alındı.**
  ///
  /// ⚠️ Bu rotanın yolu `BackupReminderBanner` içinde de geçer; ikisi birlikte
  /// değiştirilmelidir. Banner kilit dışı bir ekranda (satış) durur ve kapıya
  /// götürür — hatırlatma görünür kalır, yedek alma kilidin arkasındadır.
  static const String backup = '/backup';

  /// Ayarlar → Bakım → Veri Tutarlılığı Kontrolü (docs/24 §3.3).
  static const String consistency = '/maintenance/consistency';

  /// Satış ekranı (docs/12 · REQ-UX-001). **Kilit dışındadır** — satış
  /// uygulamanın asıl işidir (BR-AUTH-014).
  static const String sales = '/sales';

  /// 🔒 **Yönetici erişim kilidinin arkasındaki rotalar** — BR-AUTH-018 ·
  /// REQ-AUTH-029/030 · [OD-030](../../docs/28-open-decisions.md).
  ///
  /// Bu küme iki yerde kullanılır ve **tek kaynaktır**:
  ///
  /// 1. [routes] — her biri `AdminGate` ile sarılır (ekran kurulmaz)
  /// 2. `HomeScreen` — kilit kapalıyken bu ekranların kutuları **gizlenir**
  ///
  /// Kümede olmayan üç rota kilit dışındadır: satış, satış geçmişi ve stok
  /// (BR-AUTH-014). Yeni bir yönetim ekranı eklendiğinde **buraya da**
  /// eklenmelidir; `test/app/app_routing_test.dart` bunu doğrular.
  static const Set<String> adminOnly = {
    users,
    financialAccessSettings,
    categories,
    suppliers,
    vatRates,
    products,
    barcodeDiagnostics,
    dashboard,
    reports,
    importExport,
    consistency,
    backup,
  };

  /// Kilit arkasındaki bir ekranı kapıya sarar — BR-AUTH-018.
  ///
  /// [builder] yalnızca kilit açıkken çağrılır; kilitliyken ekran **kurulmaz**
  /// ve parola sorulur (`AdminGate`).
  static WidgetBuilder _guarded(WidgetBuilder builder) =>
      (_) => AdminGate(builder: builder);

  static Map<String, WidgetBuilder> routes() => {
    // Kilit dışı (BR-AUTH-014) — satış, satış geçmişi, stok + oturum ekranları.
    setup: (_) => const SetupWizardScreen(),
    login: (_) => const LoginScreen(),
    home: (_) => const HomeScreen(),
    sales: (_) => const SaleScreen(),
    saleHistory: (_) => const SaleHistoryScreen(),
    stock: (_) => const StockOverviewScreen(),
    stockEntry: (_) => const StockEntryScreen(),
    stockMovements: (_) => const StockMovementsScreen(),

    // 🔒 Kilit arkasında (BR-AUTH-013 · [adminOnly]).
    users: _guarded((_) => const UserManagementScreen()),
    financialAccessSettings: _guarded(
      (_) => const FinancialAccessSettingsScreen(),
    ),
    categories: _guarded((_) => const CategoryManagementScreen()),
    suppliers: _guarded((_) => const SupplierManagementScreen()),
    vatRates: _guarded((_) => const VatRateManagementScreen()),
    products: _guarded((_) => const ProductListScreen()),
    barcodeDiagnostics: _guarded((_) => const BarcodeDiagnosticsScreen()),
    dashboard: _guarded((_) => const DashboardScreen()),
    reports: _guarded((_) => const ReportsScreen()),
    importExport: _guarded((_) => const ImportExportScreen()),
    consistency: _guarded((_) => const ConsistencyScreen()),
    backup: _guarded((_) => const BackupScreen()),
  };
}
