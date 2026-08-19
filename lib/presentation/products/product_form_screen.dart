/// Ürün formu — **docs/09 §1, §2.2, §3 · REQ-PROD-001…008, 011…015**
///
/// | Alan | Kural |
/// |---|---|
/// | Satış fiyatı etiketi **"KDV Dahil"** | **REQ-PROD-014** — gereksinim, tercih değil |
/// | Alış fiyatı boş → `₺0,00` | BR-PROD-002 |
/// | Kategori boş → `Genel` | BR-PROD-003 |
/// | Gramaj değeri + birimi **birlikte** | BR-PROD-011 · EC-PROD-018 |
/// | **Stok düzenlenemez** | docs/09 §1 · BR-STOCK-003 |
/// | Başlangıç stoğu yalnızca **eklemede** | REQ-PROD-007 |
/// | %50+ fiyat değişikliğinde onay | REQ-PROD-012 |
///
/// ## Uyarılar burada hesaplanmaz
///
/// rules/05 §8: UI iş kuralı değerlendirmez. Alış > satış (EC-PROD-009), aynı
/// ad + kategori (EC-PROD-010), EAN-13 checksum (EC-PROD-015) ve %50 fiyat
/// eşiği (REQ-PROD-012) **servisten** `ProductWarning` olarak gelir; bu ekran
/// yalnızca gösterir. Eşiği burada yeniden hesaplamak `rules/01 §2`'nin tek
/// implementasyon kuralını bozardı.
///
/// ## Stok alanı neden salt okunur
///
/// docs/09 §1: "Ürün formundaki 'Stok' alanı düzenlenebilir değildir."
/// `stock_quantity` türetilmiş bir önbellektir; yalnızca stok hareketiyle
/// değişir (BR-STOCK-002/003). Forma yazılabilir bir alan koymak invariant'ı
/// ilk günden delerdi.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/product/product_draft.dart';
import '../../application/product/product_service.dart';
import '../../application/product/product_warnings.dart';
import '../../application/product/providers.dart';
import '../../application/reference/providers.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../core/result/result.dart';
import '../../domain/models/product.dart';
import '../../domain/services/product_rules.dart';
import '../common/current_user.dart';
import '../common/form_message.dart';
import '../common/submit_button.dart';

class ProductFormScreen extends ConsumerStatefulWidget {
  static const Key nameFieldKey = Key('product_form_name');
  static const Key salePriceFieldKey = Key('product_form_sale_price');
  static const Key purchasePriceFieldKey = Key('product_form_purchase_price');
  static const Key initialStockFieldKey = Key('product_form_initial_stock');
  static const Key stockReadOnlyKey = Key('product_form_stock_readonly');
  static const Key minimumStockFieldKey = Key('product_form_minimum_stock');
  static const Key barcodeFieldKey = Key('product_form_barcode');
  static const Key barcodeAddKey = Key('product_form_barcode_add');
  static const Key submitKey = Key('product_form_submit');
  static const Key messageKey = Key('product_form_message');
  static const Key warningsKey = Key('product_form_warnings');
  static const Key priceChangeConfirmKey = Key('product_price_change_confirm');
  static const Key priceChangeCancelKey = Key('product_price_change_cancel');

  static Key barcodeRemoveKey(String barcode) =>
      ValueKey('product_barcode_remove_$barcode');

  /// `null` ise ekleme, doluysa düzenleme formudur.
  final Product? product;

  const ProductFormScreen({this.product, super.key});

  @override
  ConsumerState<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends ConsumerState<ProductFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _brand;
  late final TextEditingController _salesUnit;
  late final TextEditingController _netWeightValue;
  late final TextEditingController _salePrice;
  late final TextEditingController _purchasePrice;
  late final TextEditingController _minimumStock;
  late final TextEditingController _shelfLocation;
  final TextEditingController _initialStock = TextEditingController(text: '0');
  final TextEditingController _barcode = TextEditingController();

  String? _netWeightUnit;
  int? _categoryId;
  int? _vatRateId;
  int? _supplierId;

  /// Eklemede ürünle **birlikte** yazılır; düzenlemede servise anında gider.
  List<String> _barcodes = const [];

  String? _message;
  List<ProductWarning> _warnings = const [];

