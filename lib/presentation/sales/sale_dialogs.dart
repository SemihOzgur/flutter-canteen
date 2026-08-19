/// Satış ekranının dialogları — **docs/12 §4–§5 · docs/13 §4 · docs/11 §4.2–4.3**
///
/// ## Esc yolu ayrı bir koddur
///
/// Her dialog `Navigator.pop(false)` ile açıkça vazgeçer; `Esc` ve bariyer
/// tıklaması ise `null` döndürür. İkisi **ayrı kod yollarıdır** — `?? false`
/// olmadan `Esc` sessizce "onaylandı" sayılırdı. Bu dosyadaki her dönüş
/// değeri bu yüzden null-güvenlidir ve testleri de ikisini ayrı ayrı sınar.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../domain/models/product.dart';

/// docs/13 §4 · BR-STOCK-006 — **engelleyici değildir.**
///
/// `true` → kullanıcı "Devam Et" dedi. `Esc`/bariyer/İptal → `false`.
Future<bool> showStockWarningDialog(
  BuildContext context, {
  required String productName,
  required int stockQuantity,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('sale_stock_warning_dialog'),
      title: const Text('⚠ ${AppStringsTr.saleStockWarningTitle}'),
      content: Text(
        AppStringsTr.saleStockWarningBody(productName, stockQuantity),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(AppStringsTr.cancelAction),
        ),
        FilledButton(
          key: const Key('sale_stock_warning_continue'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(AppStringsTr.saleStockWarningContinue),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// docs/11 §4.3 — pasif ürün okutuldu.
Future<bool> showInactiveProductDialog(
  BuildContext context, {
  required String productName,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('sale_inactive_product_dialog'),
      title: Text(AppStringsTr.saleInactiveProductTitle(productName)),
      content: const Text(AppStringsTr.saleInactiveProductBody),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(AppStringsTr.cancelAction),
        ),
        FilledButton(
          key: const Key('sale_inactive_product_activate'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(AppStringsTr.saleInactiveProductActivate),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// REQ-UX-009 — sepeti temizlemek geri alınamaz, onay ister.
Future<bool> showClearCartDialog(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('sale_clear_dialog'),
      title: const Text(AppStringsTr.saleClearTitle),
      content: const Text(AppStringsTr.saleClearMessage),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text(AppStringsTr.cancelAction),
        ),
        FilledButton(
          key: const Key('sale_clear_confirm'),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: const Text(AppStringsTr.saleClearConfirm),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// REQ-UX-010 — tüm kısayollar `F1` ekranında listelenir.
Future<void> showShortcutsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      key: const Key('sale_shortcuts_dialog'),
      title: const Text(AppStringsTr.saleShortcutsTitle),
      content: SizedBox(
        width: 460,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final (key, description) in AppStringsTr.saleShortcuts)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        key,
                        style: const TextStyle(fontFeatures: []),
                      ),
                    ),
                    Expanded(child: Text(description)),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text(AppStringsTr.saleShortcutsClose),
        ),
      ],
    ),
  );
}

/// docs/12 §4 — satır fiyatı değiştirme. Vazgeçilirse `null`.
///
/// EC-SALE-006 `0` fiyatı kabul eder (ikram); EC-SALE-007 negatifi reddeder.
/// Ayrıştırma `core/money`'deki **tek** parser'a devredilir (rules/01 §2).
Future<Money?> showPriceOverrideDialog(
  BuildContext context, {
  required String productName,
  required Money listPrice,
  required Money currentPrice,
}) {
  return showDialog<Money>(
    context: context,
    builder: (dialogContext) => _PriceOverrideDialog(
      productName: productName,
      listPrice: listPrice,
      currentPrice: currentPrice,
    ),
  );
}

class _PriceOverrideDialog extends StatefulWidget {
  final String productName;
  final Money listPrice;
  final Money currentPrice;

  const _PriceOverrideDialog({
    required this.productName,
    required this.listPrice,
    required this.currentPrice,
  });

  @override
  State<_PriceOverrideDialog> createState() => _PriceOverrideDialogState();
}

class _PriceOverrideDialogState extends State<_PriceOverrideDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: MoneyFormatter.format(widget.currentPrice),
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = MoneyParser.tryParse(_controller.text);
    // EC-SALE-007 — negatif reddedilir; EC-SALE-006 — `0` kabul edilir.
    if (parsed == null || parsed.isNegative) {
      setState(() => _error = AppStringsTr.salePriceInvalid);
      return;
    }
    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('sale_price_dialog'),
      title: Text(AppStringsTr.salePriceDialogTitle(widget.productName)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStringsTr.salePriceListLabel(
              MoneyFormatter.format(widget.listPrice),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('sale_price_field'),
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: AppStringsTr.salePriceNewLabel,
              errorText: _error,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Text(
            '⚠ ${AppStringsTr.salePriceDialogNotice}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStringsTr.cancelAction),
        ),
        FilledButton(
          key: const Key('sale_price_apply'),
          onPressed: _submit,
          child: const Text(AppStringsTr.salePriceApply),
        ),
      ],
    );
  }
}

