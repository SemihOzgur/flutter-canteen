/// Tedarikçi yönetimi — **docs/10 §2 · BR-SUP-001/002 ·
/// REQ-SUP-001/002/004/006 · EC-SUP-001/003**
///
/// | İşlem | Kural |
/// |---|---|
/// | Ekle | **Yalnızca ad zorunlu**; diğer alanlar opsiyonel (REQ-SUP-001) |
/// | Düzenle | Tüm alanlar (docs/10 §2.1) |
/// | Pasife al | Bağlı ürünler ve stok girişleri korunur (EC-SUP-001) |
/// | Yeniden aktifleştir | REQ-SUP-006 · EC-SUP-003 (OD-020) |
/// | **Sil** | ❌ **YOK** — BR-SUP-002 |
///
/// ## Silme butonu bilinçli olarak yoktur
///
/// BR-SUP-002 · REQ-SUP-002: tedarikçi silinmez. Bu kural koda bir runtime
/// kontrolü olarak değil, `SupplierService`'te silme metodunun **hiç
/// bulunmaması** olarak yansır; ekranda da karşılığı olan bir eylem yoktur.
/// Buraya "sil" eklemek bir business kuralı değişikliğidir (rules/00 §3).
///
/// ## Tedarikçi detayı burada değildir
///
/// REQ-SUP-003 (bağlı ürünler, stok girişleri, toplam alış tutarı) **Faz 6**
/// kapsamındadır (docs/25). Stok hareketleri henüz yoktur; bugün yazılacak bir
/// detay ekranı boş kalırdı.
///
/// ## Onay dialogu neden yok
///
/// rules/05 §5 · REQ-UX-009: onay yalnızca **geri alınamaz** işlemlerde
/// istenir. Pasifleştirme geri alınabilir (aynı ekrandan aktifleştirilir).
///
/// ## Katman sınırı — rules/01 §1 · rules/05 §8
///
/// Ekran veritabanına inmez: tedarikçiler `SupplierService` üzerinden **domain**
/// `Supplier` olarak gelir. Hata mesajları `Failure.userMessage`'dır
/// (REQ-UX-008 · REQ-SEC-007).
library;

import 'supplier_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/reference/providers.dart';
import '../../core/result/result.dart';
import '../../domain/models/supplier.dart';
import '../common/current_user.dart';
import '../common/form_message.dart';
import '../common/submit_button.dart';

class SupplierManagementScreen extends ConsumerStatefulWidget {
  /// Test ve odak doğrulaması için sabit anahtarlar.
  static const Key addButtonKey = Key('suppliers_add_button');
  static const Key messageKey = Key('suppliers_message');

  static Key tileKey(int id) => ValueKey('supplier_tile_$id');
  static Key editButtonKey(int id) => ValueKey('supplier_edit_$id');
  static Key activeSwitchKey(int id) => ValueKey('supplier_active_$id');

  const SupplierManagementScreen({super.key});

  @override
  ConsumerState<SupplierManagementScreen> createState() =>
      _SupplierManagementScreenState();
}

