/// Ürün görseli gösterimi — **docs/21 §3 · BR-IMG-005 · REQ-IMG-009**
///
/// | Yer | Boyut |
/// |---|---|
/// | Ürün listesi satırı | 40×40 |
/// | Ürün formu | 200×200 |
///
/// ## Kırık görsel HATA DEĞİLDİR
///
/// > BR-IMG-005 / REQ-IMG-009 (🔴 Must): "Görseli bulunamayan ürün **hata
/// > göstermez**; varsayılan ikonla gösterilir."
///
/// Dosya elle silinmiş, yedekten eksik gelmiş veya yol bozulmuş olabilir.
/// Bunların hiçbiri kullanıcının çözebileceği bir şey değildir ve ürün
/// listesini kırmızı ünlemlerle doldurmak yalnızca gürültü üretir. Bu yüzden
/// hem `null` yol hem de okuma hatası **aynı** sonuca çıkar: varsayılan ikon.
///
/// Dosyanın varlığı **önceden kontrol edilmez**: her liste satırında senkron
/// `existsSync` çağırmak UI thread'i dosya sistemine indirirdi (`rules/01 §8`).
/// Hata yolu `errorBuilder` ile karşılanır.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/files/providers.dart';

class ProductImageView extends ConsumerWidget {
  static const Key fallbackKey = Key('product_image_fallback');
  static const Key imageKey = Key('product_image');

  /// Veri dizinine **göreli** yol (`images/<uuid>.jpg`) — docs/21 §1.
  final String? relativePath;

  final double size;

  const ProductImageView({
    required this.relativePath,
    required this.size,
    super.key,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.watch(productImageSourceProvider)(relativePath);
    if (provider == null) return _fallback(context);

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image(
        key: imageKey,
        image: provider,
        width: size,
        height: size,
        fit: BoxFit.cover,
        // docs/21 §3 — liste kaydırılırken görseller tembel yüklenir; çözünen
        // kare belirene kadar varsayılan ikon durur, boş kutu görünmez.
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) =>
            wasSynchronouslyLoaded || frame != null
            ? child
            : _fallback(context),
        // REQ-IMG-009 — kırık dosya sessizce varsayılan ikona düşer.
        errorBuilder: (context, error, stackTrace) => _fallback(context),
      ),
    );
  }

  Widget _fallback(BuildContext context) => Container(
    key: fallbackKey,
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(6),
    ),
    child: Icon(Icons.inventory_2_outlined, size: size * 0.55),
  );
}
