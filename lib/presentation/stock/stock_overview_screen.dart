/// Stok görünürlüğü ve işlemleri — **docs/13 §6–§7 · BR-STOCK-007 ·
/// REQ-STOCK-006/009/011**
///
/// Faz 6'nın stok giriş noktası: kritik ve negatif stok listeleri burada
/// görünür, fire ve düzeltme buradan başlatılır.
///
/// ## Negatif stok GİZLENMEZ
///
/// BR-STOCK-007 · docs/13 §4: negatif stok bir **hata sinyalidir** ve
/// vurgulanır. Pasif ürünler de listelenir — pasifleştirilmiş olmak sinyali
/// geçersiz kılmaz.
///
/// ## Kritik stok eşiği
///
/// REQ-STOCK-011: `minimum_stock = 0` olan ürünler **hiç girmez** — kullanıcı
/// o ürün için takip istemiyor demektir. Sorgu bunu `data/` katmanında
/// uygular; ekran filtre uydurmaz.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../app/router.dart';
import '../../application/product/providers.dart';
import '../../application/stock/providers.dart';
import '../../domain/models/product.dart';
import '../common/current_user.dart';
import 'stock_dialogs.dart';

class StockOverviewScreen extends ConsumerStatefulWidget {
  static const Key criticalListKey = Key('stock_critical_list');
  static const Key negativeListKey = Key('stock_negative_list');
  static const Key entryButtonKey = Key('stock_overview_entry');
  static const Key searchFieldKey = Key('stock_overview_search');
  static const Key searchListKey = Key('stock_overview_results');
  static const Key movementsButtonKey = Key('stock_overview_movements');

  const StockOverviewScreen({super.key});

  @override
  ConsumerState<StockOverviewScreen> createState() =>
      _StockOverviewScreenState();
}

class _StockOverviewScreenState extends ConsumerState<StockOverviewScreen> {
  final TextEditingController _search = TextEditingController();
  List<Product> _critical = const [];
  List<Product> _negative = const [];
  List<Product> _results = const [];
  bool _loading = true;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// docs/13 §6 fire ve düzeltmeyi **kritik/negatif ürünlerle sınırlamaz.**
  /// Bozulan süt, stoğu 50 olan bir üründe de olur; arama olmadan o ürüne
  /// hiçbir yerden ulaşılamazdı.
  Future<void> _runSearch(String query) async {
    final results = query.trim().isEmpty
        ? const <Product>[]
        : await ref.read(productServiceProvider).search(query, limit: 20);
    if (!mounted) return;
    setState(() => _results = results);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    // rules/01 §1 — ekran `data/` katmanını tanımaz.
    final stock = ref.read(stockServiceProvider);
    final critical = await stock.criticalStock();
    final negative = await stock.negativeStock();
    if (!mounted) return;
    setState(() {
      _critical = critical;
      _negative = negative;
      _loading = false;
    });
  }

  Future<void> _waste(Product product) async {
    final input = await showWasteDialog(
      context,
      productName: product.name,
      currentStock: product.stockQuantity,
    );
    if (!mounted || input == null) return;

    final userId = await currentUserId(ref);
    if (!mounted || userId == null) return;

    final result = await ref
        .read(stockServiceProvider)
        .recordWaste(
          productId: product.id,
          quantity: input.quantity,
          reason: input.reason,
          userId: userId,
        );
    _report(
      result.isErr
          ? result.failureOrNull!.userMessage
          : AppStringsTr.stockWasteSaved,
    );
    if (result.isOk) await _load();
  }

  Future<void> _adjust(Product product) async {
    final input = await showAdjustmentDialog(
      context,
      productName: product.name,
      currentStock: product.stockQuantity,
    );
    if (!mounted || input == null) return;

    final userId = await currentUserId(ref);
    if (!mounted || userId == null) return;

    final result = await ref
        .read(stockServiceProvider)
        .recordAdjustment(
          productId: product.id,
          newQuantity: input.quantity,
          reason: input.reason,
          userId: userId,
        );
    _report(
      result.isErr
          ? result.failureOrNull!.userMessage
          : AppStringsTr.stockAdjustSaved,
    );
    if (result.isOk) await _load();
  }