/// docs/12 §5 — nakit hesaplama. Vazgeçilirse `null`.
///
/// BR-SALE-007: **opsiyoneldir ve satışı bloklamaz.** BR-SALE-008: alınan
/// toplamdan azsa "Tamamla" pasiftir (EC-SALE-009). EC-SALE-010: büyük tutar
/// reddedilmez.
Future<Money?> showCashDialog(BuildContext context, {required Money total}) {
  return showDialog<Money>(
    context: context,
    builder: (dialogContext) => _CashDialog(total: total),
  );
}

class _CashDialog extends StatefulWidget {
  final Money total;

  const _CashDialog({required this.total});

  @override
  State<_CashDialog> createState() => _CashDialogState();
}

class _CashDialogState extends State<_CashDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Money? get _received => MoneyParser.tryParse(_controller.text);

  /// docs/12 §5 — para üstü **canlı** hesaplanır.
  Money? get _change {
    final received = _received;
    if (received == null || received < widget.total) return null;
    return received - widget.total;
  }

  /// docs/12 §5 — akıllı öneriler: toplamın üstündeki yuvarlak tutarlar.
  ///
  /// Kasiyerin en sık aldığı banknotlar üretilir; toplamın altındakiler
  /// elenir çünkü BR-SALE-008 onları zaten reddeder.
  List<Money> get _suggestions {
    const steps = [5000, 10000, 20000, 50000, 100000, 20000000];
    final total = widget.total.minor;
    final values = <int>{};
    for (final step in steps) {
      final rounded = ((total + step - 1) ~/ step) * step;
      if (rounded > total) values.add(rounded);
      if (values.length >= 3) break;
    }
    final sorted = values.toList()..sort();
    return sorted.map(Money.new).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final change = _change;
    final received = _received;
    final insufficient = received != null && received < widget.total;

    return AlertDialog(
      key: const Key('sale_cash_dialog'),
      title: const Text(AppStringsTr.saleCashTitle),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(AppStringsTr.saleCashTotal),
                Text(
                  MoneyFormatter.format(widget.total),
                  style: theme.textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('sale_cash_field'),
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: AppStringsTr.saleCashReceived,
                errorText: insufficient
                    ? AppStringsTr.saleCashInsufficient
                    : null,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (change != null) Navigator.of(context).pop(_received);
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(AppStringsTr.saleCashChange),
                Text(
                  key: const Key('sale_cash_change'),
                  change == null ? '—' : MoneyFormatter.format(change),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (final suggestion in _suggestions)
                  OutlinedButton(
                    onPressed: () => setState(() {
                      _controller.text = MoneyFormatter.format(suggestion);
                    }),
                    child: Text(MoneyFormatter.format(suggestion)),
                  ),
                OutlinedButton(
                  key: const Key('sale_cash_exact'),
                  onPressed: () => setState(() {
                    _controller.text = MoneyFormatter.format(widget.total);
                  }),
                  child: const Text(AppStringsTr.saleCashExact),
                ),
              ],
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
          key: const Key('sale_cash_submit'),
          // BR-SALE-008 · EC-SALE-009 — yetersiz tutarda pasiftir.
          onPressed: change == null
              ? null
              : () => Navigator.of(context).pop(received),
          child: const Text(AppStringsTr.saleCompleteAction),
        ),
      ],
    );
  }
}