  bool get _isEdit => widget.product != null;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _name = TextEditingController(text: p?.name ?? '');
    _description = TextEditingController(text: p?.description ?? '');
    _brand = TextEditingController(text: p?.brand ?? '');
    _salesUnit = TextEditingController(text: p?.salesUnit ?? '');
    _netWeightValue = TextEditingController(
      text: p?.netWeightValue?.toString() ?? '',
    );
    _salePrice = TextEditingController(
      text: p == null ? '' : MoneyFormatter.format(p.salePrice),
    );
    _purchasePrice = TextEditingController(
      text: p == null ? '' : MoneyFormatter.format(p.purchasePrice),
    );
    _minimumStock = TextEditingController(
      text: (p?.minimumStock ?? 0).toString(),
    );
    _shelfLocation = TextEditingController(text: p?.shelfLocation ?? '');
    _netWeightUnit = p?.netWeightUnit;
    _categoryId = p?.categoryId;
    _vatRateId = p?.vatRateId;
    _supplierId = p?.supplierId;

    if (p != null) _loadBarcodes(p.id);
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _brand,
      _salesUnit,
      _netWeightValue,
      _salePrice,
      _purchasePrice,
      _minimumStock,
      _shelfLocation,
      _initialStock,
      _barcode,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadBarcodes(int productId) async {
    final list = await ref.read(productServiceProvider).barcodesOf(productId);
    if (!mounted) return;
    setState(() => _barcodes = list);
  }

  // --- Girdi çözümleme -----------------------------------------------------

  /// REQ-FIN-006 — `25,50` · `25.50` · `25` · `₺25,50` kabul edilir.
  /// Çözümleme `MoneyParser`'dadır; burada ikinci bir kural yazılmaz.
  Money? _parseMoney(String raw, {required bool allowEmpty}) {
    final text = raw.trim();
    if (text.isEmpty) return allowEmpty ? Money.zero : null;
    return MoneyParser.tryParse(text);
  }

  int? _parseInt(String raw, {required bool allowEmpty}) {
    final text = raw.trim();
    if (text.isEmpty) return allowEmpty ? 0 : null;
    return int.tryParse(text);
  }

  ProductDraft? _buildDraft() {
    final salePrice = _parseMoney(_salePrice.text, allowEmpty: false);
    if (salePrice == null) return null;
    final purchasePrice = _parseMoney(_purchasePrice.text, allowEmpty: true);
    if (purchasePrice == null) return null;
    final minimumStock = _parseInt(_minimumStock.text, allowEmpty: true);
    if (minimumStock == null) return null;

    final weightText = _netWeightValue.text.trim();
    final weight = weightText.isEmpty ? null : int.tryParse(weightText);
    if (weightText.isNotEmpty && weight == null) return null;

    String? nullIfBlank(String value) =>
        value.trim().isEmpty ? null : value.trim();

    return ProductDraft(
      name: _name.text,
      description: nullIfBlank(_description.text),
      categoryId: _categoryId,
      brand: nullIfBlank(_brand.text),
      salesUnit: nullIfBlank(_salesUnit.text),
      netWeightValue: weight,
      netWeightUnit: _netWeightUnit,
      purchasePrice: purchasePrice,
      salePrice: salePrice,
      vatRateId: _vatRateId,
      minimumStock: minimumStock,
      supplierId: _supplierId,
      shelfLocation: nullIfBlank(_shelfLocation.text),
    );
  }

  // --- Barkodlar -----------------------------------------------------------

  Future<void> _addBarcode() async {
    final raw = _barcode.text.trim();
    if (raw.isEmpty) return;
    setState(() => _message = null);

    // EC-PROD-003 — aynı barkod aynı üründe: sessizce yok sayılır.
    if (_barcodes.contains(raw)) {
      _barcode.clear();
      return;
    }

    if (!_isEdit) {
      // Kaydedilmemiş ürün: barkodlar ürünle BİRLİKTE yazılır (tek transaction).
      setState(() {
        _barcodes = [..._barcodes, raw];
        _barcode.clear();
      });
      return;
    }

    final userId = await _requireUserId();
    if (userId == null) return;

    final result = await ref
        .read(productServiceProvider)
        .addBarcode(widget.product!.id, raw, userId: userId);
    if (!mounted) return;

    switch (result) {
      case Err(:final failure):
        // EC-PROD-001 — sahip ürünün adı mesajın içindedir; "Ürüne Git"
        // eylemi de sunulur.
        setState(() => _message = failure.userMessage);
      case Ok(:final value):
        _barcode.clear();
        setState(() => _warnings = value);
        await _loadBarcodes(widget.product!.id);
    }
  }

