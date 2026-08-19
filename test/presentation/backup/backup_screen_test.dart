/// Yedekleme ekranı — **docs/19 §3–§4 · REQ-BKUP-007/008/014/016/018/020**
///
/// ## Bu dosya dosya sistemine DOKUNMAZ
///
/// Yedek **oluşturma** ve **geri yükleme** gerçek `VACUUM INTO`, ZIP ve dosya
/// takası yapar; bunlar `test/application/backup/` altında **42 testle** ve
/// gerçek dosya tabanlı veritabanıyla kapsanmıştır. Aynı işi widget testinde
/// tekrarlamak güvenilir değildir: `testWidgets`'in sahte zamanı gerçek dosya
/// I/O'sunu ilerletmez ve `tester.tap` + `runAsync` birlikte kilitlenir.
///
/// Buradaki soru farklıdır: **ekran ne gösteriyor ve neyi engelliyor?**
///
/// Aynı sebeple "bozuk yedek özet ekranına ulaşmaz" iddiası da burada
/// **değildir**: doğrulama gerçek arşiv okur. O iddia
/// `restore_service_test.dart` içinde, doğrulamanın `Err` döndüğü ve mevcut
/// verilere dokunulmadığı gösterilerek kapsanır.
///
/// | Test | Kural |
/// |---|---|
/// | **Yazarak onay** olmadan düğme pasif | REQ-BKUP-008 |
/// | `Esc` onay SAYILMAZ | REQ-BKUP-008 |
/// | Karşılaştırmalı özet gösterilir | REQ-BKUP-007 |
/// | Kaybolacak satış AÇIKÇA vurgulanır | docs/19 §4 |
/// | Parola uyarısı ONAYDAN ÖNCE gösterilir | REQ-BKUP-020 |
/// | Eksik görsel bilgilendirir, ENGELLEMEZ | REQ-BKUP-018 |
/// | Eski şema uyarısı | REQ-BKUP-014 |
/// | Hatırlatma çubuğu 7/30 günde görünür | REQ-BKUP-016 |
library;

import 'dart:io';

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/application/backup/backup_manifest.dart';
import 'package:canteen/application/backup/restore_service.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/db/app_setting_keys.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, Category, Product, Sale, SaleItem, StockMovement, Supplier;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/data/files/providers.dart';
import 'package:canteen/presentation/backup/backup_screen.dart';
import 'package:canteen/presentation/backup/restore_confirm_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

/// Sentetik önizleme — hiçbir arşiv okunmaz.
RestorePreview preview({
  BackupCounts? backup,
  BackupCounts? current,
  bool migrationRequired = false,
  int missingImageCount = 0,
}) => RestorePreview(
  file: File('yedek.canteenbackup'),
  metadata: BackupMetadata(
    backupFormatVersion: 1,
    schemaVersion: 1,
    appVersion: '1.2.0',
    createdAtUtc: DateTime.utc(2026, 8, 13, 12, 2),
    createdBy: 'ahmet',
    platform: 'macos',
    counts: backup ?? _counts(products: 512, sales: 8340, images: 87),
    databaseBytes: 0,
    imagesBytes: 0,
  ),
  current: current ?? _counts(products: 489, sales: 8401, images: 85),
  migrationRequired: migrationRequired,
  missingImageCount: missingImageCount,
);

BackupCounts _counts({int products = 0, int sales = 0, int images = 0}) =>
    BackupCounts(
      products: products,
      categories: 0,
      suppliers: 0,
      sales: sales,
      saleItems: 0,
      stockMovements: 0,
      auditLogs: 0,
      images: images,
    );

