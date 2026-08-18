/// Ayarlar → Finansal Erişim widget testleri — **docs/17 §8, §9 ·
/// BR-AUTH-010/014/016 · REQ-AUTH-018/022/028 · EC-DASH-008/014 ·
/// EC-REC-008/009**
///
/// docs/27 §4: widget testleri **seçicidir.** Buradaki testler sessizce
/// ihlal edilebilecek kuralları korur:
///
/// | Test | Kural |
/// |---|---|
/// | Ekran kilidin **arkasında değildir** | BR-AUTH-014 · EC-DASH-014 |
/// | Mevcut parola yanlışsa değişiklik reddedilir | EC-DASH-008 · BR-AUTH-010 |
/// | Parola değişikliği kilidi **açmaz** | BR-AUTH-016 |
/// | Yanlış parolayla kod yenilenemez | EC-REC-008 |
/// | Doğru parolayla üretilen kod **gerçekten geçerlidir** | EC-REC-009 |
/// | Yeni kod onaylanmadan ekrandan kaldırılamaz | REQ-AUTH-023 · EC-REC-006 deseni |
/// | Ekranda teknik detay / hata kodu yok | REQ-UX-008 · REQ-SEC-007 |
///
/// Golden (piksel) testi **yazılmaz** (docs/27 §4).
library;

import 'package:canteen/application/auth/financial_access_failures.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/presentation/settings/financial_access_settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

const String kDashboardPassword = 'dashboard-parolasi-9Z2K';
const String kNewDashboardPassword = 'yeni-dashboard-parolasi-3M8V';

