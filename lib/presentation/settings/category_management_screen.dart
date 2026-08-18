/// Kategori yönetimi — **docs/10 §1 · BR-CAT-001…005 · REQ-CAT-001…007 ·
/// EC-CAT-001/002/005/006/007**
///
/// | İşlem | Kural |
/// |---|---|
/// | Ekle | Ad benzersizdir — **pasifler dâhil** (REQ-CAT-005 · EC-CAT-003) |
/// | Adı düzenle | `Genel` hariç (BR-CAT-004) |
/// | Sıralama düzenle | Satış ekranı sırası (docs/10 §1.1) |
/// | Pasife al | Ürün sayısı gösterilir + taşıma seçeneği (docs/10 §1.3) |
/// | Yeniden aktifleştir | REQ-CAT-007 · EC-CAT-007 (OD-020) |
/// | **Sil** | Yalnızca **hiç kullanılmamışsa** (REQ-CAT-006) — kararı servis verir |
///
/// ## `Genel` neden gizlenmiyor da devre dışı
///
/// EC-CAT-001 "engellenir; **sebep açıklanır**" der. Eylemi tamamen gizlemek
/// sebebi de gizlerdi: kullanıcı "neden silemiyorum?" sorusunu ekranı terk
/// etmeden yanıtlayabilmelidir (rules/05 §5). Bu yüzden satırda hem
/// [AppStringsTr.categorySystemBadge] etiketi hem de açıklama görünür; ad,
/// pasifleştirme ve silme eylemleri **pasif** durumdadır.
///
/// ## Silme kararı burada verilmez
///
/// REQ-CAT-006'nın "hiç kullanılmamış" ölçütü (ürün + satış snapshot'ı)
/// `CategoryService.delete` içinde, sayım ile silmeyi aynı transaction'da
/// tutarak uygulanır. Ekran yalnızca **geri alınamaz** işlem için onay ister
/// (rules/05 §5 · REQ-UX-009) ve reddi kullanıcıya gösterir; aynı kontrolü
/// burada tekrarlamak iş kuralını iki yere kopyalardı (rules/01 §2).
///
/// ## Bu ekran finansal kilit dışındadır
///
/// rules/04 §4: kilit yalnızca Dashboard ve Raporlar içindir; kategori yönetimi
/// kilit kapsamında **değildir** — `ensureFinancialAccess` çağrılmaz.
///
/// ## Katman sınırı — rules/01 §1 · rules/05 §8
///
/// Ekran veritabanına inmez: kategoriler `CategoryService` üzerinden **domain**
/// `Category` olarak gelir. Transaction, audit ve iş kuralı servistedir; hata
/// mesajları `Failure.userMessage`'dır (REQ-UX-008 · REQ-SEC-007).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/reference/providers.dart';
import '../../core/result/result.dart';
import '../../domain/models/category.dart';
import '../common/current_user.dart';
import '../common/form_message.dart';
import '../common/submit_button.dart';

/// docs/10 §1.3 — pasifleştirme öncesi kullanıcıya sunulan üç seçenek.
enum _DeactivateChoice { cancel, moveProducts, deactivate }

class CategoryManagementScreen extends ConsumerStatefulWidget {
  /// Test ve odak doğrulaması için sabit anahtarlar.
  static const Key addButtonKey = Key('categories_add_button');
  static const Key messageKey = Key('categories_message');
  static const Key deleteConfirmButtonKey = Key('category_delete_confirm');
  static const Key deleteCancelButtonKey = Key('category_delete_cancel');
  static const Key deactivateConfirmButtonKey = Key(
    'category_deactivate_confirm',
  );
  static const Key deactivateMoveButtonKey = Key('category_deactivate_move');
  static const Key deactivateCancelButtonKey = Key(
    'category_deactivate_cancel',
  );

  static Key tileKey(int id) => ValueKey('category_tile_$id');
  static Key renameButtonKey(int id) => ValueKey('category_rename_$id');
  static Key sortButtonKey(int id) => ValueKey('category_sort_$id');
  static Key deleteButtonKey(int id) => ValueKey('category_delete_$id');
  static Key activeSwitchKey(int id) => ValueKey('category_active_$id');
  static Key moveTargetKey(int id) => ValueKey('category_move_target_$id');

  const CategoryManagementScreen({super.key});

  @override
  ConsumerState<CategoryManagementScreen> createState() =>
      _CategoryManagementScreenState();
}

