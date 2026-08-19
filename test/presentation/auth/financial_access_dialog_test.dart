/// Finansal erişim dialogu widget testleri — **docs/17 §7 · docs/22 F9 ·
/// BR-AUTH-012/013/016 · REQ-AUTH-015/019/021 · EC-DASH-001…004 · EC-REC-012**
///
/// docs/27 §4: widget testleri **seçicidir.** Buradaki testler sessizce
/// ihlal edilebilecek kilit kurallarını korur:
///
/// | Test | Kural |
/// |---|---|
/// | Kilit kapalıyken **hiçbir finansal sorgu çalışmaz** (sayaç 0) | BR-AUTH-012 · REQ-AUTH-019 |
/// | "Vazgeç" kilidi açmaz | EC-DASH-003 |
/// | Yanlış parola kilidi açmaz, mesaj servisten gelir | EC-DASH-002 |
/// | Kilit açıkken parola **tekrar sorulmaz** | EC-DASH-004/013 · BR-AUTH-016 |
/// | Kurtarma kaydı yoksa "Şifremi unuttum" **gösterilmez** | EC-REC-012 |
/// | Ekranda teknik detay / hata kodu yok | REQ-UX-008 · REQ-SEC-007 |
///
/// Golden (piksel) testi **yazılmaz** (docs/27 §4).
library;

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/presentation/auth/financial_access_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

const String kDashboardPassword = 'dashboard-parolasi-9Z2K';

/// Faz 8'in dashboard/rapor sorgusunu temsil eden **casus** kaynak.
///
/// BR-AUTH-012'nin tek doğrulanabilir kanıtı budur: kilit kapalıyken bu
/// sayacın **artmamış** olması gerekir (docs/27 §6.1b — sorgu sayacı).
class SpyFinancialSource {
  int queryCount = 0;

  Future<int> totalRevenueMinor() async {
    queryCount++;
    return 123400;
  }
}

/// Kapının **çağıranı** ne yaptı?
///
/// EC-DASH-003'un iki yarisi vardir: (1) sorgu calismaz, (2) ekran acilmaz.
/// Birincisini `SpyFinancialSource` korur — ama onu servisteki `guard` da
/// koruyor, yani tek basina kapinin sozlesmesini kanitlamaz. Ikincisini
/// yalnizca bu sayac korur: Faz 8 dashboard'u `ensureFinancialAccess`
/// `false` dondugunde ekrani **hic acmamalidir**.
class _ScreenOpenSpy {
  int openCount = 0;
}

/// Faz 8'in yapacağı çağrının aynısı: **önce kapı, sonra sorgu.**
class _DashboardEntry extends ConsumerWidget {
  static const Key openKey = Key('test_open_dashboard');

  final SpyFinancialSource source;
  final _ScreenOpenSpy screen;

  const _DashboardEntry(this.source, this.screen);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: openKey,
          onPressed: () async {
            // EC-DASH-003: kapı `false` dönerse ekran açılmaz, veri yüklenmez.
            if (!await ensureFinancialAccess(context, ref)) return;
            screen.openCount++;
            await ref
                .read(financialAccessProvider)
                .guard(source.totalRevenueMinor);
          },
          child: const Text('Dashboard'),
        ),
      ),
    );
  }
}

