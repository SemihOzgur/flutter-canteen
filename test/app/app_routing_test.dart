/// Rota bağlantısı widget testleri — **docs/03 §6 adım 7/9 · docs/17 §3/§4**
///
/// docs/27 §4: widget testleri **seçicidir.** Buradaki tek soru, bootstrap'ın
/// çözdüğü rotanın gerçekten ilgili ekranı açıp açmadığıdır — form davranışları
/// (odak, validasyon) ekranlar yazıldığında test edilecektir.
library;

import 'package:canteen/app/app.dart';
import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/app/router.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/presentation/auth/financial_access_dialog.dart';
import 'package:canteen/presentation/dashboard/dashboard_screen.dart';
import 'package:canteen/presentation/home/home_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  late CanteenDatabase db;

  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester, String initialRoute) async {
    // docs/23 §4 — desteklenen **minimum** çözünürlük 1366×768. Flutter'ın
    // 800×600 varsayılanı ürünün hiç desteklemediği bir boyuttur; orada
    // kaydırma gerektiren bir düğme "bulunamadı" gibi görünür.
    // Ana ekran her fazda yeni bir giriş noktası kazanıyor. Test yüzeyi
    // ürünün HEDEF çözünürlüğüdür (docs/23 §4 — 1920×1080); minimum
    // çözünürlükte düğmelerin kaydırma gerektirmesi bir kusur değildir,
    // ekran zaten `SingleChildScrollView` içindedir.
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [canteenDatabaseProvider.overrideWithValue(db)],
        child: CanteenApp(initialRoute: initialRoute),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('setup rotası sihirbazı açar ve kaldığı adımı gösterir', (
    tester,
  ) async {
    await pumpApp(tester, AppRoutes.setup);

    expect(find.text(AppStringsTr.setupTitle), findsOneWidget);
    expect(
      find.text(AppStringsTr.setupStepUser),
      findsOneWidget,
      reason:
          'Boş veritabanında sihirbaz Adım 1\'den başlamalı (EC-AUTH-008); '
          'yarım kurulumda ilk eksik adımdan devam eder (H6).',
    );
  });

  testWidgets('login rotası giriş ekranını açar', (tester) async {
    await pumpApp(tester, AppRoutes.login);

    expect(find.text(AppStringsTr.loginTitle), findsOneWidget);
  });

  testWidgets('home rotası ana ekranı açar', (tester) async {
    await pumpApp(tester, AppRoutes.home);

    expect(find.text(AppStringsTr.foundationReady), findsOneWidget);
  });

  // --- Faz 3a rotaları (docs/17 §8, §9, §11) --------------------------------

  testWidgets('kullanıcı yönetimi rotası ekranı açar', (tester) async {
    await pumpApp(tester, AppRoutes.users);

    expect(find.text(AppStringsTr.usersTitle), findsOneWidget);
  });

  testWidgets('finansal erişim ayarları rotası ekranı açar', (tester) async {
    await pumpApp(tester, AppRoutes.financialAccessSettings);

    expect(find.text(AppStringsTr.financialAccessTitle), findsOneWidget);
    expect(
      find.text(AppStringsTr.changeDashboardPasswordTitle),
      findsOneWidget,
    );
  });

  testWidgets('ana ekrandan kullanıcı yönetimine gidilir', (tester) async {
    await pumpApp(tester, AppRoutes.home);

    await tester.tap(find.byKey(HomeScreen.usersButtonKey));
    await tester.pumpAndSettle();

    expect(find.text(AppStringsTr.usersTitle), findsOneWidget);
  });

  testWidgets('ana ekrandan finansal erişim ayarlarına gidilir', (
    tester,
  ) async {
    await pumpApp(tester, AppRoutes.home);

    await tester.tap(find.byKey(HomeScreen.financialAccessSettingsButtonKey));
    await tester.pumpAndSettle();

    expect(
      find.text(AppStringsTr.changeDashboardPasswordTitle),
      findsOneWidget,
    );
  });

  /// docs/22 F9 · BR-AUTH-013: Dashboard kilidin arkasındadır — ekran Faz 8'de
  /// Faz 8'de ekran geldi; kapı hâlâ ekranın ÖNÜNDEDİR.
  testWidgets('ana ekranda Dashboard finansal erişim parolası sorar', (
    tester,
  ) async {
    await pumpApp(tester, AppRoutes.home);

    await tester.tap(find.byKey(HomeScreen.dashboardButtonKey));
    await tester.pumpAndSettle();

    expect(find.byType(FinancialAccessDialog), findsOneWidget);
    expect(
      find.byType(DashboardScreen),
      findsNothing,
      reason:
          'docs/22 F9 — kilit ekranın ÖNÜNDEDİR; parola girilmeden Dashboard '
          'hiç kurulmaz.',
    );
  });

  testWidgets('vazgeçilirse Dashboard AÇILMAZ', (tester) async {
    // EC-DASH-003 — kullanıcı vazgeçerse hiçbir şey açılmaz ve kilit kapalı
    // kalır.
    await pumpApp(tester, AppRoutes.home);
    await tester.tap(find.byKey(HomeScreen.dashboardButtonKey));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStringsTr.cancelAction));
    await tester.pumpAndSettle();

    expect(find.byType(DashboardScreen), findsNothing);
    expect(find.byType(FinancialAccessDialog), findsNothing);
  });
}
