/// Giriş ekranı widget testleri — **docs/17 §3 · EC-AUTH-001/002/006 ·
/// rules/05 §1**
///
/// docs/27 §4: widget testleri **seçicidir.** Burada yalnızca kasadaki akışı
/// bozan ve sessizce ihlal edilebilecek davranışlar doğrulanır:
///
/// | Test | Kural |
/// |---|---|
/// | Açılışta odak kullanıcı adında | rules/05 §1 · REQ-UX-002 |
/// | `Enter` parola alanında giriş yapar | docs/17 §3 |
/// | Hatalı giriş **genel** mesaj gösterir | EC-AUTH-001 |
/// | Kullanıcı adı büyük harfle de çalışır | EC-AUTH-006 |
/// | Ekranda teknik detay / hata kodu yok | REQ-UX-008 · REQ-SEC-007 |
///
/// Golden (piksel) testi **yazılmaz** (docs/27 §4).
library;

import 'package:canteen/app/app.dart';
import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/app/router.dart';
import 'package:canteen/application/auth/auth_failures.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/presentation/auth/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_window.dart';

import '../../support/test_database.dart';

const String kUsername = 'kasa';
const String kPassword = 'kasa-parolasi-7Q4X';
const String kDisplayName = 'Kasa Kullanıcısı';

void main() {
  late CanteenDatabase db;

  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  /// Ekranı açar. [withUser] verilirse test kullanıcısı önceden oluşturulur.
  Future<void> pumpLogin(WidgetTester tester, {bool withUser = true}) async {
    useSupportedSurface(tester);
    if (withUser) {
      final container = ProviderContainer(
        overrides: [canteenDatabaseProvider.overrideWithValue(db)],
      );
      await container
          .read(authServiceProvider)
          .createUser(
            username: kUsername,
            password: kPassword,
            displayName: kDisplayName,
          );
      container.dispose();
    }

    await tester.pumpWidget(
      ProviderScope(
        overrides: [canteenDatabaseProvider.overrideWithValue(db)],
        child: const CanteenApp(initialRoute: AppRoutes.login),
      ),
    );
    await tester.pumpAndSettle();
  }

  TextField fieldOf(WidgetTester tester, Key key) => tester.widget<TextField>(
    find.descendant(of: find.byKey(key), matching: find.byType(TextField)),
  );

  testWidgets('açılışta odak kullanıcı adı alanındadır', (tester) async {
    await pumpLogin(tester);

    expect(
      fieldOf(tester, LoginScreen.usernameFieldKey).focusNode?.hasFocus,
      isTrue,
      reason:
          'rules/05 §1: ekran açıldığında odak ilk alandadır; kasada ilk '
          'karakterin kaybolmaması buna bağlıdır.',
    );
  });

  testWidgets('parola alanı gizlidir', (tester) async {
    await pumpLogin(tester);

    expect(fieldOf(tester, LoginScreen.passwordFieldKey).obscureText, isTrue);
    expect(fieldOf(tester, LoginScreen.usernameFieldKey).obscureText, isFalse);
  });

  testWidgets('Enter parola alanında girişi tetikler ve ana ekrana geçer', (
    tester,
  ) async {
    await pumpLogin(tester);

    await tester.enterText(find.byKey(LoginScreen.usernameFieldKey), kUsername);
    await tester.enterText(find.byKey(LoginScreen.passwordFieldKey), kPassword);
    // docs/17 §3: parola alanında `Enter` giriş yapar — butona basılmaz.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(
      find.text(AppStringsTr.homeWelcome),
      findsOneWidget,
      reason: 'Başarılı giriş ana ekrana geçirir (REQ-AUTH-001).',
    );
  });

  testWidgets('kullanıcı adı büyük/küçük harf duyarsızdır (EC-AUTH-006)', (
    tester,
  ) async {
    await pumpLogin(tester);

    await tester.enterText(
      find.byKey(LoginScreen.usernameFieldKey),
      kUsername.toUpperCase(),
    );
    await tester.enterText(find.byKey(LoginScreen.passwordFieldKey), kPassword);
    await tester.tap(find.byKey(LoginScreen.submitButtonKey));
    await tester.pumpAndSettle();

    expect(find.text(AppStringsTr.homeWelcome), findsOneWidget);
  });

  group('EC-AUTH-001 — hangi alanın yanlış olduğu söylenmez', () {
    testWidgets('hatalı parola genel mesaj gösterir', (tester) async {
      await pumpLogin(tester);

      await tester.enterText(
        find.byKey(LoginScreen.usernameFieldKey),
        kUsername,
      );
      await tester.enterText(
        find.byKey(LoginScreen.passwordFieldKey),
        'yanlis-parola',
      );
      await tester.tap(find.byKey(LoginScreen.submitButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.text(AuthFailures.invalidCredentials.userMessage),
        findsOneWidget,
      );
      expect(find.text(AppStringsTr.homeWelcome), findsNothing);
    });

    testWidgets('bilinmeyen kullanıcı adı AYNI mesajı gösterir', (
      tester,
    ) async {
      await pumpLogin(tester);

      await tester.enterText(
        find.byKey(LoginScreen.usernameFieldKey),
        'boyle-bir-kullanici-yok',
      );
      await tester.enterText(
        find.byKey(LoginScreen.passwordFieldKey),
        kPassword,
      );
      await tester.tap(find.byKey(LoginScreen.submitButtonKey));
      await tester.pumpAndSettle();

      expect(
        find.text(AuthFailures.invalidCredentials.userMessage),
        findsOneWidget,
        reason:
            'EC-AUTH-001: bilinmeyen kullanıcı adı ile hatalı parola aynı '
            'mesajı almalıdır; aksi hâlde kullanıcı adının varlığı sızar.',
      );
      // Kullanıcı adının varlığına dair hiçbir ipucu ekranda olmamalı.
      expect(find.textContaining('kullanıcı bulunamadı'), findsNothing);
      expect(find.textContaining('Kullanıcı bulunamadı'), findsNothing);
    });
  });

  testWidgets('ekranda teknik detay ve hata kodu gösterilmez', (tester) async {
    await pumpLogin(tester);

    await tester.enterText(find.byKey(LoginScreen.usernameFieldKey), kUsername);
    await tester.enterText(
      find.byKey(LoginScreen.passwordFieldKey),
      'yanlis-parola',
    );
    await tester.tap(find.byKey(LoginScreen.submitButtonKey));
    await tester.pumpAndSettle();

    // REQ-UX-008 · REQ-SEC-007: kod, exception adı ve dosya yolu sızmaz.
    final visibleText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data ?? '')
        .join('\n');

    for (final forbidden in const [
      'auth_', // Failure.code önekleri
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

  testWidgets('boş alanlar için satır içi doğrulama mesajı gösterilir', (
    tester,
  ) async {
    await pumpLogin(tester);

    await tester.tap(find.byKey(LoginScreen.submitButtonKey));
    await tester.pumpAndSettle();

    expect(find.text(AppStringsTr.usernameRequired), findsOneWidget);
    expect(find.text(AppStringsTr.passwordRequired), findsOneWidget);
    expect(find.text(AppStringsTr.homeWelcome), findsNothing);
  });
}
