/// Ürün import doğrulaması — **docs/20 §3–§4 · BR-IMEX-001/002**
///
/// Saf Dart (rules/01 §1): veritabanı bilmez, dosya okumaz. Girdi bir satır
/// ve o satırın **bağlamı**dır (barkod sistemde var mı, dosyada tekrarlanıyor
/// mu); çıktı hata/uyarı listesidir.
///
/// ## Hata ile uyarı KESİN olarak ayrılır
///
/// docs/20 §4:
/// - 🔴 **Hata** → satır **alınmaz**
/// - 🟡 **Uyarı** → satır **alınır**, kullanıcı bilgilendirilir
///
/// Bu ayrım keyfî değildir: "alış fiyatı satış fiyatından yüksek" gerçek bir
/// iş durumudur (zararına satış) ve satırı reddetmek kullanıcının verisini
/// kaybettirirdi. "Satış fiyatı okunamadı" ise ürünü fiyatsız oluşturmak
/// demektir ve bu asla kabul edilemez.
library;

import 'turkish_text.dart';

/// Bir satırdaki tek bulgu.
class ImportIssue {
  final String message;

  /// `true` → satır **alınmaz** (🔴). `false` → alınır, uyarı gösterilir (🟡).
  final bool isBlocking;

  const ImportIssue(this.message, {required this.isBlocking});

  const ImportIssue.error(String message) : this(message, isBlocking: true);
  const ImportIssue.warning(String message) : this(message, isBlocking: false);

  @override
  String toString() => '${isBlocking ? "🔴" : "🟡"} $message';
}

/// docs/20 §3 — şablondaki sistem alanları.
enum ImportField {
  name('Ürün adı', required: true),
  salePrice('Satış fiyatı (KDV dahil)', required: true),
  purchasePrice('Alış fiyatı'),
  category('Kategori'),
  barcode('Barkod'),
  brand('Marka'),
  salesUnit('Satış birimi'),
  netWeightValue('Net ağırlık'),
  netWeightUnit('Ağırlık birimi'),
  vatRate('KDV oranı'),
  supplier('Tedarikçi'),
  initialStock('Başlangıç stoğu'),
  minimumStock('Minimum stok'),
  shelfLocation('Raf konumu'),
  description('Açıklama');

  final String label;

  /// docs/20 §4 — eşleşmemiş **zorunlu** sütun import'u başlatmaz.
  final bool required;

  const ImportField(this.label, {this.required = false});
}

/// docs/20 §4.1 · BR-IMEX-001 — sistemde zaten kayıtlı barkod politikası.
enum DuplicateBarcodePolicy {
  /// Varsayılan, en güvenli.
  skip,

  /// Ad, fiyat, kategori vb. güncellenir; **stok import edilmez.**
  updateExisting,

  /// Kullanıcı import'u tamamen iptal eder.
  cancel,
}

abstract final class ProductImportRules {
  /// docs/20 §4 — ürün adı üst sınırı; aşılırsa **kırpılır**.
  static const int maxNameLength = 120;

  /// docs/20 §3 — çoklu barkod ayırıcısı.
  static const String barcodeSeparator = '|';

  /// Başlıkları sistem alanlarına **otomatik** eşleştirir (docs/20 §3).
  ///
  /// Şablonla birebir aynı başlıklar kendiliğinden eşleşir; kullanıcı kalanı
  /// elle seçer. Karşılaştırma büyük/küçük harf ve boşluk duyarsızdır —
  /// tedarikçiden gelen dosyada "ÜRÜN ADI" da yazabilir.
  static Map<int, ImportField> autoMap(List<String> header) {
    final result = <int, ImportField>{};
    final used = <ImportField>{};

    for (var i = 0; i < header.length; i++) {
      final normalized = _normalizeHeader(header[i]);
      for (final field in ImportField.values) {
        if (used.contains(field)) continue;
        if (_normalizeHeader(field.label) == normalized) {
          result[i] = field;
          used.add(field);
          break;
        }
      }
    }
    return result;
  }

  /// Eşleşmemiş **zorunlu** alanlar — boş değilse import başlatılamaz.
  static List<ImportField> missingRequired(Map<int, ImportField> mapping) {
    final mapped = mapping.values.toSet();
    return [
      for (final field in ImportField.values)
        if (field.required && !mapped.contains(field)) field,
    ];
  }

