/// Edge case ↔ test izlenebilirliği — **docs/26 · docs/31 Faz 11**
///
/// `docs/26` uç durumları `EC-*` kimlikleriyle sayar ve `docs/27 §…` bunların
/// **integration testiyle** doğrulanmasını ister. `requirement_traceability_
/// test.dart` ile aynı mekanizma: dokümanı ayrıştır, test kaynağında ara,
/// **gerekçesiz boşluk bırakma.**
///
/// Fark: `EC-*` maddeleri 🔴/🟡 önceliklendirilmemiştir ve bir kısmı
/// tanımı gereği elle sınanır (elektrik kesintisi, disk dolu). Bu yüzden
/// muafiyet listesi burada daha uzundur — ama **her satırın bir sebebi
/// vardır.**
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `docs/26` içindeki tüm `EC-*` kimlikleri.
Set<String> documentedEdgeCases() {
  final doc = File('docs/26-edge-cases.md').readAsStringSync();
  return RegExp(
    r'^\|\s*\**(EC-[A-Z]+-\d+)\**\s*\|',
    multiLine: true,
  ).allMatches(doc).map((m) => m.group(1)!).toSet();
}

Set<String> edgeCasesMentionedInTests() {
  final pattern = RegExp(r'EC-[A-Z]+-\d+');
  final mentioned = <String>{};
  for (final entity in Directory('test').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    if (entity.path.endsWith('edge_case_traceability_test.dart')) continue;
    mentioned.addAll(
      pattern.allMatches(entity.readAsStringSync()).map((m) => m.group(0)!),
    );
  }
  return mentioned;
}

/// Testte anılmayan uç durumlar ve **neden**.
///
/// Bu harita bir muafiyet listesi değil, bir **borç defteridir**: her satır
/// ya donanım/işletim sistemi gerektirdiği için `docs/32`'ye, ya da açık bir
/// kusura işaret eder. Liste dışındaki her boşluk testi düşürür — yani
/// `docs/26`'ya yeni bir `EC-*` eklenirse kimse onu sessizce atlayamaz.
const Map<String, String> knownUncovered = {
  // ─ Donanım / işletim sistemi gerektiriyor — docs/32 §7 (W1–W15)
  'EC-BARC-009': 'Türkçe Q/F klavyede alfanümerik barkod — docs/32 W8',
  'EC-BKUP-010': 'Restore sırasında disk doluyor — docs/32 D9',
  'EC-IMEX-012': 'Export sırasında disk doluyor — docs/32 H9',
  'EC-SYS-002': 'Veri dizini yazılamıyor (izin) — docs/32 W6',
  'EC-SYS-003': 'Disk dolu, satış tamamlanıyor — docs/32 W10',
  'EC-SYS-008': 'Çözünürlük 1366×768 altında — docs/32 W7',
  'EC-SYS-009': 'Uygulama 7 gün açık kalıyor — docs/32 W11',
  'EC-SYS-010': 'Antivirüs yedeği karantinaya alıyor — docs/32 W12',

  // ─ Şema hâlâ v1: "daha eski yedek" ÜRETİLEMEZ
  //
  // v2 yayımlandığı anda bu iki satır silinir ve testleri yazılır; aksi
  // hâlde ilk migration'la birlikte sessizce kapsam dışı kalırlar.
  'EC-BKUP-005': 'Daha eski şema versiyonlu yedek — v2 gelene kadar üretilemez',
  'EC-CART-008': 'Migration sonrası sepet — v2 gelene kadar üretilemez',

  // ─ V1 kapsamı dışı
  'EC-IMEX-004': 'Şifre korumalı Excel — V1 CSV ile çalışır (OD-009)',
  'EC-CART-006':
      'Aktif sepetle farklı kullanıcı girişi — REQ-AUTH-010 🟢 Could, '
      'V1\'de uygulanmadı',

  // ─ Ayrı kod yolu yok
  'EC-CART-007':
      'Restore veritabanını BÜTÜN olarak değiştirir; `carts` için '
      'ayrı bir kod yolu yoktur — restore_service_test veri değişimini '
      'bütün olarak doğrular',

  // ─ 🐛 AÇIK KUSUR — docs ile çelişen mevcut davranış
  //
  // docs/19 REQ-BKUP-018: *"Bozuk veya eksik görsel içeren yedek, geri
  // yüklemeyi ENGELLEMEZ."* Mevcut `RestoreService` bozuk görselde
  // `checksumMismatch` döndürüp restore'u tamamen reddediyor. Eksik görsel
  // doğru davranıyor, bozuk görsel davranmıyor.
  'EC-BKUP-007':
      'Bozuk görsel restore\'u ENGELLİYOR — REQ-BKUP-018 ihlali, '
      'bugfix/backup-corrupt-image kapsamında düzeltilecek',
};

void main() {
  test('docs/26 ayrıştırması makul sonuç veriyor', () {
    expect(documentedEdgeCases().length, greaterThan(100));
  });

  test('her açık uç durum ya kapsanır ya da GEREKÇESİYLE kayıtlıdır', () {
    final documented = documentedEdgeCases();
    final mentioned = edgeCasesMentionedInTests().intersection(documented);
    final missing = documented.difference(mentioned).toList()..sort();

    final ratio = (mentioned.length * 100 / documented.length).round();
    // ignore: avoid_print
    print('EC kapsamı: ${mentioned.length}/${documented.length} (%$ratio)');

    final unexplained = missing
        .where((ec) => !knownUncovered.containsKey(ec))
        .toList();
    expect(
      unexplained,
      isEmpty,
      reason:
          'Bu uç durumlar hiçbir testte anılmıyor ve `knownUncovered` içinde '
          'gerekçesi de yok. Ya testini yazın ya da NEDEN yazılamadığını '
          'kaydedin: $unexplained',
    );
  });

  test('borç defterinde ARTIK kapsanan madde kalmaz', () {
    // Bir uç durumun testi yazıldığında satırı silinmelidir; kalırsa defter
    // gerçek borcu abartır ve zamanla kimse ona bakmaz.
    final mentioned = edgeCasesMentionedInTests();
    final stale = knownUncovered.keys.where(mentioned.contains).toList();
    expect(
      stale,
      isEmpty,
      reason:
          'Bunlar artık test ediliyor; `knownUncovered` satırlarını silin: '
          '$stale',
    );
  });

  test('borç defterindeki her kimlik docs/26\'da GERÇEKTEN var', () {
    final documented = documentedEdgeCases();
    final unknown = knownUncovered.keys
        .where((ec) => !documented.contains(ec))
        .toList();
    expect(
      unknown,
      isEmpty,
      reason: 'docs/26\'da bulunmayan kimlikler: $unknown',
    );
  });

  test('her gerekçe anlamlı bir metindir', () {
    for (final entry in knownUncovered.entries) {
      expect(
        entry.value.split(RegExp(r'\s+')).length,
        greaterThanOrEqualTo(4),
        reason: '${entry.key} gerekçesi bir açıklama değil.',
      );
    }
  });

  test('test kaynağında OLMAYAN bir EC anılmıyor', () {
    // Yazım hatası veya silinmiş bir maddeye referans, testin neyi
    // doğruladığını belirsizleştirir.
    final documented = documentedEdgeCases();
    final unknown = edgeCasesMentionedInTests().difference(documented).toList()
      ..sort();

    expect(
      unknown,
      isEmpty,
      reason:
          'Bu kimlikler docs/26\'da bulunmuyor — yazım hatası olabilir: '
          '$unknown',
    );
  });
}
