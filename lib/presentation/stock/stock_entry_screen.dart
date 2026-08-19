/// Stok girişi (mal kabul) — **docs/13 §5 · REQ-STOCK-007/008**
///
/// > *"En sık kullanılan ikinci ekran."*
///
/// Satış ekranıyla aynı iki alışkanlığı paylaşır: barkod okutma satır ekler,
/// odak arama girişinde kalır. Ama **stoğa yazma anında değildir** — satırlar
/// ekranda birikir ve "Girişi Kaydet" ile **tek transaction**'da yazılır
/// (REQ-STOCK-007). Yarım bir mal kabul oluşamaz.
///
/// ## Hata durumunda ekran KORUNUR
///
/// docs/13 §10: *"Girilen veriler ekranda korunur, kullanıcı düzeltip tekrar
/// deneyebilir."* Bu yüzden satırlar yalnızca kaydetme **başarılı olduğunda**
/// temizlenir.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/product/providers.dart';
import '../../application/reference/providers.dart';
import '../../application/stock/providers.dart';
import '../../application/stock/stock_service.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../domain/models/product.dart';
import '../../domain/models/supplier.dart';
import '../barcode/barcode_listener.dart';
import '../common/current_user.dart';
import 'stock_dialogs.dart';

/// Ekrandaki bir satır — henüz yazılmamıştır.
class _EntryDraft {
  final Product product;
  int quantity;
  Money unitCost;

  /// BR-STOCK-009 — kullanıcı ürünün fiyatının da güncellenmesini onayladı mı?
  bool updateProductPrice;

  _EntryDraft({required this.product, required this.unitCost})
    : quantity = 1,
      updateProductPrice = false;

  Money get total => unitCost * quantity;
}

class StockEntryScreen extends ConsumerStatefulWidget {
  static const Key searchFieldKey = Key('stock_entry_search');
  static const Key saveButtonKey = Key('stock_entry_save');
  static const Key totalKey = Key('stock_entry_total');
  static const Key supplierKey = Key('stock_entry_supplier');

  /// Barkod eşiklerinin saati — rules/06 §7 (test için enjekte edilir).
  final DateTime Function()? clock;

  const StockEntryScreen({this.clock, super.key});

  @override
  ConsumerState<StockEntryScreen> createState() => _StockEntryScreenState();
}

