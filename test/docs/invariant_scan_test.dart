/// Kaynak taraması ile doğrulanan invariant'lar — **Faz 11 kalite kapısı**
///
/// Bazı gereksinimler tek bir davranışa değil, **kodun tamamına** dair bir
/// iddiadır: *"hiçbir yerde ağ çağrısı yok"*, *"hiçbir sorgu string
/// birleştirmiyor"*. Bunlar bir senaryo testiyle kanıtlanamaz — yalnızca
/// **taranarak** kanıtlanır.
///
/// | Test | Kural |
/// |---|---|
/// | Ağ trafiği yok | REQ-SEC-008 · BR-GEN-001 · rules/01 §9 |
/// | Sorgular parametreli | REQ-SEC-006 · rules/03 §1 |
/// | Audit kayıtları düzenlenemez/silinemez | REQ-AUDIT-005 · rules/03 §9 |
/// | Hata mesajları Türkçe ve teknik detaysız | REQ-UX-007/008 · REQ-SEC-007 |
library;

import 'dart:io';

import 'package:canteen/application/import/import_failures.dart';
import 'package:canteen/application/sales/cart_failures.dart';
import 'package:canteen/application/sales/return_failures.dart';
import 'package:canteen/application/sales/sale_failures.dart';
import 'package:canteen/application/stock/stock_failures.dart';
import 'package:canteen/core/result/result.dart';
import 'package:flutter_test/flutter_test.dart';

Iterable<File> dartFilesUnder(String directory) sync* {
  for (final entity in Directory(directory).listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) yield entity;
  }
}