/// docs/11 §4.2 · REQ-BARC-006/007 — bilinmeyen barkod → hızlı ürün.
///
/// Barkod alanı **dolu ve salt okunur**; kullanıcı yalnızca ad ve fiyat girer.
/// Vazgeçilirse `null` döner: ürün oluşmaz, sepete bir şey eklenmez.
Future<QuickProductDraft?> showQuickProductDialog(
  BuildContext context, {
  required String barcode,
}) {
  return showDialog<QuickProductDraft>(
    context: context,
    builder: (dialogContext) => _QuickProductDialog(barcode: barcode),
  );
}

/// Hızlı ürün ekleme formunun sonucu.
///
/// Alış fiyatı **yoktur**: hızlı eklemede boş bırakılabilir ve `0` kaydedilir
/// (rules/02 §9 — asla `null`). Kategori de sorulmaz; `Genel` sistem
/// kategorisi kullanılır (BR-PROD-003).
class QuickProductDraft {
  final String name;
  final Money salePrice;
  final String barcode;

  const QuickProductDraft({
    required this.name,
    required this.salePrice,
    required this.barcode,
  });
}

class _QuickProductDialog extends StatefulWidget {
  final String barcode;

  const _QuickProductDialog({required this.barcode});

  @override
  State<_QuickProductDialog> createState() => _QuickProductDialogState();
}

class _QuickProductDialogState extends State<_QuickProductDialog> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _price = TextEditingController();
  String? _nameError;
  String? _priceError;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    final price = MoneyParser.tryParse(_price.text);

    setState(() {
      _nameError = name.isEmpty ? AppStringsTr.saleQuickAddNameRequired : null;
      // BR-PROD-006 — satış fiyatı `>= 0` (0 = ikram ürünü).
      _priceError = price == null || price.isNegative
          ? AppStringsTr.salePriceInvalid
          : null;
    });
    if (_nameError != null || _priceError != null) return;

    Navigator.of(context).pop(
      QuickProductDraft(name: name, salePrice: price!, barcode: widget.barcode),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('sale_quick_product_dialog'),
      title: const Text(AppStringsTr.saleQuickAddTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(AppStringsTr.saleQuickAddIntro),
            const SizedBox(height: 12),
            TextField(
              key: const Key('sale_quick_barcode_field'),
              // REQ-BARC-006 — barkod alanı OTOMATİK DOLU ve salt okunur.
              readOnly: true,
              controller: TextEditingController(text: widget.barcode),
              decoration: const InputDecoration(
                labelText: AppStringsTr.saleQuickAddBarcode,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('sale_quick_name_field'),
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(
                labelText: AppStringsTr.saleQuickAddName,
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('sale_quick_price_field'),
              controller: _price,
              decoration: InputDecoration(
                labelText: AppStringsTr.saleQuickAddPrice,
                errorText: _priceError,
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
          key: const Key('sale_quick_submit'),
          onPressed: _submit,
          child: const Text(AppStringsTr.saleQuickAddSubmit),
        ),
      ],
    );
  }
}

/// Ürün kartının stok rozetini üretir — docs/13 §4 "satış ekranı ürün kartı".
///
/// Renkle iletilen her durum **ikon veya metinle de** ifade edilir
/// (rules/05 §5).
Widget? stockBadge(BuildContext context, Product product) {
  if (product.stockQuantity > 0) return null;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(
        Icons.warning_amber_rounded,
        size: 14,
        color: Theme.of(context).colorScheme.error,
      ),
      const SizedBox(width: 2),
      Flexible(
        child: Text(
          AppStringsTr.saleOutOfStockBadge,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.error,
          ),
        ),
      ),
    ],
  );
}

/// `Esc` her dialogu kapatır — docs/23 §2.
///
/// Flutter'ın `Navigator`'ı bunu zaten yapar; sabit yalnızca testlerin aynı
/// tuşu kullanmasını sağlar.
const LogicalKeyboardKey escapeKey = LogicalKeyboardKey.escape;
