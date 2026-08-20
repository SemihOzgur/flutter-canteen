/// İçe / dışa aktarma ekranı — **docs/20 · REQ-IMEX-002…013**
///
/// | Test | Kural |
/// |---|---|
/// | Önizleme olmadan "İçe Aktar" **yok** | REQ-IMEX-007 |
/// | Hatalı satırlar satır numarası + sebeple | REQ-IMEX-005 |
/// | Hata listesi CSV indirilebilir | REQ-IMEX-006 |
/// | Politika değişince önizleme **yeniden** hesaplanır | BR-IMEX-001 |
/// | Şablon import başlıklarıyla **aynı** | REQ-IMEX-002/013 |
/// | Satış import edilemez uyarısı ekranda | docs/20 §1 |
library;

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/application/import/data_export_service.dart';
import 'package:canteen/application/reporting/providers.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide
        Cart,
        CartItem,
        Category,
        Product,
        Sale,
        SaleItem,
        StockMovement,
        Supplier;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/data/files/csv_parser.dart';
import 'package:canteen/data/files/providers.dart';
import 'package:canteen/presentation/import/import_export_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late TempAppPaths temp;
  late ProviderContainer container;
  late List<({String path, String contents})> written;
  late int userId;

  const header =
      'Ürün adı;Satış fiyatı (KDV dahil);Alış fiyatı;Kategori;'
      'Barkod;Başlangıç stoğu;Tedarikçi';

  setUp(() async {
    db = memoryDatabase();
    temp = await TempAppPaths.create();
    written = [];
    container = ProviderContainer(
      overrides: [
        canteenDatabaseProvider.overrideWithValue(db),
        appPathsProvider.overrideWithValue(temp.paths),
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
    temp.dispose();
  });

  Future<void> pump(
    WidgetTester tester, {
    String? fileContents,
    Future<String?> Function(String)? picker,
  }) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ImportExportScreen(
            fileReader: fileContents == null
                ? null
                : () async => (name: 'urunler.csv', contents: fileContents),
            savePicker: picker ?? (name) async => '/tmp/$name',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> selectFile(WidgetTester tester) async {
    await tester.tap(find.byKey(ImportExportScreen.pickFileKey));
    await tester.pumpAndSettle();
  }

  Future<int> productCount() async =>
      (await db.select(db.products).get()).length;

  group('REQ-IMEX-007 — onaysız import yok', () {
    testWidgets('dosya seçilmeden önizleme ve onay YOKTUR', (tester) async {
      await pump(tester);

      expect(find.byKey(ImportExportScreen.previewKey), findsNothing);
      expect(find.byKey(ImportExportScreen.confirmKey), findsNothing);
      expect(find.text(AppStringsTr.importNoFile), findsOneWidget);
    });

    testWidgets('önizleme onaydan ÖNCE gelir ve ürün oluşmaz', (tester) async {
      await pump(tester, fileContents: '$header\nKola;25,00;;İçecek;;10;');

      await selectFile(tester);

      expect(find.byKey(ImportExportScreen.previewKey), findsOneWidget);
      expect(
        await productCount(),
        0,
        reason: 'Önizleme HİÇBİR ŞEY yazmaz (docs/20 §5).',
      );
    });

    testWidgets('onaylanınca ürün oluşur ve ekran sıfırlanır', (tester) async {
      await pump(tester, fileContents: '$header\nKola;25,00;;İçecek;;10;');
      await selectFile(tester);

      await tester.tap(find.byKey(ImportExportScreen.confirmKey));
      await tester.pumpAndSettle();

      expect(await productCount(), 1);
      expect(find.byKey(ImportExportScreen.previewKey), findsNothing);
      expect(find.textContaining('1 yeni'), findsOneWidget);
    });

    testWidgets('geçerli satır yoksa onay PASİF', (tester) async {
      await pump(tester, fileContents: '$header\n;25,00;;;;;');
      await selectFile(tester);

      expect(
        tester
            .widget<FilledButton>(find.byKey(ImportExportScreen.confirmKey))
            .onPressed,
        isNull,
      );
    });
  });

  group('REQ-IMEX-004/005 — önizleme ve hata listesi', () {
    testWidgets('hatalı satır SATIR NUMARASI ve sebeple gösterilir', (
      tester,
    ) async {
      await pump(tester, fileContents: '$header\nKola;25,00;;;;;\n;10,00;;;;;');
      await selectFile(tester);

      // Başlık 1, ilk veri 2, ikinci veri 3.
      expect(find.byKey(const Key('import_row_3')), findsOneWidget);
      expect(find.text('(boş)'), findsOneWidget);
      expect(find.textContaining('Ürün adı zorunlu'), findsOneWidget);
      expect(find.byKey(const Key('import_rejected_count')), findsOneWidget);
    });

    testWidgets('"Sorunlular" filtresi temiz satırları gizler', (tester) async {
      await pump(tester, fileContents: '$header\nKola;25,00;;;;;\n;10,00;;;;;');
      await selectFile(tester);
      expect(find.byKey(const Key('import_row_2')), findsOneWidget);

      await tester.tap(find.byKey(const Key('import_filter_problems')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import_row_2')), findsNothing);
      expect(find.byKey(const Key('import_row_3')), findsOneWidget);
    });

    testWidgets('REQ-IMEX-006 — hata listesi CSV indirilir', (tester) async {
      await pump(tester, fileContents: '$header\nKola;25,00;;;;;\n;10,00;;;;;');
      await selectFile(tester);

      await tester.tap(find.byKey(ImportExportScreen.errorsCsvKey));
      await tester.pumpAndSettle();

      expect(written, hasLength(1));
      final csv = written.single.contents;
      expect(csv, contains('Satır;Ürün adı;Sorun'));
      expect(csv, contains('Ürün adı zorunlu'));
      expect(csv, contains('3'), reason: 'Kullanıcı kendi dosyasında bulmalı.');
    });

    testWidgets('hata yoksa CSV düğmesi SUNULMAZ', (tester) async {
      await pump(tester, fileContents: '$header\nKola;25,00;;;;;');
      await selectFile(tester);

      expect(find.byKey(ImportExportScreen.errorsCsvKey), findsNothing);
    });
  });

  group('BR-IMEX-001 — politika', () {
    testWidgets('politika değişince önizleme YENİDEN hesaplanır', (
      tester,
    ) async {
      // Sistemde kayıtlı barkod: `skip` reddeder, `updateExisting` güncelller.
      final id = await insertTestProduct(db, name: 'Eski');
      await db
          .into(db.productBarcodes)
          .insert(
            ProductBarcodesCompanion.insert(
              productId: id,
              barcode: '8690',
              createdAt: testEpochUtc,
            ),
          );

      await pump(tester, fileContents: '$header\nYeni;30,00;;;8690;;');
      await selectFile(tester);
      expect(find.byKey(const Key('import_rejected_count')), findsOneWidget);

      await tester.tap(find.byKey(ImportExportScreen.policyKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text(AppStringsTr.importPolicyUpdate).last);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('import_rejected_count')), findsNothing);
      expect(find.textContaining('güncellenecek'), findsWidgets);
    });
  });

  group('REQ-IMEX-002/013 — şablon ve round-trip', () {
    testWidgets('şablon indirilir ve import başlıklarıyla AYNI', (
      tester,
    ) async {
      await pump(tester);

      await tester.tap(find.byKey(ImportExportScreen.templateKey));
      await tester.pumpAndSettle();

      final csv = written.single.contents;
      final parsed = CsvParser.parse(csv)!;
      expect(
        parsed.header,
        DataExportService.productHeader,
        reason:
            'Şablon ile export başlıkları ayrışırsa döngü SESSİZCE kırılır.',
      );
      expect(find.text(AppStringsTr.importTemplateSaved), findsOneWidget);
    });

    testWidgets('ürün export → import ROUND-TRIP', (tester) async {
      // docs/20 §8: "dışa aktar, düzenle, içe aktar döngüsü çalışır."
      await pump(
        tester,
        fileContents: '$header\nKola;25,00;18,00;İçecek;8690;7;',
      );
      await selectFile(tester);
      await tester.tap(find.byKey(ImportExportScreen.confirmKey));
      await tester.pumpAndSettle();
      expect(await productCount(), 1);

      await tester.tap(find.byKey(const Key('export_products')));
      await tester.pumpAndSettle();

      final exported = written.last.contents;
      final parsed = CsvParser.parse(exported)!;
      expect(parsed.rows.single[0], 'Kola');
      expect(parsed.rows.single[1], '₺25,00');
      expect(parsed.rows.single[4], '8690');
      expect(parsed.rows.single[11], '7', reason: 'Güncel stok.');
    });

    testWidgets('kategori ve tedarikçi dışa aktarılır', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const Key('export_categories')));
      await tester.pumpAndSettle();
      expect(written.last.contents, contains('Kategori;Sıra;Durum'));

      await tester.tap(find.byKey(const Key('export_suppliers')));
      await tester.pumpAndSettle();
      expect(written.last.contents, contains('Tedarikçi;Telefon'));
    });

    testWidgets('kaydetme iptal edilirse dosya YAZILMAZ', (tester) async {
      await pump(tester, picker: (_) async => null);

      await tester.tap(find.byKey(ImportExportScreen.templateKey));
      await tester.pumpAndSettle();

      expect(written, isEmpty);
      expect(find.text(AppStringsTr.exportCancelled), findsOneWidget);
    });
  });

  testWidgets('docs/20 §1 — satış import edilemez uyarısı EKRANDA', (
    tester,
  ) async {
    // Kodda engellemek yetmez: kullanıcı "neden yok?" diye aramadan önce
    // cevabı görmelidir.
    await pump(tester);

    expect(find.text(AppStringsTr.importForbiddenNotice), findsOneWidget);
  });
}
