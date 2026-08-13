/// Uygulama kökü.
library;

import 'package:flutter/material.dart';

import '../presentation/startup/already_running_screen.dart';
import 'l10n/app_strings_tr.dart';
import 'router.dart';
import 'theme/app_theme.dart';

/// Normal uygulama.
class CanteenApp extends StatelessWidget {
  const CanteenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStringsTr.appTitle,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: AppRoutes.home,
      routes: AppRoutes.routes(),
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
