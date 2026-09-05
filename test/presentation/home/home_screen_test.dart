/// Ana ekran — **OD-030 · docs/22 F9/F16 · docs/23 §6 · rules/05 §3/§5**
///
/// Ekranın kendisi veri okumaz (rules/05 §8); test edilen şey **gezinme,
/// görünürlük ve anlaşılırlıktır.**
///
/// OD-030 ile ekranın **iki hâli** vardır ve aradaki fark bir güvenlik
/// kararıdır (BR-AUTH-018): kilit kapalıyken yönetim kutuları ağaçta
/// **bulunmaz.**
///
/// | Test | Kural |
/// |---|---|
/// | Kilitliyken yalnızca satış · satış geçmişi · stok görünür | REQ-AUTH-029 · REQ-UX-015 · EC-DASH-015 |
/// | Kilit açılınca tüm kutular belirir | REQ-AUTH-029 |
/// | "Erişimi Kapat" kilidi kapatır, oturum kapanmaz | REQ-AUTH-031 · EC-DASH-018 |
/// | Çıkış eylemi vardır ve oturumu kapatır | REQ-UX-016 · REQ-AUTH-032 |
/// | Sepette ürün varken çıkışta sepet KORUNUR | BR-AUTH-005 · REQ-AUTH-005 |
library;

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/app/router.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/application/sales/providers.dart';
import 'package:canteen/data/db/app_setting_keys.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/presentation/auth/financial_access_dialog.dart';
import 'package:canteen/presentation/home/home_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';
import '../../support/test_window.dart';

const String kAdminPassword = 'yonetici-parolasi-7Q4X';

