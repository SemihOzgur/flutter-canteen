/// Kullanıcı yönetimi widget testleri — **docs/17 §11 · BR-AUTH-002/006 ·
/// BR-SEC-001 · REQ-AUTH-008/009/013 · EC-AUTH-005**
///
/// docs/27 §4: widget testleri **seçicidir.** Buradaki testler sessizce
/// ihlal edilebilecek kullanıcı yönetimi kurallarını korur:
///
/// | Test | Kural |
/// |---|---|
/// | Son aktif kullanıcı pasifleştirilemez | BR-AUTH-006 · EC-AUTH-005 |
/// | Ekranda **hash / salt / parola** görünmez | BR-SEC-001 · rules/04 §8 |
/// | **Silme** butonu yoktur | BR-AUTH-006 |
/// | Pasif kullanıcılar listelenir ve geri alınabilir | REQ-AUTH-008 |
/// | Ekranda teknik detay / hata kodu yok | REQ-UX-008 · REQ-SEC-007 |
///
/// Golden (piksel) testi **yazılmaz** (docs/27 §4).
library;

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/application/auth/auth_failures.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/presentation/settings/user_management_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

const String kPassword = 'KANTIN-PW-SENTINEL-7Q4X';

void main() {
  late CanteenDatabase db;

  setUp(() => db = memoryDatabase());
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

  Future<int> createUser(String username, {String displayName = 'Kasa'}) async {
    final created = await withServices(
      (container) => container
          .read(authServiceProvider)
          .createUser(
            username: username,
            password: kPassword,
            displayName: displayName,
          ),
    );
    return created.valueOrNull!;
  }

  Future<void> pumpScreen(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [canteenDatabaseProvider.overrideWithValue(db)],
        child: const MaterialApp(home: UserManagementScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Ekranda görünen tüm metin (Text + SelectableText).
  String visibleText(WidgetTester tester) => [
    ...tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? ''),
    ...tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((w) => w.data ?? ''),
  ].join('\n');

  testWidgets('kullanıcılar listelenir; pasifler de görünür', (tester) async {
    await createUser('kasa', displayName: 'Kasa Görevlisi');
    final ikinciId = await createUser('ikinci', displayName: 'İkinci Kişi');
    await withServices(
      (container) =>
          container.read(authServiceProvider).setActive(ikinciId, false),
    );

    await pumpScreen(tester);

    expect(find.text('Kasa Görevlisi'), findsOneWidget);
    expect(find.text('İkinci Kişi'), findsOneWidget);
    expect(
      find.textContaining(AppStringsTr.userInactive),
      findsOneWidget,
      reason:
          'BR-AUTH-006: kullanıcı silinmez, pasifleşir — ekran onu göstermeli '
          've geri alınabilmelidir.',
    );
  });

  testWidgets('ekranda parola, hash veya salt GÖRÜNMEZ — BR-SEC-001', (
    tester,
  ) async {
    final userId = await createUser('kasa');
    final row = await withServices(
      (container) => container.read(usersDaoProvider).findById(userId),
    );

    await pumpScreen(tester);
    final text = visibleText(tester);

    expect(text.contains(kPassword), isFalse, reason: 'Düz metin parola!');
    expect(
      text.contains(row!.passwordHash),
      isFalse,
      reason: 'rules/04 §8: hash hiçbir ekrana yazılmaz.',
    );
    expect(
      text.contains(row.passwordSalt),
      isFalse,
      reason: 'rules/04 §8: salt hiçbir ekrana yazılmaz.',
    );
    expect(
      text.toLowerCase().contains('hash'),
      isFalse,
      reason: 'Ekranda hash kavramı bile geçmemelidir.',
    );
  });

  testWidgets('SİLME butonu yoktur — BR-AUTH-006', (tester) async {
    await createUser('kasa');
    await pumpScreen(tester);

    expect(find.byIcon(Icons.delete), findsNothing);
    expect(find.byIcon(Icons.delete_outline), findsNothing);
    expect(find.byIcon(Icons.delete_forever), findsNothing);
    expect(find.textContaining('Sil'), findsNothing);
  });

  testWidgets('son aktif kullanıcı pasifleştirilemez — EC-AUTH-005', (
    tester,
  ) async {
    final userId = await createUser('kasa');
    await pumpScreen(tester);

    await tester.tap(find.byKey(UserManagementScreen.activeSwitchKey(userId)));
    await tester.pumpAndSettle();

    expect(
      find.text(AuthFailures.lastActiveUser.userMessage),
      findsOneWidget,
      reason:
          'BR-AUTH-006: sistemde en az bir aktif kullanıcı kalmalıdır; '
          'kullanıcı nedenini Türkçe görmelidir.',
    );
    expect(
      tester
          .widget<Switch>(
            find.byKey(UserManagementScreen.activeSwitchKey(userId)),
          )
          .value,
      isTrue,
      reason: 'Reddedilen işlem ekranda da uygulanmamalıdır.',
    );
  });

  testWidgets('ikinci kullanıcı varken pasifleştirme çalışır', (tester) async {
    await createUser('kasa');
    final ikinciId = await createUser('ikinci', displayName: 'İkinci Kişi');
    await pumpScreen(tester);

    await tester.tap(
      find.byKey(UserManagementScreen.activeSwitchKey(ikinciId)),
    );
    await tester.pumpAndSettle();

    expect(find.text(AuthFailures.lastActiveUser.userMessage), findsNothing);
    expect(
      tester
          .widget<Switch>(
            find.byKey(UserManagementScreen.activeSwitchKey(ikinciId)),
          )
          .value,
      isFalse,
    );
  });

  testWidgets('yeni kullanıcı eklenir ve listede görünür', (tester) async {
    await createUser('kasa');
    await pumpScreen(tester);

    await tester.tap(find.byKey(UserManagementScreen.addUserButtonKey));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('user_form_username')), 'ayse');
    await tester.enterText(
      find.byKey(const Key('user_form_display_name')),
      'Ayşe Yılmaz',
    );
    await tester.enterText(
      find.byKey(const Key('user_form_password')),
      kPassword,
    );
    await tester.enterText(
      find.byKey(const Key('user_form_password_confirm')),
      kPassword,
    );
    await tester.tap(find.byKey(const Key('user_form_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Ayşe Yılmaz'), findsOneWidget);
    expect(
      await withServices(
        (container) => container.read(authServiceProvider).listUsers(),
      ),
      hasLength(2),
    );
  });

  testWidgets('kullanıcı adı benzersizdir — hata Türkçe gösterilir', (
    tester,
  ) async {
    await createUser('kasa');
    await pumpScreen(tester);

    await tester.tap(find.byKey(UserManagementScreen.addUserButtonKey));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('user_form_username')), 'kasa');
    await tester.enterText(
      find.byKey(const Key('user_form_display_name')),
      'Kopya',
    );
    await tester.enterText(
      find.byKey(const Key('user_form_password')),
      kPassword,
    );
    await tester.enterText(
      find.byKey(const Key('user_form_password_confirm')),
      kPassword,
    );
    await tester.tap(find.byKey(const Key('user_form_submit')));
    await tester.pumpAndSettle();

    expect(find.text(AuthFailures.usernameExists.userMessage), findsOneWidget);
  });

  testWidgets('görünen ad değiştirilebilir', (tester) async {
    final userId = await createUser('kasa', displayName: 'Eski Ad');
    await pumpScreen(tester);

    await tester.tap(find.byKey(UserManagementScreen.editButtonKey(userId)));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('user_display_name_field')),
      'Yeni Ad',
    );
    await tester.tap(find.byKey(const Key('user_display_name_submit')));
    await tester.pumpAndSettle();

    expect(find.text('Yeni Ad'), findsOneWidget);
    expect(find.text('Eski Ad'), findsNothing);
  });

  testWidgets('ekranda teknik detay ve hata kodu gösterilmez', (tester) async {
    final userId = await createUser('kasa');
    await pumpScreen(tester);

    // Reddedilen bir işlem tetiklenir (EC-AUTH-005) — mesaj ekrandayken taranır.
    await tester.tap(find.byKey(UserManagementScreen.activeSwitchKey(userId)));
    await tester.pumpAndSettle();

    final text = visibleText(tester);
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