  Future<void> _removeBarcode(String barcode) async {
    setState(() => _message = null);

    if (!_isEdit) {
      setState(() => _barcodes = [..._barcodes]..remove(barcode));
      return;
    }

    final userId = await _requireUserId();
    if (userId == null) return;

    // EC-PROD-016 — son barkod da silinebilir; ürün barkodsuz kalır.
    final result = await ref
        .read(productServiceProvider)
        .removeBarcode(widget.product!.id, barcode, userId: userId);
    if (!mounted) return;

    switch (result) {
      case Err(:final failure):
        setState(() => _message = failure.userMessage);
      case Ok<void>():
        await _loadBarcodes(widget.product!.id);
    }
  }

  // --- Kaydetme ------------------------------------------------------------

  Future<int?> _requireUserId() async {
    final userId = await currentUserId(ref);
    if (userId == null && mounted) {
      setState(() => _message = AppStringsTr.sessionRequiredMessage);
    }
    return userId;
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _message = null;
      _warnings = const [];
    });

    final draft = _buildDraft();
    if (draft == null) return;

    final service = ref.read(productServiceProvider);

    // REQ-PROD-012 — %50+ fiyat değişikliği onay ister. Eşiği SERVİS
    // hesaplar (`ProductRules.isSignificantPriceChange`); ekran yalnızca
    // uyarının varlığına bakar.
    final preview = await service.previewWarnings(
      draft,
      productId: widget.product?.id,
    );
    if (!mounted) return;

    final largeChange = preview
        .where((w) => w.code == ProductWarnings.largePriceChange.code)
        .firstOrNull;
    if (largeChange != null && !await _confirmPriceChange(largeChange)) return;

    final userId = await _requireUserId();
    if (userId == null) return;

    final result = _isEdit
        ? await service.update(widget.product!.id, draft, userId: userId)
        : await service.create(
            draft,
            userId: userId,
            initialStock: _parseInt(_initialStock.text, allowEmpty: true) ?? 0,
            barcodes: _barcodes,
          );
    if (!mounted) return;

    switch (result) {
      case Err(:final failure):
        setState(() => _message = failure.userMessage);
      case Ok<ProductSaveOutcome>(:final value):
        // EC-PROD-009/010/015 — uyarılar kaydı ENGELLEMEZ; kullanıcıya
        // kaydedildikten sonra gösterilir.
        if (value.warnings.isNotEmpty) {
          for (final warning in value.warnings) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(warning.message)));
          }
        }
        Navigator.of(context).pop(true);
    }
  }

  /// REQ-PROD-012 — onay dialogu.
  ///
  /// ⚠️ İptalin **üç yolu** vardır ve üçü de değişikliği engellemelidir:
  /// `[Vazgeç]` butonu, `Esc` ve bariyer. `showDialog` son ikisinde `null`
  /// döndürür; varsayılan bu yüzden `?? false`'tur — `?? true` olsaydı `Esc`'e
  /// basan kullanıcının fiyatı sessizce değişirdi.
  Future<bool> _confirmPriceChange(ProductWarning warning) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStringsTr.productPriceChangeTitle),
        content: Text(warning.message),
        actions: [
          TextButton(
            key: ProductFormScreen.priceChangeCancelKey,
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text(AppStringsTr.cancelAction),
          ),
          FilledButton(
            key: ProductFormScreen.priceChangeConfirmKey,
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(AppStringsTr.productPriceChangeConfirmAction),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  // --- Görünüm -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final categories = ref.watch(categoryListProvider).valueOrNull ?? const [];
    final suppliers = ref.watch(supplierListProvider).valueOrNull ?? const [];
    final vatRates = ref.watch(vatRateListProvider).valueOrNull ?? const [];

    // Referans listeleri **asenkron** gelir. İlk karede henüz boşken seçili
    // kimliği dropdown'a vermek Flutter'ın "tam olarak bir eşleşen öğe
    // olmalı" assertion'ını patlatır ve düzenleme formu açılmaz. Değer ancak
    // karşılığı listede varsa verilir.
    int? presentOrNull(int? id, Iterable<int> available) =>
        id != null && available.contains(id) ? id : null;
    final vatDisabled = ref.watch(vatDisabledProvider).valueOrNull ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEdit
              ? AppStringsTr.productEditTitle
              : AppStringsTr.productAddTitle,
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            _section(AppStringsTr.productTabGeneral),
            TextFormField(
              key: ProductFormScreen.nameFieldKey,
              controller: _name,
              autofocus: true,
              maxLength: ProductRules.nameMaxLength,
              decoration: const InputDecoration(
                labelText: AppStringsTr.productNameLabel,
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? AppStringsTr.productNameRequired
                  : null,
            ),
            TextFormField(
              controller: _description,
              maxLength: ProductRules.descriptionMaxLength,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: AppStringsTr.productDescriptionLabel,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              initialValue: presentOrNull(
                _categoryId,
                categories.map((c) => c.id),
              ),
              decoration: const InputDecoration(
                labelText: AppStringsTr.productCategoryLabel,
                helperText: AppStringsTr.productCategoryDefaultHint,
              ),
              items: [
                const DropdownMenuItem<int?>(
                  child: Text(AppStringsTr.productCategoryDefaultOption),
                ),
                // EC-PROD-005 — pasif kategori seçili kalabilir ve
                // "(pasif)" etiketiyle gösterilir; ürün geçerliliğini korur.
                for (final c in categories)
                  DropdownMenuItem<int?>(
                    value: c.id,
                    child: Text(
                      c.isActive
                          ? c.name
                          : AppStringsTr.inactiveOptionLabel(c.name),
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _categoryId = value),
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _brand,
              decoration: const InputDecoration(
                labelText: AppStringsTr.productBrandLabel,
              ),
            ),
            TextFormField(
              controller: _salesUnit,
              decoration: const InputDecoration(
                labelText: AppStringsTr.productSalesUnitLabel,
                helperText: AppStringsTr.productSalesUnitHint,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _netWeightValue,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: AppStringsTr.productNetWeightValueLabel,
                      helperText: AppStringsTr.productNetWeightHint,
                    ),
                    validator: (value) {
                      final text = (value ?? '').trim();
                      if (text.isEmpty) return null;
                      return int.tryParse(text) == null
                          ? AppStringsTr.productNetWeightInvalid
                          : null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _netWeightUnit,
                    decoration: const InputDecoration(
                      labelText: AppStringsTr.productNetWeightUnitLabel,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(child: Text('—')),
                      for (final unit in ProductRules.netWeightUnitSuggestions)
                        DropdownMenuItem<String?>(
                          value: unit,
                          child: Text(unit),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _netWeightUnit = value),
                  ),
                ),
              ],
            ),
            TextFormField(
              controller: _shelfLocation,
              maxLength: ProductRules.shelfLocationMaxLength,
              decoration: const InputDecoration(
                labelText: AppStringsTr.productShelfLocationLabel,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<int?>(
              initialValue: presentOrNull(
                _supplierId,
                suppliers.map((s) => s.id),
              ),
              decoration: const InputDecoration(
                labelText: AppStringsTr.productSupplierLabel,
              ),
              items: [
                const DropdownMenuItem<int?>(
                  child: Text(AppStringsTr.productSupplierNone),
                ),
                for (final s in suppliers)
                  DropdownMenuItem<int?>(
                    value: s.id,
                    child: Text(
                      s.isActive
                          ? s.name
                          : AppStringsTr.inactiveOptionLabel(s.name),
                    ),
                  ),
              ],
              onChanged: (value) => setState(() => _supplierId = value),
            ),

            _section(AppStringsTr.productTabPricing),
            TextFormField(
              key: ProductFormScreen.salePriceFieldKey,
              controller: _salePrice,
              decoration: const InputDecoration(
                // REQ-PROD-014 — etiket bir gereksinimdir.
                labelText: AppStringsTr.productSalePriceLabel,
                helperText: AppStringsTr.productSalePriceHint,
              ),
              validator: (value) =>
                  _parseMoney(value ?? '', allowEmpty: false) == null
                  ? AppStringsTr.productSalePriceInvalid
                  : null,
            ),
            TextFormField(
              key: ProductFormScreen.purchasePriceFieldKey,
              controller: _purchasePrice,
              decoration: const InputDecoration(
                labelText: AppStringsTr.productPurchasePriceLabel,
                helperText: AppStringsTr.productPurchasePriceHint,
              ),
              validator: (value) =>
                  _parseMoney(value ?? '', allowEmpty: true) == null
                  ? AppStringsTr.productSalePriceInvalid
                  : null,
            ),
            const SizedBox(height: 8),
            if (vatDisabled)
              const FormMessage(
                AppStringsTr.productVatDisabledNotice,
                kind: FormMessageKind.info,
              )
            else
              DropdownButtonFormField<int?>(
                initialValue: presentOrNull(
                  _vatRateId,
                  vatRates.map((r) => r.id),
                ),
                decoration: const InputDecoration(
                  labelText: AppStringsTr.productVatRateLabel,
                ),
                items: [
                  const DropdownMenuItem<int?>(
                    child: Text(AppStringsTr.productVatRateDefaultOption),
                  ),
                  for (final r in vatRates)
                    DropdownMenuItem<int?>(
                      value: r.id,
                      child: Text(
                        r.isActive
                            ? r.name
                            : AppStringsTr.inactiveOptionLabel(r.name),
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _vatRateId = value),
              ),

            _section(AppStringsTr.productTabStock),
            TextFormField(
              key: ProductFormScreen.minimumStockFieldKey,
              controller: _minimumStock,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: AppStringsTr.productMinimumStockLabel,
                helperText: AppStringsTr.productMinimumStockHint,
              ),
            ),
            if (_isEdit)
              // docs/09 §1 — stok elle düzenlenemez.
              TextFormField(
                key: ProductFormScreen.stockReadOnlyKey,
                initialValue: widget.product!.stockQuantity.toString(),
                readOnly: true,
                enabled: false,
                decoration: const InputDecoration(
                  labelText: AppStringsTr.productStockLabel,
                  helperText: AppStringsTr.productStockReadOnlyHint,
                ),
              )
            else
              // REQ-PROD-007 — `initial` stok hareketi üretir.
              TextFormField(
                key: ProductFormScreen.initialStockFieldKey,
                controller: _initialStock,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: AppStringsTr.productInitialStockLabel,
                  helperText: AppStringsTr.productInitialStockHint,
                ),
                validator: (value) =>
                    _parseInt(value ?? '', allowEmpty: true) == null
                    ? AppStringsTr.productIntegerInvalid
                    : null,
              ),

            _section(AppStringsTr.productTabBarcodes),
            const Text(AppStringsTr.productBarcodesDescription),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: ProductFormScreen.barcodeFieldKey,
                    controller: _barcode,
                    decoration: const InputDecoration(
                      labelText: AppStringsTr.productBarcodeLabel,
                    ),
                    onFieldSubmitted: (_) => _addBarcode(),
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  key: ProductFormScreen.barcodeAddKey,
                  onPressed: _addBarcode,
                  icon: const Icon(Icons.add),
                  label: const Text(AppStringsTr.productBarcodeAddAction),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_barcodes.isEmpty)
              const Text(AppStringsTr.productBarcodesEmpty)
            else
              for (final barcode in _barcodes)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.qr_code_2),
                  title: Text(barcode),
                  trailing: IconButton(
                    key: ProductFormScreen.barcodeRemoveKey(barcode),
                    tooltip: AppStringsTr.productBarcodeRemoveAction,
                    onPressed: () => _removeBarcode(barcode),
                    icon: const Icon(Icons.close),
                  ),
                ),
            if (!_isEdit && _barcodes.isNotEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(AppStringsTr.productBarcodePendingNotice),
              ),

            if (_message != null) ...[
              const SizedBox(height: 16),
              FormMessage(
                _message!,
                key: ProductFormScreen.messageKey,
                kind: FormMessageKind.error,
              ),
            ],
            if (_warnings.isNotEmpty) ...[
              const SizedBox(height: 16),
              FormMessage(
                _warnings.map((w) => w.message).join('\n'),
                key: ProductFormScreen.warningsKey,
                kind: FormMessageKind.warning,
              ),
            ],
            const SizedBox(height: 24),
            SubmitButton(
              key: ProductFormScreen.submitKey,
              label: AppStringsTr.saveAction,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 24, bottom: 8),
    child: Text(
      title,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
}
