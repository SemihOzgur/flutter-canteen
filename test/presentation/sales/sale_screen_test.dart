/// Satış ekranı widget testleri — **docs/12 · docs/23 · REQ-UX-001…005/010/014
/// · REQ-BARC-004…007/012 · REQ-STOCK-005**
///
/// docs/27 §4: widget testleri **seçicidir.** Buradakiler sessizce ihlal
/// edilebilecek kuralları korur:
///
/// | Test | Kural |
/// |---|---|
/// | Sepet paneli hiçbir çözünürlükte gizlenmez | REQ-UX-005 · rules/05 §2 |
/// | Okutulan ürün **ara onay olmadan** eklenir | REQ-BARC-004 |
/// | Tekrar okutma miktarı artırır | REQ-BARC-005 |
/// | Bilinmeyen barkod → barkod alanı **dolu ve salt okunur** | REQ-BARC-006 |
/// | Kaydedilen ürün **otomatik** sepete girer | REQ-BARC-007 |
/// | İptal edilirse ürün oluşmaz, sepete bir şey eklenmez | docs/11 §4.2 |
/// | Barkodsuz ürün **tıklanarak** eklenir | REQ-CART-009 · REQ-BARC-012 |
/// | Yazınca odak döner ve **karakter kaybolmaz** | REQ-UX-003 |
/// | Stok uyarısı engellemez — `[İptal]` **ve** `Esc` | BR-STOCK-006 |
/// | Boş sepette tamamlama kapalıdır | BR-CART-005 · EC-SALE-001 |
/// | Yetersiz nakitte "Tamamla" pasiftir | BR-SALE-008 · EC-SALE-009 |
/// | Sepeti temizleme onaysız çalışmaz — `[Vazgeç]` **ve** `Esc` | REQ-UX-009 |
///
/// Golden (piksel) testi **yazılmaz** (docs/27 §4).
library;

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/application/product/product_draft.dart';
import 'package:canteen/application/product/product_service.dart';
import 'package:canteen/application/product/providers.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/money/money_formatter.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, Category, Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/presentation/sales/cart_panel.dart';
import 'package:canteen/presentation/sales/product_picker.dart';
import 'package:canteen/presentation/sales/sale_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late int userId;
  late DateTime now;

  setUp(() async {
    now = testEpochUtc;
    db = memoryDatabase();
    userId = await insertTestUser(db);
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
    int initialStock = 10,
    List<String> barcodes = const [],
    bool isFavorite = false,
  }) async {
    final result = await withServices(
      (container) => container
          .read(productServiceProvider)
          .create(
            ProductDraft(name: name, salePrice: Money(salePriceMinor)),
            userId: userId,
            initialStock: initialStock,
            barcodes: barcodes,
            isFavorite: isFavorite,
          ),
    );
    return (result as Ok<ProductSaveOutcome>).value.productId;
  }

  /// docs/23 §4 — desteklenen **minimum** çözünürlük.
  void useSalesSurface(
    WidgetTester tester, {
    Size size = const Size(1366, 768),
  }) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpSale(WidgetTester tester, {Size? size}) async {
    useSalesSurface(tester, size: size ?? const Size(1366, 768));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [canteenDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: SaleScreen(clock: () => now)),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Scanner hızında okutur — karakterler arası 5 ms, sonunda `Enter`.
  ///
  /// Saat enjekte edildiği için eşikler **gerçek beklemeye** bağlı değildir
  /// (rules/06 §7): makinenin yükü testi etkilemez.
  Future<void> scan(WidgetTester tester, String barcode) async {
    for (final char in barcode.split('')) {
      await tester.sendKeyEvent(_keyFor(char), character: char);
      now = now.add(const Duration(milliseconds: 5));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
  }

  Future<void> press(
    WidgetTester tester,
    LogicalKeyboardKey key, {
    bool control = false,
  }) async {
    if (control) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    }
    await tester.sendKeyEvent(key);
    if (control) {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
    await tester.pumpAndSettle();
  }

  /// **Aktif** sepetin satır sayısı.
  ///
  /// Tamamlanan satış eski sepeti `closed` yapar ama satırlarını silmez
  /// (docs/12 §6.2 adım 4) — ham `cart_items` sayımı bu yüzden satıştan sonra
  /// sıfırlanmaz ve yanlış soruya cevap verirdi.
  Future<List<CartItem>> activeCartLines() async {
    final cart = await CartsDao(db).findActive();
    if (cart == null) return const [];
    return CartItemsDao(db).listOfCart(cart.id);
  }

  Future<int> cartLineCount() async => (await activeCartLines()).length;

  // -------------------------------------------------------------------------

  group('REQ-UX-005 · rules/05 §2 — sepet paneli gizlenmez', () {
    testWidgets('1366×768 minimumda sepet paneli görünür', (tester) async {
      await createProduct();
      await pumpSale(tester);

      expect(find.byType(CartPanel), findsOneWidget);
      expect(find.byType(ProductPicker), findsOneWidget);
    });

    testWidgets('dar pencerede de sepet paneli KORUNUR', (tester) async {
      await createProduct();
      await pumpSale(tester, size: const Size(1280, 720));

      expect(
        find.byType(CartPanel),
        findsOneWidget,
        reason:
            'rules/05 §2: sepet paneli hiçbir çözünürlükte gizlenmez veya '
            'sekmeye dönüşmez.',
      );
    });

    testWidgets('REQ-UX-014 — toplam 32 px kalın gösterilir', (tester) async {
      await createProduct();
      await pumpSale(tester);

      final total = tester.widget<Text>(find.byKey(CartPanel.totalKey));
      expect(total.style?.fontSize, 32);
      expect(total.style?.fontWeight, FontWeight.bold);
    });
  });

  group('REQ-BARC-004/005 — okutma', () {
    testWidgets('bulunan ürün ARA ONAY OLMADAN sepete eklenir', (tester) async {
      await createProduct(name: 'Kola', barcodes: ['8690000000001']);
      await pumpSale(tester);

      await scan(tester, '8690000000001');

      expect(
        find.byType(AlertDialog),
        findsNothing,
        reason: 'docs/12 §2: akışı kesen dialog YASAKTIR.',
      );
      expect(find.text('Kola'), findsWidgets);
      expect(await cartLineCount(), 1);
    });

    testWidgets('aynı barkod tekrar okutulunca MİKTAR artar', (tester) async {
      await createProduct(name: 'Kola', barcodes: ['8690000000001']);
      await pumpSale(tester);

      await scan(tester, '8690000000001');
      await scan(tester, '8690000000001');

      expect(await cartLineCount(), 1, reason: 'Yeni satır AÇILMAZ.');
      final line = (await activeCartLines()).single;
      expect(line.quantity, 2);
    });
  });

  group('REQ-BARC-006/007 — bilinmeyen barkod', () {
    testWidgets('hızlı ürün dialogu açılır, barkod DOLU ve SALT OKUNUR', (
      tester,
    ) async {
      await pumpSale(tester);

      await scan(tester, '8690000000009');

      expect(
        find.byKey(const Key('sale_quick_product_dialog')),
        findsOneWidget,
      );
      final field = tester.widget<TextField>(
        find.byKey(const Key('sale_quick_barcode_field')),
      );
      expect(field.controller!.text, '8690000000009');
      expect(field.readOnly, isTrue);
    });

    testWidgets('kaydedilen ürün OTOMATİK sepete eklenir', (tester) async {
      await pumpSale(tester);

      await scan(tester, '8690000000009');
      await tester.enterText(
        find.byKey(const Key('sale_quick_name_field')),
        'Yeni Gofret',
      );
      await tester.enterText(
        find.byKey(const Key('sale_quick_price_field')),
        '12,50',
      );
      await tester.tap(find.byKey(const Key('sale_quick_submit')));
      await tester.pumpAndSettle();

      expect(await cartLineCount(), 1);
      final line = (await activeCartLines()).single;
      expect(line.unitPriceMinor, 1250);

      // Ürün ve barkodu gerçekten oluşmuştur (docs/11 §4.2 — tek transaction).
      final products = await db.select(db.products).get();
      expect(products.single.name, 'Yeni Gofret');
      final barcodes = await db.select(db.productBarcodes).get();
      expect(barcodes.single.barcode, '8690000000009');
    });

    testWidgets('İPTAL edilirse ürün oluşmaz, sepete bir şey eklenmez', (
      tester,
    ) async {
      await pumpSale(tester);

      await scan(tester, '8690000000009');
      await tester.tap(find.text(AppStringsTr.cancelAction));
      await tester.pumpAndSettle();

      expect(await db.select(db.products).get(), isEmpty);
      expect(await cartLineCount(), 0);
    });

    testWidgets('ürün adı boşsa kaydedilmez', (tester) async {
      await pumpSale(tester);

      await scan(tester, '8690000000009');
      await tester.enterText(
        find.byKey(const Key('sale_quick_price_field')),
        '10',
      );
      await tester.tap(find.byKey(const Key('sale_quick_submit')));
      await tester.pumpAndSettle();

      expect(find.text(AppStringsTr.saleQuickAddNameRequired), findsOneWidget);
      expect(await db.select(db.products).get(), isEmpty);
    });
  });

  group('REQ-CART-009 · REQ-BARC-012 — barkodsuz ürün', () {
    testWidgets('ürün kartına tıklayarak sepete eklenir', (tester) async {
      final id = await createProduct(name: 'Poğaça', salePriceMinor: 1500);
      await pumpSale(tester);

      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();

      expect(await cartLineCount(), 1);
      expect(find.byKey(CartPanel.totalKey), findsOneWidget);
      expect(find.text(MoneyFormatter.format(const Money(1500))), findsWidgets);
    });

    testWidgets('favoriden eklenir', (tester) async {
      final id = await createProduct(name: 'Çay', isFavorite: true);
      await pumpSale(tester);

      await tester.tap(find.byKey(Key('sale_favorite_$id')));
      await tester.pumpAndSettle();

      expect(await cartLineCount(), 1);
    });
  });

  group('REQ-UX-002/003 — odak yönetimi', () {
    testWidgets('açılışta odak arama girişindedir', (tester) async {
      await createProduct();
      await pumpSale(tester);

      final field = tester.widget<TextField>(
        find.byKey(SaleScreen.searchFieldKey),
      );
      expect(field.focusNode!.hasFocus, isTrue);
    });

    testWidgets('sepette gezinirken yazınca odak DÖNER ve KARAKTER KAYBOLMAZ', (
      tester,
    ) async {
      final id = await createProduct(name: 'Kola');
      await pumpSale(tester);
      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();

      // Kullanıcı `Tab` ile başka bir öğeye geçer (docs/23 §7 — tüm
      // etkileşimli öğelere `Tab` ile ulaşılır). Kasada odak sürekli böyle
      // kayar — ve tam o anda barkod okutulur veya ürün adı yazılır.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(SaleScreen.searchFieldKey),
      );
      expect(
        field.focusNode!.hasFocus,
        isFalse,
        reason: 'Ön koşul: odak arama kutusundan ÇIKMIŞ olmalı.',
      );

      // Yazmaya başlar.
      await tester.sendKeyEvent(LogicalKeyboardKey.keyK, character: 'K');
      await tester.pumpAndSettle();

      expect(field.focusNode!.hasFocus, isTrue, reason: 'REQ-UX-002/003');
      expect(
        field.controller!.text,
        'K',
        reason:
            'REQ-UX-003: girilen ilk karakter KAYBOLMAZ. Yalnızca odaklamak '
            'yetmez — requestFocus bir sonraki frame\'de etkili olur ve o '
            'tuş vuruşu hiçbir alana ulaşmazdı.',
      );
    });

    testWidgets('satış tamamlandıktan sonra odak arama girişine döner', (
      tester,
    ) async {
      final id = await createProduct();
      await pumpSale(tester);
      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(CartPanel.completeButtonKey));
      await tester.pumpAndSettle();

      final field = tester.widget<TextField>(
        find.byKey(SaleScreen.searchFieldKey),
      );
      expect(field.focusNode!.hasFocus, isTrue);
    });
  });

  group('docs/12 §6 — satışı tamamlama', () {
    testWidgets('EC-SALE-001 — boş sepette tamamlama KAPALIDIR', (
      tester,
    ) async {
      await createProduct();
      await pumpSale(tester);

      final button = tester.widget<FilledButton>(
        find.byKey(CartPanel.completeButtonKey),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('F12 satışı tamamlar, sepet boşalır, fiş no gösterilir', (
      tester,
    ) async {
      final id = await createProduct(name: 'Kola', salePriceMinor: 2500);
      await pumpSale(tester);
      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.f12);

      expect(await db.select(db.sales).get(), hasLength(1));
      expect(await cartLineCount(), 0);
      expect(find.textContaining('2026-000001'), findsOneWidget);
      expect(find.text(AppStringsTr.saleCartEmptyTitle), findsOneWidget);
    });

    testWidgets('satış stok defterine `sale` hareketi yazar', (tester) async {
      final id = await createProduct(initialStock: 10);
      await pumpSale(tester);
      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.f12);

      final movements = await db.select(db.stockMovements).get();
      // İlki `initial`, ikincisi `sale`.
      expect(movements, hasLength(2));
      expect(movements.last.quantityDelta, -1);
    });
  });

  group('docs/12 §5 — nakit (F4)', () {
    testWidgets('EC-SALE-009 — yetersiz tutarda "Tamamla" PASİFTİR', (
      tester,
    ) async {
      final id = await createProduct(salePriceMinor: 13500);
      await pumpSale(tester);
      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.f4);
      await tester.enterText(
        find.byKey(const Key('sale_cash_field')),
        '100,00',
      );
      await tester.pumpAndSettle();

      final submit = tester.widget<FilledButton>(
        find.byKey(const Key('sale_cash_submit')),
      );
      expect(submit.onPressed, isNull);
      expect(find.text(AppStringsTr.saleCashInsufficient), findsOneWidget);
    });

    testWidgets('para üstü canlı hesaplanır ve satışa yazılır', (tester) async {
      final id = await createProduct(salePriceMinor: 13500);
      await pumpSale(tester);
      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.f4);
      await tester.enterText(
        find.byKey(const Key('sale_cash_field')),
        '200,00',
      );
      await tester.pumpAndSettle();
      expect(find.text(MoneyFormatter.format(const Money(6500))), findsWidgets);

      await tester.tap(find.byKey(const Key('sale_cash_submit')));
      await tester.pumpAndSettle();

      final sale = (await db.select(db.sales).get()).single;
      expect(sale.cashReceivedMinor, 20000);
      expect(sale.changeMinor, 6500);
    });
  });

  group('BR-STOCK-006 · REQ-STOCK-005 — negatif stok', () {
    testWidgets('uyarı gösterilir, "Devam Et" satırı EKLER', (tester) async {
      final id = await createProduct(name: 'Kola', initialStock: 0);
      await pumpSale(tester);

      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const Key('sale_stock_warning_dialog')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('sale_stock_warning_continue')));
      await tester.pumpAndSettle();

      expect(
        await cartLineCount(),
        1,
        reason: 'BR-STOCK-006: stok satışı ENGELLEMEZ.',
      );
    });

    testWidgets('"İptal" satırı EKLEMEZ', (tester) async {
      final id = await createProduct(initialStock: 0);
      await pumpSale(tester);

      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStringsTr.cancelAction));
      await tester.pumpAndSettle();

      expect(await cartLineCount(), 0);
    });

    testWidgets('Esc de satırı EKLEMEZ — ayrı kod yolu', (tester) async {
      // `[İptal]` açıkça `false` döndürür; `Esc` ve bariyer `null` döndürür.
      // `?? false` olmasaydı Esc sessizce "Devam Et" sayılırdı.
      final id = await createProduct(initialStock: 0);
      await pumpSale(tester);

      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(await cartLineCount(), 0);
    });

    testWidgets('docs/13 §4 — aynı ürün için uyarı BİR KEZ gösterilir', (
      tester,
    ) async {
      final id = await createProduct(initialStock: 0);
      await pumpSale(tester);

      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sale_stock_warning_continue')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('sale_stock_warning_dialog')),
        findsNothing,
        reason: '"Aynı satış içinde aynı ürün için uyarı bir kez gösterilir."',
      );
      final line = (await activeCartLines()).single;
      expect(line.quantity, 2);
    });

    testWidgets('tükenmiş satır sepette İŞARETLENİR', (tester) async {
      final id = await createProduct(initialStock: 0);
      await pumpSale(tester);
      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sale_stock_warning_continue')));
      await tester.pumpAndSettle();

      final line = (await activeCartLines()).single;
      expect(
        find.byKey(Key('sale_badge_stock_${line.id}')),
        findsOneWidget,
        reason: 'docs/13 §4: uyarı kapalı olsa bile satır işaretlenir.',
      );
    });
  });

  group('docs/12 §4 — satır fiyatı (F2)', () {
    testWidgets('fiyat değişir, rozet görünür, ürünün fiyatı DEĞİŞMEZ', (
      tester,
    ) async {
      final id = await createProduct(name: 'Kola', salePriceMinor: 2500);
      await pumpSale(tester);
      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.f2);
      expect(find.byKey(const Key('sale_price_dialog')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('sale_price_field')),
        '20,00',
      );
      await tester.tap(find.byKey(const Key('sale_price_apply')));
      await tester.pumpAndSettle();

      final line = (await activeCartLines()).single;
      expect(line.unitPriceMinor, 2000);
      expect(line.isPriceOverridden, isTrue);
      expect(
        find.byKey(Key('sale_badge_overridden_${line.id}')),
        findsOneWidget,
      );

      final product = (await db.select(db.products).get()).single;
      expect(product.salePriceMinor, 2500, reason: 'BR-SALE-003');
    });

    testWidgets('EC-SALE-007 — negatif fiyat reddedilir', (tester) async {
      final id = await createProduct();
      await pumpSale(tester);
      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.f2);
      await tester.enterText(
        find.byKey(const Key('sale_price_field')),
        '-5,00',
      );
      await tester.tap(find.byKey(const Key('sale_price_apply')));
      await tester.pumpAndSettle();

      expect(find.text(AppStringsTr.salePriceInvalid), findsOneWidget);
      final line = (await activeCartLines()).single;
      expect(line.unitPriceMinor, 1000, reason: 'Fiyat değişmemiştir.');
    });
  });

  group('REQ-UX-009 — sepeti temizleme onayı', () {
    testWidgets('Ctrl+Del onay sorar, "Temizle" sepeti boşaltır', (
      tester,
    ) async {
      final id = await createProduct();
      await pumpSale(tester);
      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.delete, control: true);
      expect(find.byKey(const Key('sale_clear_dialog')), findsOneWidget);
      await tester.tap(find.byKey(const Key('sale_clear_confirm')));
      await tester.pumpAndSettle();

      expect(await cartLineCount(), 0);
    });

    testWidgets('Esc sepeti TEMİZLEMEZ — ayrı kod yolu', (tester) async {
      final id = await createProduct();
      await pumpSale(tester);
      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.delete, control: true);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(await cartLineCount(), 1);
    });
  });

  group('miktar kısayolları — docs/23 §2', () {
    testWidgets('+ artırır, - azaltır, Del satırı siler', (tester) async {
      final id = await createProduct();
      await pumpSale(tester);
      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.equal);
      expect((await activeCartLines()).single.quantity, 2);

      await press(tester, LogicalKeyboardKey.minus);
      expect((await activeCartLines()).single.quantity, 1);

      await press(tester, LogicalKeyboardKey.delete);
      expect(await cartLineCount(), 0);
    });

    testWidgets('arama kutusunda METİN varken - miktarı DEĞİŞTİRMEZ', (
      tester,
    ) async {
      // Aksi hâlde tireli bir arama terimi yazmak imkânsız olurdu.
      final id = await createProduct(name: 'Kola');
      await pumpSale(tester);
      await tester.tap(find.byKey(Key('sale_product_$id')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(SaleScreen.searchFieldKey), 'Ko');
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.minus);

      expect((await activeCartLines()).single.quantity, 1);
    });
  });

  testWidgets('REQ-UX-010 — F1 kısayol listesini açar', (tester) async {
    await createProduct();
    await pumpSale(tester);

    await press(tester, LogicalKeyboardKey.f1);

    expect(find.byKey(const Key('sale_shortcuts_dialog')), findsOneWidget);
    expect(find.text('F12'), findsWidgets);
  });

  testWidgets('docs/11 §4.3 — pasif ürün okutulunca dialog açılır', (
    tester,
  ) async {
    final id = await createProduct(name: 'Kola', barcodes: ['8690000000001']);
    await withServices(
      (container) =>
          container.read(productServiceProvider).deactivate(id, userId: userId),
    );
    await pumpSale(tester);

    await scan(tester, '8690000000001');

    expect(
      find.byKey(const Key('sale_inactive_product_dialog')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('sale_inactive_product_activate')));
    await tester.pumpAndSettle();

    expect(await cartLineCount(), 1);
    final product = (await db.select(db.products).get()).single;
    expect(product.isActive, isTrue);
  });

  testWidgets('EC-CART-002 — ürünün fiyatı değişince satır rozetlenir', (
    tester,
  ) async {
    final id = await createProduct(name: 'Kola', salePriceMinor: 2500);
    await pumpSale(tester);
    await tester.tap(find.byKey(Key('sale_product_$id')));
    await tester.pumpAndSettle();

    await (db.update(db.products)..where((p) => p.id.equals(id))).write(
      const ProductsCompanion(salePriceMinor: Value(3000)),
    );
    // Ekranı tazelemek için aramaya dokunulur.
    await tester.enterText(find.byKey(SaleScreen.searchFieldKey), '');
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.equal);

    final line = (await activeCartLines()).single;
    expect(line.unitPriceMinor, 2500, reason: 'REQ-CART-007: fiyat KORUNUR.');
    expect(find.byKey(Key('sale_badge_stale_${line.id}')), findsOneWidget);
  });

  testWidgets('REQ-CART-003 — ekran yeniden açılınca sepet geri gelir', (
    tester,
  ) async {
    final id = await createProduct();
    await pumpSale(tester);
    await tester.tap(find.byKey(Key('sale_product_$id')));
    await tester.pumpAndSettle();

    // Uygulama öldürülüp yeniden açılmış gibi.
    await pumpSale(tester);

    expect(find.text(AppStringsTr.saleCartEmptyTitle), findsNothing);
    expect(await cartLineCount(), 1);
  });
}

LogicalKeyboardKey _keyFor(String character) {
  const digits = <String, LogicalKeyboardKey>{
    '0': LogicalKeyboardKey.digit0,
    '1': LogicalKeyboardKey.digit1,
    '2': LogicalKeyboardKey.digit2,
    '3': LogicalKeyboardKey.digit3,
    '4': LogicalKeyboardKey.digit4,
    '5': LogicalKeyboardKey.digit5,
    '6': LogicalKeyboardKey.digit6,
    '7': LogicalKeyboardKey.digit7,
    '8': LogicalKeyboardKey.digit8,
    '9': LogicalKeyboardKey.digit9,
  };
  return digits[character] ?? LogicalKeyboardKey.keyA;
}