void main() {
  late CanteenDatabase db;
  late ProviderContainer screenContainer;

  String? savedContents;

  setUp(() {
    db = memoryDatabase();
    savedContents = null;
  });
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

  Future<String> prepare() async {
    await withServices(
      (container) => container
          .read(financialAccessProvider)
          .setPassword(kDashboardPassword),
    );
    final code = await withServices(
      (container) =>
          container.read(recoveryCodeServiceProvider).generateInitial(),
    );
    return code.valueOrNull!;
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    screenContainer = ProviderContainer(
      overrides: [canteenDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(screenContainer.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: screenContainer,
        child: MaterialApp(
          home: FinancialAccessSettingsScreen(
            savePicker: (name) async => '/tmp/$name',
            fileWriter: (path, contents) async => savedContents = contents,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool isUnlocked() => screenContainer.read(financialAccessProvider).isUnlocked;

  Future<void> tapKey(WidgetTester tester, Key key) async {
    await tester.ensureVisible(find.byKey(key));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(key));
    await tester.pumpAndSettle();
  }

  Future<void> changePassword(
    WidgetTester tester, {
    required String current,
    String next = kNewDashboardPassword,
  }) async {
    await tester.enterText(
      find.byKey(FinancialAccessSettingsScreen.currentPasswordFieldKey),
      current,
    );
    await tester.enterText(
      find.byKey(FinancialAccessSettingsScreen.newPasswordFieldKey),
      next,
    );
    await tester.enterText(
      find.byKey(FinancialAccessSettingsScreen.newPasswordConfirmFieldKey),
      next,
    );
    await tapKey(tester, FinancialAccessSettingsScreen.changePasswordButtonKey);
  }

  Future<void> regenerate(WidgetTester tester, String password) async {
    await tester.enterText(
      find.byKey(FinancialAccessSettingsScreen.regeneratePasswordFieldKey),
      password,
    );
    await tapKey(tester, FinancialAccessSettingsScreen.regenerateButtonKey);
  }

  Future<bool> verify(String password) => withServices(
    (container) =>
        container.read(financialAccessProvider).verifyPassword(password),
  );

  testWidgets('ekran kilit sorulmadan açılır — BR-AUTH-014 · EC-DASH-014', (
    tester,
  ) async {
    await prepare();
    await pumpScreen(tester);

    expect(
      find.byKey(FinancialAccessSettingsScreen.currentPasswordFieldKey),
      findsOneWidget,
    );
    expect(
      isUnlocked(),
      isFalse,
      reason:
          'Ayarlar kilit kapsamı dışındadır; kilit de kendiliğinden açılmaz.',
    );
  });

  group('dashboard parolasını değiştir (docs/17 §9)', () {
    testWidgets('mevcut parola yanlışsa reddedilir — EC-DASH-008', (
      tester,
    ) async {
      await prepare();
      await pumpScreen(tester);

      await changePassword(tester, current: 'yanlis-parola');

      expect(
        find.text(FinancialAccessFailures.currentPasswordWrong.userMessage),
        findsOneWidget,
      );
      expect(
        await verify(kDashboardPassword),
        isTrue,
        reason: 'Reddedilen değişiklik parolayı değiştirmemelidir.',
      );
      expect(await verify(kNewDashboardPassword), isFalse);
    });

    testWidgets('doğru parolayla değişir ve kilidi AÇMAZ', (tester) async {
      await prepare();
      await pumpScreen(tester);

      await changePassword(tester, current: kDashboardPassword);

      expect(await verify(kNewDashboardPassword), isTrue);
      expect(await verify(kDashboardPassword), isFalse);
      expect(
        isUnlocked(),
        isFalse,
        reason:
            'BR-AUTH-016: parolayı değiştirmek finansal erişim açmaz; '
            'kilit yalnızca doğrulanmış girişle açılır.',
      );
    });
  });

  group('yeni kurtarma kodu üret (docs/17 §8)', () {
    testWidgets('parola yanlışsa reddedilir — EC-REC-008', (tester) async {
      final code = await prepare();
      await pumpScreen(tester);

      await regenerate(tester, 'yanlis-parola');

      expect(
        find.text(FinancialAccessFailures.currentPasswordWrong.userMessage),
        findsOneWidget,
      );
      expect(
        find.byKey(FinancialAccessSettingsScreen.newCodeTextKey),
        findsNothing,
      );

      // EC-REC-008: eski kod geçerli kalır.
      final reset = await withServices(
        (container) => container
            .read(recoveryCodeServiceProvider)
            .resetPasswordWithCode(code: code, newPassword: 'gecici-parola'),
      );
      expect(reset.isOk, isTrue);
    });

    testWidgets('doğru parolayla yeni kod üretilir ve GEÇERLİDİR — EC-REC-009', (
      tester,
    ) async {
      final oldCode = await prepare();
      await pumpScreen(tester);

      await regenerate(tester, kDashboardPassword);

      final newCode = tester
          .widget<SelectableText>(
            find.byKey(FinancialAccessSettingsScreen.newCodeTextKey),
          )
          .data!;
      expect(newCode, isNot(oldCode));
      expect(
        RegExp(
          r'^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$',
        ).hasMatch(newCode),
        isTrue,
      );

      // Yeni kod gerçekten kurtarma yapabilmelidir (yalnızca ekranda üretilmiş
      // bir dize değildir).
      final reset = await withServices(
        (container) => container
            .read(recoveryCodeServiceProvider)
            .resetPasswordWithCode(
              code: newCode,
              newPassword: kNewDashboardPassword,
            ),
      );
      expect(reset.isOk, isTrue);
      expect(await verify(kNewDashboardPassword), isTrue);
    });

    testWidgets('yeni kod onay verilmeden ekrandan kaldırılamaz', (
      tester,
    ) async {
      await prepare();
      await pumpScreen(tester);

      await regenerate(tester, kDashboardPassword);

      final confirm = tester.widget<FilledButton>(
        find.descendant(
          of: find.byKey(FinancialAccessSettingsScreen.newCodeConfirmButtonKey),
          matching: find.byType(FilledButton),
        ),
      );
      expect(
        confirm.onPressed,
        isNull,
        reason: 'REQ-AUTH-023: kod bir daha gösterilemez; onay şarttır.',
      );

      await tapKey(
        tester,
        FinancialAccessSettingsScreen.newCodeSavedCheckboxKey,
      );
      await tapKey(
        tester,
        FinancialAccessSettingsScreen.newCodeConfirmButtonKey,
      );

      expect(
        find.byKey(FinancialAccessSettingsScreen.newCodeTextKey),
        findsNothing,
      );
    });

    testWidgets('yeni kod dosyaya kaydedilebilir — REQ-AUTH-022', (
      tester,
    ) async {
      await prepare();
      await pumpScreen(tester);

      await regenerate(tester, kDashboardPassword);
      final newCode = tester
          .widget<SelectableText>(
            find.byKey(FinancialAccessSettingsScreen.newCodeTextKey),
          )
          .data!;

      await tapKey(tester, FinancialAccessSettingsScreen.newCodeSaveButtonKey);

      expect(savedContents, contains(newCode));
    });
  });

  testWidgets('ekranda teknik detay ve hata kodu gösterilmez', (tester) async {
    await prepare();
    await pumpScreen(tester);

    await changePassword(tester, current: 'yanlis-parola');

    final text = [
      ...tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? ''),
      ...tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .map((w) => w.data ?? ''),
    ].join('\n');

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
        text.contains(forbidden),
        isFalse,
        reason: 'Ekranda teknik detay görünüyor: $forbidden → $text',
      );
    }
  });
}
