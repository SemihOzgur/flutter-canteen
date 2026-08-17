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
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  late CanteenDatabase db;

  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  Future<void> pumpApp(WidgetTester tester, String initialRoute) async {
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
}
