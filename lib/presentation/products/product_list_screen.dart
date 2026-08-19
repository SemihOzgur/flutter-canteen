/// Ürün listesi — **docs/09 §4, §6 · REQ-PROD-010 · REQ-PERF-006**
///
/// | Davranış | Kural |
/// |---|---|
/// | Arama Türkçe karakter duyarsız | REQ-PROD-010 · docs/09 §6 |
/// | 150 ms debounce, maks. 50 sonuç | docs/09 §6 |
/// | Liste **sayfalıdır** | REQ-PERF-006 · rules/01 §8 |
/// | "Pasifleri göster" varsayılan kapalı | docs/09 §4 |
/// | Fiyat **KDV dahil** gösterilir | BR-VAT-003 |
/// | Satır görseli 40×40, yoksa varsayılan ikon | docs/21 §3 · REQ-IMG-009 |
/// | Yıldızla tek tıkla favori | REQ-PROD-009 · docs/09 §5 |
///
/// ## Katlama burada yapılmaz
///
/// Türkçe katlama tek implementasyondur (`TurkishText.fold`) ve SQL tarafında
/// çalışır (rules/01 §2). Ekran ham sorguyu servise verir; kendi filtresini
/// kurmaz — kurarsa iki farklı arama davranışı doğar.
///
/// ## Neden tüm liste belleğe alınmaz
///
/// rules/01 §8: "Listeler sayfalanır; tüm kayıtlar belleğe alınmaz." Hedef
/// 10.000+ üründür. Sayfa boyutu [_pageSize] sabitidir; `count` ile toplam
/// sayı ayrıca sorulur ki kullanıcı nerede olduğunu görsün.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/product/providers.dart';
import '../../application/reference/providers.dart';
import '../../core/money/money_formatter.dart';
import '../../core/result/result.dart';
import '../../domain/models/product.dart';
import '../common/current_user.dart';
import '../common/form_message.dart';
import 'product_form_screen.dart';
import 'product_image_view.dart';

class ProductListScreen extends ConsumerStatefulWidget {
  static const Key addButtonKey = Key('products_add_button');
  static const Key searchFieldKey = Key('products_search_field');
  static const Key showInactiveKey = Key('products_show_inactive');
  static const Key messageKey = Key('products_message');
  static const Key previousPageKey = Key('products_previous_page');
  static const Key nextPageKey = Key('products_next_page');

  static Key tileKey(int id) => ValueKey('product_tile_$id');
  static Key editButtonKey(int id) => ValueKey('product_edit_$id');
  static Key deleteButtonKey(int id) => ValueKey('product_delete_$id');
  static Key activeSwitchKey(int id) => ValueKey('product_active_$id');
  static Key favoriteButtonKey(int id) => ValueKey('product_favorite_$id');

  const ProductListScreen({super.key});

  @override
  ConsumerState<ProductListScreen> createState() => _ProductListScreenState();
}

class _ProductListScreenState extends ConsumerState<ProductListScreen> {
  /// docs/09 §6 — arama 150 ms debounce ile çalışır.
  static const Duration _debounce = Duration(milliseconds: 150);

  /// REQ-PERF-006 — sayfa boyutu.
  static const int _pageSize = 25;

  final TextEditingController _search = TextEditingController();
  Timer? _debounceTimer;

  String _query = '';
  bool _includeInactive = false;
  int _page = 0;
  int _total = 0;
  List<Product> _items = const [];
  bool _loading = true;
  String? _message;