  /// docs/20 §3 — `8690|8691` → iki barkod. Boşlar atılır.
  static List<String> splitBarcodes(String raw) => [
    for (final part in raw.split(barcodeSeparator))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  /// docs/20 §4 — tek satırın doğrulaması.
  ///
  /// [existingBarcodes] sistemde kayıtlı barkodlar, [duplicateInFile] ise
  /// **dosya içinde** birden fazla kez geçen barkodlardır. İkisi farklı
  /// kurallara tabidir (BR-IMEX-001 ↔ BR-IMEX-002).
  static List<ImportIssue> validate({
    required String name,
    required String rawSalePrice,
    required int? salePriceMinor,
    required int? purchasePriceMinor,
    required String rawPurchasePrice,
    required List<String> barcodes,
    required Set<String> existingBarcodes,
    required Set<String> duplicateInFile,
    required String rawInitialStock,
    required int? initialStock,
    required String netWeightValue,
    required String netWeightUnit,
    required bool vatRateKnown,
    required String rawVatRate,
    required DuplicateBarcodePolicy policy,
  }) {
    final issues = <ImportIssue>[];

    if (name.trim().isEmpty) {
      issues.add(const ImportIssue.error('Ürün adı zorunlu'));
    } else if (name.length > maxNameLength) {
      issues.add(const ImportIssue.warning('Ürün adı çok uzun, kırpılacak'));
    }

    // Satış fiyatı okunamayan bir satır ürünü FİYATSIZ oluştururdu.
    if (rawSalePrice.trim().isEmpty) {
      issues.add(const ImportIssue.error('Satış fiyatı zorunlu'));
    } else if (salePriceMinor == null) {
      issues.add(ImportIssue.error('Satış fiyatı okunamadı: "$rawSalePrice"'));
    } else if (salePriceMinor < 0) {
      issues.add(const ImportIssue.error('Satış fiyatı negatif olamaz'));
    }

    // Alış fiyatı **uyarıdır**: `0` kabul edilir (BR-PROD-002).
    if (rawPurchasePrice.trim().isNotEmpty && purchasePriceMinor == null) {
      issues.add(
        const ImportIssue.warning('Alış fiyatı okunamadı, 0 kabul edildi'),
      );
    } else if (purchasePriceMinor != null &&
        salePriceMinor != null &&
        purchasePriceMinor > salePriceMinor) {
      // Zararına satış gerçek bir iş durumudur; satır REDDEDİLMEZ.
      issues.add(
        const ImportIssue.warning('Alış fiyatı satış fiyatından yüksek'),
      );
    }

    // BR-IMEX-002 — dosya içi tekrar: hangisinin doğru olduğuna sistem karar
    // veremez, o barkoda ait TÜM satırlar reddedilir.
    for (final barcode in barcodes) {
      if (duplicateInFile.contains(barcode)) {
        issues.add(
          ImportIssue.error(
            'Barkod dosyada birden fazla kez geçiyor: $barcode',
          ),
        );
      } else if (existingBarcodes.contains(barcode)) {
        // BR-IMEX-001 — politikaya göre.
        issues.add(switch (policy) {
          DuplicateBarcodePolicy.skip => ImportIssue.error(
            'Barkod sistemde zaten kayıtlı: $barcode',
          ),
          DuplicateBarcodePolicy.updateExisting => ImportIssue.warning(
            'Mevcut ürün güncellenecek: $barcode',
          ),
          DuplicateBarcodePolicy.cancel => ImportIssue.error(
            'Barkod sistemde zaten kayıtlı: $barcode',
          ),
        });
      }
    }

    if (rawInitialStock.trim().isNotEmpty) {
      if (initialStock == null) {
        issues.add(
          const ImportIssue.warning('Stok sayı değil, 0 kabul edildi'),
        );
      } else if (rawInitialStock.contains(RegExp(r'[.,]'))) {
        // BR-SALE-011 — miktar tam sayıdır.
        issues.add(
          const ImportIssue.warning('Stok ondalıklı, tam sayıya yuvarlandı'),
        );
      }
      if (initialStock != null && initialStock < 0) {
        issues.add(const ImportIssue.warning('Stok negatif'));
      }
    }

    // BR-PROD-011 — ağırlık ve birim BİRLİKTE doldurulur.
    final hasWeight = netWeightValue.trim().isNotEmpty;
    final hasUnit = netWeightUnit.trim().isNotEmpty;
    if (hasWeight != hasUnit) {
      issues.add(
        const ImportIssue.warning(
          'Net ağırlık ve birim birlikte doldurulmalı; ikisi de boşaltıldı',
        ),
      );
    }

    if (rawVatRate.trim().isNotEmpty && !vatRateKnown) {
      issues.add(
        ImportIssue.warning(
          'KDV oranı sistemde tanımsız: $rawVatRate — varsayılan kullanılacak',
        ),
      );
    }

    return issues;
  }

  /// Bir barkodun dosya içinde kaç kez geçtiğini sayar ve **birden fazla**
  /// geçenleri döner (BR-IMEX-002).
  static Set<String> findDuplicatesInFile(List<List<String>> barcodesPerRow) {
    final seen = <String, int>{};
    for (final row in barcodesPerRow) {
      // Aynı satırda aynı barkodun iki kez yazılması bir tekrar DEĞİLDİR;
      // tek üründe aynı barkodu iki kez saymak yanlış olurdu.
      for (final barcode in row.toSet()) {
        seen[barcode] = (seen[barcode] ?? 0) + 1;
      }
    }
    return {
      for (final entry in seen.entries)
        if (entry.value > 1) entry.key,
    };
  }

  /// Başlık karşılaştırması için normalize eder.
  ///
  /// **`toLowerCase()` YETMEZ.** Dart'ın katlaması locale bağımsızdır:
  /// `'ADI'.toLowerCase()` → `adi`, `adı` değil. Tedarikçiden gelen dosyada
  /// başlık büyük harfle yazılmış olabilir ve "Ürün adı" ile eşleşmezdi.
  /// `TurkishText.fold` altı Türkçe harf çiftini katlar (REQ-PROD-010 için
  /// yazılmıştı; aynı sorun burada da geçerlidir).
  static String _normalizeHeader(String value) => TurkishText.fold(
    value
        .trim()
        // Parantezli açıklama eşleşmeyi bozmamalı: "Satış fiyatı (KDV dahil)"
        // ile "satış fiyatı" aynı sütundur.
        .replaceAll(RegExp(r'\s*\([^)]*\)'), '')
        .replaceAll(RegExp(r'\s+'), ' '),
  );
}
