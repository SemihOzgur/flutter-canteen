/// İptal ve iade dialogları — **docs/14 §3–§4**
///
/// ## `Esc` yolu ayrı bir koddur
///
/// İkisi de **geri alınamaz** işlemlerdir (REQ-UX-009). `[Vazgeç]` açıkça
/// `null` döndürür, `Esc` ve bariyer de `null` döndürür — dönüş tipleri
/// nullable olduğu için sessiz bir "onaylandı" yolu **yoktur**.
library;

import 'package:flutter/material.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../domain/models/sale.dart';
import '../../domain/models/sale_return.dart';

/// docs/14 §3 — satış iptali. Vazgeçilirse `null`; **sebep zorunludur**.
Future<String?> showCancelSaleDialog(
  BuildContext context, {
  required String saleNumber,
  required Money total,
  required int itemCount,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _CancelSaleDialog(
      saleNumber: saleNumber,
      total: total,
      itemCount: itemCount,
    ),
  );
}

class _CancelSaleDialog extends StatefulWidget {
  final String saleNumber;
  final Money total;
  final int itemCount;

  const _CancelSaleDialog({
    required this.saleNumber,
    required this.total,
    required this.itemCount,
  });

  @override
  State<_CancelSaleDialog> createState() => _CancelSaleDialogState();
}

class _CancelSaleDialogState extends State<_CancelSaleDialog> {
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
      // docs/18 §3 — `saleCancelled` metadata'sı sebebi ŞART KOŞAR:
      // "bu satış neden iptal edildi?" denetim izinden yanıtlanmalıdır.
      setState(() => _error = AppStringsTr.stockReasonRequired);
      return;
    }
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('sale_cancel_dialog'),
      title: Text(AppStringsTr.saleCancelTitle(widget.saleNumber)),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStringsTr.saleCancelSummary(
                MoneyFormatter.format(widget.total),
                widget.itemCount,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '⚠ ${AppStringsTr.saleCancelWarning}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('sale_cancel_reason'),
              controller: _reason,
              autofocus: true,
              decoration: InputDecoration(
                labelText: AppStringsTr.saleCancelReason,
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
          key: const Key('sale_cancel_submit'),
          onPressed: _submit,
          child: const Text(AppStringsTr.saleCancelConfirm),
        ),
      ],
    );
  }
}

/// İade formunun sonucu.
class ReturnRequest {
  final List<ReturnLineRequest> lines;
  final String? reason;

  const ReturnRequest({required this.lines, this.reason});
}

/// docs/14 §4 — kısmi iade. Vazgeçilirse `null`.
///
/// Her satır **kalan miktarla** sınırlıdır (BR-RET-003) ve iade tutarı
/// **satış anındaki fiyattan** canlı hesaplanır (BR-RET-005).
Future<ReturnRequest?> showReturnDialog(
  BuildContext context, {
  required String saleNumber,
  required List<SaleItem> items,
}) {
  return showDialog<ReturnRequest>(
    context: context,
    builder: (_) => _ReturnDialog(saleNumber: saleNumber, items: items),
  );
}

class _ReturnDialog extends StatefulWidget {
  final String saleNumber;
  final List<SaleItem> items;

  const _ReturnDialog({required this.saleNumber, required this.items});

  @override
  State<_ReturnDialog> createState() => _ReturnDialogState();
}

class _ReturnDialogState extends State<_ReturnDialog> {
  /// saleItemId → iade edilecek miktar.
  final Map<int, int> _quantities = {};
  final TextEditingController _reason = TextEditingController();

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// BR-RET-005 — tutar **orijinal snapshot fiyattan** hesaplanır.
  ///
  /// Ekran yalnızca ÖNİZLEME yapar; kesin tutarı servis yeniden hesaplar
  /// (rules/05 §3 — UI'da finansal hesaplama yapılmaz, burada yalnızca aynı
  /// domain değerleri toplanır).
  Money get _total => Money.sum([
    for (final item in widget.items)
      item.unitPrice * (_quantities[item.id] ?? 0),
  ]);