  bool get _searching => _query.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounce, () {
      if (!mounted) return;
      setState(() {
        _query = value;
        _page = 0;
      });
      unawaited(_load());
    });
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final service = ref.read(productServiceProvider);

    if (_searching) {
      // docs/09 §6 — arama sonucu maks. 50 kayıttır; sayfalanmaz.
      final found = await service.search(
        _query,
        includeInactive: _includeInactive,
      );
      if (!mounted) return;
      setState(() {
        _items = found;
        _total = found.length;
        _loading = false;
      });
      return;
    }

    final total = await service.count(includeInactive: _includeInactive);
    final items = await service.list(
      includeInactive: _includeInactive,
      limit: _pageSize,
      offset: _page * _pageSize,
    );
    if (!mounted) return;
    setState(() {
      _items = items;
      _total = total;
      _loading = false;
    });
  }

  void _showInfo(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _openForm({Product? product}) async {
    setState(() => _message = null);

    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => ProductFormScreen(product: product),
      ),
    );
    if (!mounted || saved != true) return;

    _showInfo(
      product == null
          ? AppStringsTr.productCreated
          : AppStringsTr.productUpdated,
    );
    await _load();
  }

  /// docs/09 §4 — pasifleştirme geri alınabilir; onay istenmez
  /// (rules/05 §5). Stoğu olan ürün **uyarılır ama engellenmez.**
  Future<void> _setActive(Product product, bool isActive) async {
    setState(() => _message = null);

    final service = ref.read(productServiceProvider);
    final userId = await _requireUserId();
    if (userId == null) return;

    if (isActive) {
      final result = await service.activate(product.id, userId: userId);
      if (!mounted) return;
      if (result case Err(:final failure)) {
        setState(() => _message = failure.userMessage);
        return;
      }
      _showInfo(AppStringsTr.productActivated);
      await _load();
      return;
    }

    final result = await service.deactivate(product.id, userId: userId);
    if (!mounted) return;

    switch (result) {
      case Err(:final failure):
        setState(() => _message = failure.userMessage);
      case Ok(:final value):
        // docs/09 §4 — stoğu olan ürün pasifleştirilirken UYARILIR ama
        // engellenmez. Uyarı metni servisten gelir; ekran hesap yapmaz.
        _showInfo(
          value.isEmpty
              ? AppStringsTr.productDeactivated
              : value.map((w) => w.message).join(' '),
        );
        await _load();
    }
  }

  /// REQ-PROD-009 · docs/09 §5 — yıldızla tek tıkla favori.
  ///
  /// 30 favori uyarısı **servisten** gelir; ekran saymaz (rules/05 §8).
  /// Favori değişikliği geri alınabilir olduğu için onay istenmez
  /// (rules/05 §5).
  Future<void> _toggleFavorite(Product product) async {
    setState(() => _message = null);

    final result = await ref
        .read(productServiceProvider)
        .setFavorite(product.id, isFavorite: !product.isFavorite);
    if (!mounted) return;

    switch (result) {
      case Err(:final failure):
        setState(() => _message = failure.userMessage);
      case Ok(:final value):
        _showInfo(
          value.isEmpty
              ? (product.isFavorite
                    ? AppStringsTr.productFavoriteRemoved
                    : AppStringsTr.productFavoriteAdded)
              : value.map((w) => w.message).join(' '),
        );
        await _load();
    }
  }

  /// docs/09 §4 — **iki ayrı akış.** Kararı `ProductUsage` verir, bu ekran
  /// değil: hiç kullanılmamış ürün kalıcı silinir, kullanılmış ürün için
  /// kalıcı silme **sunulmaz.**
  Future<void> _delete(Product product) async {
    setState(() => _message = null);

    final service = ref.read(productServiceProvider);
    final usageResult = await service.usage(product.id);
    if (!mounted) return;

    if (usageResult case Err(:final failure)) {
      setState(() => _message = failure.userMessage);
      return;
    }
    final usage = (usageResult as Ok).value;

    if (!usage.canDeletePermanently) {
      // EC-PROD-020/021 — kalıcı silme SUNULMAZ.
      final deactivate = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text(AppStringsTr.productDeleteBlockedTitle),
          content: Text(
            AppStringsTr.productDeleteBlockedMessage(
              product.name,
              usage.saleItemCount,
              usage.stockMovementCount,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text(AppStringsTr.cancelAction),
            ),
            FilledButton(
              key: const Key('product_deactivate_confirm'),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text(AppStringsTr.productDeactivateAction),
            ),
          ],
        ),
      );
      // `Esc` / bariyer → `null` → vazgeçme. `?? true` OLAMAZ.
      if (!mounted || !(deactivate ?? false)) return;
      await _setActive(product, false);
      return;
    }

    // BR-PROD-014 · EC-PROD-019 — geri alınamaz; onay zorunlu (rules/05 §5).
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStringsTr.productDeleteTitle),
        content: Text(AppStringsTr.productDeleteConfirm(product.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStringsTr.cancelAction),
          ),
          FilledButton(
            key: const Key('product_delete_confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStringsTr.productDeletePermanentAction),
          ),
        ],
      ),
    );
    // `Esc` / bariyer de vazgeçmedir — buton yolundan AYRI bir kod yolu.
    if (!mounted || !(confirmed ?? false)) return;

    final userId = await _requireUserId();
    if (userId == null) return;

    final result = await service.delete(product.id, userId: userId);
    if (!mounted) return;

    switch (result) {
      case Ok<void>():
        _showInfo(AppStringsTr.productDeleted);
        await _load();
      case Err(:final failure):
        setState(() => _message = failure.userMessage);
    }
  }

  /// Ürün işlemleri stok hareketi yazabildiği için oturum zorunludur
  /// (`stock_movements.user_id` NOT NULL).
  Future<int?> _requireUserId() async {
    final userId = await currentUserId(ref);
    if (userId == null && mounted) {
      setState(() => _message = AppStringsTr.sessionRequiredMessage);
    }
    return userId;
  }

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoryListProvider);
    final categoryNames = <int, String>{
      for (final c in categories.valueOrNull ?? const []) c.id: c.name,
    };

    final pageCount = _total == 0 ? 1 : ((_total - 1) ~/ _pageSize) + 1;

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStringsTr.productsTitle),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              key: ProductListScreen.addButtonKey,
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: const Text(AppStringsTr.productAddAction),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(AppStringsTr.productsDescription),
                const SizedBox(height: 12),
                TextField(
                  key: ProductListScreen.searchFieldKey,
                  controller: _search,
                  onChanged: _onQueryChanged,
                  decoration: const InputDecoration(
                    labelText: AppStringsTr.productSearchLabel,
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Switch(
                      key: ProductListScreen.showInactiveKey,
                      value: _includeInactive,
                      onChanged: (value) {
                        setState(() {
                          _includeInactive = value;
                          _page = 0;
                        });
                        unawaited(_load());
                      },
                    ),
                    const SizedBox(width: 8),
                    const Text(AppStringsTr.productShowInactiveLabel),
                    const Spacer(),
                    Text(AppStringsTr.productTotalCount(_total)),
                  ],
                ),
                if (_message != null) ...[
                  const SizedBox(height: 12),
                  FormMessage(
                    _message!,
                    key: ProductListScreen.messageKey,
                    kind: FormMessageKind.error,
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                ? _EmptyState(query: _query)
                : ListView.separated(
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final product = _items[index];
                      return _ProductTile(
                        product: product,
                        categoryName: categoryNames[product.categoryId],
                        onEdit: () => _openForm(product: product),
                        onDelete: () => _delete(product),
                        onActiveChanged: (value) => _setActive(product, value),
                        onFavoriteToggled: () => _toggleFavorite(product),
                      );
                    },
                  ),
          ),
          if (!_searching) ...[
            const Divider(height: 1),
            _Pagination(
              page: _page,
              pageCount: pageCount,
              onPrevious: _page == 0
                  ? null
                  : () {
                      setState(() => _page -= 1);
                      unawaited(_load());
                    },
              onNext: _page + 1 >= pageCount
                  ? null
                  : () {
                      setState(() => _page += 1);
                      unawaited(_load());
                    },
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final Product product;
  final String? categoryName;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onActiveChanged;
  final VoidCallback onFavoriteToggled;

  const _ProductTile({
    required this.product,
    required this.categoryName,
    required this.onEdit,
    required this.onDelete,
    required this.onActiveChanged,
    required this.onFavoriteToggled,
  });

  @override
  Widget build(BuildContext context) {
    // rules/05 §5 — durum renkle DEĞİL, ikon ve metinle de anlatılır.
    final subtitle = <String>[
      ?categoryName,
      '${MoneyFormatter.format(product.salePrice)} '
          '(${AppStringsTr.productPriceVatIncludedSuffix})',
      AppStringsTr.productStockValue(product.stockQuantity),
      if (!product.isActive) AppStringsTr.userInactive,
    ].join(' · ');

    return ListTile(
      key: ProductListScreen.tileKey(product.id),
      // docs/21 §3 — liste satırı 40×40; görsel yoksa/okunamıyorsa varsayılan
      // ikon gösterilir, hata gösterilmez (REQ-IMG-009).
      leading: ProductImageView(relativePath: product.imagePath, size: 40),
      title: Text(product.name),
      subtitle: Text(subtitle),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            key: ProductListScreen.favoriteButtonKey(product.id),
            tooltip: product.isFavorite
                ? AppStringsTr.productFavoriteRemoveAction
                : AppStringsTr.productFavoriteAddAction,
            onPressed: onFavoriteToggled,
            icon: Icon(product.isFavorite ? Icons.star : Icons.star_border),
          ),
          IconButton(
            key: ProductListScreen.editButtonKey(product.id),
            tooltip: AppStringsTr.editAction,
            onPressed: onEdit,
            icon: const Icon(Icons.edit),
          ),
          IconButton(
            key: ProductListScreen.deleteButtonKey(product.id),
            tooltip: AppStringsTr.productDeleteTitle,
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline),
          ),
          Switch(
            key: ProductListScreen.activeSwitchKey(product.id),
            value: product.isActive,
            onChanged: onActiveChanged,
          ),
        ],
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  final int page;
  final int pageCount;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  const _Pagination({
    required this.page,
    required this.pageCount,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton.icon(
            key: ProductListScreen.previousPageKey,
            onPressed: onPrevious,
            icon: const Icon(Icons.chevron_left),
            label: const Text(AppStringsTr.previousPageAction),
          ),
          const SizedBox(width: 16),
          Text(AppStringsTr.productPageIndicator(page + 1, pageCount)),
          const SizedBox(width: 16),
          TextButton.icon(
            key: ProductListScreen.nextPageKey,
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            label: const Text(AppStringsTr.nextPageAction),
          ),
        ],
      ),
    );
  }
}

/// rules/05 §5 — her liste ekranının **eyleme yönlendiren** boş durumu vardır.
class _EmptyState extends StatelessWidget {
  final String query;

  const _EmptyState({required this.query});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          query.trim().isEmpty
              ? AppStringsTr.productsEmpty
              : AppStringsTr.productsSearchEmpty(query.trim()),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
