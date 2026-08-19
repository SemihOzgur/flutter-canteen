/// Dosya sistemi bağımlılıklarının provider'ları (OD-002 — Riverpod).
///
/// Desen `data/db/providers.dart` ile aynıdır: presentation katmanı yalnızca
/// provider'ı tüketir, `dart:io` görmez (`rules/01 §1`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/paths/app_paths.dart';
import 'product_image_source.dart';
import 'product_image_store.dart';

/// Veri dizini (BR-DATA-001).
///
/// `main.dart` bootstrap sırasında çözülmüş örneği `overrideWithValue` ile
/// verir; testler geçici dizinle override eder. Varsayılan çözümleme burada
/// **disk oluşturmaz** — yalnızca yolu hesaplar.
final appPathsProvider = Provider<AppPaths>((ref) => AppPaths.resolve());

/// Ürün görsellerinin dosya yaşam döngüsü (docs/21).
final productImageStoreProvider = Provider<ProductImageStore>(
  (ref) => ProductImageStore(paths: ref.watch(appPathsProvider)),
);

/// Görselin ekranda gösterilmesi için kaynak çözücü (docs/21 §3).
final productImageSourceProvider = Provider<ProductImageSource>(
  (ref) => productImageSourceOf(ref.watch(productImageStoreProvider)),
);
