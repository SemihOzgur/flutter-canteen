/// Sepet paneli — **docs/12 §1 · rules/05 §2 · REQ-UX-005/014**
///
/// > **Sepet paneli hiçbir çözünürlükte gizlenmez veya sekmeye dönüşmez.**
///
/// Bu panelin genişliği daralabilir ama kendisi **daima görünürdür**; satış
/// ekranının vazgeçilmezidir (docs/23 §4). Toplam tutar uzaktan okunabilir
/// boyuttadır (REQ-UX-014).
///
/// ## Burada hesap YAPILMAZ
///
/// rules/05 §3: UI içinde finansal hesaplama yoktur. Matrah/KDV/toplam
/// [Cart.totals] üzerinden gelir, o da `VatCalculator`'a devreder. Bu widget
/// yalnızca **biçimlendirir** — `₺25,50` gösterimi bir presentation
/// concern'üdür (rules/02 §1).
library;

import 'package:flutter/material.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../core/money/money_formatter.dart';
import '../../domain/models/cart.dart';

class CartPanel extends StatelessWidget {
  static const Key totalKey = Key('sale_cart_total');
  static const Key completeButtonKey = Key('sale_complete_button');
  static const Key cashButtonKey = Key('sale_cash_button');
  static const Key clearButtonKey = Key('sale_clear_button');

  final Cart cart;

  /// `↑`/`↓` ile gezinilen satır (docs/23 §2).
  final int? selectedLineId;

  final ValueChanged<int> onSelectLine;
  final void Function(int lineId, int by) onChangeQuantity;
  final ValueChanged<int> onRemoveLine;
  final ValueChanged<int> onEditPrice;
  final VoidCallback onComplete;
  final VoidCallback onCash;
  final VoidCallback onClear;

  /// Satış tamamlanırken buton kilitlenir — EC-SALE-008 · REQ-SALE-008.
  final bool busy;

