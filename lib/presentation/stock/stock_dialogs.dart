/// Stok işlemlerinin dialogları — **docs/13 §5–§6 · BR-STOCK-009/010**
///
/// ## `Esc` yolu ayrı bir koddur
///
/// `[Vazgeç]` açıkça `false`/`null` döndürür; `Esc` ve bariyer de `null`
/// döndürür. Her dönüş burada null-güvenlidir — aksi hâlde `Esc` sessizce
/// "onaylandı" sayılırdı ve BR-STOCK-009'da bu, kullanıcının onaylamadığı bir
/// **fiyat değişikliği** demek olurdu.
library;

import 'package:flutter/material.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';

/// BR-STOCK-009 · REQ-STOCK-008 — ürünün alış fiyatı da güncellensin mi?
///
/// `true` → evet. `Esc`/bariyer/hayır → `false`; yalnızca bu giriş o fiyatla
/// kaydedilir ve ürüne **dokunulmaz**.
Future<bool> askUpdatePurchasePrice(
  BuildContext context, {
  required String productName,
  required Money oldPrice,
  required Money newPrice,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('stock_cost_update_dialog'),
      title: const Text(AppStringsTr.stockEntryCostChangedTitle),
      content: Text(
        AppStringsTr.stockEntryCostChangedBody(
          productName,
          MoneyFormatter.format(oldPrice),
          MoneyFormatter.format(newPrice),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('stock_cost_update_no'),
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(AppStringsTr.stockEntryCostUpdateNo),
        ),
        FilledButton(
          key: const Key('stock_cost_update_yes'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(AppStringsTr.stockEntryCostUpdateYes),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Fire ve düzeltmenin ortak sonucu.
class StockReasonInput {
  final int quantity;
  final String reason;

  const StockReasonInput({required this.quantity, required this.reason});
}

/// docs/13 §6 — fire. **Sebep zorunludur** (BR-STOCK-010).
Future<StockReasonInput?> showWasteDialog(
  BuildContext context, {
  required String productName,
  required int currentStock,
}) {
  return showDialog<StockReasonInput>(
    context: context,
    builder: (_) => _StockReasonDialog(
      dialogKey: const Key('stock_waste_dialog'),
      title: '${AppStringsTr.stockWasteTitle} — $productName',
      quantityLabel: AppStringsTr.stockWasteQuantity,
      reasonLabel: AppStringsTr.stockWasteReason,
      submitLabel: AppStringsTr.stockWasteSave,
      currentStock: currentStock,
      // docs/13 §6 — fire için hazır sebep listesi vardır; düzeltmede serbest
      // metindir.
      suggestions: AppStringsTr.stockWasteReasons,
      requirePositive: true,
    ),
  );
}

/// docs/13 §6 — sayım düzeltmesi. Girilen değer **hedef stoktur**, fark değil.
Future<StockReasonInput?> showAdjustmentDialog(
  BuildContext context, {
  required String productName,
  required int currentStock,
}) {
  return showDialog<StockReasonInput>(
    context: context,
    builder: (_) => _StockReasonDialog(
      dialogKey: const Key('stock_adjust_dialog'),
      title: '${AppStringsTr.stockAdjustTitle} — $productName',
      quantityLabel: AppStringsTr.stockAdjustNew,
      reasonLabel: AppStringsTr.stockAdjustReason,
      submitLabel: AppStringsTr.stockAdjustSave,
      currentStock: currentStock,
      // Kullanıcı sayım sonucunu bilir; alan mevcut stokla dolu başlar.
      initialQuantity: currentStock,
      // Düzeltme yönü ± olabilir; negatif hedef stok da geçerlidir.
      requirePositive: false,
    ),
  );
}

class _StockReasonDialog extends StatefulWidget {
  final Key dialogKey;
  final String title;
  final String quantityLabel;
  final String reasonLabel;
  final String submitLabel;
  final int currentStock;
  final int? initialQuantity;
  final List<String> suggestions;
  final bool requirePositive;

  const _StockReasonDialog({
    required this.dialogKey,
    required this.title,
    required this.quantityLabel,
    required this.reasonLabel,
    required this.submitLabel,
    required this.currentStock,
    this.initialQuantity,
    this.suggestions = const [],
    this.requirePositive = true,
  });

  @override
  State<_StockReasonDialog> createState() => _StockReasonDialogState();
}

class _StockReasonDialogState extends State<_StockReasonDialog> {
  late final TextEditingController _quantity = TextEditingController(
    text: widget.initialQuantity?.toString() ?? '',
  );
  final TextEditingController _reason = TextEditingController();
  String? _quantityError;
  String? _reasonError;

  @override
  void dispose() {
    _quantity.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final quantity = int.tryParse(_quantity.text.trim());
    final reason = _reason.text.trim();

    setState(() {
      _quantityError =
          quantity == null || (widget.requirePositive && quantity <= 0)
          ? AppStringsTr.stockQuantityInvalid
          : null;
      // BR-STOCK-010 — sebep zorunludur. Boşluk da boştur.
      _reasonError = reason.isEmpty ? AppStringsTr.stockReasonRequired : null;
    });
    if (_quantityError != null || _reasonError != null) return;

    Navigator.of(
      context,
    ).pop(StockReasonInput(quantity: quantity!, reason: reason));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: widget.dialogKey,
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${AppStringsTr.stockAdjustCurrent}: ${widget.currentStock}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('stock_dialog_quantity'),
              controller: _quantity,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: widget.quantityLabel,
                errorText: _quantityError,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('stock_dialog_reason'),
              controller: _reason,
              decoration: InputDecoration(
                labelText: widget.reasonLabel,
                errorText: _reasonError,
              ),
              onSubmitted: (_) => _submit(),
            ),
            if (widget.suggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                children: [
                  for (final suggestion in widget.suggestions)
                    ActionChip(
                      key: Key('stock_reason_$suggestion'),
                      label: Text(suggestion),
                      onPressed: () => setState(() {
                        _reason.text = suggestion;
                        _reasonError = null;
                      }),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStringsTr.cancelAction),
        ),
        FilledButton(
          key: const Key('stock_dialog_submit'),
          onPressed: _submit,
          child: Text(widget.submitLabel),
        ),
      ],
    );
  }
}

/// REQ-STOCK-003 — hareket **silinmez**, ters kayıt açılır.
Future<String?> showReverseMovementDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _ReverseMovementDialog(),
  );
}

class _ReverseMovementDialog extends StatefulWidget {
  const _ReverseMovementDialog();

  @override
  State<_ReverseMovementDialog> createState() => _ReverseMovementDialogState();
}

class _ReverseMovementDialogState extends State<_ReverseMovementDialog> {
  final TextEditingController _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = _reason.text.trim();
    if (reason.isEmpty) {
      setState(() => _error = AppStringsTr.stockReasonRequired);
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('stock_reverse_dialog'),
      title: const Text(AppStringsTr.stockMovementReverseTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(AppStringsTr.stockMovementReverseBody),
            const SizedBox(height: 12),
            TextField(
              key: const Key('stock_reverse_reason'),
              controller: _reason,
              autofocus: true,
              decoration: InputDecoration(
                labelText: AppStringsTr.stockWasteReason,
                errorText: _error,
              ),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStringsTr.cancelAction),
        ),
        FilledButton(
          key: const Key('stock_reverse_submit'),
          onPressed: _submit,
          child: const Text(AppStringsTr.stockMovementReverse),
        ),
      ],
    );
  }
}