class _StockEntryScreenState extends ConsumerState<StockEntryScreen> {
  final TextEditingController _search = TextEditingController();
  final TextEditingController _document = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'stockEntrySearch');

  final List<_EntryDraft> _lines = [];
  List<Supplier> _suppliers = const [];
  List<Product> _results = const [];
  int? _supplierId;
  int? _userId;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _search.dispose();
    _document.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final userId = await currentUserId(ref);
    final suppliers = await ref
        .read(supplierServiceProvider)
        .list(onlyActive: true);
    if (!mounted) return;
    setState(() {
      _userId = userId;
      _suppliers = suppliers;
    });
    _searchFocus.requestFocus();
  }

  Future<void> _search_(String query) async {
    final results = query.trim().isEmpty
        ? const <Product>[]
        : await ref.read(productServiceProvider).search(query, limit: 20);
    if (!mounted) return;
    setState(() => _results = results);
  }

  /// docs/13 §5 — "aynı ürün tekrar okutulursa miktar +1".
  void _addProduct(Product product) {
    setState(() {
      final existing = _lines
          .where((l) => l.product.id == product.id)
          .firstOrNull;
      if (existing != null) {
        existing.quantity += 1;
      } else {
        _lines.add(
          _EntryDraft(product: product, unitCost: product.purchasePrice),
        );
      }
      _search.clear();
      _results = const [];
    });
    _searchFocus.requestFocus();
  }

  Future<void> _onScan(String barcode) async {
    final product = await ref
        .read(productServiceProvider)
        .findByBarcode(barcode);
    if (!mounted) return;
    if (product == null) {
      // Stok girişi bilinmeyen barkodla ürün OLUŞTURMAZ: mal kabul bir ürün
      // tanımlama ekranı değildir (docs/13 §5). Kullanıcı ürünü önce
      // Ürünler'den tanımlar.
      _notify(AppStringsTr.saleSearchEmpty);
      return;
    }
    _addProduct(product);
  }

  /// BR-STOCK-009 — alış fiyatı değiştirildiğinde ürünün fiyatı da
  /// güncellensin mi diye **sorulur**; karar kullanıcınındır.
  Future<void> _editCost(_EntryDraft line) async {
    final price = await showPriceOverrideDialogForCost(
      context,
      productName: line.product.name,
      currentCost: line.unitCost,
    );
    if (!mounted || price == null) return;

    var update = line.updateProductPrice;
    if (price != line.product.purchasePrice) {
      update = await askUpdatePurchasePrice(
        context,
        productName: line.product.name,
        oldPrice: line.product.purchasePrice,
        newPrice: price,
      );
    } else {
      update = false;
    }
    if (!mounted) return;
    setState(() {
      line.unitCost = price;
      line.updateProductPrice = update;
    });
  }

  Future<void> _save() async {
    if (_lines.isEmpty || _busy || _userId == null) return;
    setState(() => _busy = true);
    try {
      final result = await ref
          .read(stockServiceProvider)
          .recordEntry(
            userId: _userId!,
            supplierId: _supplierId,
            documentNumber: _document.text.trim().isEmpty
                ? null
                : _document.text.trim(),
            lines: [
              for (final line in _lines)
                StockEntryLine(
                  productId: line.product.id,
                  quantity: line.quantity,
                  unitCost: line.unitCost,
                  updateProductPurchasePrice: line.updateProductPrice,
                ),
            ],
          );
      if (!mounted) return;

      if (result.isErr) {
        // docs/13 §10 — girilen veriler ekranda KORUNUR.
        _notify(result.failureOrNull!.userMessage);
        return;
      }
      setState(() {
        _lines.clear();
        _document.clear();
      });
      _notify(AppStringsTr.stockEntrySaved);
    } finally {
      if (mounted) setState(() => _busy = false);
      _searchFocus.requestFocus();
    }
  }

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Money get _total => Money.sum(_lines.map((l) => l.total));

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BarcodeListener(
      onScan: (barcode) => unawaited(_onScan(barcode)),
      autofocus: false,
      child: Scaffold(
        appBar: AppBar(title: const Text(AppStringsTr.stockEntryTitle)),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      key: StockEntryScreen.supplierKey,
                      // Referans listesi ASENKRON gelir; ilk karede boşken
                      // seçili kimliği vermek Flutter'ın assertion'ını
                      // patlatır (Faz 3c'de aynı hata görüldü).
                      initialValue: _suppliers.any((s) => s.id == _supplierId)
                          ? _supplierId
                          : null,
                      decoration: const InputDecoration(
                        labelText: AppStringsTr.stockEntrySupplier,
                      ),
                      items: [
                        const DropdownMenuItem(
                          child: Text(AppStringsTr.stockEntryNoSupplier),
                        ),
                        for (final supplier in _suppliers)
                          DropdownMenuItem(
                            value: supplier.id,
                            child: Text(supplier.name),
                          ),
                      ],
                      onChanged: (value) => setState(() => _supplierId = value),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      key: const Key('stock_entry_document'),
                      controller: _document,
                      decoration: const InputDecoration(
                        labelText: AppStringsTr.stockEntryDocument,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                key: StockEntryScreen.searchFieldKey,
                controller: _search,
                focusNode: _searchFocus,
                decoration: const InputDecoration(
                  hintText: AppStringsTr.stockEntrySearchHint,
                  prefixIcon: Icon(Icons.qr_code_scanner),
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => unawaited(_search_(value)),
              ),
              if (_results.isNotEmpty)
                SizedBox(
                  height: 120,
                  child: Card(
                    child: ListView(
                      key: const Key('stock_entry_results'),
                      children: [
                        for (final product in _results)
                          ListTile(
                            key: Key('stock_entry_result_${product.id}'),
                            dense: true,
                            title: Text(product.name),
                            subtitle: Text(
                              '${AppStringsTr.stockEntryColumnCurrent}: '
                              '${product.stockQuantity}',
                            ),
                            onTap: () => _addProduct(product),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              Expanded(
                child: _lines.isEmpty
                    ? Center(
                        child: Text(
                          AppStringsTr.stockEntryEmpty,
                          style: theme.textTheme.bodyMedium,
                        ),
                      )
                    : ListView.builder(
                        key: const Key('stock_entry_lines'),
                        itemCount: _lines.length,
                        itemBuilder: (context, index) =>
                            _lineTile(theme, _lines[index]),
                      ),
              ),
              const Divider(),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppStringsTr.stockEntryTotal,
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    key: StockEntryScreen.totalKey,
                    MoneyFormatter.format(_total),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              FilledButton(
                key: StockEntryScreen.saveButtonKey,
                onPressed: _lines.isEmpty || _busy ? null : _save,
                child: const Text(AppStringsTr.stockEntrySave),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lineTile(ThemeData theme, _EntryDraft line) {
    return ListTile(
      key: Key('stock_entry_line_${line.product.id}'),
      title: Text(line.product.name),
      subtitle: Text(
        '${AppStringsTr.stockEntryColumnCurrent}: '
        '${line.product.stockQuantity}'
        '${line.updateProductPrice ? " · alış fiyatı güncellenecek" : ""}',
      ),
      trailing: SizedBox(
        width: 340,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              key: Key('stock_entry_dec_${line.product.id}'),
              icon: const Icon(Icons.remove, size: 18),
              onPressed: () => setState(() {
                if (line.quantity > 1) {
                  line.quantity -= 1;
                } else {
                  _lines.remove(line);
                }
              }),
            ),
            Text(
              '${line.quantity}',
              key: Key('stock_entry_qty_${line.product.id}'),
              style: theme.textTheme.titleSmall,
            ),
            IconButton(
              key: Key('stock_entry_inc_${line.product.id}'),
              icon: const Icon(Icons.add, size: 18),
              onPressed: () => setState(() => line.quantity += 1),
            ),
            const SizedBox(width: 8),
            TextButton(
              key: Key('stock_entry_cost_${line.product.id}'),
              onPressed: () => unawaited(_editCost(line)),
              child: Text(MoneyFormatter.format(line.unitCost)),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              child: Text(
                MoneyFormatter.format(line.total),
                key: Key('stock_entry_total_${line.product.id}'),
                textAlign: TextAlign.right,
                style: theme.textTheme.bodyLarge,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