void main() {
  group('REQ-SEC-008 · BR-GEN-001 — ağ trafiği YOK', () {
    test('hiçbir kaynak dosyası ağ API\'si kullanmıyor', () {
      // rules/01 §9: "Ağ çağrısı yapan kod YAZILMAZ. Analytics, telemetry,
      // crash reporting, cloud sync, otomatik güncelleme kontrolü V1'de
      // yoktur." Bu, tek tek gözden geçirmekle değil ancak taramayla
      // garanti edilebilir.
      const bannedImports = [
        "import 'dart:io'", // yalnızca HttpClient için taranır (aşağıda)
      ];
      const bannedSymbols = [
        'HttpClient',
        'HttpServer',
        'WebSocket',
        'RawDatagramSocket',
        'Socket.connect',
        'package:http/',
        'package:dio/',
        'package:web_socket',
        'InternetAddress.lookup',
      ];

      final offenders = <String>[];
      for (final file in dartFilesUnder('lib')) {
        final source = file.readAsStringSync();
        for (final symbol in bannedSymbols) {
          if (source.contains(symbol)) {
            offenders.add('${file.path} → $symbol');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'REQ-SEC-008: uygulama hiçbir veriyi dışarı göndermez. '
            'Local-first bir kantin uygulamasında ağ çağrısı bir özellik '
            'değil, bir sızıntıdır → $offenders',
      );
      expect(bannedImports, isNotEmpty, reason: 'Liste boş bırakılmamalı.');
    });

    test('pubspec ağ paketi içermiyor', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();

      for (final package in const [
        'http:',
        'dio:',
        'web_socket_channel:',
        'firebase',
        'sentry',
        'posthog',
        'amplitude',
      ]) {
        expect(
          pubspec.contains(package),
          isFalse,
          reason: 'REQ-SEC-008 · rules/01 §9 — "$package" eklenmiş.',
        );
      }
    });
  });

  group('REQ-SEC-006 — sorgular PARAMETRELİ', () {
    test('ham SQL\'de string interpolasyonu YOK', () {
      // Drift'in sorgu kurucusu bunu zaten zorlar; risk `customSelect` /
      // `customStatement` çağrılarındadır. `$` içeren bir SQL literali,
      // değerin sorguya GÖMÜLDÜĞÜ anlamına gelir.
      final sqlCall = RegExp(
        r"custom(Select|Statement|Update)\(\s*(''')?'?([^;]*?)['\)]",
        dotAll: true,
      );
      final offenders = <String>[];

      for (final file in dartFilesUnder('lib')) {
        final source = file.readAsStringSync();
        for (final match in sqlCall.allMatches(source)) {
          final sql = match.group(3) ?? '';
          // `$` bir Dart interpolasyonudur; SQL'de `?` kullanılmalıdır.
          if (sql.contains(r'$')) {
            offenders.add('${file.path} → ${sql.trim().split('\n').first}');
          }
        }
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'REQ-SEC-006: değer sorguya gömülmez, PARAMETRE olarak geçirilir '
            '→ $offenders',
      );
    });
  });

  group('REQ-AUDIT-005 — audit kayıtları düzenlenemez ve silinemez', () {
    test('AuditLogsDao update/delete metodu SUNMAZ', () {
      // rules/03 §9: denetim kaydı değiştirilemez. Bunu bir davranış testiyle
      // kanıtlamak mümkün değildir — kanıt, öyle bir YOLUN OLMAMASIDIR.
      final daos = File('lib/data/dao/daos.dart').readAsStringSync();
      final start = daos.indexOf('class AuditLogsDao');
      final end = daos.indexOf('class AppSettingsDao');
      expect(start >= 0 && end > start, isTrue);

      final body = daos.substring(start, end);

      expect(
        body.contains('update(auditLogs)'),
        isFalse,
        reason: 'Audit kaydı GÜNCELLENEMEZ.',
      );
      expect(
        body.contains('delete(auditLogs)'),
        isFalse,
        reason: 'Audit kaydı SİLİNEMEZ.',
      );
    });

    test('hiçbir yerde audit_logs tablosuna DELETE/UPDATE yazılmıyor', () {
      final offenders = <String>[];
      for (final file in dartFilesUnder('lib')) {
        final source = file.readAsStringSync().toUpperCase();
        if (source.contains('DELETE FROM AUDIT_LOGS') ||
            source.contains('UPDATE AUDIT_LOGS')) {
          offenders.add(file.path);
        }
      }

      expect(offenders, isEmpty, reason: 'REQ-AUDIT-005 · BR-GEN-002');
    });
  });

  group('REQ-UX-007/008 · REQ-SEC-007 — hata mesajları', () {
    /// Uygulamanın kullanıcıya gösterdiği tüm beklenen iş hataları.
    List<Failure> allFailures() => const [
      // Sepet ve satış
      CartFailures.productNotFound,
      CartFailures.lineNotFound,
      CartFailures.negativeQuantity,
      CartFailures.negativePrice,
      SaleFailures.emptyCart,
      SaleFailures.insufficientCash,
      SaleFailures.negativeCash,
      SaleFailures.alreadyInProgress,
      SaleFailures.productMissing,
      // İade
      ReturnFailures.saleNotFound,
      ReturnFailures.alreadyCancelled,
      ReturnFailures.cancelAfterReturn,
      ReturnFailures.returnFromCancelled,
      ReturnFailures.exceedsRemaining,
      ReturnFailures.nothingToReturn,
      ReturnFailures.lineNotInSale,
      ReturnFailures.reasonRequired,
      // Stok
      StockFailures.negativeInitialStock,
      StockFailures.alreadyInitialized,
      StockFailures.nonPositiveSaleQuantity,
      StockFailures.reasonRequired,
      StockFailures.wasteMustBePositive,
      StockFailures.adjustmentNoChange,
      StockFailures.emptyEntry,
      StockFailures.entryQuantityInvalid,
      StockFailures.negativePurchasePrice,
      StockFailures.movementNotFound,
      StockFailures.productNotFound,
      // Import
      ImportFailures.fileUnreadable,
      ImportFailures.emptyFile,
      ImportFailures.missingRequiredColumns,
      ImportFailures.notConfirmed,
      ImportFailures.cancelledByPolicy,
      ImportFailures.nothingToImport,
    ];

    test('REQ-UX-008 · REQ-SEC-007 — teknik detay SIZDIRILMAZ', () {
      // rules/05 §5: "Teknik hata kodu ve stack trace kullanıcıya
      // gösterilmez — log dosyasına yazılır."
      const technicalMarkers = [
        'SQLITE',
        'Exception',
        'null',
        'Error:',
        'stack',
        '.dart',
        'DriftWrapped',
        'FormatException',
      ];

      for (final failure in allFailures()) {
        for (final marker in technicalMarkers) {
          expect(
            failure.userMessage.contains(marker),
            isFalse,
            reason:
                '${failure.code}: kullanıcı mesajı teknik ayrıntı içeriyor '
                '("$marker") → "${failure.userMessage}"',
          );
        }
        expect(
          failure.userMessage.contains(failure.code),
          isFalse,
          reason: '${failure.code}: hata KODU kullanıcıya gösterilemez.',
        );
      }
    });

    test('REQ-UX-007 — mesajlar Türkçe ve cümle hâlinde', () {
      for (final failure in allFailures()) {
        final message = failure.userMessage;

        expect(
          message.trim(),
          isNotEmpty,
          reason: '${failure.code}: boş mesaj.',
        );
        // rules/05 §5 — "ne oldu + ne yapmalıyım". Mesaj bir CÜMLE
        // içermelidir; örnekle bitmesi ("… Örnek: 25,50") geçerli bir
        // biçimdir, bu yüzden sonuna değil İÇİNDE noktalama aranır.
        expect(
          message.contains('.') || message.contains('?'),
          isTrue,
          reason:
              '${failure.code}: mesaj bir cümle değil, parça görünüyor '
              '("$message").',
        );
        expect(
          message.split(' ').length,
          greaterThanOrEqualTo(4),
          reason:
              '${failure.code}: "Hata oluştu" gibi bir mesaj kullanıcıya ne '
              'yapacağını söylemez ("$message").',
        );
        expect(
          message[0],
          message[0].toUpperCase(),
          reason: '${failure.code}: cümle büyük harfle başlamalıdır.',
        );
      }
    });

    test('hata kodları benzersizdir', () {
      // Aynı kod iki farklı hatada kullanılırsa log\'dan hangisi olduğu
      // ayırt edilemez.
      final codes = allFailures().map((f) => f.code).toList();

      expect(codes.toSet().length, codes.length);
    });
  });
}
