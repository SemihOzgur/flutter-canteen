/// Tedarikçi detayı — **REQ-SUP-003 · docs/10 §2**
///
/// > *"Tedarikçi detayında ürün ve girişler."*
///
/// İki soruyu yanıtlar: bu tedarikçiden **hangi ürünleri** alıyoruz ve
/// **ne zaman ne kadar** aldık. İkincisi stok defterinden gelir
/// (`stock_movements.supplier_id`) — ayrı bir "alım geçmişi" tablosu yoktur
/// ve olmamalıdır (rules/01 §3).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/product/providers.dart';
import '../../application/reference/providers.dart';
import '../../application/stock/providers.dart';
import '../../core/money/money_formatter.dart';
import '../../domain/enums/stock_movement_type.dart';
import '../../domain/models/product.dart';
import '../../domain/models/stock_movement.dart';
import '../../domain/models/supplier.dart';

class SupplierDetailScreen extends ConsumerStatefulWidget {
  static const Key productsKey = Key('supplier_detail_products');
  static const Key entriesKey = Key('supplier_detail_entries');

  final int supplierId;

  const SupplierDetailScreen({required this.supplierId, super.key});

  @override
  ConsumerState<SupplierDetailScreen> createState() =>
      _SupplierDetailScreenState();
}

class _SupplierDetailScreenState extends ConsumerState<SupplierDetailScreen> {
  Supplier? _supplier;
  List<Product> _products = const [];
  List<StockMovement> _entries = const [];
  Map<int, String> _productNames = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final supplier = await ref
        .read(supplierServiceProvider)
        .findById(widget.supplierId);
    final products = await ref
        .read(productServiceProvider)
        .list(includeInactive: true, limit: 500);
    final entries = await ref
        .read(stockServiceProvider)
        .movements(
          supplierId: widget.supplierId,
          type: StockMovementType.stockEntry,
          limit: 100,
        );

    if (!mounted) return;
    setState(() {
      _supplier = supplier;
      _products = products
          .where((p) => p.supplierId == widget.supplierId)
          .toList();
      _entries = entries;
      _productNames = {for (final p in products) p.id: p.name};
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(_supplier?.name ?? AppStringsTr.supplierDetailTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${AppStringsTr.supplierDetailProducts} (${_products.length})',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_products.isEmpty)
                  const Text(AppStringsTr.supplierDetailNoProducts)
                else
                  Column(
                    key: SupplierDetailScreen.productsKey,
                    children: [
                      for (final product in _products)
                        ListTile(
                          key: Key('supplier_product_${product.id}'),
                          dense: true,
                          title: Text(product.name),
                          subtitle: Text(
                            AppStringsTr.productStockValue(
                              product.stockQuantity,
                            ),
                          ),
                          trailing: Text(
                            MoneyFormatter.format(product.purchasePrice),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 24),
                Text(
                  '${AppStringsTr.supplierDetailEntries} (${_entries.length})',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                if (_entries.isEmpty)
                  const Text(AppStringsTr.supplierDetailNoEntries)
                else
                  Column(
                    key: SupplierDetailScreen.entriesKey,
                    children: [
                      for (final entry in _entries)
                        ListTile(
                          key: Key('supplier_entry_${entry.id}'),
                          dense: true,
                          title: Text(
                            _productNames[entry.productId] ??
                                '#${entry.productId}',
                          ),
                          subtitle: Text(
                            '+${entry.quantityDelta} · '
                            '${AppStringsTr.stockMovementResulting}: '
                            '${entry.resultingStock}'
                            '${entry.note == null ? "" : " · ${entry.note}"}',
                          ),
                          trailing: entry.unitCost == null
                              ? null
                              : Text(MoneyFormatter.format(entry.unitCost!)),
                        ),
                    ],
                  ),
              ],
            ),
    );
  }
}