class _SupplierManagementScreenState
    extends ConsumerState<SupplierManagementScreen> {
  String? _message;

  void _showMessage(String message) => setState(() => _message = message);

  void _clearMessage() {
    if (_message != null) setState(() => _message = null);
  }

  void _showInfo(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _add() async {
    _clearMessage();

    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _SupplierFormDialog(),
    );
    if (!mounted || !(created ?? false)) return;

    ref.invalidate(supplierListProvider);
    _showInfo(AppStringsTr.supplierCreated);
  }

  Future<void> _edit(Supplier supplier) async {
    _clearMessage();

    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _SupplierFormDialog(supplier: supplier),
    );
    if (!mounted || !(updated ?? false)) return;

    ref.invalidate(supplierListProvider);
    _showInfo(AppStringsTr.supplierUpdated);
  }

  /// EC-SUP-001 · EC-SUP-003 — pasifleştirme bağlı ürünleri etkilemez ve geri
  /// alınabilir. Kararı servis verir; ekran yalnızca sonucu gösterir.
  Future<void> _setActive(Supplier supplier, bool isActive) async {
    _clearMessage();

    final service = ref.read(supplierServiceProvider);
    final userId = await currentUserId(ref);
    final result = isActive
        ? await service.activate(supplier.id, userId: userId)
        : await service.deactivate(supplier.id, userId: userId);
    if (!mounted) return;

    switch (result) {
      case Ok<void>():
        ref.invalidate(supplierListProvider);
        _showInfo(
          isActive
              ? AppStringsTr.supplierActivated
              : AppStringsTr.supplierDeactivated,
        );
      case Err<void>(:final failure):
        _showMessage(failure.userMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final suppliers = ref.watch(supplierListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStringsTr.suppliersTitle),
        actions: [
          TextButton.icon(
            key: SupplierManagementScreen.addButtonKey,
            onPressed: _add,
            icon: const Icon(Icons.local_shipping_outlined),
            label: const Text(AppStringsTr.supplierAddAction),
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
                  AppStringsTr.suppliersDescription,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FormMessage(
                    _message!,
                    key: SupplierManagementScreen.messageKey,
                  ),
                ),
              Expanded(
                child: suppliers.when(
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

  Widget _buildList(List<Supplier> suppliers) {
    // REQ-UX-011: her liste ekranının eyleme yönlendiren boş durumu vardır.
    // Tedarikçi seed edilmez; liste gerçekten boş başlar.
    if (suppliers.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                AppStringsTr.suppliersEmpty,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              SubmitButton(
                label: AppStringsTr.supplierAddAction,
                onPressed: _add,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: suppliers.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final supplier = suppliers[index];
        final details = [
          if (supplier.contactName != null) supplier.contactName!,
          if (supplier.phone != null) supplier.phone!,
          if (supplier.email != null) supplier.email!,
        ];

        return ListTile(
          key: SupplierManagementScreen.tileKey(supplier.id),
          // REQ-SUP-003 — satıra tıklamak tedarikçi detayını açar.
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SupplierDetailScreen(supplierId: supplier.id),
            ),
          ),
          // rules/05 §5: durum renkle değil, ikon + metinle de anlatılır.
          leading: Icon(
            supplier.isActive
                ? Icons.local_shipping_outlined
                : Icons.no_transfer_outlined,
          ),
          title: Text(supplier.name),
          subtitle: Text(
            [
              supplier.isActive
                  ? AppStringsTr.statusActive
                  : AppStringsTr.statusInactive,
              ...details,
            ].join(' · '),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: SupplierManagementScreen.editButtonKey(supplier.id),
                tooltip: AppStringsTr.supplierEditTitle,
                onPressed: () => _edit(supplier),
                icon: const Icon(Icons.edit_outlined),
              ),
              Switch(
                key: SupplierManagementScreen.activeSwitchKey(supplier.id),
                value: supplier.isActive,
                onChanged: (value) => _setActive(supplier, value),
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- Tedarikçi formu: ekle / düzenle (docs/10 §2.1) -------------------------

class _SupplierFormDialog extends ConsumerStatefulWidget {
  static const Key nameFieldKey = Key('supplier_form_name');
  static const Key contactFieldKey = Key('supplier_form_contact');
  static const Key phoneFieldKey = Key('supplier_form_phone');
  static const Key emailFieldKey = Key('supplier_form_email');
  static const Key addressFieldKey = Key('supplier_form_address');
  static const Key noteFieldKey = Key('supplier_form_note');
  static const Key submitButtonKey = Key('supplier_form_submit');

  /// `null` ise yeni tedarikçi oluşturulur.
  final Supplier? supplier;

  const _SupplierFormDialog({this.supplier});

  @override
  ConsumerState<_SupplierFormDialog> createState() =>
      _SupplierFormDialogState();
}

class _SupplierFormDialogState extends ConsumerState<_SupplierFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final _name = TextEditingController(text: widget.supplier?.name ?? '');
  late final _contactName = TextEditingController(
    text: widget.supplier?.contactName ?? '',
  );
  late final _phone = TextEditingController(text: widget.supplier?.phone ?? '');
  late final _email = TextEditingController(text: widget.supplier?.email ?? '');
  late final _address = TextEditingController(
    text: widget.supplier?.address ?? '',
  );
  late final _note = TextEditingController(text: widget.supplier?.note ?? '');

  String? _message;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    _contactName.dispose();
    _phone.dispose();
    _email.dispose();
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _submitting = true;
    setState(() => _message = null);

    try {
      final service = ref.read(supplierServiceProvider);
      final userId = await currentUserId(ref);
      final supplier = widget.supplier;

      // Boş opsiyonel alanları `null`'a indirgemek servisin işidir
      // (REQ-SUP-001); ekran metni olduğu gibi iletir.
      final Result<void> result = supplier == null
          ? await service.create(
              name: _name.text,
              contactName: _contactName.text,
              phone: _phone.text,
              email: _email.text,
              address: _address.text,
              note: _note.text,
              userId: userId,
            )
          : await service.update(
              supplier.id,
              name: _name.text,
              contactName: _contactName.text,
              phone: _phone.text,
              email: _email.text,
              address: _address.text,
              note: _note.text,
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

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.supplier != null;

    return AlertDialog(
      title: Text(
        isEdit ? AppStringsTr.supplierEditTitle : AppStringsTr.supplierAddTitle,
      ),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: _SupplierFormDialog.nameFieldKey,
                  controller: _name,
                  // rules/05 §1: dialog açıldığında odak ilk alandadır.
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: AppStringsTr.supplierNameLabel,
                    border: OutlineInputBorder(),
                  ),
                  // REQ-SUP-001: **tek** zorunlu alan.
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? AppStringsTr.supplierNameRequired
                      : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: _SupplierFormDialog.contactFieldKey,
                  controller: _contactName,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: AppStringsTr.supplierContactNameLabel,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: _SupplierFormDialog.phoneFieldKey,
                  controller: _phone,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: AppStringsTr.supplierPhoneLabel,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: _SupplierFormDialog.emailFieldKey,
                  controller: _email,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: AppStringsTr.supplierEmailLabel,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: _SupplierFormDialog.addressFieldKey,
                  controller: _address,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: AppStringsTr.supplierAddressLabel,
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: _SupplierFormDialog.noteFieldKey,
                  controller: _note,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: AppStringsTr.supplierNoteLabel,
                    border: OutlineInputBorder(),
                  ),
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
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(AppStringsTr.cancelAction),
        ),
        SubmitButton(
          key: _SupplierFormDialog.submitButtonKey,
          label: isEdit ? AppStringsTr.saveAction : AppStringsTr.addAction,
          onPressed: _submit,
        ),
      ],
    );
  }
}
