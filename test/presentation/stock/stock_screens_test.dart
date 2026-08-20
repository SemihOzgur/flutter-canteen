/// Faz 6 stok ekranları — **docs/13 §5–§8 · REQ-STOCK-003/007/008/009/011**
///
/// | Test | Kural |
/// |---|---|
/// | Aynı ürün tekrar eklenince miktar +1 | docs/13 §5 |
/// | Alış fiyatı değişince ONAY sorulur — `Esc` = HAYIR | BR-STOCK-009 |
/// | Kaydetme tek transaction; hata ekranı KORUR | REQ-STOCK-007 |
/// | Fire/düzeltmede sebep zorunlu — `Esc` iptal | BR-STOCK-010 |
/// | Hareket listesinde **Düzenle/Sil YOK**, ters kayıt var | REQ-STOCK-003 |
/// | `minimum_stock = 0` kritik listeye girmez | REQ-STOCK-011 |
/// | Negatif stok pasif üründe de görünür | BR-STOCK-007 |
///
/// ## Kapsanan requirement'lar (Faz 11 izlenebilirliği)
///
/// - **REQ-STOCK-010** — stok geçmişi referans ve sebepleriyle görünür
library;

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/application/product/product_draft.dart';
import 'package:canteen/application/product/product_service.dart';
import 'package:canteen/application/product/providers.dart';
import 'package:canteen/application/stock/providers.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, Category, Product, Sale, SaleItem, StockMovement, Supplier;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/domain/enums/stock_movement_type.dart';
import 'package:canteen/domain/models/stock_movement.dart';
import 'package:canteen/presentation/products/product_list_screen.dart';
import 'package:canteen/presentation/stock/stock_entry_screen.dart';
import 'package:canteen/presentation/stock/stock_movements_screen.dart';
import 'package:canteen/presentation/stock/stock_overview_screen.dart';
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
    int purchasePriceMinor = 1800,
    int initialStock = 0,
    int minimumStock = 0,
  }) async {
    final result = await withServices(
      (c) => c
          .read(productServiceProvider)
          .create(
            ProductDraft(
              name: name,
              salePrice: const Money(2500),
              purchasePrice: Money(purchasePriceMinor),
              minimumStock: minimumStock,
            ),
            userId: userId,
            initialStock: initialStock,
          ),
    );
    return (result as Ok<ProductSaveOutcome>).value.productId;
  }

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

  Future<List<StockMovement>> movements() async =>
      withServices((c) => c.read(stockServiceProvider).movements(limit: 500));

  // -------------------------------------------------------------------------
  // Stok girişi — docs/13 §5
  // -------------------------------------------------------------------------

  group('stok girişi ekranı', () {
    Future<void> addLine(WidgetTester tester, String name) async {
      await tester.enterText(StockEntryScreen.searchFieldKey.toFinder(), name);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
    }

    testWidgets('aynı ürün tekrar eklenince MİKTAR artar', (tester) async {
      final id = await createProduct(name: 'Kola');
      await pump(tester, const StockEntryScreen());

      await addLine(tester, 'Kola');
      await addLine(tester, 'Kola');

      expect(
        tester.widget<Text>(find.byKey(Key('stock_entry_qty_$id'))).data,
        '2',
      );
    });

    testWidgets('REQ-STOCK-007 — kaydetme tek transaction, defter yazılır', (
      tester,
    ) async {
      final id = await createProduct(name: 'Kola', initialStock: 10);
      await pump(tester, const StockEntryScreen());
      await addLine(tester, 'Kola');
      await tester.tap(find.byKey(Key('stock_entry_inc_$id')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(StockEntryScreen.saveButtonKey));
      await tester.pumpAndSettle();

      final entries = (await movements()).where(
        (m) => m.type == StockMovementType.stockEntry,
      );
      expect(entries, hasLength(1));
      expect(entries.single.quantityDelta, 2);
      expect(entries.single.resultingStock, 12);
      // Kaydetme başarılı olduğunda satırlar temizlenir.
      expect(find.text(AppStringsTr.stockEntryEmpty), findsOneWidget);
    });

    testWidgets(
      'REQ-STOCK-007 — kaydetme HATA verirse satırlar EKRANDA KORUNUR',
      (tester) async {
        // docs/13 §10 acceptance criteria: "Girilen veriler ekranda korunur,
        // kullanıcı düzeltip tekrar deneyebilir." Satırların temizlenmesi
        // kullanıcının 15 satırlık mal kabulünü yeniden girmesi demektir.
        final id = await createProduct(name: 'Kola', initialStock: 10);
        await pump(tester, const StockEntryScreen());
        await addLine(tester, 'Kola');

        // Bozulma senaryosu: ürün kaydetme anında yok oluyor.
        await db.customStatement('PRAGMA foreign_keys = OFF');
        await db.customStatement('DELETE FROM products WHERE id = $id');

        await tester.tap(find.byKey(StockEntryScreen.saveButtonKey));
        await tester.pumpAndSettle();

        expect(
          find.text(AppStringsTr.stockEntryEmpty),
          findsNothing,
          reason: 'Satırlar SİLİNMEZ; kullanıcı düzeltip tekrar dener.',
        );
        expect(find.byKey(Key('stock_entry_qty_$id')), findsOneWidget);
        // REQ-STOCK-007 — hiçbir hareket yazılmamıştır.
        expect(
          (await movements()).where(
            (m) => m.type == StockMovementType.stockEntry,
          ),
          isEmpty,
        );
      },
    );

    testWidgets('boş listede "Girişi Kaydet" PASİFTİR', (tester) async {
      await createProduct();
      await pump(tester, const StockEntryScreen());

      final button = tester.widget<FilledButton>(
        find.byKey(StockEntryScreen.saveButtonKey),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets(
      'BR-STOCK-009 — fiyat değişince ONAY sorulur, EVET güncellerse',
      (tester) async {
        final id = await createProduct(name: 'Kola', purchasePriceMinor: 1800);
        await pump(tester, const StockEntryScreen());
        await addLine(tester, 'Kola');

        await tester.tap(find.byKey(Key('stock_entry_cost_$id')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const Key('stock_cost_field')),
          '20,00',
        );
        await tester.tap(find.byKey(const Key('stock_cost_submit')));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const Key('stock_cost_update_dialog')),
          findsOneWidget,
          reason: 'REQ-STOCK-008: kullanıcıya SORULUR.',
        );
        await tester.tap(find.byKey(const Key('stock_cost_update_yes')));
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(StockEntryScreen.saveButtonKey));
        await tester.pumpAndSettle();

        final row = await (db.select(
          db.products,
        )..where((p) => p.id.equals(id))).getSingle();
        expect(row.purchasePriceMinor, 2000);
      },
    );

    testWidgets('BR-STOCK-009 — Esc ONAY SAYILMAZ, ürünün fiyatı DEĞİŞMEZ', (
      tester,
    ) async {
      // `[Hayır]` açıkça `false`, `Esc` ise `null` döndürür. `?? false`
      // olmasaydı Esc sessizce fiyatı güncellerdi.
      final id = await createProduct(name: 'Kola', purchasePriceMinor: 1800);
      await pump(tester, const StockEntryScreen());
      await addLine(tester, 'Kola');

      await tester.tap(find.byKey(Key('stock_entry_cost_$id')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('stock_cost_field')),
        '20,00',
      );
      await tester.tap(find.byKey(const Key('stock_cost_submit')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(StockEntryScreen.saveButtonKey));
      await tester.pumpAndSettle();

      final row = await (db.select(
        db.products,
      )..where((p) => p.id.equals(id))).getSingle();
      expect(row.purchasePriceMinor, 1800);
      // Giriş yine bu fiyatla kaydedilmiştir.
      final entry = (await movements()).firstWhere(
        (m) => m.type == StockMovementType.stockEntry,
      );
      expect(entry.unitCost, const Money(2000));
    });
  });

  // -------------------------------------------------------------------------
  // Fire ve düzeltme — docs/13 §6
  // -------------------------------------------------------------------------

  group('fire ve düzeltme', () {
    /// Fire ve düzeltme kritik/negatif olmayan ürünlerde de yapılabilmelidir
    /// (docs/13 §6); ekrana arama bu yüzden eklendi.
    Future<void> findProduct(WidgetTester tester, String name) async {
      await tester.enterText(
        find.byKey(StockOverviewScreen.searchFieldKey),
        name,
      );
      await tester.pumpAndSettle();
    }

    testWidgets('fire sebep olmadan KAYDEDİLMEZ', (tester) async {
      final id = await createProduct(name: 'Kola', initialStock: 50);
      await pump(tester, const StockOverviewScreen());
      await findProduct(tester, 'Kola');

      await tester.tap(find.byKey(Key('stock_waste_$id')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('stock_dialog_quantity')),
        '3',
      );
      await tester.tap(find.byKey(const Key('stock_dialog_submit')));
      await tester.pumpAndSettle();

      expect(find.text(AppStringsTr.stockReasonRequired), findsOneWidget);
      expect(
        (await movements()).where((m) => m.type == StockMovementType.waste),
        isEmpty,
      );
    });

    testWidgets('docs/13 §6 — stoğu NORMAL üründe de fire kaydedilir', (
      tester,
    ) async {
      // Bozulan süt, stoğu 20 olan bir üründe de olur.
      final id = await createProduct(name: 'Süt', initialStock: 20);
      await pump(tester, const StockOverviewScreen());
      await findProduct(tester, 'Süt');

      await tester.tap(find.byKey(Key('stock_waste_$id')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('stock_dialog_quantity')),
        '2',
      );
      await tester.tap(find.byKey(const Key('stock_reason_Bozulma')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('stock_dialog_submit')));
      await tester.pumpAndSettle();

      final waste = (await movements()).firstWhere(
        (m) => m.type == StockMovementType.waste,
      );
      expect(waste.quantityDelta, -2);
      expect(waste.note, 'Bozulma');
    });

    testWidgets('Esc fire kaydetmez', (tester) async {
      final id = await createProduct(name: 'Kola', initialStock: 50);
      await pump(tester, const StockOverviewScreen());
      await findProduct(tester, 'Kola');

      await tester.tap(find.byKey(Key('stock_waste_$id')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(
        (await movements()).where((m) => m.type == StockMovementType.waste),
        isEmpty,
      );
    });

    testWidgets('düzeltme HEDEF stok alır, delta hesaplanır', (tester) async {
      final id = await createProduct(name: 'Kola', initialStock: 0);
      await (db.update(db.products)..where((p) => p.id.equals(id))).write(
        const ProductsCompanion(stockQuantity: Value(-3)),
      );
      await pump(tester, const StockOverviewScreen());

      await tester.tap(find.byKey(Key('stock_adjust_$id')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('stock_dialog_quantity')),
        '12',
      );
      await tester.enterText(
        find.byKey(const Key('stock_dialog_reason')),
        'Fiziksel sayım',
      );
      await tester.tap(find.byKey(const Key('stock_dialog_submit')));
      await tester.pumpAndSettle();

      final adjustment = (await movements()).firstWhere(
        (m) => m.type == StockMovementType.adjustment,
      );
      expect(adjustment.resultingStock, 12);
      expect(adjustment.quantityDelta, 15);
    });
  });

  // -------------------------------------------------------------------------
  // Kritik / negatif stok — docs/13 §7
  // -------------------------------------------------------------------------

  group('docs/13 §7 — kritik ve negatif stok', () {
    testWidgets('REQ-STOCK-011 — minimum 0 olan ürün KRİTİK sayılmaz', (
      tester,
    ) async {
      final tracked = await createProduct(
        name: 'Takipli',
        initialStock: 2,
        minimumStock: 5,
      );
      final untracked = await createProduct(name: 'Takipsiz', initialStock: 0);

      await pump(tester, const StockOverviewScreen());

      expect(find.byKey(Key('stock_row_$tracked')), findsOneWidget);
      expect(
        find.byKey(Key('stock_row_$untracked')),
        findsNothing,
        reason:
            'minimum_stock = 0 → kullanıcı o ürün için takip istemiyor '
            'demektir (REQ-STOCK-011).',
      );
    });

    testWidgets('SINIR — kritik listesi stok == minimum\'u İÇERİR', (
      tester,
    ) async {
      final id = await createProduct(
        name: 'Sınır',
        initialStock: 5,
        minimumStock: 5,
      );

      await pump(tester, const StockOverviewScreen());

      expect(find.byKey(Key('stock_row_$id')), findsOneWidget);
    });

    testWidgets('BR-STOCK-007 — negatif stok PASİF üründe de görünür', (
      tester,
    ) async {
      final id = await createProduct(name: 'Pasif');
      await (db.update(db.products)..where((p) => p.id.equals(id))).write(
        const ProductsCompanion(
          stockQuantity: Value(-4),
          isActive: Value(false),
        ),
      );

      await pump(tester, const StockOverviewScreen());

      expect(
        find.byKey(Key('stock_row_$id')),
        findsOneWidget,
        reason:
            'Negatif stok bir HATA SİNYALİDİR; pasifleştirilmiş olmak onu '
            'geçersiz kılmaz.',
      );
      expect(
        find.textContaining(AppStringsTr.stockNegativeBadge),
        findsWidgets,
      );
    });
  });

  // -------------------------------------------------------------------------
  // Ürün listesi görünürlüğü — docs/13 §7
  // -------------------------------------------------------------------------

  group('docs/13 §7 — ürün listesinde kritik/negatif işareti', () {
    testWidgets('negatif stoklu ürün işaretlenir', (tester) async {
      final id = await createProduct(name: 'Kola');
      await (db.update(db.products)..where((p) => p.id.equals(id))).write(
        const ProductsCompanion(stockQuantity: Value(-4)),
      );

      await pump(tester, const ProductListScreen());

      expect(find.byKey(ProductListScreen.stockWarningKey(id)), findsOneWidget);
      // rules/05 §5 — renkle iletilen durum METİNLE de ifade edilir.
      expect(
        find.textContaining(AppStringsTr.stockNegativeBadge),
        findsOneWidget,
      );
    });

    testWidgets('kritik stoklu ürün işaretlenir', (tester) async {
      final id = await createProduct(
        name: 'Kola',
        initialStock: 2,
        minimumStock: 5,
      );

      await pump(tester, const ProductListScreen());

      expect(find.byKey(ProductListScreen.stockWarningKey(id)), findsOneWidget);
      expect(
        find.textContaining(AppStringsTr.stockCriticalBadge),
        findsOneWidget,
      );
    });

    testWidgets('REQ-STOCK-011 — minimum 0 olan ürün İŞARETLENMEZ', (
      tester,
    ) async {
      final id = await createProduct(name: 'Kola', initialStock: 0);

      await pump(tester, const ProductListScreen());

      expect(
        find.byKey(ProductListScreen.stockWarningKey(id)),
        findsNothing,
        reason: 'Kullanıcı o ürün için takip istemiyor demektir.',
      );
    });

    testWidgets('SINIR — stok minimuma EŞİTKEN kritiktir', (tester) async {
      // docs/13 §7: `stock_quantity <= minimum_stock`. Sınırın kendisi
      // kritiktir; `<` yazılsaydı tam eşikteki ürün sessizce gözden kaçardı.
      final id = await createProduct(
        name: 'Kola',
        initialStock: 5,
        minimumStock: 5,
      );

      await pump(tester, const ProductListScreen());

      expect(find.byKey(ProductListScreen.stockWarningKey(id)), findsOneWidget);
    });

    testWidgets('SINIR — minimumun bir üstü kritik DEĞİLDİR', (tester) async {
      final id = await createProduct(
        name: 'Kola',
        initialStock: 6,
        minimumStock: 5,
      );

      await pump(tester, const ProductListScreen());

      expect(find.byKey(ProductListScreen.stockWarningKey(id)), findsNothing);
    });

    testWidgets('stoğu yeterli ürün işaretlenmez', (tester) async {
      final id = await createProduct(
        name: 'Kola',
        initialStock: 50,
        minimumStock: 5,
      );

      await pump(tester, const ProductListScreen());

      expect(find.byKey(ProductListScreen.stockWarningKey(id)), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Hareket geçmişi — REQ-STOCK-003
  // -------------------------------------------------------------------------

  group('hareket geçmişi', () {
    testWidgets('REQ-STOCK-003 — Düzenle/Sil YOKTUR', (tester) async {
      await createProduct(initialStock: 10);
      await pump(tester, const StockMovementsScreen());

      expect(find.byIcon(Icons.edit), findsNothing);
      expect(find.byIcon(Icons.delete), findsNothing);
      expect(
        find.byIcon(Icons.undo),
        findsWidgets,
        reason: 'Yalnızca "Ters Kayıt Oluştur" sunulur.',
      );
    });

    testWidgets('ters kayıt orijinali BIRAKIR, yeni düzeltme ekler', (
      tester,
    ) async {
      final id = await createProduct(initialStock: 10);
      await pump(tester, const StockMovementsScreen());
      final original = (await movements()).single;

      await tester.tap(
        find.byKey(Key('stock_movement_reverse_${original.id}')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('stock_reverse_reason')),
        'Yanlış girildi',
      );
      await tester.tap(find.byKey(const Key('stock_reverse_submit')));
      await tester.pumpAndSettle();

      final all = await movements();
      expect(all, hasLength(2), reason: 'Orijinal DURUR, yenisi eklenir.');
      final adjustment = all.firstWhere(
        (m) => m.type == StockMovementType.adjustment,
      );
      expect(adjustment.quantityDelta, -10);

      final row = await (db.select(
        db.products,
      )..where((p) => p.id.equals(id))).getSingle();
      expect(row.stockQuantity, 0);
    });

    testWidgets('Esc ters kayıt oluşturmaz', (tester) async {
      await createProduct(initialStock: 10);
      await pump(tester, const StockMovementsScreen());
      final original = (await movements()).single;

      await tester.tap(
        find.byKey(Key('stock_movement_reverse_${original.id}')),
      );
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(await movements(), hasLength(1));
    });
  });
}

extension on Key {
  Finder toFinder() => find.byKey(this);
}
