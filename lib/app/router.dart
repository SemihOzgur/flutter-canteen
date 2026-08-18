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
import '../presentation/settings/financial_access_settings_screen.dart';
import '../presentation/settings/user_management_screen.dart';

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

  static Map<String, WidgetBuilder> routes() => {
    setup: (_) => const SetupWizardScreen(),
    login: (_) => const LoginScreen(),
    home: (_) => const HomeScreen(),
    users: (_) => const UserManagementScreen(),
    financialAccessSettings: (_) => const FinancialAccessSettingsScreen(),
  };
}
