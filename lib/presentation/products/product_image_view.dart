/// Ürün görseli gösterimi — **docs/21 §3 · BR-IMG-005 · REQ-IMG-009**
///
/// | Yer | Boyut |
/// |---|---|
/// | Ürün listesi satırı | 40×40 |
/// | Ürün formu | 200×200 |
/// | Satış ekranı ürün kartı | kart genişliği × 72 |
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

  /// Kare gösterim kenarı. [width]/[height] verilirse yok sayılır.
  final double size;

  /// Kare olmayan gösterim için genişlik — satış ekranı kartı gibi.
  final double? width;

  /// Kare olmayan gösterim için yükseklik.
  final double? height;

  /// Köşe yuvarlaması — kartın üstüne oturan görselde alt köşeler düz kalır.
  final BorderRadius? borderRadius;

  const ProductImageView({
    required this.relativePath,
    required this.size,
    this.width,
    this.height,
    this.borderRadius,
    super.key,
  });

  double get _width => width ?? size;
  double get _height => height ?? size;
  BorderRadius get _radius => borderRadius ?? BorderRadius.circular(6);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = ref.watch(productImageSourceProvider)(relativePath);
    if (provider == null) return _fallback(context);

    return ClipRRect(
      borderRadius: _radius,
      child: Image(
        key: imageKey,
        image: provider,
        width: _width,
        height: _height,
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
    width: _width,
    height: _height,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: _radius,
    ),
    child: Icon(Icons.inventory_2_outlined, size: _iconSize),
  );

  /// Varsayılan ikonun kenarı.
  ///
  /// Kısa kenara göre ölçeklenir; ancak kutu bir `Expanded` içindeyse kenar
  /// `double.infinity` olur ve sonsuz font boyutu Flutter'ı assert'e
  /// düşürürdü. O durumda [size] bir taban değer olarak kullanılır.
  double get _iconSize {
    final shorter = _width < _height ? _width : _height;
    return (shorter.isFinite ? shorter : size) * 0.55;
  }
}
