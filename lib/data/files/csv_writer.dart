/// CSV üretimi — **rules/03 §7 · rules/04 §7 · REQ-IMEX-014 · REQ-SEC-005**
///
/// ## Neden bir paket kullanılmıyor
///
/// OD-009 `csv` paketini **okuma** için karara bağlamıştır ve Faz 10 onu
/// kullanacaktır — ayrıştırma zor kısımdır. **Yazma** tarafı ise üç kurala
/// indirgenir ve üçü de bu projeye özgüdür:
///
/// | Kural | Sebep |
/// |---|---|
/// | UTF-8 **BOM ile** | Türkçe Excel BOM'suz dosyayı Latin-1 sanır; `ş`, `ğ`, `İ` bozulur |
/// | Ayırıcı `;` | Türkçe yerelde Excel `,`'yı ondalık ayırıcı sayar ve tek sütun açar |
/// | Formül kaçışlama | `=`, `+`, `-`, `@` ile başlayan hücre Excel'de **çalıştırılır** |
///
/// Üçünü de bir pakete devretmek, paketin varsayılanlarının bu kurallarla
/// örtüştüğünü **her sürümde** doğrulamayı gerektirirdi (rules/01 §7, soru 2).
///
/// ## Formül enjeksiyonu neden ciddi
///
/// Kullanıcı bir ürüne `=cmd|'/c calc'!A1` adını verirse, dışa aktarılan CSV
/// başka bir makinede Excel'de açıldığında bu **komut olarak yorumlanabilir**.
/// Ürün adı kullanıcı girdisidir; rapor onu dışarı taşır.
library;

import 'dart:convert';

abstract final class CsvWriter {
  /// Türkçe Excel uyumu (rules/03 §7).
  static const String separator = ';';

  /// UTF-8 BOM — `EF BB BF`.
  static const String byteOrderMark = '﻿';

  /// Excel'de formül başlatan karakterler (rules/04 §7).
  static const List<String> formulaPrefixes = ['=', '+', '-', '@'];

  /// Satırları CSV metnine çevirir; **BOM ile başlar**.
  static String encode(List<List<Object?>> rows) {
    final buffer = StringBuffer(byteOrderMark);
    for (final row in rows) {
      buffer
        ..write(row.map(escapeCell).join(separator))
        // Windows Excel `\r\n` bekler; `\n` tek satır gibi görünebilir.
        ..write('\r\n');
    }
    return buffer.toString();
  }

  /// Dosyaya yazılacak baytlar.
  static List<int> encodeBytes(List<List<Object?>> rows) =>
      utf8.encode(encode(rows));

  /// Tek bir hücreyi güvenli hâle getirir.
  ///
  /// İki ayrı iş yapar ve **sırası önemlidir**:
  /// 1. Formül önekini etkisizleştir (`'` eklenir)
  /// 2. CSV alıntılaması (ayırıcı, tırnak veya satır sonu içeriyorsa)
  ///
  /// Ters sırada yapılsaydı eklenen tırnak `=`'in başa gelmesini engellemez,
  /// yalnızca gizlerdi.
  static String escapeCell(Object? value) {
    if (value == null) return '';
    var text = value.toString();

    // rules/04 §7 — formül enjeksiyonu.
    if (text.isNotEmpty && formulaPrefixes.contains(text[0])) {
      // Baştaki tek tırnak Excel'e "bu metindir" der ve hücrede görünmez.
      text = "'$text";
    }

    final needsQuotes =
        text.contains(separator) ||
        text.contains('"') ||
        text.contains('\n') ||
        text.contains('\r');
    if (!needsQuotes) return text;

    // RFC 4180: içerideki tırnak ikiye katlanır.
    return '"${text.replaceAll('"', '""')}"';
  }
}
