/// Barkod dinleyici widget testleri — **REQ-BARC-003/011 · EC-BARC-005 ·
/// docs/11 §2**
///
/// | Test | Kural |
/// |---|---|
/// | Hızlı okuma `onScan` tetikler | REQ-BARC-003 |
/// | İnsan yazımı `Enter`'ı **normal bırakır** | docs/11 §2 |
/// | Karakterler **yutulmaz** — metin alanı görmeye devam eder | docs/11 §2 |
/// | Modal açıkken dinleme **kapalıdır** | REQ-BARC-011 · EC-BARC-005 |
/// | Odak metin alanındayken de okuma yakalanır | REQ-BARC-003 |
library;

import 'package:canteen/domain/services/barcode_input_handler.dart';
import 'package:canteen/presentation/barcode/barcode_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DateTime now;
  late List<String> scans;

  setUp(() {
    now = DateTime.utc(2026, 1, 1);
    scans = [];
  });

  BarcodeInputHandler handler() => BarcodeInputHandler(clock: () => now);

  /// Tuş olaylarını scanner hızında gönderir.
  Future<void> scan(
    WidgetTester tester,
    String text, {
    int gapMs = 5,
    bool enter = true,
  }) async {
    for (final char in text.split('')) {
      await tester.sendKeyEvent(_keyFor(char), character: char);
      now = now.add(Duration(milliseconds: gapMs));
    }
    if (enter) await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
  }

  Future<void> pumpListener(
    WidgetTester tester, {
    Widget? child,
    bool enabled = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: BarcodeListener(
          handler: handler(),
          enabled: enabled,
          onScan: scans.add,
          child: child ?? const Scaffold(body: SizedBox.expand()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('scanner hızındaki okuma onScan tetikler', (tester) async {
    await pumpListener(tester);

    await scan(tester, '8690000000001');

    expect(scans, ['8690000000001']);
  });

  testWidgets('insan hızındaki yazım okuma SAYILMAZ', (tester) async {
    await pumpListener(tester);

    await scan(tester, 'merhaba', gapMs: 80);

    expect(scans, isEmpty, reason: 'docs/11 §2: insan yazımı barkod değildir.');
  });

  testWidgets('dinleme kapalıyken okuma yakalanmaz', (tester) async {
    await pumpListener(tester, enabled: false);

    await scan(tester, '8690000000001');

    expect(scans, isEmpty);
  });

  group('REQ-BARC-003 — odak nerede olursa olsun yakalanır', () {
    testWidgets('metin alanı odaktayken de okuma tetiklenir', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);

      await pumpListener(
        tester,
        child: Scaffold(
          body: TextField(controller: controller, autofocus: true),
        ),
      );

      await scan(tester, '8690000000001');

      expect(
        scans,
        ['8690000000001'],
        reason:
            'Kullanıcı sepette veya arama kutusunda gezinirken de '
            'okutabilmelidir (docs/11 §2 — satış ekranında global dinleme).',
      );
    });

    // NOT: "karakterlerin metin alanına ulaştığı" burada doğrulanamaz —
    // widget testinde `sendKeyEvent` metni `TextField`'a taşımaz; gerçek
    // metin girişi platform kanalından gelir. Bu davranış Windows manuel
    // testlerinde doğrulanır (docs/27 §8 — W1/W3).
  });

  group('REQ-BARC-011 · EC-BARC-005 — modal açıkken dinleme KAPALI', () {
    testWidgets('dialog açıkken okutulan barkod arkadaki ekrana gitmez', (
      tester,
    ) async {
      await pumpListener(
        tester,
        child: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => const AlertDialog(content: Text('Dialog')),
              ),
              child: const Text('Aç'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await scan(tester, '8690000000001');

      expect(
        scans,
        isEmpty,
        reason:
            'EC-BARC-005: dialog açıkken okutulan barkod yok sayılır — '
            'yanlış ekrana ürün eklenmemelidir.',
      );
    });

    testWidgets('dialog kapandıktan sonra dinleme yeniden çalışır', (
      tester,
    ) async {
      await pumpListener(
        tester,
        child: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  content: TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Kapat'),
                  ),
                ),
              ),
              child: const Text('Aç'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Aç'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kapat'));
      await tester.pumpAndSettle();

      await scan(tester, '8690000000001');

      expect(scans, ['8690000000001']);
    });
  });

  group('barkodu tamamlayan Enter TÜKETİLİR', () {
    testWidgets('okumanın Enter\'ı üste çıkmaz, insan Enter\'ı çıkar', (
      tester,
    ) async {
      // `ignored` dönen olaylar ÜST düğüme çıkar; `handled` dönenler çıkmaz.
      // Testin gözlediği şey budur — `TextField.onSubmitted` widget testinde
      // platform kanalından geldiği için kullanılamaz.
      var enterReachedParent = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Focus(
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter) {
                enterReachedParent++;
              }
              return KeyEventResult.ignored;
            },
            child: BarcodeListener(
              handler: handler(),
              onScan: scans.add,
              child: const Scaffold(body: SizedBox.expand()),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await scan(tester, '8690000000001');
      expect(scans, hasLength(1));
      expect(
        enterReachedParent,
        0,
        reason:
            'Okuma hem sepete eklenip hem formu gönderemez — barkodu '
            'tamamlayan Enter tüketilir.',
      );

      await scan(tester, 'ab', gapMs: 90);
      expect(
        enterReachedParent,
        1,
        reason: 'İnsan Enter\'ı normal işlenmeye devam etmelidir.',
      );
    });
  });

  testWidgets('rota DIŞINA yerleştirmek assert ile yakalanır', (tester) async {
    // `Navigator`'ın üstüne konursa `ModalRoute.of` null döner ve dialog
    // algılanamaz; okuma arkadaki ekrana giderdi (EC-BARC-005). Sessiz bir
    // yanlış yerleştirme yerine gürültülü bir hata tercih edilir.
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => BarcodeListener(
          handler: handler(),
          onScan: scans.add,
          child: child!,
        ),
        home: const Scaffold(body: SizedBox.expand()),
      ),
    );

    expect(tester.takeException(), isA<AssertionError>());
  });
}

/// Karakter için makul bir `LogicalKeyboardKey` üretir.
///
/// Testin ilgilendiği şey `character` alanıdır; `logicalKey` yalnızca
/// `Enter` ayrımı için önemlidir.
LogicalKeyboardKey _keyFor(String character) {
  const digits = <String, LogicalKeyboardKey>{
    '0': LogicalKeyboardKey.digit0,
    '1': LogicalKeyboardKey.digit1,
    '2': LogicalKeyboardKey.digit2,
    '3': LogicalKeyboardKey.digit3,
    '4': LogicalKeyboardKey.digit4,
    '5': LogicalKeyboardKey.digit5,
    '6': LogicalKeyboardKey.digit6,
    '7': LogicalKeyboardKey.digit7,
    '8': LogicalKeyboardKey.digit8,
    '9': LogicalKeyboardKey.digit9,
  };
  return digits[character] ?? LogicalKeyboardKey.keyA;
}
