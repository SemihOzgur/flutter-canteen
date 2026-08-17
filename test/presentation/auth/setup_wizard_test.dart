/// Kurulum sihirbazı widget testleri — **docs/17 §4 · docs/22 F1 ·
/// REQ-AUTH-016/022/024 · EC-AUTH-008 · EC-DASH-011 · EC-REC-006**
///
/// docs/27 §4: widget testleri **seçicidir.** Buradaki testler sessizce
/// ihlal edilebilecek kurulum kurallarını korur:
///
/// | Test | Kural |
/// |---|---|
/// | "Kodu kaydettim" işaretlenmeden **Devam pasif** | REQ-AUTH-024 · EC-REC-006 |
/// | Kod `XXXX-XXXX-XXXX-XXXX` biçiminde ve bir kez gösterilir | REQ-AUTH-022 |
/// | Sihirbaz **kaldığı adımdan** açılır | EC-AUTH-008 · H6 |
/// | Boş dashboard parolası ile ilerlenemez | EC-DASH-011 · REQ-AUTH-016 |
/// | Uçtan uca kurulum `SetupService.isComplete()` yapar | docs/22 F1 |
/// | Ekranda teknik detay / hata kodu yok | REQ-UX-008 · REQ-SEC-007 |
///
/// Golden (piksel) testi **yazılmaz** (docs/27 §4).
library;

import 'package:canteen/app/app.dart';
import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/app/router.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/application/auth/setup_service.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/presentation/auth/setup_wizard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

const String kUsername = 'kasa';
const String kPassword = 'kasa-parolasi-7Q4X';
const String kDisplayName = 'Kasa Kullanıcısı';
const String kDashboardPassword = 'dashboard-parolasi-9Z2K';

