/// Raporlar ekranı — **docs/16 · BR-AUTH-012/013 · REQ-SEC-005**
///
/// | Test | Kural |
/// |---|---|
/// | Kilit kapalıyken **rakam yok**, dışa aktarma yok | BR-AUTH-012 |
/// | Dışa aktarma kilidin **etrafından dolaşamaz** | BR-AUTH-012 |
/// | CSV BOM + `;` ile üretilir | rules/03 §7 |
/// | Ürün adındaki formül **kaçışlanır** | REQ-SEC-005 |
/// | Kaydetme iptal edilirse dosya yazılmaz | docs/16 §2 |
library;

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/application/auth/financial_access_service.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/application/product/product_draft.dart';
import 'package:canteen/application/product/product_service.dart';
import 'package:canteen/application/product/providers.dart';
import 'package:canteen/application/reporting/providers.dart';
import 'package:canteen/application/sales/providers.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, CartItem, Category, Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/presentation/reports/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late ProviderContainer container;
  late int userId;

  /// Yazılan dosyalar — gerçek diske dokunulmaz.
  late List<({String path, String contents})> written;

  const dashboardPassword = 'DASH-REPORTS-3F8';

  setUp(() async {
    db = memoryDatabase();
    written = [];
    container = ProviderContainer(
      overrides: [
        canteenDatabaseProvider.overrideWithValue(db),
        reportFileWriterProvider.overrideWithValue((path, contents) async {
          written.add((path: path, contents: contents));
          return true;
        }),
      ],
    );
    userId = await insertTestUser(db);
    await container.read(sessionServiceProvider).save(userId);
  });

  tearDown(() async {
    container.dispose();
    await db.close();
  });

  FinancialAccessService access() => container.read(financialAccessProvider);

  Future<void> unlock() async {
    await access().setPassword(dashboardPassword);
    final opened = await access().unlock(dashboardPassword);
    expect(opened.isErr, isFalse);
  }

  Future<int> createProduct({String name = 'Kola'}) async {
    final result = await container
        .read(productServiceProvider)
        .create(
          ProductDraft(name: name, salePrice: const Money(2500)),
          userId: userId,
          initialStock: 100,
        );
    return (result as Ok<ProductSaveOutcome>).value.productId;
  }

  Future<void> sell(int productId, {int quantity = 1}) async {
    final cart = await container.read(cartServiceProvider).ensureActive(userId);
    await container
        .read(cartServiceProvider)
        .addProduct(cartId: cart.id, productId: productId, quantity: quantity);
    await container
        .read(saleServiceProvider)
        .complete(cartId: cart.id, userId: userId);
  }

  Future<void> pump(
    WidgetTester tester, {
    Future<String?> Function(String)? picker,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ReportsScreen(
            clock: () => testEpochUtc,
            savePicker: picker ?? (name) async => '/tmp/$name',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('BR-AUTH-012 — kilit', () {
    testWidgets('kilit kapalıyken rakam ve dışa aktarma YOK', (tester) async {
      await sell(await createProduct());

      await pump(tester);

      expect(find.byKey(ReportsScreen.lockedKey), findsOneWidget);
      expect(find.byKey(ReportsScreen.tableKey), findsNothing);
      expect(
        find.byKey(ReportsScreen.exportButtonKey),
        findsNothing,
        reason: 'Dışa aktarma kilidin etrafından dolaşan bir yol olamaz.',
      );
    });

    testWidgets('kilit açılınca tablo ve dışa aktarma gelir', (tester) async {
      await sell(await createProduct(name: 'Kola'), quantity: 3);
      await unlock();

      await pump(tester);

      expect(find.byKey(ReportsScreen.lockedKey), findsNothing);
      expect(find.byKey(ReportsScreen.tableKey), findsOneWidget);
      expect(find.text('Kola'), findsOneWidget);
    });
  });

  group('docs/16 §2 — CSV dışa aktarma', () {
    testWidgets('rules/03 §7 — BOM ve `;` ile yazılır', (tester) async {
      await sell(await createProduct(name: 'Kola'), quantity: 2);
      await unlock();
      await pump(tester);

      await tester.tap(find.byKey(ReportsScreen.exportButtonKey));
      await tester.pumpAndSettle();

      expect(written, hasLength(1));
      final csv = written.single.contents;
      expect(csv.codeUnitAt(0), 0xFEFF, reason: 'Türkçe Excel BOM ister.');
      expect(csv, contains('Ürün;Adet;'));
      expect(csv, contains('Kola'));
      expect(find.text(AppStringsTr.reportExported), findsOneWidget);
    });

    testWidgets('REQ-SEC-005 — ürün adındaki formül KAÇIŞLANIR', (
      tester,
    ) async {
      await sell(await createProduct(name: "=cmd|'/c calc'!A1"));
      await unlock();
      await pump(tester);

      await tester.tap(find.byKey(ReportsScreen.exportButtonKey));
      await tester.pumpAndSettle();

      final csv = written.single.contents;
      expect(csv, contains("'=cmd"));
      expect(csv.split('\r\n').any((line) => line.startsWith('=')), isFalse);
    });

    testWidgets('kaydetme İPTAL edilirse dosya YAZILMAZ', (tester) async {
      await sell(await createProduct());
      await unlock();
      await pump(tester, picker: (_) async => null);

      await tester.tap(find.byKey(ReportsScreen.exportButtonKey));
      await tester.pumpAndSettle();

      expect(written, isEmpty);
      expect(find.text(AppStringsTr.reportExportCancelled), findsOneWidget);
    });

    testWidgets('veri yokken dışa aktarma PASİF', (tester) async {
      await unlock();

      await pump(tester);

      expect(
        tester
            .widget<FilledButton>(find.byKey(ReportsScreen.exportButtonKey))
            .onPressed,
        isNull,
      );
      expect(find.text(AppStringsTr.reportEmpty), findsOneWidget);
    });

    testWidgets('docs/16 §2 — dışa aktarma kapsamı ekranda YAZILI', (
      tester,
    ) async {
      await sell(await createProduct());
      await unlock();

      await pump(tester);

      expect(find.text(AppStringsTr.reportExportNotice), findsOneWidget);
    });
  });

  testWidgets('rapor türü değiştirilince veri yeniden yüklenir', (
    tester,
  ) async {
    await sell(await createProduct(name: 'Kola'));
    await unlock();
    await pump(tester);
    expect(find.text('Kola'), findsOneWidget);

    await tester.tap(find.byKey(ReportsScreen.reportSelectorKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStringsTr.reportCategorySales).last);
    await tester.pumpAndSettle();

    // Kategori raporunda ürün adı DEĞİL, kategori adı görünür.
    expect(find.text('Kola'), findsNothing);
    expect(find.byKey(ReportsScreen.tableKey), findsOneWidget);
  });
}
