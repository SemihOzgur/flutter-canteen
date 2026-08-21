/// Kullanım kılavuzu ↔ uygulama tutarlılığı — **docs/33 · docs/31 Faz 12**
///
/// Kılavuz kullanıcıya *"F12 satışı tamamlar"* diyor. Kod bir gün `F11`
/// derse, kılavuz **yanlış** olur ve bunu ilk fark eden kasadaki kişi olur.
/// Bir doküman yanlışsa, hiç olmamasından daha kötüdür: kullanıcı ona
/// güvenir.
///
/// Bu test kılavuzun **doğrulanabilir** iddialarını kodla karşılaştırır.
/// Anlatımı değerlendirmez — onu insan okur.
library;

import 'dart:io';

import 'package:canteen/app/l10n/app_strings_tr.dart';
import 'package:canteen/core/version/app_version.dart';
import 'package:canteen/presentation/common/low_resolution_notice.dart';
import 'package:flutter_test/flutter_test.dart';

/// Kılavuzun yolu tek yerde durur: dosya yeniden adlandırılırsa burası
/// düzeltilir ve testler yolun gerçekten var olduğunu doğrular.
const String guidePath = 'docs/bilgilendirme.md';

String get guide => File(guidePath).readAsStringSync();

void main() {
  test('kılavuz repoda vardır', () {
    expect(File(guidePath).existsSync(), isTrue);
    expect(guide.length, greaterThan(2000));
  });

  test('kısayol tablosu KODDAKİ listeyle aynıdır', () {
    // Tuş adları `AppStringsTr.saleShortcuts`'tan gelir; F1 ekranı da aynı
    // listeyi gösterir. İki kaynak olsaydı biri sessizce eskirdi.
    final missing = <String>[];
    for (final (key, _) in AppStringsTr.saleShortcuts) {
      if (!guide.contains('`$key`') && !guide.contains('| $key |')) {
        missing.add(key);
      }
    }
    expect(
      missing,
      isEmpty,
      reason:
          'Bu kısayollar uygulamada var ama kılavuzda yok: $missing. '
          'Kılavuz eksikse kullanıcı özelliği hiç öğrenmez.',
    );
  });

  test('kılavuzda UYDURULMUŞ kısayol yoktur', () {
    // Kaldırılmış bir kısayolu anlatmaya devam etmek, olmayanı anlatmaktır.
    final known = AppStringsTr.saleShortcuts.map((s) => s.$1).toSet();
    final mentioned = RegExp(
      r'\| `?(F\d{1,2})`? \|',
    ).allMatches(guide).map((m) => m.group(1)!).toSet();

    final unknown = mentioned.difference(known).toList()..sort();
    expect(unknown, isEmpty, reason: 'Uygulamada olmayan kısayollar: $unknown');
  });

  test('kılavuzdaki sürüm gerçek sürümdür', () {
    expect(
      guide,
      contains(appVersion),
      reason: 'Kurulum dosyasının adı sürümü taşır; kılavuz onu gösterir.',
    );
  });

  test('kılavuzdaki minimum çözünürlük koddaki eşiktir', () {
    final width = minimumSupportedSize.width.round();
    final height = minimumSupportedSize.height.round();
    expect(guide, contains('$width×$height'));
  });

  test('kılavuz veri dizinini DOĞRU gösterir', () {
    // BR-DATA-001 — kullanıcıya yanlış klasörü göstermek, "yedeğim var"
    // sanıp yanlış yeri kopyalamasına yol açar.
    expect(guide, contains(r'AppData\Roaming\CanteenApp'));
  });

  test('KDV DAHİL kuralı kılavuzda açıkça yazılıdır', () {
    // BR-VAT-003 kullanıcının fiyat girerken bilmesi GEREKEN tek kuraldır;
    // yanlış anlaşılırsa her fiyat yanlış girilir.
    expect(guide.toUpperCase(), contains('KDV DAHİL'));
  });

  test('yedeği başka bir yere kopyalama uyarısı vardır', () {
    // RSK-005 — tek kopya veri. Aynı diskte duran yedek, disk bozulduğunda
    // hiçbir işe yaramaz.
    expect(guide, contains('.canteenbackup'));
    expect(
      guide.toLowerCase(),
      anyOf(contains('usb'), contains('harici disk')),
    );
  });

  test('kurtarma kodunun tek kullanımlık olduğu yazılıdır', () {
    // BR-AUTH-015/017 — kullanıcı bunu bilmezse kodu saklamaz.
    expect(guide, contains('tek kullanımlık'));
  });
}
