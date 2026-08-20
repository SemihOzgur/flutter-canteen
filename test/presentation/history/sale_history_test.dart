/// Satış geçmişi, iptal ve iade ekranları — **docs/12 §7 · docs/14 ·
/// REQ-SALE-010 · REQ-RET-001…008**
///
/// | Test | Kural |
/// |---|---|
/// | Satış kaydı listede **kalır**, "Sil" YOK | REQ-RET-001 · BR-GEN-002 |
/// | İade yapılmışsa iptal düğmesi **pasif** | BR-RET-001 |
/// | İptal edilmişse ikisi de pasif | BR-RET-006 |
/// | İptal sebebi olmadan kaydedilmez | docs/14 §3 |
/// | `Esc` iptali BAŞLATMAZ | REQ-UX-009 |
/// | İade miktarı kalanla **sınırlı** | BR-RET-003 |
/// | İade tutarı **snapshot** fiyattan | BR-RET-005 |
/// | Hiçbir şey seçilmezse kaydet **pasif** | docs/14 §4 |
library;

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/application/product/product_draft.dart';
import 'package:canteen/application/product/product_service.dart';
import 'package:canteen/application/product/providers.dart';
import 'package:canteen/application/sales/providers.dart';
import 'package:canteen/application/sales/sale_service.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/money/money_formatter.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, CartItem, Category, Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/domain/enums/sale_status.dart';
import 'package:canteen/domain/models/sale_return.dart';
import 'package:canteen/presentation/history/sale_history_screen.dart';
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
    String name = 'Kola',
    int salePriceMinor = 2500,
    int initialStock = 10,
  }) async {
    final result = await withServices(
      (c) => c
          .read(productServiceProvider)
          .create(
            ProductDraft(name: name, salePrice: Money(salePriceMinor)),
            userId: userId,
            initialStock: initialStock,
          ),
    );
    return (result as Ok<ProductSaveOutcome>).value.productId;
  }

  /// Satış oluşturur.
  Future<int> sell(Map<int, int> quantities) async {
    return withServices((c) async {
      final cart = await c.read(cartServiceProvider).ensureActive(userId);
      for (final entry in quantities.entries) {
        await c
            .read(cartServiceProvider)
            .addProduct(
              cartId: cart.id,
              productId: entry.key,
              quantity: entry.value,
            );
      }
      final receipt = await c
          .read(saleServiceProvider)
          .complete(cartId: cart.id, userId: userId);
      return (receipt as Ok<SaleReceipt>).value.saleId;
    });
  }

  Future<void> returnSome(int saleId, int quantity) => withServices((c) async {
    final items = await c.read(saleServiceProvider).itemsOf(saleId);
    await c
        .read(returnServiceProvider)
        .createReturn(
          saleId: saleId,
          userId: userId,
          lines: [
            ReturnLineRequest(saleItemId: items.first.id, quantity: quantity),
          ],
        );
  });

  void useSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pump(WidgetTester tester, Widget screen) async {
    useSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [canteenDatabaseProvider.overrideWithValue(db)],
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<SaleStatus> statusOf(int saleId) async => (await withServices(
    (c) => c.read(saleServiceProvider).findById(saleId),
  ))!.status;

  OutlinedButton cancelButton(WidgetTester tester) => tester
      .widget<OutlinedButton>(find.byKey(SaleDetailScreen.cancelButtonKey));

  FilledButton returnButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byKey(SaleDetailScreen.returnButtonKey));

  // -------------------------------------------------------------------------
  // Liste — docs/12 §7
  // -------------------------------------------------------------------------

  group('REQ-SALE-010 — satış geçmişi listesi', () {
    testWidgets('satışlar listelenir ve fiş numarasıyla aranır', (
      tester,
    ) async {
      final id = await createProduct(initialStock: 100);
      final first = await sell({id: 1});
      final second = await sell({id: 2});

      await pump(tester, const SaleHistoryScreen());
      expect(find.byKey(Key('sale_history_$first')), findsOneWidget);
      expect(find.byKey(Key('sale_history_$second')), findsOneWidget);

      await tester.enterText(find.byKey(SaleHistoryScreen.searchKey), '000001');
      await tester.pumpAndSettle();

      expect(find.byKey(Key('sale_history_$first')), findsOneWidget);
      expect(find.byKey(Key('sale_history_$second')), findsNothing);
    });

    testWidgets('REQ-RET-001 — iptal edilmiş satış listede KALIR', (
      tester,
    ) async {
      final id = await createProduct();
      final saleId = await sell({id: 2});
      await withServices(
        (c) => c
            .read(returnServiceProvider)
            .cancelSale(saleId: saleId, userId: userId, reason: 'x'),
      );

      await pump(tester, const SaleHistoryScreen());

      expect(find.byKey(Key('sale_history_$saleId')), findsOneWidget);
      expect(
        find.textContaining(AppStringsTr.saleStatusNames['cancelled']!),
        findsWidgets,
      );
    });

    testWidgets('REQ-RET-001 — listede "Sil" eylemi YOKTUR', (tester) async {
      await sell({await createProduct(): 1});

      await pump(tester, const SaleHistoryScreen());

      expect(
        find.byIcon(Icons.delete),
        findsNothing,
        reason: 'BR-GEN-002 — satış kayıtları hiçbir koşulda silinemez.',
      );
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });

    testWidgets('durum filtresi uygulanır', (tester) async {
      final id = await createProduct(initialStock: 100);
      final kept = await sell({id: 1});
      final cancelled = await sell({id: 1});
      await withServices(
        (c) => c
            .read(returnServiceProvider)
            .cancelSale(saleId: cancelled, userId: userId, reason: 'x'),
      );

      await pump(tester, const SaleHistoryScreen());
      await tester.tap(find.byKey(SaleHistoryScreen.statusFilterKey));
      await tester.pumpAndSettle();
      await tester.tap(
        find.text(AppStringsTr.saleStatusNames['cancelled']!).last,
      );
      await tester.pumpAndSettle();

      expect(find.byKey(Key('sale_history_$cancelled')), findsOneWidget);
      expect(find.byKey(Key('sale_history_$kept')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Detay ve iptal — docs/14 §3
  // -------------------------------------------------------------------------

  group('docs/14 §3 — satış iptali', () {
    testWidgets('sebep olmadan KAYDEDİLMEZ', (tester) async {
      final id = await createProduct();
      final saleId = await sell({id: 2});
      await pump(tester, SaleDetailScreen(saleId: saleId));

      await tester.tap(find.byKey(SaleDetailScreen.cancelButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sale_cancel_submit')));
      await tester.pumpAndSettle();

      expect(find.text(AppStringsTr.stockReasonRequired), findsOneWidget);
      expect(await statusOf(saleId), SaleStatus.completed);
    });

    testWidgets('sebep ile iptal edilir ve stok geri eklenir', (tester) async {
      final id = await createProduct(initialStock: 10);
      final saleId = await sell({id: 3});
      await pump(tester, SaleDetailScreen(saleId: saleId));

      await tester.tap(find.byKey(SaleDetailScreen.cancelButtonKey));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('sale_cancel_reason')),
        'Yanlış satış',
      );
      await tester.tap(find.byKey(const Key('sale_cancel_submit')));
      await tester.pumpAndSettle();

      expect(await statusOf(saleId), SaleStatus.cancelled);
      final row = await (db.select(
        db.products,
      )..where((p) => p.id.equals(id))).getSingle();
      expect(row.stockQuantity, 10);
    });

    testWidgets('[Vazgeç] iptali BAŞLATMAZ', (tester) async {
      // `Esc` ile `[Vazgeç]` AYRI kod yollarıdır: biri `null` döndürür,
      // diğeri açıkça `pop()` çağırır. Yalnızca birini test etmek diğerinin
      // yanlışlıkla sebep döndürmesini görünmez kılar.
      final saleId = await sell({await createProduct(): 2});
      await pump(tester, SaleDetailScreen(saleId: saleId));

      await tester.tap(find.byKey(SaleDetailScreen.cancelButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStringsTr.cancelAction));
      await tester.pumpAndSettle();

      expect(await statusOf(saleId), SaleStatus.completed);
    });

    testWidgets('Esc iptali BAŞLATMAZ — ayrı kod yolu', (tester) async {
      final saleId = await sell({await createProduct(): 2});
      await pump(tester, SaleDetailScreen(saleId: saleId));

      await tester.tap(find.byKey(SaleDetailScreen.cancelButtonKey));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(await statusOf(saleId), SaleStatus.completed);
    });

    testWidgets('BR-RET-001 — iade yapılmışsa iptal düğmesi PASİF', (
      tester,
    ) async {
      final saleId = await sell({await createProduct(): 3});
      await returnSome(saleId, 1);

      await pump(tester, SaleDetailScreen(saleId: saleId));

      expect(
        cancelButton(tester).onPressed,
        isNull,
        reason: 'İptal edilseydi stok İKİ KEZ geri eklenirdi.',
      );
      expect(returnButton(tester).onPressed, isNotNull);
    });

    testWidgets('BR-RET-006 — iptalden sonra İKİSİ DE pasif', (tester) async {
      final saleId = await sell({await createProduct(): 2});
      await withServices(
        (c) => c
            .read(returnServiceProvider)
            .cancelSale(saleId: saleId, userId: userId, reason: 'x'),
      );

      await pump(tester, SaleDetailScreen(saleId: saleId));

      expect(cancelButton(tester).onPressed, isNull);
      expect(returnButton(tester).onPressed, isNull);
    });

    testWidgets('tamamı iade edilmişse iade düğmesi PASİF', (tester) async {
      final saleId = await sell({await createProduct(): 2});
      await returnSome(saleId, 2);

      await pump(tester, SaleDetailScreen(saleId: saleId));

      expect(returnButton(tester).onPressed, isNull);
      expect(cancelButton(tester).onPressed, isNull);
    });
  });

  // -------------------------------------------------------------------------
  // İade — docs/14 §4
  // -------------------------------------------------------------------------

  group('docs/14 §4 — iade', () {
    testWidgets('hiçbir şey seçilmezse kaydet PASİF', (tester) async {
      final saleId = await sell({await createProduct(): 2});
      await pump(tester, SaleDetailScreen(saleId: saleId));

      await tester.tap(find.byKey(SaleDetailScreen.returnButtonKey));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('sale_return_submit')))
            .onPressed,
        isNull,
      );
    });

    testWidgets('BR-RET-003 — miktar KALAN ile sınırlıdır', (tester) async {
      final saleId = await sell({await createProduct(): 2});
      final itemId = (await withServices(
        (c) => c.read(saleServiceProvider).itemsOf(saleId),
      )).single.id;
      await pump(tester, SaleDetailScreen(saleId: saleId));
      await tester.tap(find.byKey(SaleDetailScreen.returnButtonKey));
      await tester.pumpAndSettle();

      final increase = find.byKey(Key('sale_return_inc_$itemId'));
      await tester.tap(increase);
      await tester.pumpAndSettle();
      await tester.tap(increase);
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(Key('sale_return_qty_$itemId'))).data,
        '2',
      );
      expect(
        tester.widget<IconButton>(increase).onPressed,
        isNull,
        reason: 'Satılan miktarda DURUR.',
      );
    });

    testWidgets('BR-RET-005 — tutar SNAPSHOT fiyattan hesaplanır', (
      tester,
    ) async {
      final id = await createProduct(salePriceMinor: 2500);
      final saleId = await sell({id: 2});
      final itemId = (await withServices(
        (c) => c.read(saleServiceProvider).itemsOf(saleId),
      )).single.id;
      // Ürünün fiyatı satıştan SONRA değişiyor.
      await (db.update(db.products)..where((p) => p.id.equals(id))).write(
        const ProductsCompanion(salePriceMinor: Value(3000)),
      );

      await pump(tester, SaleDetailScreen(saleId: saleId));
      await tester.tap(find.byKey(SaleDetailScreen.returnButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('sale_return_inc_$itemId')));
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>(find.byKey(const Key('sale_return_total'))).data,
        MoneyFormatter.format(const Money(2500)),
        reason: 'Güncel ₺30,00 DEĞİL, satış anındaki ₺25,00.',
      );
    });

    testWidgets(
      'BR-RET-005 — DEĞİŞTİRİLMİŞ satış fiyatı da snapshot\'tan gelir',
      (tester) async {
        // Bu, `unitPrice` ile `originalUnitPrice`'ın AYRIŞTIĞI tek durumdur
        // (docs/12 §4 fiyat override'ı). Ürünün güncel fiyatını değiştirmek
        // ikisini de etkilemez ve farkı göstermez.
        final id = await createProduct(salePriceMinor: 2500);
        final saleId = await withServices((c) async {
          final cart = await c.read(cartServiceProvider).ensureActive(userId);
          await c
              .read(cartServiceProvider)
              .addProduct(cartId: cart.id, productId: id, quantity: 2);
          final loaded = await c
              .read(cartServiceProvider)
              .load(cart.id, userId);
          await c
              .read(cartServiceProvider)
              .overridePrice(
                cartId: cart.id,
                lineId: loaded.lines.single.id,
                unitPrice: const Money(2000),
              );
          final receipt = await c
              .read(saleServiceProvider)
              .complete(cartId: cart.id, userId: userId);
          return (receipt as Ok<SaleReceipt>).value.saleId;
        });
        final itemId = (await withServices(
          (c) => c.read(saleServiceProvider).itemsOf(saleId),
        )).single.id;

        await pump(tester, SaleDetailScreen(saleId: saleId));
        await tester.tap(find.byKey(SaleDetailScreen.returnButtonKey));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key('sale_return_inc_$itemId')));
        await tester.pumpAndSettle();

        expect(
          tester.widget<Text>(find.byKey(const Key('sale_return_total'))).data,
          MoneyFormatter.format(const Money(2000)),
          reason:
              'Müşteri ₺20,00 ödemiştir; liste fiyatı ₺25,00 GERİ VERİLMEZ.',
        );
      },
    );

    testWidgets('kısmi iade kaydedilir ve durum güncellenir', (tester) async {
      final id = await createProduct(initialStock: 10);
      final saleId = await sell({id: 3});
      final itemId = (await withServices(
        (c) => c.read(saleServiceProvider).itemsOf(saleId),
      )).single.id;

      await pump(tester, SaleDetailScreen(saleId: saleId));
      await tester.tap(find.byKey(SaleDetailScreen.returnButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('sale_return_inc_$itemId')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sale_return_submit')));
      await tester.pumpAndSettle();

      expect(await statusOf(saleId), SaleStatus.partiallyReturned);
      final row = await (db.select(
        db.products,
      )..where((p) => p.id.equals(id))).getSingle();
      expect(row.stockQuantity, 8, reason: '7 + 1 iade');
    });

    testWidgets('Esc iadeyi BAŞLATMAZ', (tester) async {
      final saleId = await sell({await createProduct(): 2});
      final itemId = (await withServices(
        (c) => c.read(saleServiceProvider).itemsOf(saleId),
      )).single.id;

      await pump(tester, SaleDetailScreen(saleId: saleId));
      await tester.tap(find.byKey(SaleDetailScreen.returnButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('sale_return_inc_$itemId')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(await statusOf(saleId), SaleStatus.completed);
    });

    testWidgets('kalan miktar bitince o satırda alan SUNULMAZ', (tester) async {
      final saleId = await sell({await createProduct(): 2});
      final itemId = (await withServices(
        (c) => c.read(saleServiceProvider).itemsOf(saleId),
      )).single.id;
      await returnSome(saleId, 2);

      // Satış artık `returned`; iade düğmesi pasif olduğu için dialog
      // doğrudan açılır (servis yine reddederdi).
      await pump(tester, SaleDetailScreen(saleId: saleId));

      expect(returnButton(tester).onPressed, isNull);
      expect(itemId, isPositive);
    });
  });

  testWidgets('detay satırları SNAPSHOT verisini gösterir', (tester) async {
    final id = await createProduct(name: 'Kola', salePriceMinor: 2500);
    final saleId = await sell({id: 2});
    // Ürün adı ve fiyatı satıştan sonra değişiyor.
    await (db.update(db.products)..where((p) => p.id.equals(id))).write(
      const ProductsCompanion(
        name: Value('Kola XL'),
        salePriceMinor: Value(3000),
      ),
    );

    await pump(tester, SaleDetailScreen(saleId: saleId));

    expect(find.text('Kola'), findsOneWidget);
    expect(
      find.text('Kola XL'),
      findsNothing,
      reason: 'REQ-SALE-003 — geçmiş satış ürün değişince DEĞİŞMEZ.',
    );
    expect(
      tester.widget<Text>(find.byKey(const Key('sale_detail_total'))).data,
      MoneyFormatter.format(const Money(5000)),
    );
  });
}