  const CartPanel({
    required this.cart,
    required this.selectedLineId,
    required this.onSelectLine,
    required this.onChangeQuantity,
    required this.onRemoveLine,
    required this.onEditPrice,
    required this.onComplete,
    required this.onCash,
    required this.onClear,
    required this.busy,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totals = cart.totals;

    return Material(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              AppStringsTr.saleCartTitle,
              style: theme.textTheme.titleMedium,
            ),
          ),
          Expanded(
            child: cart.isEmpty
                ? _empty(theme)
                // EC-CART-005 — 200 satırlık sepette de performans korunur:
                // `ListView.builder` yalnızca görünen satırları kurar.
                : ListView.builder(
                    key: const Key('sale_cart_list'),
                    itemCount: cart.lines.length,
                    itemBuilder: (context, index) => _CartLineTile(
                      line: cart.lines[index],
                      selected: cart.lines[index].id == selectedLineId,
                      onSelect: () => onSelectLine(cart.lines[index].id),
                      onIncrease: () =>
                          onChangeQuantity(cart.lines[index].id, 1),
                      onDecrease: () =>
                          onChangeQuantity(cart.lines[index].id, -1),
                      onRemove: () => onRemoveLine(cart.lines[index].id),
                      onEditPrice: () => onEditPrice(cart.lines[index].id),
                    ),
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _totalRow(
                  theme,
                  AppStringsTr.saleSubtotal,
                  MoneyFormatter.format(totals.net),
                ),
                _totalRow(
                  theme,
                  AppStringsTr.saleVat,
                  MoneyFormatter.format(totals.vat),
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      AppStringsTr.saleGrandTotal,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Flexible(
                      child: Text(
                        key: totalKey,
                        MoneyFormatter.format(totals.gross),
                        // REQ-UX-014 — uzaktan okunabilir (rules/05 §2).
                        style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: cashButtonKey,
                        onPressed: cart.isEmpty || busy ? null : onCash,
                        child: const Text('F4 ${AppStringsTr.saleCashAction}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        key: completeButtonKey,
                        // docs/12 §6.1 — boş sepetle tamamlanamaz
                        // (BR-CART-005) ve işlem sürerken buton kilitlenir
                        // (EC-SALE-008).
                        onPressed: cart.isEmpty || busy ? null : onComplete,
                        child: Text(
                          'F12 ${AppStringsTr.saleCompleteAction}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextButton(
                  key: clearButtonKey,
                  onPressed: cart.isEmpty || busy ? null : onClear,
                  child: const Text('Ctrl+Del ${AppStringsTr.saleClearAction}'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// docs/23 §6 — boş durum eyleme yönlendirir.
  Widget _empty(ThemeData theme) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.shopping_cart_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            AppStringsTr.saleCartEmptyTitle,
            style: theme.textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          Text(
            AppStringsTr.saleCartEmptyHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );

  Widget _totalRow(ThemeData theme, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodyMedium),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    ),
  );
}

class _CartLineTile extends StatelessWidget {
  final CartLine line;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onIncrease;
  final VoidCallback onDecrease;
  final VoidCallback onRemove;
  final VoidCallback onEditPrice;

  const _CartLineTile({
    required this.line,
    required this.selected,
    required this.onSelect,
    required this.onIncrease,
    required this.onDecrease,
    required this.onRemove,
    required this.onEditPrice,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      key: Key('sale_cart_line_${line.id}'),
      onTap: onSelect,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: selected
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.4)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    line.productName,
                    style: theme.textTheme.bodyLarge,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  key: Key('sale_cart_remove_${line.id}'),
                  tooltip: AppStringsTr.saleRemoveLine,
                  icon: const Icon(Icons.close, size: 18),
                  // REQ-UX-009 — satır silmek geri alınabilir, onay istemez
                  // (docs/23 §1).
                  onPressed: onRemove,
                ),
              ],
            ),
            Row(
              children: [
                IconButton(
                  key: Key('sale_cart_decrease_${line.id}'),
                  tooltip: AppStringsTr.saleDecrease,
                  icon: const Icon(Icons.remove, size: 16),
                  onPressed: onDecrease,
                ),
                Text(
                  '${line.quantity}',
                  key: Key('sale_cart_qty_${line.id}'),
                  style: theme.textTheme.titleSmall,
                ),
                IconButton(
                  key: Key('sale_cart_increase_${line.id}'),
                  tooltip: AppStringsTr.saleIncrease,
                  icon: const Icon(Icons.add, size: 16),
                  onPressed: onIncrease,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: InkWell(
                    key: Key('sale_cart_price_${line.id}'),
                    onTap: onEditPrice,
                    child: Text(
                      '× ${MoneyFormatter.format(line.unitPrice)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                Text(
                  MoneyFormatter.format(line.lineTotal),
                  key: Key('sale_cart_total_${line.id}'),
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (_badges(context).isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Wrap(spacing: 6, children: _badges(context)),
              ),
          ],
        ),
      ),
    );
  }

  /// Rozetler — rules/05 §5: renkle iletilen her durum **metinle de** ifade
  /// edilir.
  List<Widget> _badges(BuildContext context) {
    final theme = Theme.of(context);
    Widget badge(String text, Color color, Key key) => Text(
      text,
      key: key,
      style: theme.textTheme.labelSmall?.copyWith(color: color),
    );

    return [
      // docs/12 §4 — kullanıcının bilinçli tercihi.
      if (line.isPriceOverridden)
        badge(
          AppStringsTr.salePriceOverriddenBadge,
          theme.colorScheme.primary,
          Key('sale_badge_overridden_${line.id}'),
        ),
      // EC-CART-002 — ürünün fiyatı sepet dururken değişti; sepetteki fiyat
      // KORUNUR (REQ-CART-007), kararı kullanıcı verir.
      if (line.isPriceStale)
        badge(
          AppStringsTr.salePriceStaleBadge,
          theme.colorScheme.tertiary,
          Key('sale_badge_stale_${line.id}'),
        ),
      // BR-STOCK-006 — uyarı kapalı olsa bile satır işaretlenir (docs/13 §4).
      if (line.isOutOfStock)
        badge(
          AppStringsTr.saleOutOfStockBadge,
          theme.colorScheme.error,
          Key('sale_badge_stock_${line.id}'),
        ),
      // docs/12 §2.4 — pasifleşmiş ürün sepette kalır, işaretlenir.
      if (!line.isProductActive)
        badge(
          AppStringsTr.saleInactiveBadge,
          theme.colorScheme.error,
          Key('sale_badge_inactive_${line.id}'),
        ),
    ];
  }
}
