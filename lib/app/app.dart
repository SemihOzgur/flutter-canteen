/// Uygulama kökü.
library;

import 'package:flutter/material.dart';

import '../presentation/common/low_resolution_notice.dart';
import '../presentation/startup/already_running_screen.dart';
import 'l10n/app_strings_tr.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Normal uygulama.
///
/// [initialRoute] bootstrap tarafından çözülür (`startup.dart` · docs/03 §6
/// adım 7/9): kurulum yarım kaldıysa sihirbaz, oturum yoksa login, varsa ana
/// ekran. Burada sabit bir varsayılan **yoktur** — EC-AUTH-008'de hiç kullanıcı
/// yokken login açılırsa kullanıcı sisteme hiç giremez.
class CanteenApp extends StatelessWidget {
  final String initialRoute;

  const CanteenApp({required this.initialRoute, super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStringsTr.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: initialRoute,
      routes: AppRoutes.routes(),
      // EC-SYS-008 — uyarı TÜM ekranların üstünde durur; tek tek ekranlara
      // dağıtılsaydı yeni bir ekran eklendiğinde sessizce unutulurdu.
      builder: (context, child) =>
          LowResolutionNotice(child: child ?? const SizedBox.shrink()),
    );
  }
}

/// İkinci örnek engellendiğinde gösterilen minimal uygulama (BR-GEN-005).
class AlreadyRunningApp extends StatelessWidget {
  const AlreadyRunningApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStringsTr.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      home: const AlreadyRunningScreen(),
    );
  }
}
