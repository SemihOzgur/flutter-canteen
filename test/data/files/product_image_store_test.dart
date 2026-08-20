/// Ürün görseli saklama testleri — **docs/21 · BR-IMG-001…005 ·
/// REQ-IMG-001…006, 011 · OD-016**
///
/// | Test | Kural |
/// |---|---|
/// | Format **içerikten** doğrulanır, uzantıdan değil | REQ-IMG-005 · rules/03 §8 |
/// | Sınırı aşan dosya reddedilir | REQ-IMG-004 |
/// | Uzun kenar sınıra indirilir | REQ-IMG-003 · BR-IMG-002 |
/// | **Orijinal büyük dosya saklanmaz** | BR-IMG-002 |
/// | DB'ye **göreli** yol yazılır | BR-IMG-001 · rules/03 §8 |
/// | Silinen görsel `.trash/`'a taşınır | BR-IMG-003 · REQ-IMG-006 |
/// | Sınırlar `app_settings`'ten okunur | OD-016 — business rule DEĞİL |
/// ## Kapsanan uç durumlar (docs/26 · Faz 11 izlenebilirliği)
///
/// - **EC-PROD-017** — görsel eklendi, ürün kaydedilmedi → dosya `temp/`'te kalır
/// - **EC-BKUP-015** — yedek başka bilgisayarda restore — DB göreli yol tutar
///
library;

import 'dart:io';
import 'dart:math';

