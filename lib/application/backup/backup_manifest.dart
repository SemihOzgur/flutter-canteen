/// Yedek manifesti — **docs/19 §2**
///
/// `metadata.json` ve `checksums.json`'ın saf Dart karşılığı. Dosya sistemi
/// veya veritabanı bilmez; yalnızca **ne olduğunu** ve **nasıl doğrulanacağını**
/// tarif eder.
library;

import 'dart:convert';

/// docs/19 §2 — `metadata.counts`.
///
/// İki işe yarar: restore öncesi kullanıcıya **ne geleceğini** göstermek ve
/// restore sonrası **doğrulamak** (docs/19 §4 adım 17).
class BackupCounts {
  final int products;
  final int categories;
  final int suppliers;
  final int sales;
  final int saleItems;
  final int stockMovements;
  final int auditLogs;
  final int images;

  const BackupCounts({
    required this.products,
    required this.categories,
    required this.suppliers,
    required this.sales,
    required this.saleItems,
    required this.stockMovements,
    required this.auditLogs,
    required this.images,
  });

  static const BackupCounts empty = BackupCounts(
    products: 0,
    categories: 0,
    suppliers: 0,
    sales: 0,
    saleItems: 0,
    stockMovements: 0,
    auditLogs: 0,
    images: 0,
  );

  Map<String, Object?> toJson() => {
    'products': products,
    'categories': categories,
    'suppliers': suppliers,
    'sales': sales,
    'saleItems': saleItems,
    'stockMovements': stockMovements,
    'auditLogs': auditLogs,
    'images': images,
  };

  static BackupCounts fromJson(Map<String, Object?> json) => BackupCounts(
    products: _int(json['products']),
    categories: _int(json['categories']),
    suppliers: _int(json['suppliers']),
    sales: _int(json['sales']),
    saleItems: _int(json['saleItems']),
    stockMovements: _int(json['stockMovements']),
    auditLogs: _int(json['auditLogs']),
    images: _int(json['images']),
  );

  static int _int(Object? value) => value is int ? value : 0;

  @override
  String toString() => 'BackupCounts(${toJson()})';
}

/// docs/19 §2 — `metadata.json`.
///
/// ⚠️ **Parola bilgisi içermez** (BR-SEC-001 · REQ-BKUP-019). Manifest
/// kullanıcı **adını** taşır (`createdBy`) çünkü "bu yedeği kim aldı"
/// denetim sorusudur; parola, hash ve salt hiçbir alanında bulunmaz.
class BackupMetadata {
  /// Bu **dosya formatının** versiyonu — şema versiyonundan bağımsızdır.
  ///
  /// REQ-BKUP-013: daha yeni bir format reddedilir; okuyamadığımız bir yedeği
  /// "kısmen" geri yüklemek sessiz veri kaybı olurdu.
  final int backupFormatVersion;

  /// Veritabanı şema versiyonu (docs/06).
  final int schemaVersion;

  final String appVersion;
  final DateTime createdAtUtc;

  /// Yedeği alan kullanıcının **görünen adı** — parola değil.
  final String? createdBy;

  final String platform;
  final BackupCounts counts;
  final int databaseBytes;
  final int imagesBytes;

  const BackupMetadata({
    required this.backupFormatVersion,
    required this.schemaVersion,
    required this.appVersion,
    required this.createdAtUtc,
    required this.createdBy,
    required this.platform,
    required this.counts,
    required this.databaseBytes,
    required this.imagesBytes,
  });

  /// Bu uygulamanın ürettiği format versiyonu.
  static const int currentFormatVersion = 1;

  Map<String, Object?> toJson() => {
    'backupFormatVersion': backupFormatVersion,
    'schemaVersion': schemaVersion,
    'appVersion': appVersion,
    'createdAt': createdAtUtc.toIso8601String(),
    'createdBy': createdBy,
    'platform': platform,
    'counts': counts.toJson(),
    'databaseBytes': databaseBytes,
    'imagesBytes': imagesBytes,
  };

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// docs/19 §4 adım 2 — parse edilemiyorsa veya **zorunlu alanlar** eksikse
  /// `null` döner.
  ///
  /// `metadata.json` kendi checksum'ını içermez (docs/19 §2); bütünlüğü tam
  /// olarak bu doğrulamayla kurulur.
  static BackupMetadata? tryDecode(String source) {
    try {
      final json = jsonDecode(source);
      if (json is! Map<String, Object?>) return null;

      final formatVersion = json['backupFormatVersion'];
      final schemaVersion = json['schemaVersion'];
      final createdAt = json['createdAt'];
      if (formatVersion is! int || schemaVersion is! int) return null;
      if (createdAt is! String) return null;
      final parsedDate = DateTime.tryParse(createdAt);
      if (parsedDate == null) return null;

      final counts = json['counts'];
      return BackupMetadata(
        backupFormatVersion: formatVersion,
        schemaVersion: schemaVersion,
        appVersion: json['appVersion'] as String? ?? 'bilinmiyor',
        createdAtUtc: parsedDate.toUtc(),
        createdBy: json['createdBy'] as String?,
        platform: json['platform'] as String? ?? 'bilinmiyor',
        counts: counts is Map<String, Object?>
            ? BackupCounts.fromJson(counts)
            : BackupCounts.empty,
        databaseBytes: json['databaseBytes'] as int? ?? 0,
        imagesBytes: json['imagesBytes'] as int? ?? 0,
      );
    } on Object {
      // Bozuk JSON beklenen bir sonuçtur: kullanıcı yanlış dosya seçmiş
      // olabilir. Exception fırlatmak yerine "geçersiz yedek" denir.
      return null;
    }
  }
}

/// docs/19 §2 — `checksums.json`: dosya adı → SHA-256.
abstract final class BackupChecksums {
  static String encode(Map<String, String> checksums) {
    final sorted = Map.fromEntries(
      checksums.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
    return const JsonEncoder.withIndent('  ').convert(sorted);
  }

  static Map<String, String>? tryDecode(String source) {
    try {
      final json = jsonDecode(source);
      if (json is! Map<String, Object?>) return null;
      return {
        for (final entry in json.entries)
          if (entry.value is String) entry.key: entry.value! as String,
      };
    } on Object {
      return null;
    }
  }
}