void main() {
  late TempAppPaths temp;
  late CanteenDatabase db;
  late FakeClock clock;

  setUp(() async {
    temp = await TempAppPaths.create();
    clock = FakeClock(testEpochUtc);
    db = memoryDatabase(clock: clock.fn);
  });

  tearDown(() async {
    await db.close();
    temp.dispose();
  });

  Future<void> pumpScreen(
    WidgetTester tester, {
    BackupFilePicker? picker,
  }) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          canteenDatabaseProvider.overrideWithValue(db),
          appPathsProvider.overrideWithValue(temp.paths),
        ],
        child: MaterialApp(home: BackupScreen(filePicker: picker)),
      ),
    );
    await tester.pumpAndSettle();
  }

  // -------------------------------------------------------------------------
  // Onay dialogu — docs/19 §4
  // -------------------------------------------------------------------------

  group('docs/19 §4 — geri yükleme onayı', () {
    /// Dialogun DÖNDÜĞÜ değer buraya yazılır.
    ///
    /// Yalnızca "dialog kapandı mı" diye bakmak yetmez: `Esc` ile dönen değer
    /// yanlışlıkla `true` olsa dialog yine kapanmış görünürdü.
    late List<bool> captured;

    Future<void> pumpDialog(WidgetTester tester, RestorePreview value) async {
      captured = <bool>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => captured.add(
                await showRestoreConfirmDialog(context, preview: value),
              ),
              child: const Text('aç'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('aç'));
      await tester.pumpAndSettle();
    }

    FilledButton submitButton(WidgetTester tester) => tester
        .widget<FilledButton>(find.byKey(const Key('restore_confirm_submit')));

    testWidgets('REQ-BKUP-008 — YAZARAK onay olmadan düğme PASİF', (
      tester,
    ) async {
      await pumpDialog(tester, preview());

      expect(submitButton(tester).onPressed, isNull);

      for (final wrong in ['evet', 'geri yükle', 'GERI YUKLE', ' ']) {
        await tester.enterText(
          find.byKey(const Key('restore_confirm_field')),
          wrong,
        );
        await tester.pumpAndSettle();
        expect(
          submitButton(tester).onPressed,
          isNull,
          reason: 'Yanlış metin: "$wrong"',
        );
      }

      await tester.enterText(
        find.byKey(const Key('restore_confirm_field')),
        RestoreService.confirmationPhrase,
      );
      await tester.pumpAndSettle();
      expect(submitButton(tester).onPressed, isNotNull);
    });

    testWidgets('onaylanınca `true` DÖNER', (tester) async {
      await pumpDialog(tester, preview());
      await tester.enterText(
        find.byKey(const Key('restore_confirm_field')),
        RestoreService.confirmationPhrase,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('restore_confirm_submit')));
      await tester.pumpAndSettle();

      expect(captured, [true]);
    });

    testWidgets('[Vazgeç] `false` DÖNER', (tester) async {
      await pumpDialog(tester, preview());

      await tester.tap(find.text(AppStringsTr.cancelAction));
      await tester.pumpAndSettle();

      expect(captured, [false]);
    });

    testWidgets('Esc onay SAYILMAZ — ayrı kod yolu', (tester) async {
      // `[Vazgeç]` açıkça `false` döndürür; `Esc` `null`. `?? false`
      // olmasaydı Esc geri yüklemeyi BAŞLATIRDI.
      await pumpDialog(tester, preview());

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('restore_confirm_dialog')), findsNothing);
      expect(
        captured,
        [false],
        reason:
            'Dialogun KAPANMASI yetmez — DÖNEN DEĞER de `false` olmalıdır. '
            '`?? false` olmasaydı Esc geri yüklemeyi BAŞLATIRDI ve dialog '
            'yine kapanmış görünürdü.',
      );
    });

    testWidgets('REQ-BKUP-007 — karşılaştırmalı özet gösterilir', (
      tester,
    ) async {
      await pumpDialog(tester, preview());

      expect(find.text(AppStringsTr.restoreColumnBackup), findsOneWidget);
      expect(find.text(AppStringsTr.restoreColumnCurrent), findsOneWidget);
      expect(find.text(AppStringsTr.restoreRowProducts), findsOneWidget);
      expect(find.text(AppStringsTr.restoreRowSales), findsOneWidget);
      // docs/19 §4 ekran örneğindeki sayılar.
      expect(find.text('512'), findsOneWidget);
      expect(find.text('489'), findsOneWidget);
      expect(find.text('8340'), findsOneWidget);
      expect(find.text('8401'), findsOneWidget);
    });

    testWidgets('docs/19 §4 — kaybolacak satış AÇIKÇA vurgulanır', (
      tester,
    ) async {
      // Yedekte 8340, şu anda 8401 → 61 satış kaybolacak.
      await pumpDialog(tester, preview());

      expect(find.byKey(const Key('restore_sales_at_risk')), findsOneWidget);
      expect(find.textContaining('61'), findsOneWidget);
    });

    testWidgets('şu anki veri DAHA AZSA vurgu gösterilmez', (tester) async {
      await pumpDialog(
        tester,
        preview(backup: _counts(sales: 900), current: _counts(sales: 100)),
      );

      expect(find.byKey(const Key('restore_sales_at_risk')), findsNothing);
    });

    testWidgets('REQ-BKUP-020 — parola uyarısı ONAYDAN ÖNCE gösterilir', (
      tester,
    ) async {
      await pumpDialog(tester, preview());

      expect(
        find.byKey(const Key('restore_password_warning')),
        findsOneWidget,
        reason:
            'Kullanıcı parolaların ve oturumun değişeceğini onaydan ÖNCE '
            'öğrenmelidir.',
      );
    });

    testWidgets('REQ-BKUP-018 — eksik görsel BİLGİLENDİRİR, engellemez', (
      tester,
    ) async {
      await pumpDialog(tester, preview(missingImageCount: 3));

      expect(find.byKey(const Key('restore_missing_images')), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('restore_confirm_field')),
        RestoreService.confirmationPhrase,
      );
      await tester.pumpAndSettle();
      expect(
        submitButton(tester).onPressed,
        isNotNull,
        reason: 'Eksik görsel geri yüklemeyi ENGELLEMEZ.',
      );
    });

    testWidgets('eksik görsel yoksa uyarı gösterilmez', (tester) async {
      await pumpDialog(tester, preview());

      expect(find.byKey(const Key('restore_missing_images')), findsNothing);
    });

    testWidgets('REQ-BKUP-014 — eski şema uyarısı gösterilir', (tester) async {
      await pumpDialog(tester, preview(migrationRequired: true));

      expect(find.byKey(const Key('restore_migration_notice')), findsOneWidget);
    });

    testWidgets('aynı şemada migration uyarısı YOK', (tester) async {
      await pumpDialog(tester, preview());

      expect(find.byKey(const Key('restore_migration_notice')), findsNothing);
    });
  });

  // -------------------------------------------------------------------------
  // Ekran
  // -------------------------------------------------------------------------

  group('yedekleme ekranı', () {
    testWidgets('yedek yokken boş durum ve "hiç yedek alınmadı"', (
      tester,
    ) async {
      await pumpScreen(tester);

      expect(find.text(AppStringsTr.backupListEmpty), findsOneWidget);
      expect(find.text(AppStringsTr.backupNeverTaken), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(BackupScreen.createButtonKey))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('docs/19 §3 — otomatik yedek uyarısı GÖSTERİLİR', (
      tester,
    ) async {
      // "Aynı diskte durur; disk arızasına karşı koruma sağlamaz."
      await pumpScreen(tester);

      expect(find.text(AppStringsTr.backupAutoNotice), findsOneWidget);
    });
  });

  // -------------------------------------------------------------------------
  // REQ-BKUP-016 — hatırlatma çubuğu
  // -------------------------------------------------------------------------

  group('REQ-BKUP-016 — hatırlatma çubuğu', () {
    /// Yedek almadan "son yedek zamanı"nı yazar — dosya I/O'suna gerek yok.
    Future<void> setLastBackup(DateTime at) => AppSettingsDao(
      db,
    ).write(AppSettingKeys.lastBackupAt, '${at.millisecondsSinceEpoch}');

    Future<void> pumpBanner(WidgetTester tester, {Key? instanceKey}) async {
      tester.view.physicalSize = const Size(1200, 400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            canteenDatabaseProvider.overrideWithValue(db),
            appPathsProvider.overrideWithValue(temp.paths),
          ],
          child: MaterialApp(
            home: Scaffold(body: BackupReminderBanner(key: instanceKey)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('hiç yedek yoksa çubuk GÖRÜNÜR', (tester) async {
      await pumpBanner(tester);

      expect(find.byKey(BackupReminderBanner.bannerKey), findsOneWidget);
      expect(find.text(AppStringsTr.backupReminderNever), findsOneWidget);
    });

    testWidgets('yeni yedek varsa çubuk GÖRÜNMEZ', (tester) async {
      await setLastBackup(testEpochUtc);

      await pumpBanner(tester);

      expect(find.byKey(BackupReminderBanner.bannerKey), findsNothing);
    });

    testWidgets('SINIR — 7 günün bir saniye altı görünmez', (tester) async {
      await setLastBackup(
        testEpochUtc.subtract(
          const Duration(days: 7) - const Duration(seconds: 1),
        ),
      );

      await pumpBanner(tester);

      expect(find.byKey(BackupReminderBanner.bannerKey), findsNothing);
    });

    testWidgets('SINIR — 7 gün dolunca GÖRÜNÜR', (tester) async {
      await setLastBackup(testEpochUtc.subtract(const Duration(days: 7)));

      await pumpBanner(tester);

      expect(find.byKey(BackupReminderBanner.bannerKey), findsOneWidget);
      expect(find.textContaining('7 gündür'), findsOneWidget);
    });

    testWidgets('kapatılabilir, ama yeniden kurulunca GERİ GELİR', (
      tester,
    ) async {
      // docs/19 §3: "Çubuk kapatılabilir ama ertesi gün geri gelir."
      //
      // Kapatma **kalıcı değildir**: hiçbir yere yazılmaz. Testin farklı bir
      // `key` vermesi bilinçlidir — aynı key ile Flutter aynı `State`'i
      // yeniden kullanır ve "yeni bir örnek" senaryosu hiç kurulmazdı.
      await pumpBanner(tester, instanceKey: const ValueKey('ilk'));

      await tester.tap(find.byKey(BackupReminderBanner.dismissKey));
      await tester.pumpAndSettle();
      expect(find.byKey(BackupReminderBanner.bannerKey), findsNothing);

      await pumpBanner(tester, instanceKey: const ValueKey('ikinci'));
      expect(
        find.byKey(BackupReminderBanner.bannerKey),
        findsOneWidget,
        reason: 'Kapatma kalıcı olsaydı uyarı bir daha hiç görünmezdi.',
      );
    });
  });
}