  int get _unitCount =>
      _quantities.values.fold(0, (sum, quantity) => sum + quantity);

  void _setQuantity(SaleItem item, int value) {
    // BR-RET-003 — kalan miktarı aşamaz.
    //
    // **İKİNCİ savunma hattıdır.** `+` düğmesi sınırda zaten pasifleşir, bu
    // yüzden mutasyon testi bu satırı kaldırınca hiçbir test kırılmıyor.
    // Yine de duruyor: sınır bir 🔴 business kuralıdır (BR-RET-003) ve tek
    // dayanağının bir düğmenin `onPressed: null` olması kabul edilemez.
    // Servis de aynı kuralı ayrıca uygular (`ReturnFailures.exceedsRemaining`)
    // — üç katman, çünkü aşılırsa şemadaki CHECK anlaşılmaz bir hatayla
    // patlar.
    final clamped = value.clamp(0, item.remainingQuantity);
    setState(() {
      if (clamped == 0) {
        _quantities.remove(item.id);
      } else {
        _quantities[item.id] = clamped;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      key: const Key('sale_return_dialog'),
      title: Text(AppStringsTr.saleReturnTitle(widget.saleNumber)),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final item in widget.items) _lineTile(theme, item),
                ],
              ),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStringsTr.saleReturnTotal,
                      style: theme.textTheme.titleSmall,
                    ),
                    Text(
                      AppStringsTr.saleReturnPriceNote,
                      style: theme.textTheme.labelSmall,
                    ),
                  ],
                ),
                Text(
                  MoneyFormatter.format(_total),
                  key: const Key('sale_return_total'),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('sale_return_reason'),
              controller: _reason,
              decoration: const InputDecoration(
                labelText: AppStringsTr.saleReturnReason,
              ),
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
          key: const Key('sale_return_submit'),
          // docs/14 §4 — toplam iade miktarı `> 0` olmalıdır.
          onPressed: _unitCount == 0
              ? null
              : () => Navigator.of(context).pop(
                  ReturnRequest(
                    lines: [
                      for (final entry in _quantities.entries)
                        ReturnLineRequest(
                          saleItemId: entry.key,
                          quantity: entry.value,
                        ),
                    ],
                    reason: _reason.text.trim().isEmpty
                        ? null
                        : _reason.text.trim(),
                  ),
                ),
          child: const Text(AppStringsTr.saleReturnSave),
        ),
      ],
    );
  }

  Widget _lineTile(ThemeData theme, SaleItem item) {
    final selected = _quantities[item.id] ?? 0;
    final remaining = item.remainingQuantity;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.productNameSnapshot),
                Text(
                  MoneyFormatter.format(item.unitPrice),
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ),
          Expanded(
            child: Text('${item.quantity}', textAlign: TextAlign.center),
          ),
          Expanded(
            child: Text(
              '${item.returnedQuantity}',
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: remaining == 0
                // İade edilecek miktar kalmamışsa alan HİÇ sunulmaz
                // (docs/14 §8: "iade miktarı alanı 0 ile sınırlıdır").
                ? Text(
                    AppStringsTr.saleHistoryReturnedBadge,
                    key: Key('sale_return_exhausted_${item.id}'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall,
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        key: Key('sale_return_dec_${item.id}'),
                        icon: const Icon(Icons.remove, size: 16),
                        onPressed: selected == 0
                            ? null
                            : () => _setQuantity(item, selected - 1),
                      ),
                      Text(
                        '$selected',
                        key: Key('sale_return_qty_${item.id}'),
                        style: theme.textTheme.titleSmall,
                      ),
                      IconButton(
                        key: Key('sale_return_inc_${item.id}'),
                        icon: const Icon(Icons.add, size: 16),
                        // BR-RET-003 — kalan miktarda durur.
                        onPressed: selected >= remaining
                            ? null
                            : () => _setQuantity(item, selected + 1),
                      ),
                      Text(
                        AppStringsTr.saleReturnMax(remaining),
                        style: theme.textTheme.labelSmall,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