class _CategoryManagementScreenState
    extends ConsumerState<CategoryManagementScreen> {
  /// Servisten gelen kullanıcıya gösterilebilir hata (örn. `category_in_use`).
  String? _message;

  void _showMessage(String message) => setState(() => _message = message);

  void _clearMessage() {
    if (_message != null) setState(() => _message = null);
  }

  void _showInfo(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _refresh() {
    ref.invalidate(categoryListProvider);
    ref.invalidate(activeCategoryListProvider);
  }

  Future<void> _add() async {
    _clearMessage();

    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _CategoryNameDialog(),
    );
    if (!mounted || !(created ?? false)) return;

    _refresh();
    _showInfo(AppStringsTr.categoryCreated);
  }

  Future<void> _rename(Category category) async {
    _clearMessage();

    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _CategoryNameDialog(category: category),
    );
    if (!mounted || !(updated ?? false)) return;

    _refresh();
    _showInfo(AppStringsTr.categoryRenamed);
  }

  Future<void> _editSortOrder(Category category) async {
    _clearMessage();

    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _SortOrderDialog(category: category),
    );
    if (!mounted || !(updated ?? false)) return;

    _refresh();
    _showInfo(AppStringsTr.categorySortOrderUpdated);
  }

  /// REQ-CAT-006 — kalıcı silme **geri alınamaz**, bu yüzden önce onay istenir
  /// (rules/05 §5 · REQ-UX-009).
  ///
  /// Kategorinin gerçekten silinebilir olup olmadığına servis karar verir
  /// (EC-CAT-005 / EC-CAT-006); reddedilirse mesajı kullanıcı görür ve
  /// pasifleştirmeye yönlendirilir.
  Future<void> _delete(Category category) async {
    _clearMessage();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStringsTr.categoryDeleteTitle),
        content: Text(AppStringsTr.categoryDeleteConfirm(category.name)),
        actions: [
          TextButton(
            key: CategoryManagementScreen.deleteCancelButtonKey,
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStringsTr.cancelAction),
          ),
          TextButton(
            key: CategoryManagementScreen.deleteConfirmButtonKey,
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(AppStringsTr.deleteAction),
          ),
        ],
      ),
    );
    if (!mounted || !(confirmed ?? false)) return;

    final userId = await currentUserId(ref);
    final result = await ref
        .read(categoryServiceProvider)
        .delete(category.id, userId: userId);
    if (!mounted) return;

    switch (result) {
      case Ok<void>():
        _refresh();
        _showInfo(AppStringsTr.categoryDeleted);
      case Err<void>(:final failure):
        _showMessage(failure.userMessage);
    }
  }

  Future<void> _setActive(Category category, bool isActive) async {
    _clearMessage();
    if (isActive) {
      await _activate(category);
    } else {
      await _confirmDeactivate(category);
    }
  }

  /// REQ-CAT-007 · EC-CAT-007 (OD-020) — geri alınabilir işlem, onay istemez
  /// (rules/05 §5).
  Future<void> _activate(Category category) async {
    final userId = await currentUserId(ref);
    final result = await ref
        .read(categoryServiceProvider)
        .activate(category.id, userId: userId);
    if (!mounted) return;

    switch (result) {
      case Ok<void>():
        _refresh();
        _showInfo(AppStringsTr.categoryActivated);
      case Err<void>(:final failure):
        _showMessage(failure.userMessage);
    }
  }

  /// docs/10 §1.3 · EC-CAT-002 — pasifleştirme öncesi **ürün sayısı gösterilir**
  /// ve ürünleri başka kategoriye taşıma seçeneği sunulur (REQ-CAT-004).
  ///
  /// Taşıma başarılı olursa akış aynı diyaloga güncel sayıyla döner:
  /// pasifleştirme yine kullanıcının açık onayını ister.
  Future<void> _confirmDeactivate(Category category) async {
    final productCount = await ref
        .read(categoryServiceProvider)
        .productCount(category.id);
    if (!mounted) return;

    final choice = await showDialog<_DeactivateChoice>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(AppStringsTr.categoryDeactivateTitle),
        content: Text(
          AppStringsTr.categoryDeactivateMessage(category.name, productCount),
        ),
        actions: [
          TextButton(
            key: CategoryManagementScreen.deactivateCancelButtonKey,
            onPressed: () =>
                Navigator.of(dialogContext).pop(_DeactivateChoice.cancel),
            child: const Text(AppStringsTr.cancelAction),
          ),
          if (productCount > 0)
            TextButton(
              key: CategoryManagementScreen.deactivateMoveButtonKey,
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(_DeactivateChoice.moveProducts),
              child: const Text(AppStringsTr.categoryMoveProductsAction),
            ),
          TextButton(
            key: CategoryManagementScreen.deactivateConfirmButtonKey,
            onPressed: () =>
                Navigator.of(dialogContext).pop(_DeactivateChoice.deactivate),
            child: const Text(AppStringsTr.deactivateAction),
          ),
        ],
      ),
    );
    if (!mounted) return;

    switch (choice) {
      case null:
      case _DeactivateChoice.cancel:
        return;
      case _DeactivateChoice.moveProducts:
        if (await _moveProducts(category)) {
          if (!mounted) return;
          await _confirmDeactivate(category);
        }
      case _DeactivateChoice.deactivate:
        await _deactivate(category);
    }
  }

  Future<void> _deactivate(Category category) async {
    final userId = await currentUserId(ref);
    final result = await ref
        .read(categoryServiceProvider)
        .deactivate(category.id, userId: userId);
    if (!mounted) return;

    switch (result) {
      case Ok<void>():
        _refresh();
        _showInfo(AppStringsTr.categoryDeactivated);
      case Err<void>(:final failure):
        _showMessage(failure.userMessage);
    }
  }

  /// REQ-CAT-004 · docs/10 §1.4 — toplu taşıma tek transaction'dır (servis).
  ///
  /// Hedef listesi yalnızca **aktif** ve kaynaktan **farklı** kategorileri
  /// içerir: pasif kategoriye yeni ürün ataması yapılamaz (docs/10 §1.3).
  Future<bool> _moveProducts(Category source) async {
    final target = await showDialog<Category>(
      context: context,
      builder: (_) => _MoveTargetDialog(source: source),
    );
    if (!mounted || target == null) return false;

    final userId = await currentUserId(ref);
    final result = await ref
        .read(categoryServiceProvider)
        .moveProducts(
          fromCategoryId: source.id,
          toCategoryId: target.id,
          userId: userId,
        );
    if (!mounted) return false;

    switch (result) {
      case Ok<int>(:final value):
        _refresh();
        _showInfo(AppStringsTr.categoryProductsMoved(value, target.name));
        return true;
      case Err<int>(:final failure):
        _showMessage(failure.userMessage);
        return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories = ref.watch(categoryListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStringsTr.categoriesTitle),
        actions: [
          TextButton.icon(
            key: CategoryManagementScreen.addButtonKey,
            onPressed: _add,
            icon: const Icon(Icons.create_new_folder_outlined),
            label: const Text(AppStringsTr.categoryAddAction),
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
                  AppStringsTr.categoriesDescription,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FormMessage(
                    _message!,
                    key: CategoryManagementScreen.messageKey,
                  ),
                ),
              Expanded(
                child: categories.when(
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

  /// Boş durum yoktur: `Genel` sistem kategorisi kurulum seed'i ile daima
  /// vardır ve silinemez (BR-CAT-004 · docs/08 §3 seed yolu), yani liste hiçbir
  /// zaman boşalmaz. Var olmayan bir durum için metin uydurulmaz.
  Widget _buildList(List<Category> categories) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: categories.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final category = categories[index];
        final protected = category.isSystem;

        return ListTile(
          key: CategoryManagementScreen.tileKey(category.id),
          // rules/05 §5: durum renkle değil, ikon + metinle de anlatılır.
          leading: Icon(
            category.isActive
                ? Icons.folder_outlined
                : Icons.folder_off_outlined,
          ),
          title: Text(category.name),
          subtitle: Text(
            [
              AppStringsTr.categorySortOrderValue(category.sortOrder),
              category.isActive
                  ? AppStringsTr.statusActive
                  : AppStringsTr.statusInactive,
              if (protected) AppStringsTr.categorySystemBadge,
            ].join(' · '),
          ),
          // EC-CAT-001: sebep satırın kendisinde açıklanır.
          isThreeLine: protected,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: CategoryManagementScreen.renameButtonKey(category.id),
                tooltip: protected
                    ? AppStringsTr.categorySystemHint
                    : AppStringsTr.categoryRenameTitle,
                onPressed: protected ? null : () => _rename(category),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                key: CategoryManagementScreen.sortButtonKey(category.id),
                tooltip: AppStringsTr.categorySortOrderTitle,
                onPressed: () => _editSortOrder(category),
                icon: const Icon(Icons.swap_vert),
              ),
              IconButton(
                key: CategoryManagementScreen.deleteButtonKey(category.id),
                tooltip: protected
                    ? AppStringsTr.categorySystemHint
                    : AppStringsTr.categoryDeleteTitle,
                onPressed: protected ? null : () => _delete(category),
                icon: const Icon(Icons.delete_outline),
              ),
              Switch(
                key: CategoryManagementScreen.activeSwitchKey(category.id),
                value: category.isActive,
                onChanged: protected
                    ? null
                    : (value) => _setActive(category, value),
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- Kategori adı: ekle / yeniden adlandır (REQ-CAT-001/005) ----------------

class _CategoryNameDialog extends ConsumerStatefulWidget {
  static const Key nameFieldKey = Key('category_form_name');
  static const Key submitButtonKey = Key('category_form_submit');

  /// `null` ise yeni kategori oluşturulur.
  final Category? category;

  const _CategoryNameDialog({this.category});

  @override
  ConsumerState<_CategoryNameDialog> createState() =>
      _CategoryNameDialogState();
}

class _CategoryNameDialogState extends ConsumerState<_CategoryNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.category?.name ?? '',
  );

  String? _message;
  bool _submitting = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _submitting = true;
    setState(() => _message = null);

    try {
      final service = ref.read(categoryServiceProvider);
      final userId = await currentUserId(ref);
      final category = widget.category;

      final Result<void> result = category == null
          ? await service.create(name: _name.text, userId: userId)
          : await service.rename(category.id, _name.text, userId: userId);
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
    final isEdit = widget.category != null;

    return AlertDialog(
      title: Text(
        isEdit
            ? AppStringsTr.categoryRenameTitle
            : AppStringsTr.categoryAddTitle,
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
                key: _CategoryNameDialog.nameFieldKey,
                controller: _name,
                // rules/05 §1: dialog açıldığında odak ilk alandadır.
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: AppStringsTr.categoryNameLabel,
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? AppStringsTr.categoryNameRequired
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
          key: _CategoryNameDialog.submitButtonKey,
          label: isEdit ? AppStringsTr.saveAction : AppStringsTr.addAction,
          onPressed: _submit,
        ),
      ],
    );
  }
}

// --- Sıralama (docs/10 §1.1) -----------------------------------------------

class _SortOrderDialog extends ConsumerStatefulWidget {
  static const Key sortFieldKey = Key('category_form_sort_order');
  static const Key submitButtonKey = Key('category_sort_submit');

  final Category category;

  const _SortOrderDialog({required this.category});

  @override
  ConsumerState<_SortOrderDialog> createState() => _SortOrderDialogState();
}

class _SortOrderDialogState extends ConsumerState<_SortOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _sortOrder = TextEditingController(
    text: '${widget.category.sortOrder}',
  );

  String? _message;
  bool _submitting = false;

  @override
  void dispose() {
    _sortOrder.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _submitting = true;
    setState(() => _message = null);

    try {
      final value = int.parse(_sortOrder.text.trim());
      final result = await ref
          .read(categoryServiceProvider)
          .updateSortOrder(widget.category.id, value);
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
    return AlertDialog(
      title: const Text(AppStringsTr.categorySortOrderTitle),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: _SortOrderDialog.sortFieldKey,
                controller: _sortOrder,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: AppStringsTr.categorySortOrderLabel,
                  border: OutlineInputBorder(),
                ),
                // rules/05 §5: hata mesajı örnekle birlikte verilir.
                validator: (value) => int.tryParse((value ?? '').trim()) == null
                    ? AppStringsTr.categorySortOrderInvalid
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
          key: _SortOrderDialog.submitButtonKey,
          label: AppStringsTr.saveAction,
          onPressed: _submit,
        ),
      ],
    );
  }
}

