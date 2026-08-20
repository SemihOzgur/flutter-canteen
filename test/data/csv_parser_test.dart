/// CSV okuma — **docs/20 §2 · OD-009**
///
/// | Test | Kural |
/// |---|---|
/// | `;` ve `,` otomatik algılanır | docs/20 §2 |
/// | BOM atılır | Excel çıktısı |
/// | `\r\n` ve `\n` desteklenir | docs/20 §2 |
/// | RFC 4180 tırnak kuralları | docs/20 §2 |
/// | Boş satırlar atlanır | Excel dosya sonuna boş satır ekler |
library;

import 'package:canteen/data/files/csv_parser.dart';
import 'package:canteen/data/files/csv_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('docs/20 §2 — ayırıcı algılama', () {
    test('noktalı virgül algılanır', () {
      final parsed = CsvParser.parse('Ad;Fiyat\nKola;25,00')!;

      expect(parsed.separator, ';');
      expect(parsed.header, ['Ad', 'Fiyat']);
      expect(parsed.rows.single, ['Kola', '25,00']);
    });

    test('virgül algılanır', () {
      final parsed = CsvParser.parse('Ad,Fiyat\nKola,25.00')!;

      expect(parsed.separator, ',');
      expect(parsed.rows.single, ['Kola', '25.00']);
    });

    test('sekme algılanır', () {
      final parsed = CsvParser.parse('Ad\tFiyat\nKola\t25')!;

      expect(parsed.separator, '\t');
      expect(parsed.rows.single, ['Kola', '25']);
    });

    test('TIRNAK İÇİNDEKİ ayırıcı sayılmaz', () {
      // `"Ürün; Açıklama",Fiyat` — `;` iki kez geçer ama gerçek ayırıcı `,`.
      final parsed = CsvParser.parse('"Ürün; Açıklama",Fiyat\n"Kola; 330",25')!;

      expect(
        parsed.separator,
        ',',
        reason: 'Ham sayım yanlış ayırıcı seçtirirdi.',
      );
      expect(parsed.header, ['Ürün; Açıklama', 'Fiyat']);
    });

    test('tek sütunlu dosyada varsayılan `;` kalır', () {
      final parsed = CsvParser.parse('Ad\nKola')!;

      expect(parsed.separator, ';');
      expect(parsed.header, ['Ad']);
    });
  });

  group('kodlama ve satır sonları', () {
    test('BOM atılır — ilk başlık bozulmaz', () {
      final parsed = CsvParser.parse(
        '${CsvWriter.byteOrderMark}Ad;Fiyat\nKola;25',
      )!;

      expect(
        parsed.header.first,
        'Ad',
        reason: 'BOM atılmasaydı ilk sütun adı eşleşmezdi.',
      );
    });

    test('CRLF ve LF birlikte çalışır', () {
      final crlf = CsvParser.parse('Ad;Fiyat\r\nKola;25\r\nSu;10')!;
      final lf = CsvParser.parse('Ad;Fiyat\nKola;25\nSu;10')!;

      expect(crlf.rows, lf.rows);
      expect(crlf.rows, hasLength(2));
    });

    test('CsvWriter çıktısı geri OKUNABİLİR — round-trip', () {
      // REQ-IMEX-013: export → düzenle → import döngüsü çalışmalıdır.
      final csv = CsvWriter.encode([
        ['Ad', 'Fiyat'],
        ['Kola; 330ml', '25,00'],
        ['12" ekran', '10,00'],
      ]);

      final parsed = CsvParser.parse(csv)!;

      expect(parsed.header, ['Ad', 'Fiyat']);
      expect(parsed.rows[0], ['Kola; 330ml', '25,00']);
      expect(parsed.rows[1], ['12" ekran', '10,00']);
    });
  });

  group('RFC 4180', () {
    test('tırnak içindeki ayırıcı korunur', () {
      final parsed = CsvParser.parse('Ad;Not\n"Kola; büyük";x')!;

      expect(parsed.rows.single, ['Kola; büyük', 'x']);
    });

    test('çiftlenmiş tırnak tek tırnağa çözülür', () {
      final parsed = CsvParser.parse('Ad\n"12"" ekran"')!;

      expect(parsed.rows.single.single, '12" ekran');
    });
  });

  group('boş girdiler', () {
    test('boş dosya null döner', () {
      expect(CsvParser.parse(''), isNull);
      expect(CsvParser.parse('   \n  '), isNull);
    });

    test('yalnızca başlık varsa satır YOKTUR', () {
      final parsed = CsvParser.parse('Ad;Fiyat')!;

      expect(parsed.header, hasLength(2));
      expect(parsed.rows, isEmpty);
    });

    test('araya ve sona serpilmiş boş satırlar ATLANIR', () {
      // Excel dosya sonuna boş satır eklemeye meyillidir; her biri
      // "ürün adı zorunlu" hatası üretirdi.
      final parsed = CsvParser.parse('Ad;Fiyat\nKola;25\n;\n\nSu;10\n;\n')!;

      expect(parsed.rows, hasLength(2));
      expect(parsed.rows.map((r) => r.first), ['Kola', 'Su']);
    });

    test('yalnızca BOŞLUK içeren satır da atlanır', () {
      // Ayrıştırıcının `skipEmptyLines`'ı bu satırı boş SAYMAZ: hücreler
      // teknik olarak doludur (` `). Kendi filtremiz `trim()` sonrası bakar
      // ve satırı eler. Bu ayrım gerçek dosyalarda ortaya çıkar — kullanıcı
      // bir hücreye yanlışlıkla boşluk bırakmış olabilir.
      final parsed = CsvParser.parse('Ad;Fiyat\nKola;25\n  ;   \nSu;10')!;

      expect(
        parsed.rows,
        hasLength(2),
        reason: 'Boşluklu satır "ürün adı zorunlu" hatası üretmemelidir.',
      );
    });
  });

  group('REQ-IMEX-005 — satır numarası', () {
    test('başlık 1, ilk veri satırı 2', () {
      expect(ParsedCsv.lineNumberOf(0), 2);
      expect(ParsedCsv.lineNumberOf(41), 43);
    });
  });
}
