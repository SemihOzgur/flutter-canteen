/// Düşük çözünürlük uyarısı — **docs/23 §4**
///
/// ## Kapsanan uç durumlar (docs/26 · Faz 11 izlenebilirliği)
///
/// - **EC-SYS-008** — ekran çözünürlüğü 1366×768'in altında
library;

import 'package:canteen/presentation/common/low_resolution_notice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(Size size) => MediaQuery(
    data: MediaQueryData(size: size),
    child: const MaterialApp(
      home: LowResolutionNotice(
        child: Scaffold(body: Center(child: Text('içerik'))),
      ),
    ),
  );

  const warning = Key('low_resolution_warning');

  testWidgets('1366×768 uyarı GÖSTERMEZ — sınırın kendisi desteklenir', (
    tester,
  ) async {
    await tester.pumpWidget(app(const Size(1366, 768)));
    expect(find.byKey(warning), findsNothing);
  });

  testWidgets('SINIR — bir piksel dar pencere uyarır', (tester) async {
    await tester.pumpWidget(app(const Size(1365, 768)));
    expect(find.byKey(warning), findsOneWidget);
  });

  testWidgets('SINIR — bir piksel alçak pencere de uyarır', (tester) async {
    await tester.pumpWidget(app(const Size(1366, 767)));
    expect(find.byKey(warning), findsOneWidget);
  });

  testWidgets('uyarı ENGELLEYİCİ DEĞİLDİR — içerik görünür kalır', (
    tester,
  ) async {
    // EC-SYS-008: "uygulama açılır ama düzen bozulabilir". Küçük ekranlı bir
    // kasada satışı durdurmak, uyarı vermekten çok daha pahalıdır.
    await tester.pumpWidget(app(const Size(1024, 768)));

    expect(find.byKey(warning), findsOneWidget);
    expect(find.text('içerik'), findsOneWidget);
  });

  testWidgets('uyarı gerçek ölçüyü SÖYLER', (tester) async {
    await tester.pumpWidget(app(const Size(1024, 600)));

    final text = tester.widget<Text>(find.byKey(warning)).data!;
    expect(text, contains('1024×600'));
    expect(text, contains('1366×768'));
  });

  testWidgets('kapatılan uyarı GERİ GELMEZ', (tester) async {
    // Pencereyi her yeniden boyutlandırışında geri gelen bir çubuk, uyarıyı
    // bilgi olmaktan çıkarıp engele dönüştürürdü (rules/05 §5).
    await tester.pumpWidget(app(const Size(1024, 768)));
    await tester.tap(find.byKey(const Key('low_resolution_dismiss')));
    await tester.pump();

    expect(find.byKey(warning), findsNothing);

    await tester.pumpWidget(app(const Size(800, 600)));
    expect(find.byKey(warning), findsNothing);
    expect(find.text('içerik'), findsOneWidget);
  });
}