// --- Taşıma hedefi (REQ-CAT-004 · docs/10 §1.3/1.4) -------------------------

class _MoveTargetDialog extends ConsumerWidget {
  final Category source;

  const _MoveTargetDialog({required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categories = ref.watch(activeCategoryListProvider);

    return AlertDialog(
      title: const Text(AppStringsTr.categoryMoveTargetTitle),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360, maxHeight: 420),
        child: categories.when(
          data: (all) {
            // docs/10 §1.3: pasif kategori hedef olamaz (aktif liste zaten
            // pasifleri içermez); kaynağın kendisi de seçilemez.
            final targets = [
              for (final category in all)
                if (category.id != source.id) category,
            ];
            if (targets.isEmpty) {
              return const Text(AppStringsTr.categoryMoveNoTarget);
            }

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppStringsTr.categoryMoveTargetDescription,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                // `AlertDialog` içeriği intrinsic ölçü ister; lazy viewport
                // (ListView) bunu desteklemez. Kategori sayısı yönetilebilir
                // olduğu için liste doğrudan kurulur ve gerekirse kaydırılır.
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final target in targets)
                          ListTile(
                            key: CategoryManagementScreen.moveTargetKey(
                              target.id,
                            ),
                            leading: const Icon(Icons.folder_outlined),
                            title: Text(target.name),
                            onTap: () => Navigator.of(context).pop(target),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) =>
              const FormMessage(AppStringsTr.unexpectedErrorMessage),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(AppStringsTr.cancelAction),
        ),
      ],
    );
  }
}
