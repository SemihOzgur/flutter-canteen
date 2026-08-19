/// Ürün görsellerinin dosya sistemi yaşam döngüsü —
/// **docs/21 §1, §2, §4 · BR-IMG-001/002/003 · REQ-IMG-001…006/011/013**
///
/// ## Katman
///
/// `rules/01 §1`: dosya sistemi erişimi **data** katmanına aittir; presentation
/// dosya sistemine inmez. Emsal: `data/files/text_file_writer.dart`.
///
/// `rules/01 §4`: **Image doğrudan sınıftır, interface yazılmaz** ("Backup /
/// Image / Csv → ❌ doğrudan sınıf").
///
/// ## Neden iki adım (prepare → commit)
///
/// docs/21 §2 adım 6–7: optimize edilmiş dosya önce `temp/` altına yazılır ve
/// **ürün kaydedilirken** `images/` altına taşınır. Kullanıcı formu kaydetmeden
/// kapatırsa `images/` kirlenmez; `temp/`'te kalan dosya EC-PROD-017 gereği
/// gecikmeli temizlikte silinir (Faz 9).
///
/// ## Neden anında silme yok
///
/// docs/21 §4: **"Görsel dosyaları asla anında silinmez."** Dosya sistemi
/// transaction'a katılmaz; kayıt geri alınırsa silinmiş dosya geri gelmez.
/// Bu yüzden eski dosya [moveToTrash] ile `images/.trash/` altına taşınır.
/// Çöpün süreli temizliği ve orphan taraması **Faz 9**'dur (REQ-IMG-007/008).
///
/// ## Veritabanına yazılan değer
///
/// `rules/03 §8`: DB'de **göreli** yol tutulur (`images/<uuid>.jpg`);
/// **mutlak yol asla** yazılmaz — bilgisayar veya kullanıcı adı değişince
/// kırılır (docs/21 §1).
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../core/paths/app_paths.dart';
import '../../core/result/result.dart';
import '../../core/uuid/uuid_v4.dart';
import 'image_failures.dart';
import 'image_format.dart';
import 'image_optimization_policy.dart';
import 'image_optimizer.dart';

/// `temp/` altına yazılmış, ürün kaydedilmeyi bekleyen optimize görsel.
class PreparedProductImage {
  /// Veri dizinine göreli geçici yol — `temp/<uuid>.jpg`.
  final String temporaryRelativePath;

  /// Kaydedilince alacağı kalıcı göreli yol — `images/<uuid>.jpg`.
  final String targetRelativePath;

  final int byteLength;
  final int width;
  final int height;

  const PreparedProductImage({
    required this.temporaryRelativePath,
    required this.targetRelativePath,
    required this.byteLength,
    required this.width,
    required this.height,
  });
}

class ProductImageStore {
  /// docs/21 §1 — görsellerin kök klasör adı; DB'ye yazılan göreli yolun ilk
  /// parçasıdır.
  static const String imagesSegment = 'images';

  /// docs/21 §4 — geciktirmeli silme klasörü.
  static const String trashSegment = '.trash';

  static const String tempSegment = 'temp';

  final AppPaths _paths;
  final Random _random;
  final ImageOptimizer _optimize;

  ProductImageStore({
    required AppPaths paths,
    Random? random,
    ImageOptimizer? optimizer,
  }) : _paths = paths,
       // rules/06 §7 — rastgelelik enjekte edilebilir; üretimde güvenli kaynak.
       _random = random ?? Random.secure(),
       _optimize = optimizer ?? optimizeImageInIsolate;

  // --- Yol çözümleme -------------------------------------------------------

