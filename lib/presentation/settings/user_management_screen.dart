/// Kullanıcı yönetimi — **docs/17 §11 · BR-AUTH-002/006 ·
/// REQ-AUTH-008/009/012/013 · EC-AUTH-005**
///
/// | İşlem | Kural |
/// |---|---|
/// | Kullanıcı ekle | Kullanıcı adı benzersizdir (servis doğrular) |
/// | Görünen ad değiştir | Serbest |
/// | Pasifleştir / aktifleştir | **Son aktif kullanıcı pasifleştirilemez** (EC-AUTH-005) |
/// | **Sil** | ❌ **YOK** — kullanıcı silinmez (BR-AUTH-006) |
///
/// ## Silme butonu bilinçli olarak yoktur
///
/// BR-AUTH-006: satış, stok hareketi ve audit kayıtları kullanıcıya referans
/// verir; silme geçmişi bozardı. Bu ekrana "sil" eklenmesi bir business kuralı
/// değişikliğidir (`rules/00 §3`), UI kararı değildir.
///
/// ## Rol/yetki YOKTUR
///
/// BR-AUTH-002 · REQ-AUTH-013: tüm kullanıcılar aynı yetkilere sahiptir. Bu
/// ekranda rol, yetki veya izin kavramı **bulunmaz**; çoklu kullanıcının tek
/// faydası izlenebilirliktir.
///
/// ## Onay dialogu neden yok
///
/// `rules/05 §5` · REQ-UX-009: onay yalnızca **geri alınamaz** işlemlerde
/// istenir. Pasifleştirme geri alınabilir (aynı ekrandan tekrar aktif edilir),
/// bu yüzden ayrıca onay sorulmaz.
///
/// ## Katman sınırı — rules/01 §1 · rules/05 §8
///
/// Ekran veritabanına inmez: kullanıcılar `AuthService.listUsers()` üzerinden
/// **`AuthUser`** olarak gelir; parola hash'i ve salt'ı bu tipte **yoktur**
/// (BR-SEC-001 · rules/04 §8). Hata mesajları `Failure.userMessage`'dır;
/// teknik detay gösterilmez (REQ-UX-008 · REQ-SEC-007).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/auth/providers.dart';
import '../../core/result/result.dart';
import '../../domain/models/auth_user.dart';
import '../common/form_message.dart';
import '../common/submit_button.dart';

class UserManagementScreen extends ConsumerStatefulWidget {
  /// Test ve odak doğrulaması için sabit anahtarlar.
  static const Key addUserButtonKey = Key('users_add_button');
  static const Key messageKey = Key('users_message');

  static Key tileKey(int userId) => ValueKey('user_tile_$userId');
  static Key activeSwitchKey(int userId) => ValueKey('user_active_$userId');
  static Key editButtonKey(int userId) => ValueKey('user_edit_$userId');

  const UserManagementScreen({super.key});

  @override
  ConsumerState<UserManagementScreen> createState() =>
      _UserManagementScreenState();
}

class _UserManagementScreenState extends ConsumerState<UserManagementScreen> {
  /// Servisten gelen kullanıcıya gösterilebilir hata (örn. EC-AUTH-005).
  String? _message;

  void _showMessage(String message) => setState(() => _message = message);

  void _clearMessage() {
    if (_message != null) setState(() => _message = null);
  }