void main() {
  late CanteenDatabase db;
  late SpyFinancialSource source;
  late _ScreenOpenSpy screen;

  setUp(() {
    db = memoryDatabase();
    source = SpyFinancialSource();
    screen = _ScreenOpenSpy();
  });
  tearDown(() => db.close());

  /// Ekranın dışından servislere erişim; aynı veritabanını kullanır.
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

  Future<void> setDashboardPassword() => withServices(
    (container) =>
        container.read(financialAccessProvider).setPassword(kDashboardPassword),
  );

  Future<void> generateRecoveryCode() => withServices(
    (container) =>
        container.read(recoveryCodeServiceProvider).generateInitial(),
  );

  /// Ekranın container'ı — kilit **bellekte** olduğu için (BR-AUTH-016) test
  /// doğrulaması aynı container üzerinden yapılmalıdır.
  late ProviderContainer screenContainer;

  Future<void> pumpEntry(WidgetTester tester) async {
    screenContainer = ProviderContainer(
      overrides: [canteenDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(screenContainer.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: screenContainer,
        child: MaterialApp(home: _DashboardEntry(source, screen)),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool isUnlocked() => screenContainer.read(financialAccessProvider).isUnlocked;

  Future<void> openGate(WidgetTester tester) async {
    await tester.tap(find.byKey(_DashboardEntry.openKey));
    await tester.pumpAndSettle();
  }

  Future<void> enterPassword(WidgetTester tester, String password) async {
    await tester.enterText(
      find.byKey(FinancialAccessDialog.passwordFieldKey),
      password,
    );
    await tester.tap(find.byKey(FinancialAccessDialog.submitButtonKey));
    await tester.pumpAndSettle();
  }

  group('BR-AUTH-012 — parola doğrulanmadan sorgu çalışmaz', () {
    testWidgets('dialog açılıp "Vazgeç" ile kapatılınca sayaç 0 kalır', (
      tester,
    ) async {
      await setDashboardPassword();
      await pumpEntry(tester);

      await openGate(tester);
      expect(
        find.byType(FinancialAccessDialog),
        findsOneWidget,
        reason: 'EC-DASH-001: kilit kapalıyken parola sorulur.',
      );
      expect(
        source.queryCount,
        0,
        reason:
            'BR-AUTH-012: dialog AÇIKKEN hiçbir finansal sorgu '
            'çalıştırılmamalıdır.',
      );

      await tester.tap(find.byKey(FinancialAccessDialog.cancelButtonKey));
      await tester.pumpAndSettle();

      expect(
        source.queryCount,
        0,
        reason:
            'BR-AUTH-012 · EC-DASH-003: vazgeçildiğinde de hiçbir ciro/kâr '
            'verisi yüklenmez.',
      );
      expect(isUnlocked(), isFalse, reason: 'EC-DASH-003: kilit kapalı kalır.');
      expect(
        screen.openCount,
        0,
        reason:
            'EC-DASH-003: vazgeçildiğinde ekran AÇILMAZ. Sayaç 0 kalması '
            'yetmez — onu servisteki guard da sağlıyor; kapının kendi '
            'sözleşmesini yalnızca bu iddia korur.',
      );
    });

    testWidgets('Esc ile kapatmak da vazgeçmedir — EC-DASH-003', (
      tester,
    ) async {
      await setDashboardPassword();
      await pumpEntry(tester);

      await openGate(tester);
      expect(find.byType(FinancialAccessDialog), findsOneWidget);

      // "Vazgeç" butonu `pop(false)` yapar; `Esc` ise `null` döndürür.
      // İkisi ayrı kod yoludur — bu test `?? false` varsayılanını korur.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byType(FinancialAccessDialog), findsNothing);
      expect(source.queryCount, 0);
      expect(isUnlocked(), isFalse, reason: 'EC-DASH-003: kilit kapalı kalır.');
      expect(
        screen.openCount,
        0,
        reason: 'EC-DASH-003: Esc ile çıkışta ekran açılmaz.',
      );
    });

    testWidgets('yanlış parola sorguyu çalıştırmaz ve kilidi açmaz', (
      tester,
    ) async {
      await setDashboardPassword();
      await pumpEntry(tester);

      await openGate(tester);
      await enterPassword(tester, 'yanlis-parola');

      expect(source.queryCount, 0);
      expect(isUnlocked(), isFalse);
      expect(screen.openCount, 0, reason: 'EC-DASH-002: ekran açılmaz.');
      expect(
        find.byType(FinancialAccessDialog),
        findsOneWidget,
        reason: 'Hatalı denemede dialog açık kalır ve mesaj gösterilir.',
      );
      expect(find.byType(Icon), findsWidgets);
    });

    testWidgets('doğru parola kilidi açar ve sorgu ancak o zaman çalışır', (
      tester,
    ) async {
      await setDashboardPassword();
      await pumpEntry(tester);

      await openGate(tester);
      await enterPassword(tester, kDashboardPassword);

      expect(find.byType(FinancialAccessDialog), findsNothing);
      expect(isUnlocked(), isTrue);
      expect(
        source.queryCount,
        1,
        reason: 'Kilit açıldıktan sonra sorgu kapıdan geçer.',
      );
      expect(screen.openCount, 1, reason: 'Kapı açılınca ekran da açılır.');
    });
  });

  testWidgets('kilit açıkken parola tekrar sorulmaz — EC-DASH-004/013', (
    tester,
  ) async {
    await setDashboardPassword();
    await pumpEntry(tester);

    await openGate(tester);
    await enterPassword(tester, kDashboardPassword);
    expect(source.queryCount, 1);

    // Dashboard ↔ Raporlar geçişini temsil eder: aynı oturumda ikinci giriş.
    await openGate(tester);

    expect(
      find.byType(FinancialAccessDialog),
      findsNothing,
      reason: 'BR-AUTH-016: kilit oturum kapsamlıdır, parola tekrar sorulmaz.',
    );
    expect(source.queryCount, 2);
  });

  group('"Şifremi unuttum" görünürlüğü — EC-REC-012', () {
    testWidgets('kurtarma kaydı yokken gösterilmez', (tester) async {
      await setDashboardPassword();
      await pumpEntry(tester);

      await openGate(tester);

      expect(
        find.byKey(FinancialAccessDialog.forgotButtonKey),
        findsNothing,
        reason:
            'EC-REC-012: kurtarma kaydı olmayan kurulumda var olmayan bir '
            'kurtarma yolu önerilmez.',
      );
      expect(find.text(AppStringsTr.financialAccessForgotAction), findsNothing);
    });

    testWidgets('cevap gelmeden ÖNCE gösterilmez — güvenli varsayılan', (
      tester,
    ) async {
      await setDashboardPassword();
      await generateRecoveryCode();
      await pumpEntry(tester);

      // `isAvailable()` asenkrondur. Cevap gelene kadar var olmayan bir
      // kurtarma yolu önerilmemelidir; bu kare `pumpAndSettle` ile
      // atlandığı için ayrıca sabitlenir (EC-REC-012).
      await tester.tap(find.byKey(_DashboardEntry.openKey));
      await tester.pump();

      expect(find.byType(FinancialAccessDialog), findsOneWidget);
      expect(
        find.byKey(FinancialAccessDialog.forgotButtonKey),
        findsNothing,
        reason:
            'EC-REC-012: cevap gelmeden bağlantı gösterilmez — varsayılan '
            '`false` olmalıdır.',
      );

      // Cevap geldiğinde görünür hale gelir.
      await tester.pumpAndSettle();
      expect(find.byKey(FinancialAccessDialog.forgotButtonKey), findsOneWidget);
    });

    testWidgets('kullanılabilir kod varken gösterilir', (tester) async {
      await setDashboardPassword();
      await generateRecoveryCode();
      await pumpEntry(tester);

      await openGate(tester);

      expect(find.byKey(FinancialAccessDialog.forgotButtonKey), findsOneWidget);
    });
  });

  testWidgets('ekranda teknik detay ve hata kodu gösterilmez', (tester) async {
    await setDashboardPassword();
    await generateRecoveryCode();
    await pumpEntry(tester);

    await openGate(tester);
    await enterPassword(tester, 'yanlis-parola');

    final visibleText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join('\n');

    for (final forbidden in const [
      'auth_',
      'recovery_code_',
      'financial_access_',
      'Failure(',
      'Exception',
      'sqlite',
      '.dart',
      'technicalDetail',
    ]) {
      expect(
        visibleText.contains(forbidden),
        isFalse,
        reason: 'Ekranda teknik detay görünüyor: $forbidden → $visibleText',
      );
    }
  });
}
