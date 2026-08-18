/// KDV oranı yönetimi — **docs/08 §3, §4 · BR-VAT-001/004/005/006 ·
/// REQ-VAT-001/002/010/011 · EC-VAT-001/002/003**
///
/// | İşlem | Kural |
/// |---|---|
/// | Ekle | Oran **basis point** tam sayıdır (BR-FIN-002) |
/// | Düzenle (ad ve/veya oran) | Oran DEĞERİ değişiyorsa önce uyarı (docs/08 §4) |
/// | Varsayılan yap | **Pasif oran varsayılan yapılamaz** (BR-VAT-006 · EC-VAT-001) |
/// | Pasife al / aktifleştir | REQ-VAT-011 (OD-020) |
/// | **Sil** | ❌ **YOK** — docs/08 §4 · EC-VAT-003 |
///
/// ## Oran değişikliği uyarısı neden zorunlu
///
/// BR-VAT-004: değişiklik yalnızca **bundan sonraki** satışları etkiler;
/// geçmiş satışlar `vat_rate_snapshot_bp` taşıdığı için değişmez (BR-VAT-002).
/// Kullanıcı bunu bilmeden oranı değiştirirse geçmişi bozduğunu sanır. Uyarı
/// bu yüzden **kaydetmeden önce** gösterilir ve [AppStringsTr.cancelAction]
/// hiçbir şey uygulamaz.
///
/// ## Pasif satırda "Varsayılan yap" neden sunulmaz
///
/// EC-VAT-001 (OD-019): varsayılan araması aktiflik filtreler; pasif bir oran
/// varsayılan olsaydı sistem "varsayılan yok" durumuna düşer ve KDV **sessizce
/// %0** hesaplanırdı. Servis çağrıyı zaten reddeder — ekran ise kullanıcıyı o
/// çıkmaza hiç sokmaz.
///
/// ## Boş durum yoktur
///
/// OD-017 · docs/08 §3: kurulumda nötr `%0 — KDV Yok` oranı oluşturulur,
/// varsayılandır ve **silinemez** (EC-VAT-003). Liste hiçbir zaman boş
/// başlamaz; var olmayan bir durum için metin uydurulmaz.
///
/// ## Katman sınırı — rules/01 §1 · rules/05 §8
///
/// Ekranda **KDV hesabı yoktur.** Girdi ayrıştırma tek implementasyon olan
/// `domain/services/vat_rate_parser.dart`'a (servisin `parseRate` sarmalayıcısı
/// üzerinden) devredilir; gösterim biçimi `presentation/common/rate_format.dart`
/// içindedir. Hata mesajları `Failure.userMessage`'dır (REQ-SEC-007).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/reference/providers.dart';
import '../../application/reference/vat_rate_service.dart';
import '../../core/result/result.dart';
import '../../domain/models/vat_rate.dart';
import '../common/current_user.dart';
import '../common/form_message.dart';
import '../common/rate_format.dart';
import '../common/submit_button.dart';

class VatRateManagementScreen extends ConsumerStatefulWidget {
  /// Test ve odak doğrulaması için sabit anahtarlar.
  static const Key addButtonKey = Key('vat_rates_add_button');
  static const Key messageKey = Key('vat_rates_message');
  static const Key changeConfirmButtonKey = Key('vat_rate_change_confirm');
  static const Key changeCancelButtonKey = Key('vat_rate_change_cancel');

  static Key tileKey(int id) => ValueKey('vat_rate_tile_$id');
  static Key editButtonKey(int id) => ValueKey('vat_rate_edit_$id');
  static Key setDefaultButtonKey(int id) => ValueKey('vat_rate_default_$id');
  static Key activeSwitchKey(int id) => ValueKey('vat_rate_active_$id');

  const VatRateManagementScreen({super.key});

  @override
  ConsumerState<VatRateManagementScreen> createState() =>
      _VatRateManagementScreenState();
}

