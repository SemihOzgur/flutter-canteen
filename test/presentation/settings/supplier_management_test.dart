/// Tedarikçi yönetimi widget testleri — **docs/10 §2 · BR-SUP-002 ·
/// REQ-SUP-001/002/006 · EC-SUP-001/003**
///
/// docs/27 §4: widget testleri **seçicidir.** Buradaki testler sessizce
/// ihlal edilebilecek tedarikçi kurallarını korur:
///
/// | Test | Kural |
/// |---|---|
/// | **Sil** butonu yoktur | BR-SUP-002 · REQ-SUP-002 |
/// | Yalnızca ad ile tedarikçi eklenir | REQ-SUP-001 |
/// | Pasif tedarikçi listelenir ve geri alınabilir | REQ-SUP-006 · EC-SUP-003 |
/// | Ekranda teknik detay / hata kodu yok | REQ-UX-008 · REQ-SEC-007 |
///
/// Golden (piksel) testi **yazılmaz** (docs/27 §4).
library;

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/application/reference/providers.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Category, Product, Sale, SaleItem, StockMovement, Supplier, VatRate;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/presentation/settings/supplier_management_screen.dart';
import 'package:flutter/material.dart';
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

  Future<int> createSupplier(String name) async {
    final created = await withServices(
      (container) => container.read(supplierServiceProvider).create(name: name),
    );
    return created.valueOrNull!;
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [canteenDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: SupplierManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  String visibleText(WidgetTester tester) => [
    ...tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? ''),
    ...tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.data ?? ''),
  ].join('\n');

  testWidgets('tedarikçiler listelenir; pasifler de görünür — REQ-SUP-006', (
    tester,
  ) async {
    await createSupplier('Anadolu Gıda');
    final passiveId = await createSupplier('Eski Tedarikçi');
    await withServices(
      (container) =>
          container.read(supplierServiceProvider).deactivate(passiveId),
    );

    await pumpScreen(tester);

    expect(find.text('Anadolu Gıda'), findsOneWidget);
    expect(find.text('Eski Tedarikçi'), findsOneWidget);
    expect(
      find.textContaining(AppStringsTr.statusInactive),
      findsOneWidget,
      reason: 'rules/05 §5: pasiflik metinle de anlatılmalıdır.',
    );
  });

  testWidgets('SİL butonu YOKTUR — BR-SUP-002 · REQ-SUP-002', (tester) async {
    await createSupplier('Anadolu Gıda');

    await pumpScreen(tester);

    expect(
      find.byIcon(Icons.delete_outline),
      findsNothing,
      reason: 'BR-SUP-002: tedarikçi silinmez, yalnızca pasifleştirilir.',
    );
    expect(find.text(AppStringsTr.deleteAction), findsNothing);
  });

  testWidgets('yalnızca ad ile tedarikçi eklenebilir — REQ-SUP-001', (
    tester,
  ) async {
    await pumpScreen(tester);

    // REQ-UX-011: boş durum eyleme yönlendirir.
    expect(find.text(AppStringsTr.suppliersEmpty), findsOneWidget);

    await tester.tap(find.byKey(SupplierManagementScreen.addButtonKey));
    await tester.pumpAndSettle();

    // Ad boşken kaydedilemez; diğer alanların hiçbiri zorunlu değildir.
    await tester.tap(find.byKey(const Key('supplier_form_submit')));
    await tester.pumpAndSettle();
    expect(find.text(AppStringsTr.supplierNameRequired), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('supplier_form_name')),
      'Anadolu Gıda',
    );
    await tester.tap(find.byKey(const Key('supplier_form_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Anadolu Gıda'), findsOneWidget);
  });

  testWidgets('pasifleştirme geri alınabilir — EC-SUP-003 (OD-020)', (
    tester,
  ) async {
    final id = await createSupplier('Anadolu Gıda');

    await pumpScreen(tester);
    await tester.tap(find.byKey(SupplierManagementScreen.activeSwitchKey(id)));
    await tester.pumpAndSettle();
    expect(find.textContaining(AppStringsTr.statusInactive), findsOneWidget);

    await tester.tap(find.byKey(SupplierManagementScreen.activeSwitchKey(id)));
    await tester.pumpAndSettle();
    expect(find.textContaining(AppStringsTr.statusActive), findsOneWidget);
  });

  testWidgets('ekranda teknik detay / hata kodu görünmez — REQ-SEC-007', (
    tester,
  ) async {
    await createSupplier('Anadolu Gıda');

    await pumpScreen(tester);
    final text = visibleText(tester);

    expect(text.contains('supplier_'), isFalse);
    expect(text.contains('Exception'), isFalse);
    expect(text.contains('SQLITE'), isFalse);
  });
}