void main() {
  late CanteenDatabase db;
  late ProviderContainer container;

  setUp(() {
    db = memoryDatabase();
    // Kilit **bellekte** yaşadığı için (BR-AUTH-016) ekran ve doğrulama aynı
    // container üzerinden gitmek zorundadır. Container `pumpHome`'dan önce
    // kurulur ki kilit ekran **kurulmadan** açılabilsin.
    container = ProviderContainer(
      overrides: [canteenDatabaseProvider.overrideWithValue(db)],
    );
  });
  tearDown(() {
    container.dispose();
    db.close();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    useSupportedSurface(tester);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        // Çıkış akışı `login` rotasına gider; rota tablosu gerçek olanıdır.
        child: MaterialApp(
          initialRoute: AppRoutes.home,
          routes: AppRoutes.routes(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Yönetici parolasını kurar ve kilidi açar — ekranın "açık" hâli.
  Future<void> unlockAdmin() async {
    await container.read(financialAccessProvider).setPassword(kAdminPassword);
    await container.read(financialAccessProvider).unlock(kAdminPassword);
  }

  /// Kutuyu görünür hâle getirir.
  ///
  /// Ana ekran kaydırılabilir bir listedir ve `ListView` yalnızca görünen
  /// çocukları kurar; alttaki kutular ekrana gelmeden ağaçta bulunmaz.
  Future<void> reveal(WidgetTester tester, Key key) async {
    await tester.scrollUntilVisible(
      find.byKey(key),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// BR-AUTH-014 — kilitten **etkilenmeyen** kutular.
  const alwaysVisible = <(Key, String)>[
    (HomeScreen.salesButtonKey, AppStringsTr.homeHintSale),
    (HomeScreen.saleHistoryButtonKey, AppStringsTr.homeHintSaleHistory),
    (HomeScreen.stockButtonKey, AppStringsTr.homeHintStock),
  ];

  /// BR-AUTH-013 — yalnızca kilit **açıkken** listelenen kutular.
  const adminTiles = <(Key, String)>[
    (HomeScreen.productsButtonKey, AppStringsTr.homeHintProducts),
    (HomeScreen.categoriesButtonKey, AppStringsTr.homeHintCategories),
    (HomeScreen.suppliersButtonKey, AppStringsTr.homeHintSuppliers),
    (HomeScreen.vatRatesButtonKey, AppStringsTr.homeHintVatRates),
    (HomeScreen.usersButtonKey, AppStringsTr.homeHintUsers),
    (HomeScreen.backupButtonKey, AppStringsTr.homeHintBackup),
    (HomeScreen.importExportButtonKey, AppStringsTr.homeHintImportExport),
    (HomeScreen.consistencyButtonKey, AppStringsTr.homeHintConsistency),
    (
      HomeScreen.barcodeDiagnosticsButtonKey,
      AppStringsTr.homeHintBarcodeDiagnostics,
    ),
    (HomeScreen.dashboardButtonKey, AppStringsTr.homeHintDashboard),
    (HomeScreen.reportsButtonKey, AppStringsTr.homeHintReports),
    (
      HomeScreen.financialAccessSettingsButtonKey,
      AppStringsTr.homeHintFinancialAccess,
    ),
  ];

  // --- Kilit KAPALI (harici kullanıcı) --------------------------------------

  testWidgets(
    'REQ-AUTH-029 · REQ-UX-015 · EC-DASH-015 — kilitliyken YALNIZCA üç ekran '
    'listelenir',
    (tester) async {
      await pumpHome(tester);

      for (final (key, _) in alwaysVisible) {
        await reveal(tester, key);
        expect(find.byKey(key), findsOneWidget, reason: '$key bulunamadı.');
      }

      // Kilidi açacak eylem görünür olmalı — yoksa yönetici içeri giremez.
      await reveal(tester, HomeScreen.adminUnlockButtonKey);
      expect(find.byKey(HomeScreen.adminUnlockButtonKey), findsOneWidget);

      // Asıl iddia: yönetim kutuları AĞAÇTA YOK.
      await tester.scrollUntilVisible(
        find.byKey(HomeScreen.adminUnlockButtonKey),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      for (final (key, _) in adminTiles) {
        expect(
          find.byKey(key),
          findsNothing,
          reason:
              '$key kilit kapalıyken görünmemeli (BR-AUTH-018). Gizleme '
              'Opacity/Visibility ile yapılırsa kutu ağaçta kalır ve `Tab` '
              'ile odaklanılabilir.',
        );
      }
    },
  );

  testWidgets('kilitliyken "yetkiniz yok" gibi bir mesaj GÖSTERİLMEZ', (
    tester,
  ) async {
    // rules/04 §2 — bu projede yetki kavramı yoktur; gösterilecek bir yetki
    // reddi de yoktur (rules/05 §3).
    await pumpHome(tester);

    for (final forbidden in [
      'yetki',
      'Yetki',
      'izin yok',
      'erişim reddedildi',
    ]) {
      expect(
        find.textContaining(forbidden),
        findsNothing,
        reason: '"$forbidden" ana ekranda geçmemeli.',
      );
    }
  });

  testWidgets('kilit simgesi taşıyan kutu kilidi AÇAR', (tester) async {
    // rules/05 §5 — kilit renkle değil SİMGEYLE anlatılır.
    await pumpHome(tester);
    await reveal(tester, HomeScreen.adminUnlockButtonKey);

    expect(
      find.descendant(
        of: find.byKey(HomeScreen.adminUnlockButtonKey),
        matching: find.byIcon(Icons.lock_outline),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(HomeScreen.adminUnlockButtonKey));
    await tester.pumpAndSettle();

    expect(find.byType(FinancialAccessDialog), findsOneWidget);
  });

  // --- Kilit AÇIK (yönetici) ------------------------------------------------

  testWidgets('kilit açıkken tüm eylem kutuları ekranda vardır', (
    tester,
  ) async {
    await unlockAdmin();
    await pumpHome(tester);

    for (final (key, _) in [...alwaysVisible, ...adminTiles]) {
      await reveal(tester, key);
      expect(find.byKey(key), findsOneWidget, reason: '$key bulunamadı.');
    }
  });

  testWidgets('HER kutu ne işe yaradığını anlatan bir ipucu taşır', (
    tester,
  ) async {
    // rules/05 §5 — etiket ne olduğunu söyler, ipucu ne işe yaradığını.
    // Yeni bir kutu ipucusuz eklenirse bu test düşer.
    await unlockAdmin();
    await pumpHome(tester);

    for (final (key, hint) in [
      ...alwaysVisible,
      ...adminTiles,
      (HomeScreen.adminLockButtonKey, AppStringsTr.homeHintAdminLock),
    ]) {
      await reveal(tester, key);
      final tooltip = find.ancestor(
        of: find.byKey(key),
        matching: find.byType(Tooltip),
      );
      expect(tooltip, findsWidgets, reason: '$key ipucusuz.');
      expect(
        tester.widget<Tooltip>(tooltip.first).message,
        hint,
        reason: '$key yanlış ipucu taşıyor.',
      );
    }
  });

  testWidgets('ipucu fareyle üzerine gelince GÖRÜNÜR', (tester) async {
    await pumpHome(tester);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(
      tester.getCenter(find.byKey(HomeScreen.stockButtonKey)),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text(AppStringsTr.homeHintStock), findsOneWidget);
  });

  testWidgets('eylemler BÖLÜMLERE ayrılmıştır', (tester) async {
    // Kutuların tek yığın hâlinde durması, aranan şeyin her seferinde gözle
    // taranmasını gerektiriyordu.
    await unlockAdmin();
    await pumpHome(tester);

    for (final title in [
      AppStringsTr.homeSectionDaily,
      AppStringsTr.homeSectionCatalog,
      AppStringsTr.homeSectionData,
      AppStringsTr.homeSectionFinancial,
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(title), findsOneWidget, reason: title);
    }
  });

  testWidgets('BR-AUTH-013 — finansal ekranlar kilit SİMGESİ taşır', (
    tester,
  ) async {
    // rules/05 §5: durum renkle değil, ikon veya metinle de anlatılır.
    // Kilit açık olsa bile bu iki ekran finansal veri gösterir (BR-AUTH-012).
    await unlockAdmin();
    await pumpHome(tester);

    for (final key in [
      HomeScreen.dashboardButtonKey,
      HomeScreen.reportsButtonKey,
    ]) {
      await reveal(tester, key);
      final lock = find.descendant(
        of: find.byKey(key),
        matching: find.byIcon(Icons.lock_outline),
      );
      expect(lock, findsOneWidget, reason: '$key kilit simgesi taşımıyor.');
    }
  });

  // --- REQ-AUTH-031 — kilidi elle kapatma -----------------------------------

  testWidgets(
    'REQ-AUTH-031 · EC-DASH-018 — "Erişimi Kapat" kilidi kapatır, oturumu '
    'KAPATMAZ',
    (tester) async {
      final userId = await insertTestUser(db);
      await unlockAdmin();
      await container.read(sessionServiceProvider).save(userId);
      await pumpHome(tester);

      await reveal(tester, HomeScreen.adminLockButtonKey);
      await tester.tap(find.byKey(HomeScreen.adminLockButtonKey));
      await tester.pumpAndSettle();

      expect(
        container.read(financialAccessProvider).isUnlocked,
        isFalse,
        reason: 'Kilit kapanmalı (BR-AUTH-016).',
      );
      expect(
        find.byKey(HomeScreen.productsButtonKey),
        findsNothing,
        reason: 'Yönetim kutuları hemen gizlenmeli (REQ-AUTH-029).',
      );
      expect(
        await container.read(sessionServiceProvider).load(),
        isNotNull,
        reason:
            'EC-DASH-018 — kilidi kapatmak OTURUMU sonlandırmaz; logout ile '
            'karıştırılmamalıdır.',
      );
    },
  );

  // --- REQ-AUTH-032 — çıkış -------------------------------------------------

  testWidgets(
    'REQ-UX-016 · REQ-AUTH-032 — sepet boşken çıkış doğrudan yapılır',
    (tester) async {
      final userId = await insertTestUser(db);
      await pumpHome(tester);
      await container.read(sessionServiceProvider).save(userId);

      await tester.tap(find.byKey(HomeScreen.logoutButtonKey));
      await tester.pumpAndSettle();

      expect(
        await container.read(sessionServiceProvider).load(),
        isNull,
        reason: 'REQ-AUTH-004 — oturum verisi temizlenir.',
      );
      expect(
        find.text(AppStringsTr.loginTitle),
        findsOneWidget,
        reason: 'docs/17 §10 — çıkıştan sonra login ekranı.',
      );
    },
  );

  testWidgets('REQ-AUTH-004 — çıkış yönetici erişim kilidini de kapatır', (
    tester,
  ) async {
    await unlockAdmin();
    await pumpHome(tester);

    await tester.tap(find.byKey(HomeScreen.logoutButtonKey));
    await tester.pumpAndSettle();

    expect(container.read(financialAccessProvider).isUnlocked, isFalse);
  });

  testWidgets(
    'BR-AUTH-005 · REQ-AUTH-005 — sepette ürün varken uyarılır ve sepet '
    'KORUNUR',
    (tester) async {
      final userId = await insertTestUser(db);
      final productId = await insertTestProduct(db);
      await pumpHome(tester);
      await container.read(sessionServiceProvider).save(userId);

      final cartService = container.read(cartServiceProvider);
      final cart = await cartService.ensureActive(userId);
      await cartService.addProduct(
        cartId: cart.id,
        productId: productId,
        quantity: 3,
      );

      await tester.tap(find.byKey(HomeScreen.logoutButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.text(AppStringsTr.logoutDescriptionWithCart(1)),
        findsOneWidget,
        reason:
            'docs/17 §10 — kullanıcı sepetinin korunacağını çıkıştan ÖNCE '
            'öğrenmelidir.',
      );

      // "Vazgeç" → hiçbir şey olmaz.
      await tester.tap(find.text(AppStringsTr.cancelAction));
      await tester.pumpAndSettle();
      expect(await container.read(sessionServiceProvider).load(), isNotNull);

      // "Çıkış Yap" → oturum kapanır, **sepet durur.**
      await tester.tap(find.byKey(HomeScreen.logoutButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(HomeScreen.logoutConfirmButtonKey));
      await tester.pumpAndSettle();

      expect(await container.read(sessionServiceProvider).load(), isNull);
      final summary = await container.read(cartServiceProvider).activeSummary();
      expect(
        summary?.lineCount,
        1,
        reason: 'BR-AUTH-005 — logout aktif sepeti SİLMEZ.',
      );
    },
  );

  testWidgets('"Sepeti Temizle ve Çık" kullanıcının AÇIK tercihidir', (
    tester,
  ) async {
    final userId = await insertTestUser(db);
    final productId = await insertTestProduct(db);
    await pumpHome(tester);
    await container.read(sessionServiceProvider).save(userId);

    final cartService = container.read(cartServiceProvider);
    final cart = await cartService.ensureActive(userId);
    await cartService.addProduct(
      cartId: cart.id,
      productId: productId,
      quantity: 2,
    );

    await tester.tap(find.byKey(HomeScreen.logoutButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HomeScreen.logoutClearCartButtonKey));
    await tester.pumpAndSettle();

    final summary = await container.read(cartServiceProvider).activeSummary();
    expect(summary?.lineCount ?? 0, 0);
    expect(await container.read(sessionServiceProvider).load(), isNull);
  });

  testWidgets('oturum anahtarı gerçekten silinir', (tester) async {
    final userId = await insertTestUser(db);
    await pumpHome(tester);
    await container.read(sessionServiceProvider).save(userId);

    await tester.tap(find.byKey(HomeScreen.logoutButtonKey));
    await tester.pumpAndSettle();

    final raw = await container
        .read(appSettingsDaoProvider)
        .read(AppSettingKeys.session);
    expect(raw, isNull, reason: 'docs/17 §10 — app_settings[session] silinir.');
  });

  // --- Genel ---------------------------------------------------------------

  testWidgets('sürüm ekranda görünür', (tester) async {
    await pumpHome(tester);
    expect(find.byKey(const Key('home_app_version')), findsOneWidget);
  });

  testWidgets('1366×768\'de hiçbir taşma olmaz', (tester) async {
    // docs/23 §4 — desteklenen en küçük çözünürlük.
    await pumpHome(tester);
    expect(tester.takeException(), isNull);
  });
}
