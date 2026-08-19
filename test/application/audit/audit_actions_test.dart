/// Denetim işlemleri ↔ doküman izlenebilirliği — **REQ-AUDIT-001 · docs/18 §3**
///
/// ## Bu dosya neden var
///
/// REQ-AUDIT-001 (🔴 M) *"§3'te listelenen tüm işlemler audit log'a yazılır"*
/// der. Bu, kod okunarak doğrulanamayacak kadar dağınık bir iddiadır: action
/// adları servislere yayılır ve bir tanesini unutmak **hiçbir testi kırmaz.**
/// Faz 6'ya girildiğinde dokümanda tanımlı 52 action'ın **18'i** kodda hiç
/// yoktu ve bunu fark eden bir mekanizma yoktu.
///
/// Buradaki testler `docs/18 §3`'ü **ayrıştırır** ve üç yönlü karşılaştırır:
///
/// ```text
/// docs/18 §3  ──►  AuditActions.all      (dokümanda var, sabit yok → KIRILIR)
/// AuditActions.all  ──►  docs/18 §3      (sabit var, dokümanda yok → KIRILIR)
/// AuditActions.all  ──►  lib/ kaynak     (yazım noktası yok → KIRILIR,
///                                          futurePhaseActions hariç)
/// ```
///
/// Üçüncüsü asıl korumadır: bir action'ı sabit olarak tanımlayıp yazmayı
/// unutmak artık sessiz kalamaz.
library;

import 'dart:io';

import 'package:canteen/application/audit/audit_actions.dart';
import 'package:flutter_test/flutter_test.dart';

/// docs/18 §3'teki tablo hücrelerinden action adlarını çıkarır.
Set<String> documentedActions() {
  final doc = File('docs/18-audit-log.md').readAsStringSync();
  final start = doc.indexOf('## 3. Kaydedilen işlemler');
  final end = doc.indexOf('## 4. Kaydedilmeyenler');
  expect(
    start >= 0 && end > start,
    isTrue,
    reason:
        'docs/18 §3 bölüm başlıkları değişmiş. Bu test dokümanın yapısına '
        'bağlıdır; başlık değiştiyse test de güncellenmelidir.',
  );

  // Backtick içindeki camelCase adlar — `productCreated`, `saleCompleted` …
  final pattern = RegExp(r'`([a-z][A-Za-z]+)`');
  return pattern
      .allMatches(doc.substring(start, end))
      .map((m) => m.group(1)!)
      .toSet();
}

/// `lib/` içinde `AuditActions.<name>` olarak **kullanılan** adlar.
Set<String> referencedInSource() {
  final used = <String>{};
  final pattern = RegExp(r'AuditActions\.([a-z][A-Za-z]+)');

  for (final entity in Directory('lib').listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // Kayıt defterinin kendisi bir kullanım sayılmaz.
    if (entity.path.endsWith('audit_actions.dart')) continue;
    for (final match in pattern.allMatches(entity.readAsStringSync())) {
      used.add(match.group(1)!);
    }
  }
  return used;
}

void main() {
  test('docs/18 §3\'teki her action AuditActions içinde tanımlıdır', () {
    final documented = documentedActions();

    expect(
      documented.length,
      greaterThan(40),
      reason: 'Ayrıştırma bozulmuş olabilir — §3\'te 50\'ye yakın action var.',
    );
    expect(
      documented.difference(AuditActions.all),
      isEmpty,
      reason:
          'REQ-AUDIT-001: dokümanda tanımlı bir denetim işlemi kodda karşılığı '
          'olmadan bırakılamaz.',
    );
  });

  test('AuditActions içindeki her action dokümanda tanımlıdır', () {
    // Ters yön: rules/00 §6 — dokümanda olmayan action UYDURULMAZ.
    expect(
      AuditActions.all.difference(documentedActions()),
      isEmpty,
      reason:
          'Kodda dokümanda bulunmayan bir action var. Önce docs/18 §3 '
          'güncellenir, sonra kod (rules/00 §3).',
    );
  });

  test('futurePhaseActions yalnızca tanımlı action\'lara işaret eder', () {
    expect(
      AuditActions.futurePhaseActions.keys.toSet().difference(AuditActions.all),
      isEmpty,
    );
  });

  test('ertelenmemiş her action\'ın bir YAZIM NOKTASI vardır', () {
    final referenced = referencedInSource();
    final expectedNow = AuditActions.all.difference(
      AuditActions.futurePhaseActions.keys.toSet(),
    );

    final missing = expectedNow.difference(referenced)..toList().sort();

    expect(
      missing,
      isEmpty,
      reason:
          'Bu action\'lar tanımlı ama hiçbir yerde YAZILMIYOR. Ya yazım '
          'noktası eklenmeli ya da hangi faza ait olduğu '
          'AuditActions.futurePhaseActions içinde belirtilmelidir — '
          '"tanımladım ama unuttum" durumu sessiz kalmamalıdır.\n'
          'Eksikler: ${missing.toList()..sort()}',
    );
  });

  test('ertelenen action\'ların yazım noktası HENÜZ yoktur', () {
    // Tersi de kontrol edilir: bir action yazılmaya başlandıysa
    // `futurePhaseActions` listesinden çıkarılmalıdır, yoksa harita yalan
    // söylemeye başlar.
    final referenced = referencedInSource();
    final stale = AuditActions.futurePhaseActions.keys
        .where(referenced.contains)
        .toList();

    expect(
      stale,
      isEmpty,
      reason:
          'Bu action\'lar artık yazılıyor; futurePhaseActions listesinden '
          'çıkarılmalıdır: $stale',
    );
  });
}
