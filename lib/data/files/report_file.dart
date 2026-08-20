/// Rapor dosyası yazımı — **rules/03 §7.**
///
/// CSV **baytları** yazılır. [CsvWriter.encode] çıktısı zaten BOM karakteriyle
/// başlar; `utf8.encode` onu `EF BB BF` baytlarına çevirir. Türkçe Excel
/// BOM'suz dosyayı Latin-1 sanar ve `ş`, `ğ`, `İ` bozulur.
library;

import 'dart:convert';
import 'dart:io';

/// Başarılıysa `true`; yazılamazsa `false` (dolu disk, izin, kilitli dosya).
///
/// Exception fırlatmaz: dosya yazamamak **beklenen** bir kullanıcı hatasıdır
/// (rules/06 §7) ve ekran sade bir Türkçe mesaj gösterir.
Future<bool> writeReportFile(String path, String contents) async {
  try {
    await File(path).writeAsBytes(utf8.encode(contents), flush: true);
    return true;
  } on Object {
    return false;
  }
}
