/// Ana ekran — **docs/22 · docs/23 §6 · rules/05 §5**
///
/// Ekranın kendisi veri okumaz (rules/05 §8): burada sorgu, hesap veya
/// veri kaynağı yoktur. Test edilen şey **gezinme ve anlaşılırlıktır.**
library;

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/presentation/home/home_screen.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_window.dart';

void main() {
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

  Future<void> pumpHome(WidgetTester tester) async {
    useSupportedSurface(tester);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: HomeScreen())),
    );
    await tester.pumpAndSettle();
  }

  /// Ana ekrandaki her eylem kutusu ve taşıması gereken açıklama.
  const tiles = <(Key, String)>[
    (HomeScreen.salesButtonKey, AppStringsTr.homeHintSale),
    (HomeScreen.saleHistoryButtonKey, AppStringsTr.homeHintSaleHistory),
    (HomeScreen.stockButtonKey, AppStringsTr.homeHintStock),
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

  testWidgets('tüm eylem kutuları ekranda vardır', (tester) async {
    await pumpHome(tester);

    for (final (key, _) in tiles) {
      await reveal(tester, key);
      expect(find.byKey(key), findsOneWidget, reason: '$key bulunamadı.');
    }
  });

  testWidgets('HER kutu ne işe yaradığını anlatan bir ipucu taşır', (
    tester,
  ) async {
    // rules/05 §5 — etiket ne olduğunu söyler, ipucu ne işe yaradığını.
    // Yeni bir kutu ipucusuz eklenirse bu test düşer.
    await pumpHome(tester);

    for (final (key, hint) in tiles) {
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
    // 15 eylemin tek yığın hâlinde durması, aranan şeyin her seferinde
    // gözle taranmasını gerektiriyordu.
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
    // Kullanıcı parolanın neden sorulacağını TIKLAMADAN önce anlamalıdır.
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
