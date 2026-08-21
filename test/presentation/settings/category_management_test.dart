/// Kategori yönetimi widget testleri — **docs/10 §1 · BR-CAT-002/004/005 ·
/// REQ-CAT-001/004/006 · EC-CAT-001/002/005/006**
///
/// docs/27 §4: widget testleri **seçicidir.** Buradaki testler sessizce
/// ihlal edilebilecek kategori kurallarını korur:
///
/// | Test | Kural |
/// |---|---|
/// | `Genel` için sil/pasifleştir/yeniden adlandır sunulmaz | BR-CAT-004 · EC-CAT-001 |
/// | Kalıcı silme **onay olmadan** çalışmaz | REQ-CAT-006 · rules/05 §5 |
/// | Kullanımdaki kategoride servis reddi gösterilir | EC-CAT-005 · EC-CAT-006 |
/// | Pasifleştirmede ürün sayısı + taşıma seçeneği | docs/10 §1.3 · EC-CAT-002 |
/// | Taşıma hedefinde pasif kategori ve kaynak yok | REQ-CAT-004 · docs/10 §1.3 |
/// | Ekranda teknik detay / hata kodu yok | REQ-UX-008 · REQ-SEC-007 |
///
/// Golden (piksel) testi **yazılmaz** (docs/27 §4).
library;

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/application/reference/providers.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Category, Product, Sale, SaleItem, StockMovement, Supplier, VatRate;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/presentation/settings/category_management_screen.dart';
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

  Future<int> createCategory(String name) async {
    final created = await withServices(
      (container) => container.read(categoryServiceProvider).create(name: name),
    );
    return created.valueOrNull!;
  }

  Future<void> deactivate(int id) => withServices(
    (container) => container.read(categoryServiceProvider).deactivate(id),
  );

  Future<int> systemCategoryId() async {
    final category = await withServices(
      (container) => container.read(categoryServiceProvider).systemCategory(),
    );
    return category!.id;
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [canteenDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: CategoryManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Ekranda görünen tüm metin.
  String visibleText(WidgetTester tester) => [
    ...tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? ''),
    ...tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.data ?? ''),
  ].join('\n');

  Future<String?> iconOf(int id) async => (await (db.select(
    db.categories,
  )..where((c) => c.id.equals(id))).getSingle()).iconKey;

  group('OD-029 · REQ-CAT-008 — kategori ikonu', () {
    testWidgets('yeni kategoriye ikon seçilebilir', (tester) async {
      await pumpScreen(tester);

      await tester.tap(find.byKey(CategoryManagementScreen.addButtonKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('category_form_name')),
        'Soğuk İçecek',
      );
      await tester.tap(find.byKey(const Key('category_form_icon_drink')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category_form_submit')));
      await tester.pumpAndSettle();

      final created = await withServices(
        (container) => container.read(categoryServiceProvider).list(),
      );
      final category = created.firstWhere((c) => c.name == 'Soğuk İçecek');
      expect(category.iconKey, 'drink');
    });

    testWidgets('"Otomatik" seçiliyken ikon YAZILMAZ', (tester) async {
      // Varsayılan seçim budur; kullanıcı ikon seçmek zorunda değildir.
      await pumpScreen(tester);

      await tester.tap(find.byKey(CategoryManagementScreen.addButtonKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('category_form_name')),
        'Raf 3',
      );
      await tester.tap(find.byKey(const Key('category_form_submit')));
      await tester.pumpAndSettle();

      final created = await withServices(
        (container) => container.read(categoryServiceProvider).list(),
      );
      expect(created.firstWhere((c) => c.name == 'Raf 3').iconKey, isNull);
    });

    testWidgets('mevcut kategorinin ikonu DEĞİŞTİRİLEBİLİR', (tester) async {
      final id = await createCategory('Deneme');
      await pumpScreen(tester);

      await tester.tap(
        find.byKey(CategoryManagementScreen.renameButtonKey(id)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category_form_icon_snack')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category_form_submit')));
      await tester.pumpAndSettle();

      expect(await iconOf(id), 'snack');
    });

    testWidgets('BR-CAT-004 — `Genel`in İKONU değiştirilebilir', (
      tester,
    ) async {
      // Koruma ad, silme ve pasifleştirme içindir; ikon o listede yoktur.
      // `Genel` için "yeniden adlandır" SUNULMAZ, bu yüzden ikon düzenleme
      // ayrı bir yoldan açılmalıdır.
      final id = await systemCategoryId();
      await pumpScreen(tester);

      expect(
        find.byKey(CategoryManagementScreen.iconKeyOf(id)),
        findsOneWidget,
        reason: '`Genel` için ikon düzenleme sunulmalıdır.',
      );

      await tester.tap(find.byKey(CategoryManagementScreen.iconKeyOf(id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category_form_icon_other')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('category_form_submit')));
      await tester.pumpAndSettle();

      expect(await iconOf(id), 'other');
    });
  });

  testWidgets('kategoriler listelenir; pasifler ikon + metinle işaretlenir', (
    tester,
  ) async {
    final id = await createCategory('Şekerleme');
    await deactivate(id);

    await pumpScreen(tester);

    expect(find.text('Şekerleme'), findsOneWidget);
    expect(
      find.textContaining(AppStringsTr.statusInactive),
      findsOneWidget,
      reason: 'rules/05 §5: pasiflik renkle değil, metinle de anlatılmalıdır.',
    );
    expect(find.byIcon(Icons.folder_off_outlined), findsOneWidget);
  });

  testWidgets(
    '"Genel" için sil / pasifleştir / yeniden adlandır SUNULMAZ — EC-CAT-001',
    (tester) async {
      final id = await systemCategoryId();

      await pumpScreen(tester);

      final rename = tester.widget<IconButton>(
        find.byKey(CategoryManagementScreen.renameButtonKey(id)),
      );
      final delete = tester.widget<IconButton>(
        find.byKey(CategoryManagementScreen.deleteButtonKey(id)),
      );
      final active = tester.widget<Switch>(
        find.byKey(CategoryManagementScreen.activeSwitchKey(id)),
      );

      expect(rename.onPressed, isNull, reason: 'BR-CAT-004: adı değişmez.');
      expect(delete.onPressed, isNull, reason: 'BR-CAT-004: silinemez.');
      expect(
        active.onChanged,
        isNull,
        reason: 'BR-CAT-004: pasifleştirilemez.',
      );
      // EC-CAT-001: "engellenir; SEBEP AÇIKLANIR".
      expect(
        find.textContaining(AppStringsTr.categorySystemBadge),
        findsOneWidget,
      );
    },
  );

  testWidgets('kalıcı silme ONAY OLMADAN çalışmaz — REQ-CAT-006', (
    tester,
  ) async {
    final id = await createCategory('Test Kategori');

    await pumpScreen(tester);
    await tester.tap(find.byKey(CategoryManagementScreen.deleteButtonKey(id)));
    await tester.pumpAndSettle();

    // REQ-CAT-006 acceptance criteria: onay metni kalıcılığı söyler.
    expect(find.textContaining('kalıcı olarak silinecek'), findsOneWidget);

    await tester.tap(
      find.byKey(CategoryManagementScreen.deleteCancelButtonKey),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Test Kategori'),
      findsOneWidget,
      reason: 'Vazgeçilen silme uygulanmamalıdır.',
    );

    await tester.tap(find.byKey(CategoryManagementScreen.deleteButtonKey(id)));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(CategoryManagementScreen.deleteConfirmButtonKey),
    );
    await tester.pumpAndSettle();

    expect(find.text('Test Kategori'), findsNothing);
  });

  testWidgets(
    'kullanımdaki kategori silinemez; servis reddi kullanıcıya gösterilir — '
    'EC-CAT-005/006',
    (tester) async {
      final id = await createCategory('İçecek');
      await insertTestProduct(db, name: 'Ayran', categoryId: id);

      await pumpScreen(tester);
      await tester.tap(
        find.byKey(CategoryManagementScreen.deleteButtonKey(id)),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(CategoryManagementScreen.deleteConfirmButtonKey),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(CategoryManagementScreen.messageKey), findsOneWidget);
      expect(find.textContaining('Bu kategori silinemez'), findsOneWidget);
      expect(
        find.text('İçecek'),
        findsOneWidget,
        reason: 'BR-CAT-005: kullanımdaki kategori silinmez.',
      );

      // REQ-SEC-007 · REQ-UX-008: hata kodu ve teknik detay sızmaz.
      final text = visibleText(tester);
      expect(text.contains('category_'), isFalse);
      expect(text.contains('Exception'), isFalse);
      expect(text.contains('SQLITE'), isFalse);
    },
  );

  testWidgets(
    'pasifleştirmede ürün sayısı ve taşıma seçeneği gösterilir — docs/10 §1.3',
    (tester) async {
      final id = await createCategory('Şekerleme');
      await insertTestProduct(db, name: 'Bonibon', categoryId: id);
      await insertTestProduct(db, name: 'Draje', categoryId: id);

      await pumpScreen(tester);
      await tester.tap(
        find.byKey(CategoryManagementScreen.activeSwitchKey(id)),
      );
      await tester.pumpAndSettle();

      // EC-CAT-002: ürün sayısı gösterilir.
      expect(find.textContaining('2 ürün'), findsOneWidget);
      // REQ-CAT-004: taşıma seçeneği sunulur.
      expect(
        find.byKey(CategoryManagementScreen.deactivateMoveButtonKey),
        findsOneWidget,
      );
      expect(
        find.byKey(CategoryManagementScreen.deactivateConfirmButtonKey),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'taşıma hedef listesinde PASİF kategoriler ve kaynağın kendisi yok — '
    'REQ-CAT-004',
    (tester) async {
      final sourceId = await createCategory('Şekerleme');
      final targetId = await createCategory('Atıştırmalık');
      final passiveId = await createCategory('Eski Kategori');
      await deactivate(passiveId);
      await insertTestProduct(db, name: 'Bonibon', categoryId: sourceId);

      await pumpScreen(tester);
      await tester.tap(
        find.byKey(CategoryManagementScreen.activeSwitchKey(sourceId)),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(CategoryManagementScreen.deactivateMoveButtonKey),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(CategoryManagementScreen.moveTargetKey(targetId)),
        findsOneWidget,
      );
      expect(
        find.byKey(CategoryManagementScreen.moveTargetKey(passiveId)),
        findsNothing,
        reason: 'docs/10 §1.3: pasif kategoriye yeni ürün ataması yapılamaz.',
      );
      expect(
        find.byKey(CategoryManagementScreen.moveTargetKey(sourceId)),
        findsNothing,
        reason: 'Kaynak kategori kendi hedefi olamaz.',
      );

      await tester.tap(
        find.byKey(CategoryManagementScreen.moveTargetKey(targetId)),
      );
      await tester.pumpAndSettle();

      // Taşıma sonrası akış aynı diyaloga güncel sayıyla döner; pasifleştirme
      // yine açık onay ister.
      expect(find.textContaining('Bu kategoride ürün yok'), findsOneWidget);
    },
  );
}