  void _report(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStringsTr.homeStockAction),
        actions: [
          IconButton(
            key: StockOverviewScreen.movementsButtonKey,
            tooltip: AppStringsTr.stockMovementsTitle,
            icon: const Icon(Icons.history),
            onPressed: () => unawaited(
              Navigator.of(
                context,
              ).pushNamed(AppRoutes.stockMovements).then((_) => _load()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: StockOverviewScreen.entryButtonKey,
        onPressed: () => unawaited(
          Navigator.of(
            context,
          ).pushNamed(AppRoutes.stockEntry).then((_) => _load()),
        ),
        icon: const Icon(Icons.add_box_outlined),
        label: const Text(AppStringsTr.stockEntryTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                TextField(
                  key: StockOverviewScreen.searchFieldKey,
                  controller: _search,
                  decoration: const InputDecoration(
                    hintText: AppStringsTr.stockSearchHint,
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => unawaited(_runSearch(value)),
                ),
                if (_results.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _section(
                    theme,
                    title: AppStringsTr.stockSearchResults,
                    emptyText: '',
                    products: _results,
                    listKey: StockOverviewScreen.searchListKey,
                    color: theme.colorScheme.onSurfaceVariant,
                    badge: AppStringsTr.productStockLabel,
                  ),
                ],
                const SizedBox(height: 16),
                _section(
                  theme,
                  title: AppStringsTr.stockNegativeTitle,
                  emptyText: AppStringsTr.stockNegativeEmpty,
                  products: _negative,
                  listKey: StockOverviewScreen.negativeListKey,
                  // BR-STOCK-007 — negatif stok VURGULANIR.
                  color: theme.colorScheme.error,
                  badge: AppStringsTr.stockNegativeBadge,
                ),
                const SizedBox(height: 24),
                _section(
                  theme,
                  title: AppStringsTr.stockCriticalTitle,
                  emptyText: AppStringsTr.stockCriticalEmpty,
                  products: _critical,
                  listKey: StockOverviewScreen.criticalListKey,
                  color: theme.colorScheme.tertiary,
                  badge: AppStringsTr.stockCriticalBadge,
                ),
              ],
            ),
    );
  }

  Widget _section(
    ThemeData theme, {
    required String title,
    required String emptyText,
    required List<Product> products,
    required Key listKey,
    required Color color,
    required String badge,
  }) {
    return Column(
      key: listKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: color, size: 20),
            const SizedBox(width: 6),
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(width: 8),
            Text('(${products.length})', style: theme.textTheme.bodySmall),
          ],
        ),
        const SizedBox(height: 8),
        if (products.isEmpty)
          Text(emptyText, style: theme.textTheme.bodySmall)
        else
          for (final product in products)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                key: Key('stock_row_${product.id}'),
                title: Text(product.name),
                subtitle: Text(
                  // rules/05 §5 — renkle iletilen durum METİNLE de ifade
                  // edilir.
                  '$badge · ${product.stockQuantity}'
                  '${product.minimumStock > 0 ? " · ${AppStringsTr.stockMinimumLabel(product.minimumStock)}" : ""}'
                  '${product.isActive ? "" : " · ${AppStringsTr.saleInactiveBadge}"}',
                  style: TextStyle(color: color),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextButton(
                      key: Key('stock_waste_${product.id}'),
                      onPressed: () => unawaited(_waste(product)),
                      child: const Text(AppStringsTr.stockWasteTitle),
                    ),
                    TextButton(
                      key: Key('stock_adjust_${product.id}'),
                      onPressed: () => unawaited(_adjust(product)),
                      child: const Text(AppStringsTr.stockAdjustTitle),
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }
}
