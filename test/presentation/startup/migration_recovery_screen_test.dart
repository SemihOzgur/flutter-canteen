/// Kurtarma ekranı — **docs/06 §3 · REQ-MIG-006 · REQ-DATA-004**
///
/// docs/06 §3 dört adım tanımlar; bu ekran 1–2'yi gösterir, 3–4'ü çağırana
/// devreder.
///
/// ## Kapsanan requirement'lar (Faz 11 izlenebilirliği)
///
/// - **REQ-MIG-006** — yarım migration açılışta kurtarılır
library;

import 'dart:async';

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/presentation/startup/migration_recovery_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    String? snapshotPath = '/tmp/premigration_v1_1.sqlite',
    Future<bool> Function()? onRestore,
    VoidCallback? onQuit,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MigrationRecoveryScreen(
          snapshotPath: snapshotPath,
          onRestore: onRestore ?? () async => true,
          onQuit: onQuit ?? () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('durum bildirilir ve geri yükleme ÖNERİLİR', (tester) async {
    // docs/06 §3 adım 1–2.
    await pump(tester);

    expect(find.text(AppStringsTr.migrationRecoveryTitle), findsOneWidget);
    expect(
      find.byKey(MigrationRecoveryScreen.restoreButtonKey),
      findsOneWidget,
    );
    expect(find.byKey(MigrationRecoveryScreen.quitButtonKey), findsOneWidget);
  });

  testWidgets('bu bir ÇIKIŞSIZ hata ekranı DEĞİLDİR', (tester) async {
    // Kullanıcının verisi kaybolmuş değildir; kurtarılabilir bir durumu
    // kurtarılamaz gibi anlatmak, kullanıcıyı dosyaları elle karıştırmaya
    // iter ve asıl kayıp o zaman yaşanır.
    var restored = false;
    await pump(tester, onRestore: () async => restored = true);

    await tester.tap(find.byKey(MigrationRecoveryScreen.restoreButtonKey));
    await tester.pumpAndSettle();

    expect(restored, isTrue);
  });

  testWidgets('SNAPSHOT YOKSA geri yükleme SUNULMAZ', (tester) async {
    // Olmayan bir yedeği ima eden düğme, basıldığında hata veren düğmedir.
    await pump(tester, snapshotPath: null);

    expect(find.byKey(MigrationRecoveryScreen.restoreButtonKey), findsNothing);
    expect(
      tester.widget<Text>(find.byKey(MigrationRecoveryScreen.messageKey)).data,
      AppStringsTr.migrationRecoveryNoSnapshot,
    );
    // docs/06 §3 adım 4 — yarım şemayla çalışmaya izin verilmez; tek çıkış
    // kapatmaktır.
    expect(find.byKey(MigrationRecoveryScreen.quitButtonKey), findsOneWidget);
  });

  testWidgets('kapatmak geri yüklemeden ÇIKIŞ verir — docs/06 §3 adım 4', (
    tester,
  ) async {
    var quit = false;
    await pump(tester, onQuit: () => quit = true);

    await tester.tap(find.byKey(MigrationRecoveryScreen.quitButtonKey));
    await tester.pumpAndSettle();

    expect(quit, isTrue);
  });

  testWidgets('geri yükleme BAŞARISIZ olursa ekran kapanmaz, hata söylenir', (
    tester,
  ) async {
    await pump(tester, onRestore: () async => false);

    await tester.tap(find.byKey(MigrationRecoveryScreen.restoreButtonKey));
    await tester.pumpAndSettle();

    expect(find.text(AppStringsTr.migrationRecoveryFailed), findsOneWidget);
    // Kullanıcı yine kapatabilmelidir — çıkışsız bırakılmaz.
    expect(find.byKey(MigrationRecoveryScreen.quitButtonKey), findsOneWidget);
  });

  testWidgets('geri yükleme sürerken düğmeler KİLİTLENİR', (tester) async {
    // Çift tıklama ikinci bir geri yükleme başlatırsa dosyalar yarı yolda
    // birbirine karışır.
    final completer = Completer<bool>();
    await pump(tester, onRestore: () => completer.future);

    await tester.tap(find.byKey(MigrationRecoveryScreen.restoreButtonKey));
    await tester.pump();

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(MigrationRecoveryScreen.restoreButtonKey),
          )
          .onPressed,
      isNull,
    );
    expect(find.text(AppStringsTr.migrationRecoveryWorking), findsOneWidget);

    completer.complete(true);
    await tester.pumpAndSettle();
  });

  testWidgets('mesaj teknik detay SIZDIRMAZ — REQ-SEC-007', (tester) async {
    await pump(tester, snapshotPath: '/veri/yolu/premigration_v1_9.sqlite');

    final text = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? '')
        .join('\n');
    expect(text, isNot(contains('premigration_v1_9')));
    expect(text, isNot(contains('migration_in_progress')));
    expect(text, isNot(contains('user_version')));
  });
}