class _VatRateManagementScreenState
    extends ConsumerState<VatRateManagementScreen> {
  String? _message;

  void _showMessage(String message) => setState(() => _message = message);

  void _clearMessage() {
    if (_message != null) setState(() => _message = null);
  }

  void _showInfo(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _refresh() {
    ref.invalidate(vatRateListProvider);
    // BR-VAT-005: KDV alanlarının gizlenip gizlenmeyeceği bu listeye bağlıdır.
    ref.invalidate(vatDisabledProvider);
  }

  Future<void> _add() async {
    _clearMessage();

    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _VatRateFormDialog(),
    );
    if (!mounted || !(created ?? false)) return;

    _refresh();
    _showInfo(AppStringsTr.vatRateCreated);
  }

  Future<void> _edit(VatRate rate) async {
    _clearMessage();

    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _VatRateFormDialog(rate: rate),
    );
    if (!mounted || !(updated ?? false)) return;

    _refresh();
    _showInfo(AppStringsTr.vatRateUpdated);
  }

  /// docs/04 §3.4 — aynı anda yalnızca bir varsayılan; devir servistedir.
  Future<void> _setDefault(VatRate rate) async {
    _clearMessage();

    final userId = await currentUserId(ref);
    final result = await ref
        .read(vatRateServiceProvider)
        .setDefault(rate.id, userId: userId);
    if (!mounted) return;

    switch (result) {
      case Ok<void>():
        _refresh();
        _showInfo(AppStringsTr.vatRateDefaultUpdated);
      case Err<void>(:final failure):
        _showMessage(failure.userMessage);
    }
  }

  /// EC-VAT-002 — varsayılan oran pasifleştirilebilir; `is_default` bayrağına
  /// dokunulmaz. Kararı servis verir.
  Future<void> _setActive(VatRate rate, bool isActive) async {
    _clearMessage();

    final service = ref.read(vatRateServiceProvider);
    final userId = await currentUserId(ref);
    final result = isActive
        ? await service.activate(rate.id, userId: userId)
        : await service.deactivate(rate.id, userId: userId);
    if (!mounted) return;

    switch (result) {
      case Ok<void>():
        _refresh();
        _showInfo(
          isActive
              ? AppStringsTr.vatRateActivated
              : AppStringsTr.vatRateDeactivated,
        );
      case Err<void>(:final failure):
        _showMessage(failure.userMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rates = ref.watch(vatRateListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStringsTr.vatRatesTitle),
        actions: [
          TextButton.icon(
            key: VatRateManagementScreen.addButtonKey,
            onPressed: _add,
            icon: const Icon(Icons.percent_outlined),
            label: const Text(AppStringsTr.vatRateAddAction),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  AppStringsTr.vatRatesDescription,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FormMessage(
                    _message!,
                    key: VatRateManagementScreen.messageKey,
                  ),
                ),
              Expanded(
                child: rates.when(
                  data: _buildList,
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  // REQ-SEC-007: teknik detay kullanıcıya gösterilmez.
                  error: (_, _) => const Padding(
                    padding: EdgeInsets.all(16),
                    child: FormMessage(AppStringsTr.unexpectedErrorMessage),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(List<VatRate> rates) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: rates.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final rate = rates[index];

        return ListTile(
          key: VatRateManagementScreen.tileKey(rate.id),
          // rules/05 §5: durum renkle değil, ikon + metinle de anlatılır.
          leading: Icon(
            rate.isActive ? Icons.percent_outlined : Icons.money_off_outlined,
          ),
          title: Text(rate.name),
          subtitle: Text(
            [
              formatRateBasisPoints(rate.rateBasisPoints),
              rate.isActive
                  ? AppStringsTr.statusActive
                  : AppStringsTr.statusInactive,
              if (rate.isDefault) AppStringsTr.vatRateDefaultBadge,
            ].join(' · '),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // EC-VAT-001: pasif satırda bu eylem HİÇ sunulmaz; varsayılan
              // olan satırda ise tekrarlamanın anlamı yoktur.
              if (rate.isActive && !rate.isDefault)
                TextButton(
                  key: VatRateManagementScreen.setDefaultButtonKey(rate.id),
                  onPressed: () => _setDefault(rate),
                  child: const Text(AppStringsTr.vatRateSetDefaultAction),
                ),
              IconButton(
                key: VatRateManagementScreen.editButtonKey(rate.id),
                tooltip: AppStringsTr.vatRateEditTitle,
                onPressed: () => _edit(rate),
                icon: const Icon(Icons.edit_outlined),
              ),
              Switch(
                key: VatRateManagementScreen.activeSwitchKey(rate.id),
                value: rate.isActive,
                onChanged: (value) => _setActive(rate, value),
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- Oran formu: ekle / düzenle (docs/08 §4) --------------------------------

class _VatRateFormDialog extends ConsumerStatefulWidget {
  static const Key nameFieldKey = Key('vat_rate_form_name');
  static const Key rateFieldKey = Key('vat_rate_form_rate');
  static const Key submitButtonKey = Key('vat_rate_form_submit');

  /// `null` ise yeni oran oluşturulur.
  final VatRate? rate;

  const _VatRateFormDialog({this.rate});

  @override
  ConsumerState<_VatRateFormDialog> createState() => _VatRateFormDialogState();
}

class _VatRateFormDialogState extends ConsumerState<_VatRateFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.rate?.name ?? '');
  late final _rate = TextEditingController(
    text: widget.rate == null
        ? ''
        : formatRateBasisPoints(widget.rate!.rateBasisPoints),
  );

  String? _message;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _rate.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _submitting = true;
    setState(() => _message = null);

    try {
      // Tek ayrıştırma implementasyonu: VatRateParser (rules/01 §2).
      final parsed = VatRateService.parseRate(_rate.text);
      if (parsed case Err<int>(:final failure)) {
        setState(() => _message = failure.userMessage);
        return;
      }
      final rateBasisPoints = parsed.valueOrNull!;

      final service = ref.read(vatRateServiceProvider);
      final existing = widget.rate;

      if (existing != null &&
          rateBasisPoints != existing.rateBasisPoints &&
          !await _confirmRateChange(existing)) {
        // docs/08 §4 — [Vazgeç]: hiçbir değişiklik uygulanmaz.
        return;
      }
      if (!mounted) return;

      final userId = await currentUserId(ref);
      final Result<void> result = existing == null
          ? await service.create(
              name: _name.text,
              rateBasisPoints: rateBasisPoints,
              userId: userId,
            )
          : await service.update(
              existing.id,
              name: _name.text,
              rateBasisPoints: rateBasisPoints,
              userId: userId,
            );
      if (!mounted) return;

      switch (result) {
        case Ok<void>():
          Navigator.of(context).pop(true);
        case Err<void>(:final failure):
          setState(() => _message = failure.userMessage);
      }
    } finally {
      _submitting = false;
    }
  }

  /// docs/08 §4 — oran DEĞERİ değişiyorsa kaydetmeden önce kullanıcı uyarılır
  /// ve etkilenen ürün sayısı gösterilir (BR-VAT-004).
  Future<bool> _confirmRateChange(VatRate rate) async {
    final productCount = await ref
        .read(vatRateServiceProvider)
        .productCount(rate.id);
    if (!mounted) return false;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStringsTr.vatRateChangeWarningTitle),
        content: Text(AppStringsTr.vatRateChangeWarning(productCount)),
        actions: [
          TextButton(
            key: VatRateManagementScreen.changeCancelButtonKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStringsTr.cancelAction),
          ),
          TextButton(
            key: VatRateManagementScreen.changeConfirmButtonKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStringsTr.changeAction),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.rate != null;

    return AlertDialog(
      title: Text(
        isEdit ? AppStringsTr.vatRateEditTitle : AppStringsTr.vatRateAddTitle,
      ),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: _VatRateFormDialog.nameFieldKey,
                controller: _name,
                // rules/05 §1: dialog açıldığında odak ilk alandadır.
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: AppStringsTr.vatRateNameLabel,
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? AppStringsTr.vatRateNameRequired
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: _VatRateFormDialog.rateFieldKey,
                controller: _rate,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: AppStringsTr.vatRateValueLabel,
                  // rules/05 §5: kabul edilen biçim örnekle gösterilir.
                  hintText: AppStringsTr.vatRateValueHint,
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? AppStringsTr.vatRateValueRequired
                    : null,
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_message != null) ...[
                const SizedBox(height: 16),
                FormMessage(_message!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(AppStringsTr.cancelAction),
        ),
        SubmitButton(
          key: _VatRateFormDialog.submitButtonKey,
          label: isEdit ? AppStringsTr.saveAction : AppStringsTr.addAction,
          onPressed: _submit,
        ),
      ],
    );
  }
}