import 'package:canteen/core/paths/app_paths.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/files/image_optimization_policy.dart';
import 'package:canteen/data/files/product_image_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late AppPaths paths;
  late ProductImageStore store;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('canteen_images_test');
    paths = AppPaths(rootPath: root.path);
    await paths.ensureDirectories();
    // Rastgelelik enjekte edilir — UUID adları testte deterministiktir.
    store = ProductImageStore(paths: paths, random: Random(42));
  });

  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  /// Gerçek bir görsel üretir — testler sahte bayt dizisiyle çalışmaz;
  /// çözme ve yeniden boyutlandırma gerçekten koşar.
  String writeImage({
    required String name,
    int width = 2400,
    int height = 1200,
    bool png = false,
  }) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(120, 180, 240));
    final bytes = png ? img.encodePng(image) : img.encodeJpg(image);
    final file = File(p.join(root.path, name))..writeAsBytesSync(bytes);
    return file.path;
  }

  group('REQ-IMG-005 — format İÇERİKTEN doğrulanır', () {
    test('uzantısı .jpg olan sahte dosya REDDEDİLİR', () async {
      final fake = File(p.join(root.path, 'sahte.jpg'))
        ..writeAsStringSync('bu bir görsel değil');

      final result = await store.prepare(
        fake.path,
        ImageOptimizationPolicy.defaults,
      );

      expect(
        result.isErr,
        isTrue,
        reason:
            'rules/03 §8: format doğrulaması dosya içeriğinden yapılır, '
            'uzantıdan değil.',
      );
    });

    test('gerçek JPEG kabul edilir', () async {
      final source = writeImage(name: 'gercek.jpg');

      final result = await store.prepare(
        source,
        ImageOptimizationPolicy.defaults,
      );

      expect(result.isOk, isTrue);
    });
  });

  group('REQ-IMG-004 — boyut sınırı', () {
    test('yapılandırılmış üst sınırı aşan dosya reddedilir', () async {
      final source = writeImage(name: 'buyuk.jpg');
      const tinyLimit = ImageOptimizationPolicy(
        maxLongEdgePx: 1000,
        jpegQuality: 85,
        maxUploadBytes: 64,
        allowedFormats: ['jpg', 'jpeg', 'png', 'webp'],
      );

      final result = await store.prepare(source, tinyLimit);

      expect(result.isErr, isTrue);
    });
  });

  group('BR-IMG-002 — optimizasyon', () {
    test('uzun kenar yapılandırılmış sınıra indirilir', () async {
      final source = writeImage(name: 'genis.jpg', width: 2400, height: 1200);

      final prepared =
          (await store.prepare(source, ImageOptimizationPolicy.defaults)
                  as Ok<PreparedProductImage>)
              .value;

      expect(max(prepared.width, prepared.height), lessThanOrEqualTo(1000));
    });

    test('ORİJİNAL büyük dosya saklanmaz — yalnızca optimize kopya', () async {
      final source = writeImage(name: 'orijinal.jpg');
      final originalBytes = File(source).lengthSync();

      final prepared =
          (await store.prepare(source, ImageOptimizationPolicy.defaults)
                  as Ok<PreparedProductImage>)
              .value;

      expect(
        prepared.byteLength,
        lessThan(originalBytes),
        reason: 'BR-IMG-002: yalnızca optimize edilmiş kopya kalır.',
      );

      // Veri dizininde orijinal boyutta hiçbir dosya bulunmamalıdır.
      final written = Directory(
        paths.tempDir,
      ).listSync().whereType<File>().map((f) => f.lengthSync());
      expect(written, everyElement(lessThan(originalBytes)));
    });

    test('OD-016: sınırlar app_settings profilinden okunur', () async {
      final source = writeImage(name: 'profil.jpg', width: 2400, height: 1200);

      // Bu değerler **business rule değil**, yapılandırılabilir teknik
      // politikadır: profil değişince davranış da değişmelidir.
      final policy = ImageOptimizationPolicy.decode(
        '{"max_long_edge_px": 200, "jpeg_quality": 60}',
      );
      final prepared =
          (await store.prepare(source, policy) as Ok<PreparedProductImage>)
              .value;

      expect(
        max(prepared.width, prepared.height),
        lessThanOrEqualTo(200),
        reason: 'Sınır koda gömülü olsaydı bu test 1000 px üretirdi.',
      );
    });

    test('bozuk profil uygulamayı çökertmez, varsayılana düşer', () {
      expect(
        ImageOptimizationPolicy.decode('{bozuk json').maxLongEdgePx,
        ImageOptimizationPolicy.defaults.maxLongEdgePx,
      );
      expect(
        ImageOptimizationPolicy.decode(null).maxLongEdgePx,
        ImageOptimizationPolicy.defaults.maxLongEdgePx,
      );
    });
  });

  group('BR-IMG-001 — göreli yol', () {
    test('hazırlanan yol GÖRELİDİR; mutlak yol taşımaz', () async {
      final source = writeImage(name: 'yol.jpg');

      final prepared =
          (await store.prepare(source, ImageOptimizationPolicy.defaults)
                  as Ok<PreparedProductImage>)
              .value;

      expect(p.isAbsolute(prepared.targetRelativePath), isFalse);
      expect(
        prepared.targetRelativePath,
        startsWith('${ProductImageStore.imagesSegment}/'),
        reason:
            'rules/03 §8: DB\'de göreli yol tutulur; mutlak yol bilgisayar '
            'değişince kırılır.',
      );
      expect(prepared.targetRelativePath, isNot(contains(root.path)));
    });

    test('commit dosyayı temp/ → images/ taşır', () async {
      final source = writeImage(name: 'commit.jpg');
      final prepared =
          (await store.prepare(source, ImageOptimizationPolicy.defaults)
                  as Ok<PreparedProductImage>)
              .value;

      final relative = await store.commit(prepared);

      expect(relative, prepared.targetRelativePath);
      expect(File(store.absolutePathOf(relative)!).existsSync(), isTrue);
      expect(
        File(
          store.absolutePathOf(prepared.temporaryRelativePath)!,
        ).existsSync(),
        isFalse,
        reason: 'Geçici kopya kalmamalıdır.',
      );
    });

    test('veri dizininin DIŞINA çıkan yol çözülmez', () {
      expect(store.absolutePathOf('../../etc/passwd'), isNull);
      expect(store.absolutePathOf('/etc/passwd'), isNull);
    });
  });

  group('BR-IMG-003 · REQ-IMG-006 — silme .trash/\'a taşır', () {
    test('dosya silinmez, çöpe taşınır', () async {
      final source = writeImage(name: 'cop.jpg');
      final prepared =
          (await store.prepare(source, ImageOptimizationPolicy.defaults)
                  as Ok<PreparedProductImage>)
              .value;
      final relative = await store.commit(prepared);
      final absolute = store.absolutePathOf(relative)!;

      final moved = await store.moveToTrash(relative);

      expect(moved, isTrue);
      expect(
        File(absolute).existsSync(),
        isFalse,
        reason: 'Görsel artık images/ altında değildir.',
      );

      final trash = Directory(store.trashDirPath);
      expect(
        trash.existsSync() && trash.listSync().isNotEmpty,
        isTrue,
        reason:
            'BR-IMG-003: dosya anında SİLİNMEZ; gecikmeli temizlik Faz 9\'dur.',
      );
    });

    test('görseli olmayan ürün için sessizce false döner', () async {
      expect(await store.moveToTrash(null), isFalse);
      expect(await store.moveToTrash(''), isFalse);
    });
  });
}
