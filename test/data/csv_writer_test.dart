/// CSV üretimi — **rules/03 §7 · rules/04 §7 · REQ-IMEX-014 · REQ-SEC-005**
///
/// | Test | Kural |
/// |---|---|
/// | UTF-8 **BOM** ile başlar | Türkçe Excel uyumu |
/// | Ayırıcı `;` | Türkçe yerelde `,` ondalık ayırıcıdır |
/// | `=`, `+`, `-`, `@` kaçışlanır | Formül enjeksiyonu (rules/04 §7) |
/// | Ayırıcı ve tırnak içeren hücre alıntılanır | RFC 4180 |
/// ## Kapsanan uç durumlar (docs/26 · Faz 11 izlenebilirliği)
///
/// - **EC-IMEX-013** — export'ta ürün adı `=CMD()` ile başlıyor
///
library;

import 'dart:convert';

import 'package:canteen/data/files/csv_writer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rules/03 §7 — Türkçe Excel uyumu', () {
    test('çıktı UTF-8 BOM ile BAŞLAR', () {
      final csv = CsvWriter.encode([
        ['Ürün', 'Tutar'],
      ]);

      expect(csv.codeUnitAt(0), 0xFEFF);
      final bytes = CsvWriter.encodeBytes([
        ['a'],
      ]);
      expect(bytes.take(3), [
        0xEF,
        0xBB,
        0xBF,
      ], reason: 'BOM olmadan Türkçe Excel dosyayı Latin-1 sanar.');
    });

    test('ayırıcı NOKTALI VİRGÜLDÜR', () {
      final csv = CsvWriter.encode([
        ['a', 'b', 'c'],
      ]);

      expect(csv, contains('a;b;c'));
      expect(csv, isNot(contains('a,b,c')));
    });

    test('satır sonu CRLF', () {
      final csv = CsvWriter.encode([
        ['a'],
        ['b'],
      ]);

      expect(csv, '﻿a\r\nb\r\n');
    });

    test('Türkçe karakterler bozulmadan kodlanır', () {
      final bytes = CsvWriter.encodeBytes([
        ['Şule ığdır ÇĞİÖŞÜ'],
      ]);

      expect(utf8.decode(bytes), contains('Şule ığdır ÇĞİÖŞÜ'));
    });
  });

  group('rules/04 §7 — formül enjeksiyonu', () {
    test('dört tehlikeli önek de kaçışlanır', () {
      for (final prefix in ['=', '+', '-', '@']) {
        final cell = CsvWriter.escapeCell('${prefix}cmd');
        expect(
          cell.startsWith("'"),
          isTrue,
          reason: '"$prefix" ile başlayan hücre Excel\'de ÇALIŞTIRILABİLİR.',
        );
        expect(cell, "'${prefix}cmd");
      }
    });

    test('gerçek saldırı yükü etkisizleşir', () {
      // Ürün adı KULLANICI GİRDİSİDİR ve rapor onu dışarı taşır.
      const payload = "=cmd|'/c calc'!A1";

      final cell = CsvWriter.escapeCell(payload);

      expect(cell.startsWith('='), isFalse);
      expect(cell.startsWith("'="), isTrue);
    });

    test('normal metin DEĞİŞTİRİLMEZ', () {
      expect(CsvWriter.escapeCell('Coca Cola 330ml'), 'Coca Cola 330ml');
      expect(CsvWriter.escapeCell('2026-000148'), '2026-000148');
    });

    test('sayılar ve boş değerler', () {
      expect(CsvWriter.escapeCell(42), '42');
      expect(CsvWriter.escapeCell(null), '');
      expect(CsvWriter.escapeCell(''), '');
    });

    test('NEGATİF sayı da kaçışlanır — veri kaybı değil, güvenlik', () {
      // `-5` teknik olarak formül önekiyle başlar. Kaçışlamak sayıyı metne
      // çevirir; alternatifi (kaçışlamamak) `-2+3` gibi bir hücrenin
      // hesaplanmasına izin vermek olurdu.
      expect(CsvWriter.escapeCell('-500'), "'-500");
    });
  });

  group('RFC 4180 — alıntılama', () {
    test('ayırıcı içeren hücre alıntılanır', () {
      expect(CsvWriter.escapeCell('a;b'), '"a;b"');
    });

    test('tırnak İKİYE katlanır', () {
      expect(CsvWriter.escapeCell('12" ekran'), '"12"" ekran"');
    });

    test('satır sonu içeren hücre alıntılanır', () {
      expect(CsvWriter.escapeCell('ilk\nikinci'), '"ilk\nikinci"');
    });

    test('formül kaçışı ÖNCE, alıntılama SONRA uygulanır', () {
      // Ters sırada olsaydı eklenen tırnak `=`'in başa gelmesini engellemez,
      // yalnızca gizlerdi.
      final cell = CsvWriter.escapeCell('=a;b');

      expect(cell, '"\'=a;b"');
      expect(cell.contains("'="), isTrue);
    });
  });
}
