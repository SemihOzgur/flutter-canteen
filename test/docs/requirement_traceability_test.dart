/// Requirement ↔ test izlenebilirliği — **docs/31 Faz 11 çıkış kriteri**
///
/// > *"Tüm 🔴 Must requirement'lar test edilmiş."*
///
/// ## Bu iddia elle doğrulanamaz
///
/// `docs/25` 185 adet 🔴 Must requirement içeriyor. "Hepsi test edildi mi?"
/// sorusunu bir insanın tek tek cevaplaması hem hataya açık hem de her
/// değişiklikte baştan yapılması gerekir. Bu dosya soruyu **ölçülebilir** bir
/// hâle getirir:
///
/// ```text
/// docs/25  ──►  🔴 Must REQ listesi
///                    │
///                    ▼
///            test/ içinde anılıyor mu?
///                    │
///            ┌───────┴────────┐
///            ▼                ▼
///         anılıyor      anılmıyor → kapsam dışı GEREKÇESİ var mı?
///                                        │
///                                   yoksa → TEST KIRILIR
/// ```
///
/// ## Bu bir "kapsama yüzdesi" DEĞİLDİR
///
/// Bir REQ'in test dosyasında **anılması**, doğru test edildiğini kanıtlamaz.
/// Ölçtüğü şey daha mütevazı ama gerçek: *"bu gereksinimi kimse unutmadı."*
/// Testin niteliğini mutasyon testi ölçer (rules/06 §2); bu dosya yalnızca
/// **sessiz boşluk** bırakılmadığını garanti eder.
///
/// Gerekçesiz bir boşluk testi kırar — "unuttum" ile "kapsam dışı" aynı yere
/// yazılamaz.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `docs/25` tablo satırından çıkarılan requirement.
class Requirement {
  final String id;
  final String summary;
  final bool isMust;
  final String phase;

  const Requirement({
    required this.id,
    required this.summary,
    required this.isMust,
    required this.phase,
  });

  @override
  String toString() => '$id (Faz $phase) — $summary';
}

/// `docs/25 §…` katalog tablosunu ayrıştırır.
///
/// Yalnızca **dört sütunlu** satırlar (ID · Özet · Öncelik · Faz) alınır;
/// dokümanın başındaki değişiklik tabloları farklı biçimdedir ve elenir.
List<Requirement> parseRequirements() {
  final doc = File('docs/25-functional-requirements.md').readAsLinesSync();
  final pattern = RegExp(
    r'^\|\s*\**(REQ-[A-Z]+-\d+)\**\s*\|(.+?)\|(.+?)\|(.+?)\|\s*$',
  );

  final result = <Requirement>[];
  for (final line in doc) {
    final match = pattern.firstMatch(line);
    if (match == null) continue;
    result.add(
      Requirement(
        id: match.group(1)!,
        summary: match.group(2)!.trim(),
        isMust: match.group(3)!.contains('🔴'),
        phase: match.group(4)!.trim(),
      ),
    );
  }
  return result;
}

/// `test/` altındaki tüm dosyalarda anılan REQ kimlikleri.
///
/// Doküman metni değil **test kaynağı** taranır: bir REQ'in yalnızca
/// `docs/` içinde geçmesi test edildiğini göstermez.
Set<String> requirementsMentionedInTests() {
  final pattern = RegExp(r'REQ-[A-Z]+-\d+');
  final mentioned = <String>{};

  for (final entity in Directory('test').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // Bu dosyanın kendisi sayılmaz: `docs/25`'i ayrıştırdığı için tüm
    // kimlikleri "anıyor" görünürdü.
    if (entity.path.endsWith('requirement_traceability_test.dart')) continue;
    mentioned.addAll(
      pattern.allMatches(entity.readAsStringSync()).map((m) => m.group(0)!),
    );
  }
  return mentioned;
}

