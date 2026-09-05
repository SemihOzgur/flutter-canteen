/// Rota bağlantısı widget testleri — **docs/03 §6 adım 7/9 · docs/17 §3/§4/§7 ·
/// OD-030**
///
/// docs/27 §4: widget testleri **seçicidir.** İki soru sorulur:
///
/// 1. Bootstrap'ın çözdüğü rota gerçekten ilgili ekranı açıyor mu?
/// 2. **Kilit arkasındaki bir rota, kilit kapalıyken ekranı KURMUYOR mu?**
///    (BR-AUTH-018 · REQ-AUTH-030 · EC-DASH-016)
///
/// İkincisi bu dosyanın asıl yüküdür: ana ekran kutuyu gizlese bile rota
/// kısayolla veya doğrudan `pushNamed` ile açılabilir; kapı orada durmalıdır.
library;

import 'dart:async';

import 'package:canteen/app/app.dart';
import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/app/router.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/presentation/auth/financial_access_dialog.dart';
import 'package:canteen/presentation/dashboard/dashboard_screen.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/presentation/home/home_screen.dart';
import 'package:canteen/presentation/settings/user_management_screen.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

const String kAdminPassword = 'yonetici-parolasi-7Q4X';

void main() {
  late CanteenDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = memoryDatabase();
    // Kilit bellektedir (BR-AUTH-016): ekran ve doğrulama aynı container
    // üzerinden gitmelidir.
    container = ProviderContainer(
      overrides: [canteenDatabaseProvider.overrideWithValue(db)],
    );
  });
  tearDown(() {
    container.dispose();
    db.close();
  });

  /// Yönetici parolasını kurar ve kilidi açar (ekran kurulmadan ÖNCE).
  Future<void> unlockAdmin() async {
    await container.read(financialAccessProvider).setPassword(kAdminPassword);
    await container.read(financialAccessProvider).unlock(kAdminPassword);
  }

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
      UncontrolledProviderScope(
        container: container,
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

    expect(find.text(AppStringsTr.homeWelcome), findsOneWidget);
  });

  // --- Faz 3a rotaları (docs/17 §8, §9, §11) --------------------------------

  // --- OD-030 — kilit arkasındaki rotalar ----------------------------------

  testWidgets(
    'REQ-AUTH-030 · EC-DASH-016 — kilit arkasındaki rota kilitliyken EKRANI '
    'KURMAZ',
    (tester) async {
      await pumpApp(tester, AppRoutes.users);

      expect(
        find.byType(UserManagementScreen),
        findsNothing,
        reason:
            'BR-AUTH-018 — kapı görsel bir perde değildir: ekran hiç '
            'kurulmamalı, dolayısıyla veri yükleyicisi de başlamamalıdır.',
      );
      expect(
        find.byType(FinancialAccessDialog),
        findsOneWidget,
        reason: 'Kapı parolayı kendisi sorar (admin_gate.dart).',
      );
      expect(find.text(AppStringsTr.usersTitle), findsNothing);
    },
  );

  testWidgets('kilit AÇIKKEN aynı rota ekranı açar', (tester) async {
    await unlockAdmin();
    await pumpApp(tester, AppRoutes.users);

    expect(find.text(AppStringsTr.usersTitle), findsOneWidget);
    expect(find.byType(FinancialAccessDialog), findsNothing);
  });

  testWidgets('yönetici erişim ayarları rotası kilit AÇIKKEN ekranı açar', (
    tester,
  ) async {
    await unlockAdmin();
    await pumpApp(tester, AppRoutes.financialAccessSettings);

    expect(find.text(AppStringsTr.financialAccessTitle), findsWidgets);
    expect(
      find.text(AppStringsTr.changeDashboardPasswordTitle),
      findsOneWidget,
    );
  });

  testWidgets('AppRoutes.adminOnly ile rota tablosu TUTARLIDIR', (
    tester,
  ) async {
    // Yeni bir yönetim ekranı `adminOnly` kümesine eklenmeden rota tablosuna
    // girerse burada yakalanır: kilit dışı üç ekran dışında her rota kilit
    // arkasında olmalıdır (BR-AUTH-014).
    const unlockedRoutes = {
      AppRoutes.setup,
      AppRoutes.login,
      AppRoutes.home,
      AppRoutes.sales,
      AppRoutes.saleHistory,
      AppRoutes.stock,
      AppRoutes.stockEntry,
      AppRoutes.stockMovements,
    };

    final all = AppRoutes.routes().keys.toSet();
    expect(
      all.difference(unlockedRoutes),
      AppRoutes.adminOnly,
      reason:
          'Kilit dışı rotalar yalnızca satış, satış geçmişi, stok ve oturum '
          'ekranlarıdır (BR-AUTH-014 · OD-030). Yeni bir yönetim ekranı '
          'eklendiyse AppRoutes.adminOnly kümesine de eklenmelidir.',
    );
  });

  testWidgets('ana ekrandan kullanıcı yönetimine gidilir', (tester) async {
    await unlockAdmin();
    await pumpApp(tester, AppRoutes.home);

    await tester.scrollUntilVisible(
      find.byKey(HomeScreen.usersButtonKey),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(HomeScreen.usersButtonKey));
    await tester.pumpAndSettle();

    expect(find.text(AppStringsTr.usersTitle), findsOneWidget);
  });

  /// docs/22 F9 · BR-AUTH-013: Dashboard kilidin arkasındadır.
  testWidgets('ana ekranda Dashboard yönetici erişim parolası sorar', (
    tester,
  ) async {
    // Kilit kapalıyken Dashboard kutusu ana ekranda **yoktur** (REQ-AUTH-029);
    // kilidi açan kutu vardır ve parolayı o sorar.
    await pumpApp(tester, AppRoutes.home);

    expect(find.byKey(HomeScreen.dashboardButtonKey), findsNothing);

    await tester.tap(find.byKey(HomeScreen.adminUnlockButtonKey));
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
    await unlockAdmin();
    await pumpApp(tester, AppRoutes.home);

    await tester.scrollUntilVisible(
      find.byKey(HomeScreen.dashboardButtonKey),
      120,
      scrollable: find.byType(Scrollable).first,
    );

    // Kilidi kapatıp Dashboard'a basmak: parola yeniden sorulur.
    container.read(financialAccessProvider).lock();
    await tester.tap(find.byKey(HomeScreen.dashboardButtonKey));
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStringsTr.cancelAction));
    await tester.pumpAndSettle();

    expect(find.byType(DashboardScreen), findsNothing);
    expect(find.byType(FinancialAccessDialog), findsNothing);
  });

  testWidgets(
    'EC-DASH-019 — kilit elle kapatılınca aynı ekran parolayı YENİDEN sorar',
    (tester) async {
      await unlockAdmin();
      await pumpApp(tester, AppRoutes.home);

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.pushNamed(AppRoutes.users));
      await tester.pumpAndSettle();
      expect(find.text(AppStringsTr.usersTitle), findsOneWidget);

      // Geri dön ve kilidi elle kapat (REQ-AUTH-031).
      navigator.pop();
      await tester.pumpAndSettle();
      container.read(financialAccessProvider).lock();

      unawaited(navigator.pushNamed(AppRoutes.users));
      await tester.pumpAndSettle();

      expect(
        find.byType(FinancialAccessDialog),
        findsOneWidget,
        reason:
            'BR-AUTH-016 — kilidi kapatmak açmayı geri alır; ekran yeniden '
            'parola ister.',
      );
      expect(find.text(AppStringsTr.usersTitle), findsNothing);
    },
  );

  testWidgets('EC-DASH-016 — kapıda vazgeçilirse önceki ekrana DÖNÜLÜR', (
    tester,
  ) async {
    await pumpApp(tester, AppRoutes.home);

    // Kısayol/`pushNamed` yolu: kutu görünmese de rota açılabilir.
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(navigator.pushNamed(AppRoutes.products));
    await tester.pumpAndSettle();

    expect(find.byType(FinancialAccessDialog), findsOneWidget);

    await tester.tap(find.text(AppStringsTr.cancelAction));
    await tester.pumpAndSettle();

    expect(
      find.text(AppStringsTr.homeWelcome),
      findsOneWidget,
      reason: 'Kapı vazgeçilince rotayı kendisi kapatır (admin_gate.dart).',
    );
    expect(container.read(financialAccessProvider).isUnlocked, isFalse);
  });
}
