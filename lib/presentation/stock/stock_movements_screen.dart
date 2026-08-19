/// Stok hareket geçmişi — **docs/13 §8 · REQ-STOCK-003/010 · BR-STOCK-010**
///
/// > *"Bu ürünün stoğu neden 12?" sorusu defterden geriye dönük
/// > yanıtlanabilmelidir.*
///
/// ## Düzenle/Sil YOKTUR
///
/// REQ-STOCK-003 · BR-STOCK-005: hareket kayıtları yazıldıktan sonra
/// değiştirilemez. Bu ekranda **bilinçli olarak** "Düzenle" ve "Sil" eylemi
/// bulunmaz; yanlış bir kayıt yalnızca **ters kayıtla** düzeltilir ve orijinal
/// olduğu gibi kalır (docs/13 §10 acceptance criteria).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/product/providers.dart';
import '../../application/stock/providers.dart';
import '../../core/money/money_formatter.dart';
import '../../domain/enums/stock_movement_type.dart';
import '../../domain/models/product.dart';
import '../../domain/models/stock_movement.dart';
import '../common/current_user.dart';
import 'stock_dialogs.dart';

class StockMovementsScreen extends ConsumerStatefulWidget {
  static const Key listKey = Key('stock_movements_list');
  static const Key typeFilterKey = Key('stock_movements_type');
  static const Key productFilterKey = Key('stock_movements_product');

  /// Belirli bir ürünle açılırsa filtre önceden seçilidir (ürün detayından
  /// gelinen yol).
  final int? initialProductId;

  const StockMovementsScreen({this.initialProductId, super.key});

  @override
  ConsumerState<StockMovementsScreen> createState() =>
      _StockMovementsScreenState();
}

class _StockMovementsScreenState extends ConsumerState<StockMovementsScreen> {
  List<StockMovement> _movements = const [];
  Map<int, Product> _products = const {};
  StockMovementType? _type;
  int? _productId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _productId = widget.initialProductId;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final movements = await ref
        .read(stockServiceProvider)
        .movements(productId: _productId, type: _type, limit: 200);
    // Ürün adları hareket üzerinde yoktur (defter ürüne referans verir);
    // yalnızca listede geçen ürünler çözülür.
    final service = ref.read(productServiceProvider);
    final products = <int, Product>{};
    for (final id in movements.map((m) => m.productId).toSet()) {
      final product = await service.findById(id);
      if (product != null) products[id] = product;
    }

    if (!mounted) return;
    setState(() {
      _movements = movements;
      _products = products;
      _loading = false;
    });
  }

  /// REQ-STOCK-003 — hareket silinmez; ters kayıt açılır.
  Future<void> _reverse(StockMovement movement) async {
    final reason = await showReverseMovementDialog(context);
    if (!mounted || reason == null) return;

    final userId = await currentUserId(ref);
    if (!mounted || userId == null) return;

    final result = await ref
        .read(stockServiceProvider)
        .reverseMovement(
          movementId: movement.id,
          reason: reason,
          userId: userId,
        );
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(
            result.isErr
                ? result.failureOrNull!.userMessage
                : AppStringsTr.stockMovementReversed,
          ),
        ),
      );
    if (result.isOk) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStringsTr.stockMovementsTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<StockMovementType?>(
                    key: StockMovementsScreen.typeFilterKey,
                    initialValue: _type,
                    decoration: const InputDecoration(
                      labelText: AppStringsTr.stockMovementsAllTypes,
                    ),
                    items: [
                      const DropdownMenuItem(
                        child: Text(AppStringsTr.stockMovementsAllTypes),
                      ),
                      for (final type in StockMovementType.values)
                        DropdownMenuItem(
                          value: type,
                          child: Text(_typeName(type)),
                        ),
                    ],
                    onChanged: (value) {
                      setState(() => _type = value);
                      unawaited(_load());
                    },
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _movements.isEmpty
                ? Center(
                    child: Text(
                      AppStringsTr.stockMovementsEmpty,
                      style: theme.textTheme.bodyMedium,
                    ),
                  )
                : ListView.builder(
                    key: StockMovementsScreen.listKey,
                    itemCount: _movements.length,
                    itemBuilder: (context, index) =>
                        _tile(theme, _movements[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tile(ThemeData theme, StockMovement movement) {
    final product = _products[movement.productId];
    final positive = movement.quantityDelta > 0;

    return ListTile(
      key: Key('stock_movement_${movement.id}'),
      leading: Icon(
        positive ? Icons.arrow_upward : Icons.arrow_downward,
        color: positive ? theme.colorScheme.primary : theme.colorScheme.error,
      ),
      title: Text(product?.name ?? '#${movement.productId}'),
      subtitle: Text(
        '${_typeName(movement.type)} · '
        '${AppStringsTr.stockMovementResulting}: ${movement.resultingStock}'
        '${movement.note == null ? "" : " · ${movement.note}"}'
        '${movement.unitCost == null ? "" : " · ${MoneyFormatter.format(movement.unitCost!)}"}',
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${positive ? "+" : ""}${movement.quantityDelta}',
            key: Key('stock_movement_delta_${movement.id}'),
            style: theme.textTheme.titleMedium?.copyWith(
              color: positive
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ),
          // REQ-STOCK-003 — "Düzenle"/"Sil" YOK; yalnızca ters kayıt.
          IconButton(
            key: Key('stock_movement_reverse_${movement.id}'),
            tooltip: AppStringsTr.stockMovementReverse,
            icon: const Icon(Icons.undo),
            onPressed: () => unawaited(_reverse(movement)),
          ),
        ],
      ),
    );
  }

  static String _typeName(StockMovementType type) =>
      AppStringsTr.stockMovementTypeNames[type.wire] ?? type.wire;
}
