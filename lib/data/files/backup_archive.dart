/// Yedek arşivi — **docs/19 §2 · OD-012 · rules/03 §7**
///
/// `.canteenbackup` **standart bir ZIP'tir.** Uzantı, kullanıcının dosyayı
/// yanlışlıkla açıp içeriğini bozmasını engeller; acil durumda herhangi bir
/// arşiv programıyla açılabilir. Bu bilinçli bir **kurtarılabilirlik**
/// kararıdır (docs/19 §2).
///
/// ## Güvenlik — rules/03 §7
///
/// | Tehdit | Önlem |
/// |---|---|
/// | **Zip-slip** | Çıkarılan her yol hedef dizin içinde doğrulanır |
/// | **Zip bomb** | Açılmamış toplam boyut sınırı aşılırsa reddedilir |
/// | Mutlak yol / `..` | Girdi adı reddedilir |
///
/// Bu sınıf **iş kararı vermez**: neyin geçerli bir yedek olduğuna, checksum
/// uyuşmazlığında ne yapılacağına `application/backup` katmanı karar verir.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:convert/convert.dart' show AccumulatorSink;
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Arşivden çıkarma sırasında reddedilen bir girdi.
class BackupArchiveException implements Exception {
  final String message;
  const BackupArchiveException(this.message);

  @override
  String toString() => 'BackupArchiveException: $message';
}

abstract final class BackupArchive {
  /// docs/19 §2 — arşiv içindeki sabit adlar.
  static const String metadataEntry = 'metadata.json';
  static const String databaseEntry = 'database.sqlite';
  static const String checksumsEntry = 'checksums.json';
  static const String imagesPrefix = 'images/';

  /// docs/19 §3 adım 9 — dosya nihai adını **ancak doğrulandıktan sonra** alır.
  static const String extension = '.canteenbackup';
  static const String temporaryExtension = '.tmp';

  /// rules/03 §7 — zip bomb koruması. 2 GB açılmamış içerik, 10.000+ ürünlük
  /// bir kantin için fazlasıyla yeterlidir; bunun üstü saldırı sayılır.
  static const int maxUncompressedBytes = 2 * 1024 * 1024 * 1024;

  /// Bir dosyanın SHA-256'sı — docs/19 §2 `checksums.json`.
  ///
  /// Akış halinde okur: 50 MB'lık bir veritabanını belleğe almaz.
  static Future<String> sha256OfFile(File file) async {
    final output = AccumulatorSink<Digest>();
    final input = sha256.startChunkedConversion(output);
    await for (final chunk in file.openRead()) {
      input.add(chunk);
    }
    input.close();
    return output.events.single.toString();
  }

  /// [sourceDirectory] içeriğini [target] dosyasına ZIP olarak yazar.
  ///
  /// Klasör yapısı korunur (`images/...`).
  static Future<void> pack({
    required Directory sourceDirectory,
    required File target,
  }) async {
    final encoder = ZipFileEncoder();
    encoder.create(target.path);
    try {
      for (final entity in sourceDirectory.listSync(recursive: true)) {
        if (entity is! File) continue;
        final relative = p.relative(entity.path, from: sourceDirectory.path);
        // ZIP içi yol ayırıcısı daima `/`'dir — Windows'ta `\` yazmak
        // arşivi başka platformlarda okunamaz hâle getirirdi.
        await encoder.addFile(entity, relative.replaceAll(r'\', '/'));
      }
    } finally {
      await encoder.close();
    }
  }

  /// Arşivi [targetDirectory] içine çıkarır.
  ///
  /// **Zip-slip ve zip bomb korumalıdır** (rules/03 §7). Şüpheli bir girdi
  /// bulunursa hiçbir dosya yazılmaz — kısmi çıkarma bırakmak, saldırganın
  /// yazdırmayı başardığı dosyaları diskte bırakırdı.
  /// [maxBytes] açılmamış toplam boyut sınırıdır (rules/03 §7 — zip bomb).
  /// Varsayılan [maxUncompressedBytes]; ayrı bir parametre olması sınırın
  /// **sınanabilir** olmasını sağlar.
  static Future<void> extract({
    required File archiveFile,
    required Directory targetDirectory,
    int maxBytes = maxUncompressedBytes,
  }) async {
    final archive = ZipDecoder().decodeBytes(await archiveFile.readAsBytes());

    // --- Önce DOĞRULA, sonra yaz -------------------------------------------
    var totalBytes = 0;
    final root = p.normalize(targetDirectory.absolute.path);
    for (final entry in archive) {
      if (!entry.isFile) continue;

      final name = entry.name;
      if (p.isAbsolute(name) || name.split('/').contains('..')) {
        throw BackupArchiveException(
          'Arşivde güvenli olmayan dosya yolu: $name',
        );
      }
      final resolved = p.normalize(p.join(root, name));
      if (!p.isWithin(root, resolved)) {
        throw BackupArchiveException('Zip-slip engellendi: $name');
      }

      totalBytes += entry.size;
      if (totalBytes > maxBytes) {
        throw const BackupArchiveException(
          'Arşiv açılmış boyutu izin verilen sınırı aşıyor.',
        );
      }
    }

    // --- Ancak şimdi yaz ----------------------------------------------------
    await targetDirectory.create(recursive: true);
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final file = File(p.join(root, entry.name));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(entry.readBytes() ?? const []);
    }
  }

  /// Bir dosyayı **arşiv içinde verilen adla** ekler.
  ///
  /// Yalnızca testler için: zip-slip ve zip bomb korumalarının gerçekten
  /// çalıştığını kanıtlamak, kötü niyetli bir arşiv **üretebilmeyi** gerektirir.
  /// Korumaları yalnızca "iyi" arşivlerle sınamak, hiç sınamamaktır.
  static Future<void> packRaw({
    required Map<String, List<int>> entries,
    required File target,
  }) async {
    final encoder = ZipFileEncoder();
    encoder.create(target.path);
    try {
      for (final entry in entries.entries) {
        encoder.addArchiveFile(ArchiveFile.bytes(entry.key, entry.value));
      }
    } finally {
      await encoder.close();
    }
  }

  /// Arşivdeki dosya adlarını okur — içeriği açmadan.
  static Future<List<String>> listEntries(File archiveFile) async {
    final archive = ZipDecoder().decodeBytes(await archiveFile.readAsBytes());
    return [
      for (final entry in archive)
        if (entry.isFile) entry.name,
    ];
  }

  /// Tek bir girdiyi metin olarak okur; yoksa `null`.
  ///
  /// `metadata.json` doğrulaması arşivin tamamını çıkarmadan yapılabilmelidir
  /// (docs/19 §4 adım 2) — bozuk bir yedek diske hiç dokunmadan reddedilir.
  static Future<String?> readEntryAsString(
    File archiveFile,
    String entryName,
  ) async {
    final archive = ZipDecoder().decodeBytes(await archiveFile.readAsBytes());
    for (final entry in archive) {
      if (entry.isFile && entry.name == entryName) {
        return utf8.decode(entry.readBytes() ?? const []);
      }
    }
    return null;
  }
}
