/// Kurtarma akışı widget testleri — **docs/17 §8 · docs/22 F10 ·
/// BR-AUTH-015/017 · REQ-AUTH-022/025/026/027 · EC-REC-001…006/011**
///
/// docs/27 §4: widget testleri **seçicidir.** Buradaki testler sessizce
/// ihlal edilebilecek kurtarma kurallarını korur:
///
/// | Test | Kural |
/// |---|---|
/// | Doğru kod → yeni parola → **yeni kod** gösterilir | EC-REC-001/004 · BR-AUTH-017 |
/// | Kurtarma sonunda finansal erişim **açılır** | docs/17 §8 son adım |
/// | "Kodu kaydettim" olmadan ekran **kapanmaz** | REQ-AUTH-024 · EC-REC-006 |
/// | Yanlış kod: kilit açılmaz, kullanıcı kod adımına döner | EC-REC-003 |
/// | Kod tire/harf farkıyla girilse de kabul edilir | EC-REC-011 |
/// | Yeni kod dosyaya kaydedilebilir | REQ-AUTH-022 |
/// | Ekranda teknik detay / hata kodu yok | REQ-UX-008 · REQ-SEC-007 |
///
/// Golden (piksel) testi **yazılmaz** (docs/27 §4).
library;

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/application/auth/providers.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/presentation/auth/recovery_flow_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

const String kDashboardPassword = 'dashboard-parolasi-9Z2K';
const String kNewDashboardPassword = 'yeni-dashboard-parolasi-3M8V';

/// Akışı **ikinci rota** olarak açar: son adımdaki `pop` gerçek bir rota
/// kapanışıdır ve dönüş değeri doğrulanabilir.
class _RecoveryHost extends StatefulWidget {
  static const Key openKey = Key('test_open_recovery');

  final Future<String?> Function(String suggestedName) savePicker;
  final Future<void> Function(String path, String contents) fileWriter;

  const _RecoveryHost({required this.savePicker, required this.fileWriter});

  @override
  State<_RecoveryHost> createState() => _RecoveryHostState();
}

class _RecoveryHostState extends State<_RecoveryHost> {
  bool? result;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ElevatedButton(
          key: _RecoveryHost.openKey,
          onPressed: () async {
            final value = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (_) => RecoveryFlowScreen(
                  savePicker: widget.savePicker,
                  fileWriter: widget.fileWriter,
                ),
              ),
            );
            setState(() => result = value);
          },
          child: const Text('Kurtarma'),
        ),
      ),
    );
  }
}

