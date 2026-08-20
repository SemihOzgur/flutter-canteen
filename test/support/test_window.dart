/// Widget testleri için **desteklenen** pencere boyutu.
///
/// `flutter_test`'in varsayılan yüzeyi 800×600'dür — bu, docs/23 §4'e göre
/// **desteklenmeyen** bir çözünürlüktür ve uygulama orada `EC-SYS-008`
/// uyarı çubuğunu gösterir. `CanteenApp`'i pump eden testler o çubuğun
/// altında çalışırsa, ölçtükleri şey artık gerçek düzen olmaz.
///
/// Bu yardımcı yüzeyi desteklenen en küçük çözünürlüğe (1366×768) çeker;
/// yani testler kullanıcının gerçekten göreceği düzeni ölçer.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// docs/23 §4 — tam işlevsellik için gereken en küçük çözünürlük.
const Size supportedTestSurface = Size(1366, 768);

/// [tester]'ın yüzeyini desteklenen çözünürlüğe ayarlar ve test bitince
/// geri alır.
void useSupportedSurface(WidgetTester tester) {
  tester.view.physicalSize = supportedTestSurface;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}
