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
  };
}
