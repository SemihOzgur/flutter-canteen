/// KDV oranı yönetimi widget testleri — **docs/08 §3, §4 · BR-VAT-004/006 ·
/// REQ-VAT-001/010/011 · EC-VAT-001/002/003**
///
/// docs/27 §4: widget testleri **seçicidir.** Buradaki testler sessizce
/// ihlal edilebilecek KDV kurallarını korur:
///
/// | Test | Kural |
/// |---|---|
/// | Oran değişikliğinde uyarı gösterilir; [Vazgeç] uygulamaz | docs/08 §4 · BR-VAT-004 |
/// | Pasif satırda "Varsayılan yap" sunulmaz | BR-VAT-006 · EC-VAT-001 (OD-019) |
/// | **Sil** eylemi yoktur | docs/08 §4 · EC-VAT-003 |
/// | Oran girdisi `20` / `%20` / `0,5` kabul eder | BR-FIN-002 · VatRateParser |
/// | Ekranda teknik detay / hata kodu yok | REQ-UX-008 · REQ-SEC-007 |
///
/// Golden (piksel) testi **yazılmaz** (docs/27 §4).
library;

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/application/reference/providers.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Category, Product, Sale, SaleItem, StockMovement, Supplier, VatRate;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/presentation/settings/vat_rate_management_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;

  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  T withServices<T>(T Function(ProviderContainer container) body) {
    final container = ProviderContainer(
      overrides: [canteenDatabaseProvider.overrideWithValue(db)],
    );
    try {
      return body(container);
    } finally {
      container.dispose();
    }
  }

  Future<int> createRate(String name, int rateBasisPoints) async {
    final created = await withServices(
      (container) => container
          .read(vatRateServiceProvider)
          .create(name: name, rateBasisPoints: rateBasisPoints),
    );
    return created.valueOrNull!;
  }

  Future<void> deactivate(int id) => withServices(
    (container) => container.read(vatRateServiceProvider).deactivate(id),
  );

  /// Orana bağlı ürün — docs/08 §4 uyarısındaki sayı buradan gelir.
  Future<void> attachProduct(int rateId) async {
    await insertTestProduct(db, name: 'Ayran');
    await db
        .update(db.products)
        .write(ProductsCompanion(vatRateId: Value(rateId)));
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [canteenDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: VatRateManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Gönderim sırasında açılan onay diyaloğunu bekler.
  ///
  /// `SubmitButton` 300 ms sonra süreğen bir ilerleme göstergesi açar
  /// (REQ-UX-013); bu yüzden burada `pumpAndSettle` kullanılamaz.
  Future<void> pumpUntilConfirmDialog(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
  }

  String visibleText(WidgetTester tester) => [
    ...tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? ''),
    ...tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.data ?? ''),
  ].join('\n');

  testWidgets(
    'oranlar %20 / %0,5 biçiminde gösterilir; varsayılan işaretlidir',
    (tester) async {
      await createRate('Standart', 2000);
      await createRate('Çok düşük', 50);

      await pumpScreen(tester);

      expect(find.textContaining('%20'), findsOneWidget);
      expect(find.textContaining('%0,5'), findsOneWidget);
      // OD-017: kurulumda nötr "%0 — KDV Yok" oranı vardır ve varsayılandır.
      expect(
        find.textContaining('· ${AppStringsTr.vatRateDefaultBadge}'),
        findsOneWidget,
      );
    },
  );

  testWidgets('SİL eylemi YOKTUR — docs/08 §4 · EC-VAT-003', (tester) async {
    await createRate('Standart', 2000);

    await pumpScreen(tester);

    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.text(AppStringsTr.deleteAction), findsNothing);
  });

  testWidgets('uyarıyı Esc ile kapatmak da VAZGEÇMEDİR — docs/08 §4', (
    tester,
  ) async {
    final id = await createRate('Standart', 2000);
    await attachProduct(id);

    await pumpScreen(tester);
    await tester.tap(find.byKey(VatRateManagementScreen.editButtonKey(id)));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('vat_rate_form_rate')), '10');
    await tester.tap(find.byKey(const Key('vat_rate_form_submit')));
    await pumpUntilConfirmDialog(tester);

    // "[Vazgeç]" butonu `pop(false)` yapar; `Esc` ise `null` döndürür —
    // ikisi AYRI kod yoludur. Bu test `?? false` varsayılanını korur:
    // `?? true` olsaydı Esc'e basan kullanıcının oranı SESSİZCE değişirdi.
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    final stored = await withServices(
      (container) => container.read(vatRateServiceProvider).findById(id),
    );
    expect(
      stored!.rateBasisPoints,
      2000,
      reason: 'Esc ile çıkışta oran değişmemelidir.',
    );
  });

  testWidgets(
    'oran DEĞİŞİKLİĞİNDE uyarı gösterilir ve [Vazgeç] değişikliği UYGULAMAZ — '
    'docs/08 §4 · BR-VAT-004',
    (tester) async {
      final id = await createRate('Standart', 2000);
      await attachProduct(id);

      await pumpScreen(tester);
      await tester.tap(find.byKey(VatRateManagementScreen.editButtonKey(id)));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('vat_rate_form_rate')), '10');
      await tester.tap(find.byKey(const Key('vat_rate_form_submit')));
      await pumpUntilConfirmDialog(tester);

      // docs/08 §4: uyarı metni + etkilenen ürün sayısı.
      expect(find.textContaining('1 üründe kullanılıyor'), findsOneWidget);
      expect(
        find.textContaining('Geçmiş satışların KDV tutarları değişmez'),
        findsOneWidget,
      );

      await tester.tap(
        find.byKey(VatRateManagementScreen.changeCancelButtonKey),
      );
      await tester.pumpAndSettle();

      // Vazgeçildi: kayıt değişmedi.
      final stored = await withServices(
        (container) => container.read(vatRateServiceProvider).findById(id),
      );
      expect(
        stored!.rateBasisPoints,
        2000,
        reason: '[Vazgeç] hiçbir değişikliği uygulamamalıdır.',
      );

      // [Değiştir] ise uygular.
      await tester.tap(find.byKey(const Key('vat_rate_form_submit')));
      await pumpUntilConfirmDialog(tester);
      await tester.tap(
        find.byKey(VatRateManagementScreen.changeConfirmButtonKey),
      );
      await tester.pumpAndSettle();

      final updated = await withServices(
        (container) => container.read(vatRateServiceProvider).findById(id),
      );
      expect(updated!.rateBasisPoints, 1000);
    },
  );

  testWidgets(
    'yalnızca AD değişiyorsa uyarı gösterilmez — docs/08 §4 (uyarı oran '
    'değeri içindir)',
    (tester) async {
      final id = await createRate('Standart', 2000);

      await pumpScreen(tester);
      await tester.tap(find.byKey(VatRateManagementScreen.editButtonKey(id)));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('vat_rate_form_name')),
        'Genel Oran',
      );
      await tester.tap(find.byKey(const Key('vat_rate_form_submit')));
      await tester.pumpAndSettle();

      expect(find.text(AppStringsTr.vatRateChangeWarningTitle), findsNothing);
      expect(find.text('Genel Oran'), findsOneWidget);
    },
  );

  testWidgets(
    'PASİF satırda "Varsayılan yap" SUNULMAZ — BR-VAT-006 · EC-VAT-001',
    (tester) async {
      final id = await createRate('Standart', 2000);
      await deactivate(id);

      await pumpScreen(tester);

      expect(
        find.byKey(VatRateManagementScreen.setDefaultButtonKey(id)),
        findsNothing,
        reason:
            'OD-019: pasif oran varsayılan yapılsaydı KDV sessizce %0 olurdu.',
      );
      expect(find.textContaining(AppStringsTr.statusInactive), findsOneWidget);
    },
  );

  testWidgets('aktif oran varsayılan yapılabilir — docs/04 §3.4', (
    tester,
  ) async {
    final id = await createRate('Standart', 2000);

    await pumpScreen(tester);
    await tester.tap(
      find.byKey(VatRateManagementScreen.setDefaultButtonKey(id)),
    );
    await tester.pumpAndSettle();

    final stored = await withServices(
      (container) => container.read(vatRateServiceProvider).defaultRate(),
    );
    expect(stored!.id, id);
    // Invariant: aynı anda tek varsayılan.
    expect(
      find.textContaining('· ${AppStringsTr.vatRateDefaultBadge}'),
      findsOneWidget,
    );
  });

  testWidgets('hatalı oran girdisi Türkçe örnekli mesajla reddedilir', (
    tester,
  ) async {
    await pumpScreen(tester);
    await tester.tap(find.byKey(VatRateManagementScreen.addButtonKey));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('vat_rate_form_name')),
      'Hatalı',
    );
    await tester.enterText(
      find.byKey(const Key('vat_rate_form_rate')),
      'yirmi',
    );
    await tester.tap(find.byKey(const Key('vat_rate_form_submit')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Örnek: 20 veya 0,5'), findsWidgets);

    // %20 biçimi de kabul edilmelidir (VatRateParser).
    await tester.enterText(find.byKey(const Key('vat_rate_form_rate')), '%20');
    await tester.tap(find.byKey(const Key('vat_rate_form_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Hatalı'), findsOneWidget);
    expect(find.textContaining('%20'), findsOneWidget);
  });

  testWidgets('ekranda teknik detay / hata kodu görünmez — REQ-SEC-007', (
    tester,
  ) async {
    final id = await createRate('Standart', 2000);
    await deactivate(id);

    await pumpScreen(tester);
    final text = visibleText(tester);

    expect(text.contains('vat_rate_'), isFalse);
    expect(text.contains('Exception'), isFalse);
    expect(text.contains('SQLITE'), isFalse);
  });
}
