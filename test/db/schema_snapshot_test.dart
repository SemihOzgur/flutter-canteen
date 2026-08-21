/// Şema anlık görüntüsü — **REQ-MIG-008**
///
/// docs/06 §6: "Yayınlanan her şema versiyonu repoda saklanır
/// (`test/db/schema/vN.json`) — bu, gelecekteki migration'ların eski şemalara
/// karşı test edilmesini sağlar."
///
/// ## Bu dosya iki iş yapar
///
/// 1. **Üretir:** `test/db/schema/v1.json`, gerçekten oluşturulan veritabanının
///    `sqlite_master` içeriğinden üretilir — elle yazılmaz.
/// 2. **Korur:** Sonraki her çalıştırmada şema yeniden üretilip dosyayla
///    karşılaştırılır. Şema kazara değişirse bu test **kırılır.**
///
/// Yeniden üretmek için:
/// ```sh
/// UPDATE_SCHEMA_SNAPSHOT=1 flutter test test/db/schema_snapshot_test.dart
/// ```
/// Bu, yalnızca `kSupportedSchemaVersion` bilinçli olarak artırıldığında
/// yapılır (docs/06 §2 kural 1: yayınlanmış şema sonradan düzenlenmez).
///
/// ## Kaynak notu — neden drift'in kendi dump'ı değil
///
/// `dart run drift_dev schema dump`, drift 2.34.3 + drift_dev 2.34.0
/// bileşiminde **aracın kendi içinde** derlenmiyor (`drift3_preview` /
/// `allSchemaEntities` uyumsuzluğu). Bu bir proje hatası değildir. Buradaki
/// anlık görüntü de gerçek üretilen şemadan alınır ve REQ-MIG-008'in amacını
/// (eski şemayı repoda saklamak + sapmayı yakalamak) karşılar. Araç
/// düzeldiğinde drift formatındaki dump ayrıca eklenebilir — GAP-2-006.
library;

import 'dart:convert';
import 'dart:io';

import 'package:canteen/data/db/schema_version.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  test(
    'v$kSupportedSchemaVersion şeması repodaki anlık görüntüyle AYNI',
    () async {
      final db = memoryDatabase();
      addTearDown(db.close);

      final rows = await db
          .customSelect(
            "SELECT type, name, sql FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name;",
          )
          .get();

      final entities = [
        for (final row in rows)
          {
            'type': row.data['type'],
            'name': row.data['name'],
            'sql': (row.data['sql'] as String?)
                ?.replaceAll(RegExp(r'\s+'), ' ')
                .trim(),
          },
      ];

      final snapshot = {
        'schemaVersion': kSupportedSchemaVersion,
        'entities': entities,
      };

      final encoded =
          '${const JsonEncoder.withIndent('  ').convert(snapshot)}\n';
      final file = File('test/db/schema/v$kSupportedSchemaVersion.json');

      final regenerate =
          Platform.environment['UPDATE_SCHEMA_SNAPSHOT'] == '1' ||
          !file.existsSync();

      if (regenerate) {
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(encoded);
        // ignore: avoid_print
        print('Şema anlık görüntüsü yazıldı: ${file.path}');
      }

      expect(
        file.readAsStringSync().replaceAll('\r\n', '\n'),
        encoded,
        reason:
            'Şema, repodaki v$kSupportedSchemaVersion anlık görüntüsünden SAPTI. '
            'Şema değişikliği ancak versiyonlu bir migration ile yapılır '
            '(REQ-MIG-001 · docs/06 §2).',
      );
    },
  );

  test('anlık görüntü 15 tablo ve 20 index içerir', () {
    final file = File('test/db/schema/v$kSupportedSchemaVersion.json');
    expect(file.existsSync(), isTrue);

    final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    final entities = decoded['entities']! as List<Object?>;

    final tables = entities
        .cast<Map<String, Object?>>()
        .where((e) => e['type'] == 'table')
        .length;
    final indexes = entities
        .cast<Map<String, Object?>>()
        .where((e) => e['type'] == 'index')
        .length;

    expect(
      decoded['schemaVersion'],
      kSupportedSchemaVersion,
      reason:
          'Anlık görüntü, kodun desteklediği versiyonun kendisidir; sabit '
          'bir sayıya bağlanırsa şema yükseltilince sessizce eskir.',
    );
    // OD-029 tabloya KOLON ekledi, tablo eklemedi: sayı değişmez.
    expect(tables, 15, reason: 'docs/05 §2 — şema FİNAL: 15 tablo.');
    expect(
      indexes,
      20,
      reason:
          'docs/05 §3\'teki 17 index + docs/05 §2\'deki 3 UNIQUE kısıtın '
          'adlandırılmış index karşılığı.',
    );
  });
}
