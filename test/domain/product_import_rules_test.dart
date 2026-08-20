/// Ürün import doğrulaması — **docs/20 §3–§4 · BR-IMEX-001/002**
///
/// docs/20 §4'teki tablo satır satır sınanır. Hata (🔴 satır alınmaz) ile
/// uyarı (🟡 satır alınır) ayrımı **kesindir**: yanlış tarafa düşen bir kural
/// ya kullanıcının verisini kaybettirir ya da fiyatsız ürün oluşturur.
library;

import 'package:canteen/domain/services/product_import_rules.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<ImportIssue> validate({
    String name = 'Kola',
    String rawSalePrice = '25,00',
    int? salePriceMinor = 2500,
    int? purchasePriceMinor = 1800,
    String rawPurchasePrice = '18,00',
    List<String> barcodes = const [],
    Set<String> existingBarcodes = const {},
    Set<String> duplicateInFile = const {},
    String rawInitialStock = '',
    int? initialStock,
    String netWeightValue = '',
    String netWeightUnit = '',
    bool vatRateKnown = true,
    String rawVatRate = '',
    DuplicateBarcodePolicy policy = DuplicateBarcodePolicy.skip,
  }) => ProductImportRules.validate(
    name: name,
    rawSalePrice: rawSalePrice,
    salePriceMinor: salePriceMinor,
    purchasePriceMinor: purchasePriceMinor,
    rawPurchasePrice: rawPurchasePrice,
    barcodes: barcodes,
    existingBarcodes: existingBarcodes,
    duplicateInFile: duplicateInFile,
    rawInitialStock: rawInitialStock,
    initialStock: initialStock,
    netWeightValue: netWeightValue,
    netWeightUnit: netWeightUnit,
    vatRateKnown: vatRateKnown,
    rawVatRate: rawVatRate,
    policy: policy,
  );

  bool blocks(List<ImportIssue> issues) =>
      issues.any((issue) => issue.isBlocking);

  group('docs/20 §4 — HATA: satır alınmaz', () {
    test('ürün adı boş', () {
      expect(blocks(validate(name: '')), isTrue);
      expect(blocks(validate(name: '   ')), isTrue);
    });

    test('satış fiyatı boş', () {
      expect(blocks(validate(rawSalePrice: '', salePriceMinor: null)), isTrue);
    });

    test('satış fiyatı okunamadı', () {
      final issues = validate(rawSalePrice: 'on lira', salePriceMinor: null);

      expect(blocks(issues), isTrue);
      expect(
        issues.first.message,
        contains('on lira'),
        reason: 'REQ-IMEX-005 — kullanıcı NEYİN okunamadığını görmelidir.',
      );
    });

    test('satış fiyatı negatif', () {
      expect(blocks(validate(salePriceMinor: -100)), isTrue);
    });

    test('BR-IMEX-002 — barkod DOSYADA tekrarlanıyor', () {
      final issues = validate(barcodes: ['8690'], duplicateInFile: {'8690'});

      expect(
        blocks(issues),
        isTrue,
        reason:
            'Hangisinin doğru olduğuna sistem karar veremez; o barkoda ait '
            'TÜM satırlar reddedilir.',
      );
    });
  });

  group('docs/20 §4 — UYARI: satır ALINIR', () {
    test('ürün adı çok uzun → kırpılır', () {
      final issues = validate(name: 'x' * 200);

      expect(blocks(issues), isFalse);
      expect(issues, isNotEmpty);
    });

    test('SINIR — tam 120 karakter uyarı ÜRETMEZ', () {
      expect(validate(name: 'x' * 120), isEmpty);
      expect(validate(name: 'x' * 121), isNotEmpty);
    });

    test('alış fiyatı okunamadı → 0 kabul edilir', () {
      final issues = validate(
        rawPurchasePrice: 'bilinmiyor',
        purchasePriceMinor: null,
      );

      expect(blocks(issues), isFalse);
    });

    test('alış > satış → zararına satış GERÇEK bir durumdur', () {
      final issues = validate(salePriceMinor: 1000, purchasePriceMinor: 1500);

      expect(
        blocks(issues),
        isFalse,
        reason: 'Satırı reddetmek kullanıcının verisini kaybettirirdi.',
      );
    });

    test('SINIR — eşit fiyat uyarı ÜRETMEZ', () {
      expect(validate(salePriceMinor: 1000, purchasePriceMinor: 1000), isEmpty);
    });

    test('stok sayı değil → 0', () {
      final issues = validate(rawInitialStock: 'çok', initialStock: null);

      expect(blocks(issues), isFalse);
      expect(issues, isNotEmpty);
    });

    test('BR-SALE-011 — ondalık stok yuvarlanır', () {
      final issues = validate(rawInitialStock: '12,5', initialStock: 13);

      expect(blocks(issues), isFalse);
      expect(issues.single.message, contains('yuvarlandı'));
    });

    test('negatif stok alınır', () {
      final issues = validate(rawInitialStock: '-5', initialStock: -5);

      expect(blocks(issues), isFalse);
    });

    test('BR-PROD-011 — ağırlık var, birim yok', () {
      expect(blocks(validate(netWeightValue: '330')), isFalse);
      expect(validate(netWeightValue: '330'), isNotEmpty);
      expect(validate(netWeightUnit: 'ml'), isNotEmpty);
      expect(
        validate(netWeightValue: '330', netWeightUnit: 'ml'),
        isEmpty,
        reason: 'İkisi birlikte doldurulmuşsa sorun yok.',
      );
    });

    test('KDV oranı tanımsız → varsayılan', () {
      final issues = validate(rawVatRate: '18', vatRateKnown: false);

      expect(blocks(issues), isFalse);
      expect(issues.single.message, contains('18'));
    });

    test('temiz satır HİÇ bulgu üretmez', () {
      expect(validate(), isEmpty);
    });
  });

  group('BR-IMEX-001 — sistemde kayıtlı barkod politikası', () {
    test('`skip` → satır ALINMAZ', () {
      final issues = validate(
        barcodes: ['8690'],
        existingBarcodes: {'8690'},
        policy: DuplicateBarcodePolicy.skip,
      );

      expect(blocks(issues), isTrue);
    });

    test('`updateExisting` → satır ALINIR, uyarı verilir', () {
      final issues = validate(
        barcodes: ['8690'],
        existingBarcodes: {'8690'},
        policy: DuplicateBarcodePolicy.updateExisting,
      );

      expect(blocks(issues), isFalse);
      expect(issues.single.message, contains('güncellenecek'));
    });

    test('`cancel` → satır ALINMAZ', () {
      expect(
        blocks(
          validate(
            barcodes: ['8690'],
            existingBarcodes: {'8690'},
            policy: DuplicateBarcodePolicy.cancel,
          ),
        ),
        isTrue,
      );
    });

    test('DOSYA İÇİ tekrar politikadan BAĞIMSIZDIR', () {
      // BR-IMEX-002 bir politika sorusu değildir; her zaman reddedilir.
      for (final policy in DuplicateBarcodePolicy.values) {
        expect(
          blocks(
            validate(
              barcodes: ['8690'],
              duplicateInFile: {'8690'},
              policy: policy,
            ),
          ),
          isTrue,
          reason: '$policy politikasında bile reddedilmelidir.',
        );
      }
    });
  });

  group('BR-IMEX-002 — dosya içi tekrar tespiti', () {
    test('iki satırda geçen barkod tekrar SAYILIR', () {
      final duplicates = ProductImportRules.findDuplicatesInFile([
        ['8690'],
        ['8691'],
        ['8690'],
      ]);

      expect(duplicates, {'8690'});
    });

    test('AYNI satırda iki kez yazılan barkod tekrar DEĞİLDİR', () {
      // Tek üründe aynı barkodu iki kez saymak yanlış olurdu.
      final duplicates = ProductImportRules.findDuplicatesInFile([
        ['8690', '8690'],
      ]);

      expect(duplicates, isEmpty);
    });

    test('tekrar yoksa boş küme', () {
      expect(
        ProductImportRules.findDuplicatesInFile([
          ['a'],
          ['b'],
        ]),
        isEmpty,
      );
    });
  });

  group('docs/20 §3 — sütun eşleştirme', () {
    test('şablon başlıkları otomatik eşleşir', () {
      final mapping = ProductImportRules.autoMap([
        'Ürün adı',
        'Satış fiyatı (KDV dahil)',
        'Barkod',
      ]);

      expect(mapping[0], ImportField.name);
      expect(mapping[1], ImportField.salePrice);
      expect(mapping[2], ImportField.barcode);
    });

    test('büyük/küçük harf ve fazla boşluk duyarsızdır', () {
      // Tedarikçiden gelen dosyada "ÜRÜN ADI" da yazabilir.
      //
      // ⚠️ `toLowerCase()` BURADA YETMEZ: Dart locale bağımsızdır ve
      // `'ADI'.toLowerCase()` → `adi` verir, `adı` değil. Türkçe katlama
      // (`TurkishText.fold`) olmadan bu başlık HİÇ eşleşmezdi.
      for (final header in ['  ÜRÜN   ADI  ', 'ürün adı', 'Ürün Adı']) {
        expect(
          ProductImportRules.autoMap([header])[0],
          ImportField.name,
          reason: 'Başlık: "$header"',
        );
      }
    });

    test('Türkçe harf katlaması diğer sütunlarda da çalışır', () {
      expect(
        ProductImportRules.autoMap(['SATIŞ FİYATI'])[0],
        ImportField.salePrice,
      );
      expect(ProductImportRules.autoMap(['KDV ORANI'])[0], ImportField.vatRate);
    });

    test('parantezli açıklama eşleşmeyi BOZMAZ', () {
      final mapping = ProductImportRules.autoMap(['Satış fiyatı']);

      expect(mapping[0], ImportField.salePrice);
    });

    test('tanınmayan sütun eşleşmez', () {
      final mapping = ProductImportRules.autoMap(['Tedarikçi Kodu XYZ']);

      expect(mapping, isEmpty);
    });

    test('aynı alan İKİ sütuna eşleşmez', () {
      final mapping = ProductImportRules.autoMap(['Ürün adı', 'ürün adı']);

      expect(mapping[0], ImportField.name);
      expect(mapping[1], isNull);
    });

    test('eşleşmemiş ZORUNLU alanlar bildirilir', () {
      final mapping = ProductImportRules.autoMap(['Ürün adı']);

      expect(ProductImportRules.missingRequired(mapping), [
        ImportField.salePrice,
      ]);
    });

    test('tüm zorunlular eşleştiyse liste boş', () {
      final mapping = ProductImportRules.autoMap([
        'Ürün adı',
        'Satış fiyatı (KDV dahil)',
      ]);

      expect(ProductImportRules.missingRequired(mapping), isEmpty);
    });
  });

  group('docs/20 §3 — çoklu barkod', () {
    test('`|` ile ayrılır', () {
      expect(ProductImportRules.splitBarcodes('8690|8691'), ['8690', '8691']);
    });

    test('boşluk ve boş parçalar temizlenir', () {
      expect(ProductImportRules.splitBarcodes(' 8690 || 8691 |'), [
        '8690',
        '8691',
      ]);
    });

    test('boş girdi boş liste', () {
      expect(ProductImportRules.splitBarcodes(''), isEmpty);
      expect(ProductImportRules.splitBarcodes('  '), isEmpty);
    });
  });
}
