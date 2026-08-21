/// Ürün seçme paneli — **docs/12 §1 · REQ-CART-009 · REQ-BARC-012**
///
/// Barkodsuz ürünler satış ekranına **buradan** girer: arama, kategori
/// filtresi veya favoriler üzerinden **tıklanarak** (BR-BARC-008 ·
/// rules/02 §10). Bu panel olmadan barkodsuz ürün satılamazdı.
///
/// Izgara sütun sayısı genişliğe göre değişir (docs/23 §4): 1920'de 5,
/// 1600'de 4, 1366'da 3. Sepet paneli **daralır ama korunur** — bu panel
/// esner, o değil.
library;

import 'package:flutter/material.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../core/money/money_formatter.dart';
import '../products/product_image_view.dart';
import '../../domain/models/category.dart';
import '../../domain/models/product.dart';
import 'sale_dialogs.dart';

class ProductPicker extends StatelessWidget {
  static const Key favoritesRowKey = Key('sale_favorites');
  static const Key gridKey = Key('sale_product_grid');
  static const Key allCategoriesKey = Key('sale_category_all');

  final List<Product> favorites;
  final List<Category> categories;
  final List<Product> products;
  final int? selectedCategoryId;

  /// Arama kutusunda metin varsa liste **arama sonucudur**; boş sonuç mesajı
  /// da ona göre değişir (docs/23 §6).
  final bool searching;

  final ValueChanged<int?> onSelectCategory;
  final ValueChanged<Product> onPickProduct;
  final VoidCallback onOpenProducts;

  const ProductPicker({
    required this.favorites,
    required this.categories,
    required this.products,
    required this.selectedCategoryId,
    required this.searching,
    required this.onSelectCategory,
    required this.onPickProduct,
    required this.onOpenProducts,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (favorites.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Text(
              '⭐ ${AppStringsTr.saleFavorites}',
              style: theme.textTheme.titleSmall,
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView.separated(
              key: favoritesRowKey,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: favorites.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, index) {
                final product = favorites[index];
                return OutlinedButton(
                  key: Key('sale_favorite_${product.id}'),
                  onPressed: () => onPickProduct(product),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(product.name, maxLines: 1),
                      // docs/23 §2 — Alt+1…9 favori ekler; numarayı görmeden
                      // kısayol kullanılamaz.
                      if (index < 9)
                        Text(
                          'Alt+${index + 1}',
                          style: theme.textTheme.labelSmall,
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              ChoiceChip(
                key: allCategoriesKey,
                label: const Text(AppStringsTr.saleAllCategories),
                selected: selectedCategoryId == null,
                onSelected: (_) => onSelectCategory(null),
              ),
              for (final category in categories)
                ChoiceChip(
                  key: Key('sale_category_${category.id}'),
                  label: Text(category.name),
                  selected: selectedCategoryId == category.id,
                  onSelected: (_) => onSelectCategory(category.id),
                ),
            ],
          ),
        ),
        Expanded(child: _grid(context, theme)),
      ],
    );
  }

  Widget _grid(BuildContext context, ThemeData theme) {
    if (products.isEmpty) return _empty(theme);

    return LayoutBuilder(
      builder: (context, constraints) {
        // docs/23 §4 — 1366'da 3, 1600'de 4, 1920'de 5 sütun.
        final columns = constraints.maxWidth ~/ 190;
        return GridView.builder(
          key: gridKey,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns < 2 ? 2 : columns,
            // Kart artık görsel taşıyor; sütun sayısı docs/23 §4'teki gibi
            // kalır, yalnızca yükseklik artar.
            childAspectRatio: 1.15,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            return Card(
              margin: EdgeInsets.zero,
              child: InkWell(
                // REQ-CART-009 — barkodsuz ürün TIKLANARAK sepete eklenir.
                key: Key('sale_product_${product.id}'),
                onTap: () => onPickProduct(product),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // docs/21 §3 — görsel yoksa veya okunamıyorsa varsayılan
                    // ikon gelir; hata GÖSTERİLMEZ (REQ-IMG-009). Kart
                    // yüksekliği görselli ve görselsiz üründe aynıdır, yoksa
                    // ızgara satır satır kayardı.
                    Expanded(
                      child: ProductImageView(
                        relativePath: product.imagePath,
                        size: 72,
                        width: double.infinity,
                        height: double.infinity,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(12),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            // Kart kasadan bir kol boyu uzakta okunuyor;
                            // gövde metni bu mesafede seçilemiyordu.
                            product.name,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                            // Görsel tanımayı zaten sağlıyor; ad tek satırda
                            // kalır ve kart yüksekliği ürüne göre değişmez.
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          // Rozet + fiyat dar kartta taşabilir; ikisi de esnektir
                          // ve fiyat asla kırpılmaz — kasada okunması gereken
                          // değer odur.
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              // docs/13 §4 — negatif stok GİZLENMEZ.
                              Flexible(
                                child:
                                    stockBadge(context, product) ??
                                    const SizedBox(),
                              ),
                              Flexible(
                                child: Text(
                                  MoneyFormatter.format(product.salePrice),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// docs/23 §6 — her liste ekranının **eyleme yönlendiren** boş durumu vardır.
  Widget _empty(ThemeData theme) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            searching
                ? AppStringsTr.saleSearchEmpty
                : AppStringsTr.saleProductsEmptyTitle,
            style: theme.textTheme.titleSmall,
            textAlign: TextAlign.center,
          ),
          if (!searching) ...[
            const SizedBox(height: 4),
            Text(
              AppStringsTr.saleProductsEmptyHint,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            FilledButton(
              key: const Key('sale_products_empty_action'),
              onPressed: onOpenProducts,
              child: const Text(AppStringsTr.saleProductsEmptyAction),
            ),
          ],
        ],
      ),
    ),
  );
}