void main() {
  late CanteenDatabase db;
  late ProviderContainer screenContainer;

  /// Enjekte edilen kayıt hedefi — gerçek diske ve OS dialoguna dokunulmaz.
  String? savedPath;
  String? savedContents;

  setUp(() {
    db = memoryDatabase();
    savedPath = null;
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

  /// Kurulumun Adım 2–3'ü: dashboard parolası + ilk kurtarma kodu.
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

  Future<void> pumpHost(WidgetTester tester) async {
    screenContainer = ProviderContainer(
      overrides: [canteenDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(screenContainer.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: screenContainer,
        child: MaterialApp(
          home: _RecoveryHost(
            savePicker: (name) async => savedPath = '/tmp/$name',
            fileWriter: (path, contents) async => savedContents = contents,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(_RecoveryHost.openKey));
    await tester.pumpAndSettle();
  }

  bool isUnlocked() => screenContainer.read(financialAccessProvider).isUnlocked;

  /// Adımın birincil butonu — pasifse `onPressed` `null`'dır.
  FilledButton submitButton(WidgetTester tester) => tester.widget<FilledButton>(
    find.descendant(
      of: find.byKey(RecoveryFlowScreen.submitButtonKey),
      matching: find.byType(FilledButton),
    ),
  );

  Future<void> tapSubmit(WidgetTester tester) async {
    await tester.ensureVisible(find.byKey(RecoveryFlowScreen.submitButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(RecoveryFlowScreen.submitButtonKey));
    await tester.pumpAndSettle();
  }

  Future<void> enterCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(RecoveryFlowScreen.codeFieldKey), code);
    await tapSubmit(tester);
  }

  Future<void> enterNewPassword(
    WidgetTester tester, {
    String password = kNewDashboardPassword,
    String? confirm,
  }) async {
    await tester.enterText(
      find.byKey(RecoveryFlowScreen.passwordFieldKey),
      password,
    );
    await tester.enterText(
      find.byKey(RecoveryFlowScreen.passwordConfirmFieldKey),
      confirm ?? password,
    );
    await tapSubmit(tester);
  }

  String shownNewCode(WidgetTester tester) => tester
      .widget<SelectableText>(find.byKey(RecoveryFlowScreen.newCodeTextKey))
      .data!;

  testWidgets('doğru kod → yeni parola → YENİ kod gösterilir ve kilit açılır', (
    tester,
  ) async {
    final code = await prepare();
    await pumpHost(tester);

    await enterCode(tester, code);
    expect(find.byKey(RecoveryFlowScreen.passwordFieldKey), findsOneWidget);

    await enterNewPassword(tester);

    // BR-AUTH-017 · REQ-AUTH-027: yeni kod üretilir ve bir kez gösterilir.
    expect(find.byKey(RecoveryFlowScreen.newCodeTextKey), findsOneWidget);
    final newCode = shownNewCode(tester);
    expect(
      RegExp(
        r'^[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}$',
      ).hasMatch(newCode),
      isTrue,
      reason: 'Yeni kod da XXXX-XXXX-XXXX-XXXX biçimindedir → $newCode',
    );
    expect(newCode, isNot(code), reason: 'Eski kod yeniden gösterilmez.');

    // docs/17 §8 son adım: kurtarma başarılıysa kilit AÇILIR.
    expect(isUnlocked(), isTrue);

    // Yeni parola gerçekten geçerlidir (kurtarma kalıcılaştı).
    expect(
      await withServices(
        (container) => container
            .read(financialAccessProvider)
            .verifyPassword(kNewDashboardPassword),
      ),
      isTrue,
    );
  });

  testWidgets('"Kodu kaydettim" işaretlenmeden ekran KAPANMAZ — EC-REC-006', (
    tester,
  ) async {
    final code = await prepare();
    await pumpHost(tester);

    await enterCode(tester, code);
    await enterNewPassword(tester);

    expect(
      submitButton(tester).onPressed,
      isNull,
      reason: 'REQ-AUTH-024 · EC-REC-006: onay verilmeden [Tamam] pasiftir.',
    );

    // Sistem geri tuşu (ve AppBar geri düğmesi) de ekranı kapatamaz.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(
      find.byKey(RecoveryFlowScreen.newCodeTextKey),
      findsOneWidget,
      reason: 'EC-REC-006: kod ekranı onay olmadan kapanmaz.',
    );

    await tester.tap(find.byKey(RecoveryFlowScreen.newCodeSavedCheckboxKey));
    await tester.pumpAndSettle();
    expect(submitButton(tester).onPressed, isNotNull);

    await tapSubmit(tester);
    expect(find.byKey(RecoveryFlowScreen.newCodeTextKey), findsNothing);
    expect(
      tester.state<State>(find.byType(_RecoveryHost)),
      isA<_RecoveryHostState>().having(
        (state) => state.result,
        'akışın sonucu',
        isTrue,
      ),
      reason: 'Çağıran, kurtarmanın başarılı olduğunu öğrenmelidir.',
    );
  });

  testWidgets('yanlış kod: kilit açılmaz, kullanıcı kod adımına döner', (
    tester,
  ) async {
    await prepare();
    await pumpHost(tester);

    await enterCode(tester, 'A7K2-M9QX-4RTB-8ZWD');
    await enterNewPassword(tester);

    expect(
      find.byKey(RecoveryFlowScreen.codeFieldKey),
      findsOneWidget,
      reason: 'EC-REC-003: kullanıcı kodu ancak Adım 1\'de düzeltebilir.',
    );
    expect(find.byKey(RecoveryFlowScreen.newCodeTextKey), findsNothing);
    expect(isUnlocked(), isFalse);
    expect(
      await withServices(
        (container) => container
            .read(financialAccessProvider)
            .verifyPassword(kDashboardPassword),
      ),
      isTrue,
      reason: 'EC-REC-005: başarısız kurtarma eski parolayı değiştirmez.',
    );
  });

  testWidgets('kod tire ve harf durumu farkıyla girilebilir — EC-REC-011', (
    tester,
  ) async {
    final code = await prepare();
    await pumpHost(tester);

    await enterCode(tester, code.replaceAll('-', '').toLowerCase());
    await enterNewPassword(tester);

    expect(find.byKey(RecoveryFlowScreen.newCodeTextKey), findsOneWidget);
    expect(isUnlocked(), isTrue);
  });

  testWidgets('yeni kod dosyaya kaydedilebilir — REQ-AUTH-022', (tester) async {
    final code = await prepare();
    await pumpHost(tester);

    await enterCode(tester, code);
    await enterNewPassword(tester);

    await tester.tap(find.byKey(RecoveryFlowScreen.newCodeSaveButtonKey));
    await tester.pumpAndSettle();

    expect(savedPath, isNotNull);
    expect(
      savedContents,
      contains(shownNewCode(tester)),
      reason: 'Kullanıcının seçtiği dosyaya YENİ kod yazılır.',
    );
  });

  testWidgets('ekranda teknik detay ve hata kodu gösterilmez', (tester) async {
    await prepare();
    await pumpHost(tester);

    await enterCode(tester, 'A7K2-M9QX-4RTB-8ZWD');
    await enterNewPassword(tester);

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
    expect(
      find.text(AppStringsTr.unexpectedErrorMessage),
      findsNothing,
      reason: 'Beklenen iş hatası genel hata mesajına düşmemelidir.',
    );
  });
}