  void _showInfo(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// BR-AUTH-006 · EC-AUTH-005 — son aktif kullanıcı pasifleştirilemez.
  ///
  /// Kararı **servis** verir; ekran yalnızca reddi gösterir. Aynı kontrolü
  /// burada tekrar etmek iş kuralını iki yere kopyalardı (rules/01 §2).
  Future<void> _setActive(AuthUser user, bool isActive) async {
    _clearMessage();

    final result = await ref
        .read(authServiceProvider)
        .setActive(user.id, isActive);
    if (!mounted) return;

    switch (result) {
      case Ok<void>():
        ref.invalidate(userListProvider);
        _showInfo(AppStringsTr.userUpdated);
      case Err<void>(:final failure):
        _showMessage(failure.userMessage);
    }
  }

  Future<void> _addUser() async {
    _clearMessage();

    final created = await showDialog<bool>(
      context: context,
      builder: (_) => const _AddUserDialog(),
    );
    if (!mounted || !(created ?? false)) return;

    ref.invalidate(userListProvider);
    _showInfo(AppStringsTr.userCreated);
  }

  Future<void> _editDisplayName(AuthUser user) async {
    _clearMessage();

    final updated = await showDialog<bool>(
      context: context,
      builder: (_) => _EditDisplayNameDialog(user: user),
    );
    if (!mounted || !(updated ?? false)) return;

    ref.invalidate(userListProvider);
    _showInfo(AppStringsTr.userUpdated);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final users = ref.watch(userListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStringsTr.usersTitle),
        actions: [
          TextButton.icon(
            key: UserManagementScreen.addUserButtonKey,
            onPressed: _addUser,
            icon: const Icon(Icons.person_add_alt),
            label: const Text(AppStringsTr.userAddAction),
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
                  AppStringsTr.usersDescription,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              if (_message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FormMessage(
                    _message!,
                    key: UserManagementScreen.messageKey,
                  ),
                ),
              Expanded(
                child: users.when(
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

  Widget _buildList(List<AuthUser> users) {
    // REQ-UX-011: her liste ekranının eyleme yönlendiren boş durumu vardır.
    if (users.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(AppStringsTr.usersEmpty, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              SubmitButton(
                label: AppStringsTr.userAddAction,
                onPressed: _addUser,
              ),
            ],
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: users.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final user = users[index];

        return ListTile(
          key: UserManagementScreen.tileKey(user.id),
          // rules/05 §5: durum renkle değil, ikon + metinle de anlatılır.
          leading: Icon(
            user.isActive ? Icons.person_outline : Icons.person_off_outlined,
          ),
          title: Text(user.displayName),
          subtitle: Text(
            '${user.username} · '
            '${user.isActive ? AppStringsTr.userActive : AppStringsTr.userInactive}',
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: UserManagementScreen.editButtonKey(user.id),
                tooltip: AppStringsTr.userEditDisplayNameTitle,
                onPressed: () => _editDisplayName(user),
                icon: const Icon(Icons.edit_outlined),
              ),
              Switch(
                key: UserManagementScreen.activeSwitchKey(user.id),
                value: user.isActive,
                onChanged: (value) => _setActive(user, value),
              ),
            ],
          ),
        );
      },
    );
  }
}

// --- Yeni kullanıcı (docs/17 §11) -------------------------------------------

class _AddUserDialog extends ConsumerStatefulWidget {
  static const Key usernameFieldKey = Key('user_form_username');
  static const Key displayNameFieldKey = Key('user_form_display_name');
  static const Key passwordFieldKey = Key('user_form_password');
  static const Key passwordConfirmFieldKey = Key('user_form_password_confirm');
  static const Key submitButtonKey = Key('user_form_submit');

  const _AddUserDialog();

  @override
  ConsumerState<_AddUserDialog> createState() => _AddUserDialogState();
}

class _AddUserDialogState extends ConsumerState<_AddUserDialog> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();

  final _displayNameFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _passwordConfirmFocus = FocusNode();

  String? _message;
  bool _submitting = false;

  @override
  void dispose() {
    _username.dispose();
    _displayName.dispose();
    // BR-SEC-001: düz metin parola bellekte gereğinden uzun tutulmaz.
    _password.dispose();
    _passwordConfirm.dispose();
    _displayNameFocus.dispose();
    _passwordFocus.dispose();
    _passwordConfirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _submitting = true;
    setState(() => _message = null);

    try {
      final result = await ref
          .read(authServiceProvider)
          .createUser(
            username: _username.text,
            password: _password.text,
            displayName: _displayName.text,
          );
      if (!mounted) return;

      switch (result) {
        case Ok<int>():
          _password.clear();
          _passwordConfirm.clear();
          Navigator.of(context).pop(true);
        case Err<int>(:final failure):
          setState(() => _message = failure.userMessage);
      }
    } finally {
      _submitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(AppStringsTr.userAddTitle),
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
                  key: _AddUserDialog.usernameFieldKey,
                  controller: _username,
                  // rules/05 §1: dialog açıldığında odak ilk alandadır.
                  autofocus: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: AppStringsTr.usernameLabel,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? AppStringsTr.usernameRequired
                      : null,
                  onFieldSubmitted: (_) => _displayNameFocus.requestFocus(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: _AddUserDialog.displayNameFieldKey,
                  controller: _displayName,
                  focusNode: _displayNameFocus,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: AppStringsTr.displayNameLabel,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? AppStringsTr.displayNameRequired
                      : null,
                  onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: _AddUserDialog.passwordFieldKey,
                  controller: _password,
                  focusNode: _passwordFocus,
                  obscureText: true,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: AppStringsTr.passwordLabel,
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value ?? '').isEmpty
                      ? AppStringsTr.passwordRequired
                      : null,
                  onFieldSubmitted: (_) => _passwordConfirmFocus.requestFocus(),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  key: _AddUserDialog.passwordConfirmFieldKey,
                  controller: _passwordConfirm,
                  focusNode: _passwordConfirmFocus,
                  obscureText: true,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: AppStringsTr.passwordConfirmLabel,
                    border: OutlineInputBorder(),
                  ),
                  // Form seviyesi kontrol: iki alanın eşitliği (rules/05 §8).
                  validator: (value) => value == _password.text
                      ? null
                      : AppStringsTr.passwordMismatch,
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
          key: _AddUserDialog.submitButtonKey,
          label: AppStringsTr.addAction,
          onPressed: _submit,
        ),
      ],
    );
  }
}

// --- Görünen ad (docs/17 §11 — serbest) -------------------------------------

class _EditDisplayNameDialog extends ConsumerStatefulWidget {
  static const Key displayNameFieldKey = Key('user_display_name_field');
  static const Key submitButtonKey = Key('user_display_name_submit');

  final AuthUser user;

  const _EditDisplayNameDialog({required this.user});

  @override
  ConsumerState<_EditDisplayNameDialog> createState() =>
      _EditDisplayNameDialogState();
}

class _EditDisplayNameDialogState
    extends ConsumerState<_EditDisplayNameDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayName = TextEditingController(
    text: widget.user.displayName,
  );

  String? _message;
  bool _submitting = false;

  @override
  void dispose() {
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _submitting = true;
    setState(() => _message = null);

    try {
      final result = await ref
          .read(authServiceProvider)
          .updateDisplayName(widget.user.id, _displayName.text);
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
      title: const Text(AppStringsTr.userEditDisplayNameTitle),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: _EditDisplayNameDialog.displayNameFieldKey,
                controller: _displayName,
                autofocus: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: AppStringsTr.displayNameLabel,
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? AppStringsTr.displayNameRequired
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
          key: _EditDisplayNameDialog.submitButtonKey,
          label: AppStringsTr.saveAction,
          onPressed: _submit,
        ),
      ],
    );
  }
}
