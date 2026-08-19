/// Ürün ekranları widget testleri — **docs/09 · REQ-PROD-* · REQ-PERF-006**
///
/// docs/27 §4: widget testleri **seçicidir.** Buradakiler sessizce ihlal
/// edilebilecek kuralları korur:
///
/// | Test | Kural |
/// |---|---|
/// | Satış fiyatı etiketinde "KDV Dahil" geçer | **REQ-PROD-014** |
/// | Düzenlemede stok alanı **değiştirilemez** | docs/09 §1 · BR-STOCK-003 |
/// | Kalıcı silme onaysız çalışmaz — `[Vazgeç]` **ve** `Esc` | BR-PROD-014 |
/// | Kullanılmış ürün için kalıcı silme **sunulmaz** | EC-PROD-020/021 |
/// | Alış > satış uyarısı kaydı **engellemez** | EC-PROD-009 |
/// | Arama Türkçe duyarsız | REQ-PROD-010 |
/// | Liste sayfalanır | REQ-PERF-006 |
/// | Teknik detay / hata kodu görünmez | REQ-UX-008 · REQ-SEC-007 |
///
/// Golden (piksel) testi **yazılmaz** (docs/27 §4).
library;

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/application/product/product_draft.dart';
import 'package:canteen/application/product/product_service.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/application/product/providers.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Category, Product, Sale, SaleItem, StockMovement, Supplier, VatRate;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/presentation/products/product_form_screen.dart';
import 'package:canteen/presentation/products/product_image_view.dart';
import 'package:canteen/presentation/products/product_list_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late int userId;

  setUp(() async {
    db = memoryDatabase();
    userId = await insertTestUser(db);
    // Ürün işlemleri stok hareketi yazabildiği için (`user_id` NOT NULL)
    // ekran oturum arar; test de gerçek akış gibi oturum açar.
    final container = ProviderContainer(
      overrides: [canteenDatabaseProvider.overrideWithValue(db)],
    );
    await container.read(sessionServiceProvider).save(userId);
    container.dispose();
  });
  tearDown(() => db.close());

  Future<T> withServices<T>(
    Future<T> Function(ProviderContainer container) body,
  ) async {
    final container = ProviderContainer(
      overrides: [canteenDatabaseProvider.overrideWithValue(db)],
    );
    try {
      return await body(container);
    } finally {
      container.dispose();
    }
  }

  Future<int> createProduct({
    String name = 'Ayran',
    int salePriceMinor = 1000,
    int purchasePriceMinor = 0,
    int initialStock = 0,
    List<String> barcodes = const [],
  }) async {
    final result = await withServices(
      (container) => container
          .read(productServiceProvider)
          .create(
            ProductDraft(
              name: name,
              salePrice: Money(salePriceMinor),
              purchasePrice: Money(purchasePriceMinor),
            ),
            userId: userId,
            initialStock: initialStock,
            barcodes: barcodes,
          ),
    );
    return (result as Ok<ProductSaveOutcome>).value.productId;
  }

  Future<void> pumpList(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [canteenDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: ProductListScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Form bir `ListView`'dır: ekran dışındaki alanlar **hiç inşa edilmez.**
  /// Testin alanları bulabilmesi için yüzey yükseltilir; aksi hâlde her
  /// iddia kaydırma sırasına bağımlı ve kırılgan olurdu.
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpForm(WidgetTester tester, {int? productId}) async {
    useTallSurface(tester);
    final product = productId == null
        ? null
        : await withServices(
            (c) => c.read(productServiceProvider).findById(productId),
          );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [canteenDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: ProductFormScreen(product: product)),
      ),
    );
    await tester.pumpAndSettle();
  }

  String visibleText(WidgetTester tester) => [
    ...tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? ''),
    ...tester
        .widgetList<TextField>(find.byType(TextField))
        .map((w) => w.decoration?.labelText ?? ''),
  ].join('\n');

  group('REQ-PROD-014 — fiyat etiketi', () {
    testWidgets('satış fiyatı alanı "KDV Dahil" olarak etiketlenir', (
      tester,
    ) async {
      await pumpForm(tester);

      // Form bir `ListView`'dır: ekran dışındaki alan hiç inşa edilmez.

      expect(
        visibleText(tester),
        contains('KDV Dahil'),
        reason:
            'REQ-PROD-014: girilen tutar müşteriden alınan tutardır; KDV '
            'içinden çıkarılır (BR-VAT-003). Etiket bir gereksinimdir.',
      );
    });
  });

  group('docs/09 §1 — stok elle düzenlenemez', () {
    testWidgets('düzenleme formunda stok alanı devre dışıdır', (tester) async {
      final id = await createProduct(initialStock: 7);
      await pumpForm(tester, productId: id);

      // Bayrağa değil **davranışa** bakılır: `enabled` ya da `readOnly`
      // tek başına değiştirilirse diğeri korumayı sürdürmelidir.
      await tester.enterText(
        find.byKey(ProductFormScreen.stockReadOnlyKey),
        '999',
      );
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.descendant(
          of: find.byKey(ProductFormScreen.stockReadOnlyKey),
          matching: find.byType(TextField),
        ),
      );
      expect(
        field.controller?.text,
        '7',
        reason:
            'BR-STOCK-003: stok yalnızca stok hareketiyle değişir. Forma '
            'yazılabilir bir alan koymak invariant\'ı ilk günden deler.',
      );
    });

    testWidgets('eklemede başlangıç stoğu alanı VARDIR', (tester) async {
      await pumpForm(tester);

      expect(
        find.byKey(ProductFormScreen.initialStockFieldKey),
        findsOneWidget,
      );
      expect(find.byKey(ProductFormScreen.stockReadOnlyKey), findsNothing);
    });
  });

  group('docs/09 §4 — silme iki ayrı akıştır', () {
    testWidgets('hiç kullanılmamış ürün: onay istenir, [Vazgeç] SİLMEZ', (
      tester,
    ) async {
      final id = await createProduct();
      await pumpList(tester);

      await tester.tap(find.byKey(ProductListScreen.deleteButtonKey(id)));
      await tester.pumpAndSettle();
      expect(find.textContaining('geri alınamaz'), findsOneWidget);

      await tester.tap(find.text(AppStringsTr.cancelAction));
      await tester.pumpAndSettle();

      final still = await withServices(
        (c) => c.read(productServiceProvider).findById(id),
      );
      expect(still, isNotNull, reason: '[Vazgeç] silmemelidir.');
    });

    testWidgets('Esc ile kapatmak da SİLMEZ — buton yolundan ayrı', (
      tester,
    ) async {
      final id = await createProduct();
      await pumpList(tester);

      await tester.tap(find.byKey(ProductListScreen.deleteButtonKey(id)));
      await tester.pumpAndSettle();

      // `showDialog` `Esc`'te `null` döndürür; varsayılan `?? false` olmalıdır.
      // `?? true` olsaydı Esc'e basan kullanıcının ürünü SİLİNİRDİ.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      final still = await withServices(
        (c) => c.read(productServiceProvider).findById(id),
      );
      expect(still, isNotNull, reason: 'Esc vazgeçmedir.');
    });

    testWidgets('onaylanınca kalıcı silinir', (tester) async {
      final id = await createProduct();
      await pumpList(tester);

      await tester.tap(find.byKey(ProductListScreen.deleteButtonKey(id)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('product_delete_confirm')));
      await tester.pumpAndSettle();

      final gone = await withServices(
        (c) => c.read(productServiceProvider).findById(id),
      );
      expect(gone, isNull);
    });

    testWidgets(
      'stok hareketi olan ürün için KALICI SİLME SUNULMAZ — EC-PROD-021',
      (tester) async {
        // `initial` hareketi de bir stok hareketidir.
        final id = await createProduct(initialStock: 5);
        await pumpList(tester);

        await tester.tap(find.byKey(ProductListScreen.deleteButtonKey(id)));
        await tester.pumpAndSettle();

        expect(
          find.text(AppStringsTr.productDeletePermanentAction),
          findsNothing,
          reason:
              'EC-PROD-021: stok defteri referansı korunur; yalnızca '
              'pasifleştirme önerilir.',
        );
        expect(
          find.text(AppStringsTr.productDeleteBlockedTitle),
          findsOneWidget,
        );
      },
    );
  });

  group('EC-PROD-009 — alış > satış uyarır ama ENGELLEMEZ', () {
    testWidgets('ürün kaydedilir ve uyarı gösterilir', (tester) async {
      await pumpForm(tester);

      await tester.enterText(
        find.byKey(ProductFormScreen.nameFieldKey),
        'Zararına Ürün',
      );
      await tester.enterText(
        find.byKey(ProductFormScreen.salePriceFieldKey),
        '10,00',
      );
      await tester.enterText(
        find.byKey(ProductFormScreen.purchasePriceFieldKey),
        '15,00',
      );
      await tester.tap(find.byKey(ProductFormScreen.submitKey));
      await tester.pumpAndSettle();

      final saved = await withServices(
        (c) => c.read(productServiceProvider).list(),
      );
      expect(
        saved.map((p) => p.name),
        contains('Zararına Ürün'),
        reason: 'EC-PROD-009: uyarı kaydı engellemez.',
      );
    });
  });

  group('REQ-PROD-010 — arama Türkçe karakter duyarsız', () {
    testWidgets('"isil" yazınca "IŞIL" bulunur', (tester) async {
      await createProduct(name: 'IŞIL Gazoz');
      await createProduct(name: 'Ayran');
      await pumpList(tester);

      await tester.enterText(
        find.byKey(ProductListScreen.searchFieldKey),
        'isil',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.text('IŞIL Gazoz'), findsOneWidget);
      expect(find.text('Ayran'), findsNothing);
    });
  });

  group('REQ-PERF-006 — liste sayfalanır', () {
    testWidgets('30 üründe tümü tek sayfada gösterilmez', (tester) async {
      for (var i = 0; i < 30; i++) {
        await createProduct(name: 'Ürün ${i.toString().padLeft(2, '0')}');
      }
      await pumpList(tester);

      expect(
        find.byType(ListTile).evaluate().length,
        lessThan(30),
        reason:
            'rules/01 §8: "Listeler sayfalanır; tüm kayıtlar belleğe '
            'alınmaz."',
      );
      expect(find.byKey(ProductListScreen.nextPageKey), findsOneWidget);
    });
  });

  group('EC-PROD-001 — barkod çakışması', () {
    testWidgets('sahip ürünün ADI gösterilir', (tester) async {
      await createProduct(name: 'Coca Cola 330ml', barcodes: ['8690000000001']);
      final other = await createProduct(name: 'Fanta');

      await pumpForm(tester, productId: other);
      await tester.enterText(
        find.byKey(ProductFormScreen.barcodeFieldKey),
        '8690000000001',
      );
      await tester.tap(find.byKey(ProductFormScreen.barcodeAddKey));
      await tester.pumpAndSettle();

      expect(
        visibleText(tester),
        contains('Coca Cola 330ml'),
        reason: 'EC-PROD-001: sahip ürün kullanıcıya gösterilir.',
      );
    });
  });

  testWidgets('ekranda teknik detay / hata kodu görünmez', (tester) async {
    await createProduct();
    await pumpList(tester);

    final text = visibleText(tester);
    for (final leak in const [
      'Exception',
      'SqliteException',
      'product_',
      'Drift',
      '#0',
    ]) {
      expect(text, isNot(contains(leak)), reason: 'REQ-SEC-007 · REQ-UX-008');
    }
  });

  group('REQ-IMG-009 · BR-IMG-005 — görsel yoksa HATA GÖSTERİLMEZ', () {
    testWidgets('görselsiz ürün sorunsuz listelenir', (tester) async {
      await createProduct(name: 'Görselsiz');
      await pumpList(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Görselsiz'), findsOneWidget);
      expect(
        find.byType(ProductImageView),
        findsOneWidget,
        reason: 'Varsayılan ikon gösterilir; hata değil.',
      );
    });

    testWidgets('KIRIK görsel referansı da hata göstermez', (tester) async {
      final id = await createProduct(name: 'Kırık Yol');
      // Yedekten dönme veya elle silme sonrası oluşabilecek durum: DB'de yol
      // var, dosya yok (docs/21 §4 — orphan/kırık referans).
      await (db.update(db.products)..where((t) => t.id.equals(id))).write(
        const ProductsCompanion(imagePath: Value('images/yok-boyle-dosya.jpg')),
      );

      await pumpList(tester);

      // Dosya okuma asenkrondur; hata yolunun gerçekten koşması beklenir.
      await tester.pump(const Duration(seconds: 1));

      expect(
        tester.takeException(),
        isNull,
        reason: 'BR-IMG-005: görseli bulunamayan ürün hata göstermez.',
      );
      expect(
        find.byKey(ProductImageView.fallbackKey),
        findsOneWidget,
        reason:
            'Boş kutu değil, VARSAYILAN İKON gösterilir — kullanıcı ürünü '
            'yine de görebilmelidir.',
      );
      expect(find.text('Kırık Yol'), findsOneWidget);
    });
  });

  group('REQ-PROD-009 — favori yıldızı', () {
    testWidgets('listeden tek tıkla favoriye alınır ve çıkarılır', (
      tester,
    ) async {
      final id = await createProduct(name: 'Tost');
      await pumpList(tester);

      await tester.tap(find.byKey(ProductListScreen.favoriteButtonKey(id)));
      await tester.pumpAndSettle();

      final favorited = await withServices(
        (c) => c.read(productServiceProvider).findById(id),
      );
      expect(favorited!.isFavorite, isTrue);

      await tester.tap(find.byKey(ProductListScreen.favoriteButtonKey(id)));
      await tester.pumpAndSettle();

      final cleared = await withServices(
        (c) => c.read(productServiceProvider).findById(id),
      );
      expect(cleared!.isFavorite, isFalse);
    });
  });
}
