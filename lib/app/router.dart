/// Temel navigasyon.
///
/// rules/01 §3 (over-engineering yasağı) ve Faz 1 kapsamı gereği `go_router`
/// **kullanılmaz** — Flutter'ın yerleşik `Navigator`'ı yeterlidir.
/// Ekran sayısı arttığında yeniden değerlendirilir.
library;

import 'package:flutter/material.dart';

import '../presentation/home/home_screen.dart';

class AppRoutes {
  const AppRoutes._();

  static const String home = '/';

  static Map<String, WidgetBuilder> routes() => {
    home: (_) => const HomeScreen(),
  };
}