/// **Bilinçli olarak test edilmeyen** 🔴 Must requirement'lar.
///
/// Her satırın bir gerekçesi vardır ve gerekçe `docs/32`'deki bir maddeye
/// bağlıdır. Bu harita bir *yapılacaklar listesi* değil, bir **sözleşmedir**:
/// buradan bir kayıt silmek, testin o REQ'i aramaya başlaması demektir.
const Map<String, String> deliberatelyUntested = {
  // ─ Donanım gerektiriyor — docs/32 §7 (W1–W15)
  //
  // ⚠️ REQ-BARC-001/002 buraya YAZILMAZ: zaman eşiği mantığı enjekte edilmiş
  // saatle tamamen test edilir (`barcode_input_handler_test.dart`). Yalnızca
  // GERÇEK SCANNER ile uçtan uca davranış donanım ister ve o docs/32 W1'dir.
  // Kısmen test edilen bir REQ'i tamamen muaf tutmak gerçek kapsamı gizler.
  'REQ-COMP-001': 'Windows kurulum — docs/32 W5',
  'REQ-COMP-002': 'Windows veri dizini — docs/32 W6',
  'REQ-COMP-003': 'Windows DPI/çözünürlük — docs/32 W7',
  'REQ-COMP-004': 'Windows installer — docs/32 W5',

  // ─ Faz 11–12 kapsamında, henüz ölçülmedi
  'REQ-PERF-003':
      'Uygulama soğuk açılış süresi — gerçek uygulama başlatmayı\n      // gerektirir; docs/32 W7 ile birlikte elle ölçülür',
  'REQ-PERF-005': 'Bellek profilleme — elle yapılmalı',

  // ─ Fiziksel senaryo
  'REQ-DATA-003': 'Elektrik kesintisi sonrası tutarlılık — docs/32 W9',

  // ─ Kısmen sağlanıyor, ÖLÇÜLDÜ ama test edilmedi
  //
  // Görsel optimizasyonu isolate'te çalışıyor (`optimizeImageInIsolate`);
  // import ise ana isolate'te ve 1.000 satır **795 ms** sürüyor. "UI
  // bloklanmıyor" iddiası kare süresi ölçmeyi gerektirir ve `testWidgets`
  // sahte zamanla çalıştığı için bunu ölçemez. docs/32 H10.
  'REQ-ARCH-006': 'UI bloklanmama ölçümü — docs/32 H10, elle doğrulanmalı',
};

void main() {
  late List<Requirement> requirements;
  late Set<String> mentioned;

  setUpAll(() {
    requirements = parseRequirements();
    mentioned = requirementsMentionedInTests();
  });

  test('docs/25 ayrıştırması makul bir sonuç veriyor', () {
    // Ayrıştırma sessizce bozulursa test "her şey yolunda" derdi.
    expect(
      requirements.length,
      greaterThan(250),
      reason: 'docs/25 yaklaşık 285 requirement içerir.',
    );
    expect(
      requirements.where((r) => r.isMust).length,
      greaterThan(150),
      reason: 'Yaklaşık 185 tanesi 🔴 Must\'tır.',
    );
    expect(
      requirements.map((r) => r.id).toSet().length,
      requirements.length,
      reason: 'Aynı REQ iki kez tanımlanmış olamaz.',
    );
  });

  test('test kaynağında gerçekten REQ anılıyor', () {
    expect(
      mentioned.length,
      greaterThan(100),
      reason: 'Tarama bozulmuş olabilir.',
    );
  });

  test('docs/31 Faz 11 — her 🔴 Must requirement bir testte ANILIYOR', () {
    final musts = requirements.where((r) => r.isMust).toList();
    final missing =
        musts
            .where(
              (r) =>
                  !mentioned.contains(r.id) &&
                  !deliberatelyUntested.containsKey(r.id),
            )
            .toList()
          ..sort((a, b) => a.id.compareTo(b.id));

    expect(
      missing,
      isEmpty,
      reason:
          'Bu 🔴 Must requirement\'lar hiçbir testte anılmıyor. Ya test '
          'yazılmalı ya da `deliberatelyUntested` içine GEREKÇESİYLE '
          'eklenmelidir — "unuttum" ile "kapsam dışı" aynı yere yazılamaz.\n'
          '${missing.map((r) => "  · $r").join("\n")}',
    );
  });

  test(
    '`deliberatelyUntested` yalnızca GERÇEK requirement\'lara işaret eder',
    () {
      final known = requirements.map((r) => r.id).toSet();

      expect(
        deliberatelyUntested.keys.where((id) => !known.contains(id)),
        isEmpty,
        reason:
            'docs/25\'te bulunmayan bir REQ muaf tutulamaz — büyük olasılıkla '
            'yazım hatası.',
      );
    },
  );

  test('`deliberatelyUntested` BAYATLAMIŞ kayıt içermez', () {
    // Bir REQ test edilmeye başlandıysa muafiyet listesinden çıkarılmalıdır;
    // yoksa harita yalan söylemeye başlar ve gerçek boşlukları gizler.
    final stale = deliberatelyUntested.keys.where(mentioned.contains).toList();

    expect(
      stale,
      isEmpty,
      reason:
          'Bu requirement\'lar artık test ediliyor; muafiyet listesinden '
          'çıkarılmalıdır: $stale',
    );
  });

  test('her muafiyetin bir GEREKÇESİ vardır', () {
    for (final entry in deliberatelyUntested.entries) {
      expect(
        entry.value.trim().length,
        greaterThan(10),
        reason: '${entry.key} için anlamlı bir gerekçe yazılmamış.',
      );
    }
  });
}