void main() {
  late CanteenDatabase db;

  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  /// Ekranın dışından servislere erişim — testin kurulum ve doğrulama tarafı.
  ///
  /// Ekranın kendi container'ından ayrıdır; ikisi de **aynı** veritabanını
  /// kullanır.
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

  Future<void> createUser() => withServices(
    (container) => container
        .read(authServiceProvider)
        .createUser(
          username: kUsername,
          password: kPassword,
          displayName: kDisplayName,
        ),
  );

  Future<void> setDashboardPassword() => withServices(
    (container) =>
        container.read(financialAccessProvider).setPassword(kDashboardPassword),
  );

  Future<SetupState> currentSetupState() => withServices(
    (container) => container.read(setupServiceProvider).currentState(),
  );

  Future<void> pumpWizard(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [canteenDatabaseProvider.overrideWithValue(db)],
        child: const CanteenApp(initialRoute: AppRoutes.setup),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Adımın birincil butonu — pasifse `onPressed` `null`'dır.
  FilledButton submitButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.descendant(
      of: find.byKey(SetupWizardScreen.submitButtonKey),
      matching: find.byType(FilledButton),
    ),
  );

  /// Buton, varsayılan test penceresinde (800×600) katlamanın altında
  /// kalabilir; ekran kaydırılabilir olduğu için önce görünür kılınır.
  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(SetupWizardScreen.submitButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SetupWizardScreen.submitButtonKey));
    await tester.pumpAndSettle();
  }

  Future<void> completeUserStep(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(SetupWizardScreen.usernameFieldKey),
      kUsername,
    );
    await tester.enterText(
      find.byKey(SetupWizardScreen.displayNameFieldKey),
      kDisplayName,
    );
    await tester.enterText(
      find.byKey(SetupWizardScreen.passwordFieldKey),
      kPassword,
    );
    await tester.enterText(
      find.byKey(SetupWizardScreen.passwordConfirmFieldKey),
      kPassword,
    );
    await tapSubmit(tester);
  }

  Future<void> completeDashboardStep(WidgetTester tester) async {
    await tester.enterText(
      find.byKey(SetupWizardScreen.dashboardPasswordFieldKey),
      kDashboardPassword,
    );
    await tester.enterText(
      find.byKey(SetupWizardScreen.dashboardPasswordConfirmFieldKey),
      kDashboardPassword,
    );
    await tapSubmit(tester);
  }

  group('kaldığı adımdan devam eder — EC-AUTH-008 · H6', () {
    testWidgets('boş veritabanında Adım 1 açılır', (tester) async {
      await pumpWizard(tester);

      expect(find.text(AppStringsTr.setupStepCounterUser), findsOneWidget);
      expect(find.byKey(SetupWizardScreen.usernameFieldKey), findsOneWidget);
    });

    testWidgets('kullanıcı var, dashboard parolası yok → Adım 2 açılır', (
      tester,
    ) async {
      await createUser();

      await pumpWizard(tester);

      expect(
        find.text(AppStringsTr.setupStepCounterDashboardPassword),
        findsOneWidget,
        reason:
            'Sihirbaz üç ayrı transaction\'dır ve yarım kalabilir; ekran ilk '
            'eksik adımdan devam etmelidir (H6).',
      );
      expect(find.byKey(SetupWizardScreen.usernameFieldKey), findsNothing);
      expect(
        find.byKey(SetupWizardScreen.dashboardPasswordFieldKey),
        findsOneWidget,
      );
    });

    testWidgets('kullanıcı + dashboard parolası var → Adım 3 açılır', (
      tester,
    ) async {
      await createUser();
      await setDashboardPassword();

      await pumpWizard(tester);

      expect(
        find.text(AppStringsTr.setupStepCounterRecoveryCode),
        findsOneWidget,
      );
      expect(find.byKey(SetupWizardScreen.recoveryCodeTextKey), findsOneWidget);
    });
  });

  group('Adım 2 — dashboard parolası zorunludur (EC-DASH-011)', () {
    testWidgets('boş parola ile ilerlenemez', (tester) async {
      await createUser();
      await pumpWizard(tester);

      await tapSubmit(tester);

      expect(find.text(AppStringsTr.dashboardPasswordRequired), findsOneWidget);
      expect(
        find.byKey(SetupWizardScreen.recoveryCodeTextKey),
        findsNothing,
        reason: 'REQ-AUTH-016: parola belirlenmeden Adım 3\'e geçilmez.',
      );
      expect(await currentSetupState(), SetupState.needsDashboardPassword);
    });

    testWidgets('parola tekrarı uyuşmazsa ilerlenemez', (tester) async {
      await createUser();
      await pumpWizard(tester);

      await tester.enterText(
        find.byKey(SetupWizardScreen.dashboardPasswordFieldKey),
        kDashboardPassword,
      );
      await tester.enterText(
        find.byKey(SetupWizardScreen.dashboardPasswordConfirmFieldKey),
        'baska-bir-parola',
      );
      await tapSubmit(tester);

      expect(find.text(AppStringsTr.passwordMismatch), findsOneWidget);
      expect(await currentSetupState(), SetupState.needsDashboardPassword);
    });
  });

  group('Adım 3 — kurtarma kodu (REQ-AUTH-022/024 · EC-REC-006)', () {
    testWidgets(
      '"Kodu kaydettim" işaretlenmeden Devam PASİF, işaretlenince aktif',
      (tester) async {
        await createUser();
        await setDashboardPassword();
        await pumpWizard(tester);

        expect(
          submitButton(tester).onPressed,
          isNull,
          reason:
              'REQ-AUTH-024 · EC-REC-006: kullanıcı kodu kaydettiğini '
              'onaylamadan kurulum ilerlemez.',
        );

        await tester.tap(
          find.byKey(SetupWizardScreen.recoveryCodeSavedCheckboxKey),
        );
        await tester.pumpAndSettle();

        expect(submitButton(tester).onPressed, isNotNull);
      },
    );

    testWidgets('kod XXXX-XXXX-XXXX-XXXX biçiminde gösterilir', (tester) async {
      await createUser();
      await setDashboardPassword();
      await pumpWizard(tester);

      final code = tester
          .widget<SelectableText>(
            find.byKey(SetupWizardScreen.recoveryCodeTextKey),
          )
          .data;

      expect(code, isNotNull);
      expect(
        RegExp(
          r'^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$',
        ).hasMatch(code!),
        isTrue,
        reason: 'REQ-AUTH-022: kod XXXX-XXXX-XXXX-XXXX biçimindedir → $code',
      );
      // Kod 0/O ve 1/I/l karakterlerini içermez (docs/17 §8).
      expect(RegExp('[01OIL]').hasMatch(code), isFalse);
    });

    testWidgets('kod bir daha gösterilmeyeceği uyarısıyla birlikte sunulur', (
      tester,
    ) async {
      await createUser();
      await setDashboardPassword();
      await pumpWizard(tester);

      expect(find.text(AppStringsTr.setupRecoveryCodeWarning), findsOneWidget);
      expect(
        find.byKey(SetupWizardScreen.recoveryCodeCopyButtonKey),
        findsOneWidget,
        reason: 'REQ-AUTH-022: kopyalama seçeneği sunulur.',
      );
    });
  });

  testWidgets('uçtan uca kurulum tamamlanır ve ana ekrana geçilir', (
    tester,
  ) async {
    await pumpWizard(tester);

    // Adım 1 — kullanıcı hesabı (otomatik giriş de burada olur, docs/22 F1).
    await completeUserStep(tester);
    expect(
      find.byKey(SetupWizardScreen.dashboardPasswordFieldKey),
      findsOneWidget,
    );

    // Adım 2 — dashboard parolası.
    await completeDashboardStep(tester);
    expect(find.byKey(SetupWizardScreen.recoveryCodeTextKey), findsOneWidget);

    // Adım 3 — kurtarma kodu onayı.
    await tester.tap(
      find.byKey(SetupWizardScreen.recoveryCodeSavedCheckboxKey),
    );
    await tester.pumpAndSettle();
    await tapSubmit(tester);

    expect(
      await currentSetupState(),
      SetupState.complete,
      reason: 'Üç zorunlu adım da kalıcılaşmış olmalıdır.',
    );
    expect(
      find.text(AppStringsTr.foundationReady),
      findsOneWidget,
      reason:
          'docs/22 F1: kurulum otomatik giriş ile biter; kullanıcı tekrar '
          'parola girmez.',
    );
  });

  testWidgets('Adım 1 form doğrulaması: eşleşmeyen parola ile ilerlenmez', (
    tester,
  ) async {
    await pumpWizard(tester);

    await tester.enterText(
      find.byKey(SetupWizardScreen.usernameFieldKey),
      kUsername,
    );
    await tester.enterText(
      find.byKey(SetupWizardScreen.displayNameFieldKey),
      kDisplayName,
    );
    await tester.enterText(
      find.byKey(SetupWizardScreen.passwordFieldKey),
      kPassword,
    );
    await tester.enterText(
      find.byKey(SetupWizardScreen.passwordConfirmFieldKey),
      'baska-bir-parola',
    );
    await tapSubmit(tester);

    expect(find.text(AppStringsTr.passwordMismatch), findsOneWidget);
    expect(
      await currentSetupState(),
      SetupState.needsUser,
      reason: 'Doğrulama geçmeden kullanıcı oluşturulmamalıdır.',
    );
  });

  testWidgets('ekranda teknik detay ve hata kodu gösterilmez', (tester) async {
    await createUser();
    await setDashboardPassword();
    await pumpWizard(tester);

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
    ]) {
      expect(
        visibleText.contains(forbidden),
        isFalse,
        reason: 'Ekranda teknik detay görünüyor: $forbidden → $visibleText',
      );
    }
  });
}