  /// Göreli yolu mutlak yola çevirir; yol veri dizininin **dışına** çıkıyorsa
  /// `null` döner (`rules/04 §7` — dizin dışına yazma/okuma engellenir).
  ///
  /// Göreli yollar veritabanında daima `/` ile saklanır; Windows'ta ayırıcı
  /// dönüşümü burada yapılır.
  String? absolutePathOf(String? relativePath) {
    if (relativePath == null || relativePath.trim().isEmpty) return null;
    if (p.isAbsolute(relativePath)) return null;

    final segments = p.posix.split(relativePath.replaceAll(r'\', '/'));
    final absolute = p.normalize(p.joinAll([_paths.rootPath, ...segments]));
    return p.isWithin(_paths.rootPath, absolute) ? absolute : null;
  }

  // --- 1..6: doğrula, optimize et, temp/ altına yaz -------------------------

  /// docs/21 §2 adım 1–6.
  ///
  /// ```text
  /// 1. Format doğrula — magic bytes (REQ-IMG-005)
  /// 2. Boyut kontrolü — yapılandırılmış üst sınır (REQ-IMG-004)
  /// 3. Görseli çöz; bozuksa reddet
  /// 4. Uzun kenarı sınıra indir
  /// 5. Yeniden kodla
  /// 6. temp/ altına UUID adıyla yaz (REQ-IMG-002)
  /// ```
  ///
  /// ⚠️ **Orijinal büyük dosya kopyalanmaz** (BR-IMG-002 · REQ-IMG-013):
  /// diske yalnızca optimize edilmiş bayt dizisi yazılır.
  Future<Result<PreparedProductImage>> prepare(
    String sourcePath,
    ImageOptimizationPolicy policy,
  ) async {
    final source = File(sourcePath);
    if (!await source.exists()) return const Err(ImageFailures.sourceMissing);

    // Boyut kontrolü dosyayı **belleğe almadan** yapılır: 500 MB'lık bir
    // dosyayı önce okuyup sonra reddetmek belleği gereksiz yere doldururdu.
    final length = await source.length();
    if (length > policy.maxUploadBytes) {
      return Err(ImageFailures.tooLarge(policy.maxUploadBytes));
    }

    final Uint8List bytes;
    try {
      bytes = await source.readAsBytes();
    } on FileSystemException {
      return const Err(ImageFailures.sourceMissing);
    }

    // REQ-IMG-005 — uzantıya GÜVENİLMEZ.
    final format = ImageFormatDetector.detect(bytes);
    if (format == null || !policy.allows(format.name)) {
      return const Err(ImageFailures.formatUnsupported);
    }

    final optimized = await _optimize(
      ImageOptimizeRequest(
        bytes: bytes,
        sourceFormat: format,
        maxLongEdgePx: policy.maxLongEdgePx,
        jpegQuality: policy.jpegQuality,
      ),
    );
    if (optimized == null) return const Err(ImageFailures.unreadable);

    final fileName = '${UuidV4.generate(_random)}${optimized.format.extension}';
    final temporary = File(p.join(_paths.tempDir, fileName));
    await temporary.parent.create(recursive: true);
    await temporary.writeAsBytes(optimized.bytes, flush: true);

    return Ok(
      PreparedProductImage(
        temporaryRelativePath: p.posix.join(tempSegment, fileName),
        targetRelativePath: p.posix.join(imagesSegment, fileName),
        byteLength: optimized.bytes.length,
        width: optimized.width,
        height: optimized.height,
      ),
    );
  }

  // --- 7: temp/ → images/ --------------------------------------------------

  /// docs/21 §2 adım 7 — hazırlanan dosyayı kalıcı klasöre taşır ve **veri
  /// dizinine göreli** yolu döner.
  ///
  /// Taşıma transaction'dan **önce** yapılır: `rules/01 §5` transaction içinde
  /// dosya I/O'yu yasaklar. Kayıt geri alınırsa dosya `images/` altında
  /// sahipsiz kalır — docs/21 §4'ün tam olarak öngördüğü ve orphan taramasıyla
  /// (Faz 9) çözülen durum. Ters sıra veri **kaybettirirdi**.
  Future<String> commit(PreparedProductImage prepared) async {
    final sourcePath = absolutePathOf(prepared.temporaryRelativePath);
    final targetPath = absolutePathOf(prepared.targetRelativePath);
    if (sourcePath == null || targetPath == null) {
      throw ArgumentError('Geçersiz görsel yolu.');
    }

    await Directory(p.dirname(targetPath)).create(recursive: true);
    await _move(File(sourcePath), targetPath);
    return prepared.targetRelativePath;
  }

  // --- Silme: images/ → images/.trash/ -------------------------------------

  /// BR-IMG-003 · REQ-IMG-006 · docs/21 §4 — dosya **silinmez**, çöpe taşınır.
  ///
  /// Dosya zaten yoksa (kırık referans) sessizce `false` döner: kullanıcıya
  /// hata gösterilmez (BR-IMG-005).
  Future<bool> moveToTrash(String? relativePath) async {
    final absolute = absolutePathOf(relativePath);
    if (absolute == null) return false;

    final file = File(absolute);
    if (!await file.exists()) return false;

    final trashDir = Directory(p.join(_paths.imagesDir, trashSegment));
    await trashDir.create(recursive: true);

    // Aynı ad çöpte zaten varsa üzerine yazılmaz; ikinci dosya da korunur.
    var target = p.join(trashDir.path, p.basename(absolute));
    var suffix = 1;
    while (await File(target).exists()) {
      final base = p.basenameWithoutExtension(absolute);
      final ext = p.extension(absolute);
      target = p.join(trashDir.path, '$base.$suffix$ext');
      suffix++;
    }

    await _move(file, target);
    return true;
  }

  /// Çöp klasörünün mutlak yolu — testler ve Faz 9 temizliği için.
  String get trashDirPath => p.join(_paths.imagesDir, trashSegment);

  /// `rename` aynı birim içinde atomiktir; farklı birimlerde (Windows'ta
  /// `%APPDATA%` ile geçici dizin farklı sürücüde olabilir) başarısız olur ve
  /// kopyala-sil'e düşülür.
  Future<void> _move(File file, String targetPath) async {
    try {
      await file.rename(targetPath);
    } on FileSystemException {
      await file.copy(targetPath);
      await file.delete();
    }
  }
}
