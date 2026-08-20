/// CSV okuma — **docs/20 §2 · OD-009 · BR-DATA-006**
///
/// ## Ayırıcı OTOMATİK algılanır
///
/// docs/20 §2: *"Import'ta `;` ve `,` otomatik algılanır."* Kullanıcının
/// elindeki dosya tedarikçiden gelmiş veya başka bir programdan çıkmış
/// olabilir; katı bir format dayatmak import özelliğini kullanılmaz hâle
/// getirir (docs/20 §3).
///
/// Algılama **başlık satırına** bakar: hangi aday ayırıcı daha çok sütun
/// üretiyorsa o seçilir. Tek sütunluk bir sonuç neredeyse her zaman yanlış
/// ayırıcı demektir.
///
/// ## BOM ve satır sonları
///
/// Excel'in yazdığı dosya BOM ile başlar ve `\r\n` kullanır; başka
/// programlar `\n` yazar. İkisi de kabul edilir.
library;

import 'package:csv/csv.dart';

import 'csv_writer.dart';

/// Ayrıştırılmış dosya — başlık + satırlar.
class ParsedCsv {
  final List<String> header;

  /// Veri satırları. Her satır başlıkla **aynı uzunlukta değildir**;
  /// eksik hücreler doğrulama aşamasında ele alınır.
  final List<List<String>> rows;

  /// Algılanan ayırıcı — önizlemede kullanıcıya gösterilir.
  final String separator;

  const ParsedCsv({
    required this.header,
    required this.rows,
    required this.separator,
  });

  /// Dosyadaki gerçek satır numarası: başlık 1'dir, veri 2'den başlar.
  ///
  /// Hata mesajları bu numarayı gösterir; kullanıcı kendi dosyasında o satırı
  /// bulabilmelidir (REQ-IMEX-005).
  static int lineNumberOf(int rowIndex) => rowIndex + 2;
}

abstract final class CsvParser {
  /// docs/20 §2 — aday ayırıcılar.
  static const List<String> candidateSeparators = [
    CsvWriter.separator,
    ',',
    '\t',
  ];

  /// Ayrıştırır; dosya boşsa `null`.
  static ParsedCsv? parse(String contents) {
    final text = _stripBom(contents);
    if (text.trim().isEmpty) return null;

    final separator = detectSeparator(text);
    // `\r\n` önceden `\n`'e indirgenir; ayrıştırıcı tek satır sonu görür.
    // `dynamicTyping: false` — her hücre METİN kalır. Sayıya çevirme
    // ayrıştırıcının işi değildir: `25,00` Türkçe ondalıktır ve
    // `MoneyParser` (rules/01 §2 — tek merkezî ayrıştırıcı) çözer.
    final rows = CsvDecoder(
      fieldDelimiter: separator,
    ).convert(text.replaceAll('\r\n', '\n'));

    if (rows.isEmpty) return null;

    final header = [for (final cell in rows.first) cell.toString().trim()];
    return ParsedCsv(
      header: header,
      rows: [
        for (final row in rows.skip(1))
          // Tamamen boş satırlar atlanır: Excel dosya sonuna boş satır
          // eklemeye meyillidir ve her biri "ürün adı zorunlu" hatası
          // üretirdi.
          if (row.any((cell) => cell.toString().trim().isNotEmpty))
            [for (final cell in row) cell.toString().trim()],
      ],
      separator: separator,
    );
  }

  /// Başlık satırında **en çok sütun üreten** ayırıcıyı seçer.
  static String detectSeparator(String contents) {
    final firstLine = contents
        .replaceAll('\r\n', '\n')
        .split('\n')
        .firstWhere((line) => line.trim().isNotEmpty, orElse: () => '');

    var best = CsvWriter.separator;
    var bestCount = 0;
    for (final candidate in candidateSeparators) {
      final count = _countOutsideQuotes(firstLine, candidate);
      if (count > bestCount) {
        best = candidate;
        bestCount = count;
      }
    }
    return best;
  }

  /// Tırnak **dışındaki** ayırıcıları sayar.
  ///
  /// `"Ürün; Açıklama";Fiyat` satırında `;` iki kez geçer ama yalnızca biri
  /// gerçek ayırıcıdır. Ham sayım burada yanlış ayırıcı seçtirebilirdi.
  static int _countOutsideQuotes(String line, String separator) {
    var inQuotes = false;
    var count = 0;
    for (var i = 0; i < line.length; i++) {
      final char = line[i];
      if (char == '"') {
        inQuotes = !inQuotes;
      } else if (!inQuotes && char == separator) {
        count++;
      }
    }
    return count;
  }

  /// BOM'u başlangıçtan siler.
  ///
  /// **İKİNCİ savunma hattıdır.** Dart'ın `String.trim()`'i U+FEFF'i de boşluk
  /// sayar ve her başlık hücresi zaten `trim()`'den geçiyor; mutasyon testi bu
  /// satırı kaldırınca hiçbir test kırılmıyor.
  ///
  /// Yine de duruyor: BOM'un atılması bu ayrıştırıcının **açık sözleşmesidir**,
  /// `trim()`'in Unicode boşluk tanımının bir yan etkisi değil. O tanım
  /// değişirse — ya da ileride bir alan `trim()`'siz okunursa — ilk sütun adı
  /// sessizce eşleşmez ve import "zorunlu sütun eşleşmedi" der.
  static String _stripBom(String contents) =>
      contents.startsWith(CsvWriter.byteOrderMark)
      ? contents.substring(1)
      : contents;
}