/// docs/13 §5 — satırın **alış fiyatını** düzenler.
///
/// Satış ekranındaki fiyat dialogundan ayrıdır: orada değiştirilen KDV dahil
/// **satış** fiyatıdır, burada ise **alış** fiyatı. İkisini tek dialogda
/// birleştirmek etiketleri belirsizleştirirdi.
Future<Money?> showPriceOverrideDialogForCost(
  BuildContext context, {
  required String productName,
  required Money currentCost,
}) {
  return showDialog<Money>(
    context: context,
    builder: (_) =>
        _CostDialog(productName: productName, currentCost: currentCost),
  );
}

class _CostDialog extends StatefulWidget {
  final String productName;
  final Money currentCost;

  const _CostDialog({required this.productName, required this.currentCost});

  @override
  State<_CostDialog> createState() => _CostDialogState();
}

class _CostDialogState extends State<_CostDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: MoneyFormatter.format(widget.currentCost),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = MoneyParser.tryParse(_controller.text);
    // Alış fiyatı `>= 0`; `0` geçerlidir (bağış/promosyon ürünü).
    if (parsed == null || parsed.isNegative) {
      setState(() => _error = AppStringsTr.salePriceInvalid);
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('stock_cost_dialog'),
      title: Text(
        '${AppStringsTr.stockEntryColumnCost} — ${widget.productName}',
      ),
      content: TextField(
        key: const Key('stock_cost_field'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(
          labelText: AppStringsTr.stockEntryColumnCost,
          errorText: _error,
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStringsTr.cancelAction),
        ),
        FilledButton(
          key: const Key('stock_cost_submit'),
          onPressed: _submit,
          child: const Text(AppStringsTr.salePriceApply),
        ),
      ],
    );
  }
}
