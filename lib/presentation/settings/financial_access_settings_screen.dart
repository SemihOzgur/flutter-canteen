/// Ayarlar → Finansal Erişim — **docs/17 §8, §9 · BR-AUTH-010 ·
/// REQ-AUTH-018/028 · EC-DASH-008 · EC-REC-008/009**
///
/// ```text
/// Dashboard parolasını değiştir     mevcut parola + yeni parola (iki kez)
/// Yeni kurtarma kodu üret           mevcut parola → yeni kod BİR KEZ gösterilir
/// ```
///
/// ## Bu ekran kilit ARKASINDA DEĞİLDİR
///
/// BR-AUTH-014 · EC-DASH-014: Ayarlar finansal erişim kilidinin kapsamı
/// dışındadır — kilit yalnızca Dashboard ve Raporlar içindir. Buradaki iki
/// işlem yine de korumasız değildir: ikisi de **mevcut dashboard parolasını**
/// ister (BR-AUTH-010 · EC-REC-008) ve doğrulamayı servis yapar.
///
/// Parolayı değiştirmek kilidi **açmaz** ve açık bir kilidi **kapatmaz**;
/// kurtarma kodu yenilemek de kilide dokunmaz (docs/17 §9).
///
/// ## Mevcut kod bir daha gösterilemez
///
/// Yalnızca hash'i saklandığı için (REQ-AUTH-023) "kodu göster" diye bir işlem
/// **yoktur**; kullanıcı kodunu kaybettiyse yalnızca **yenileyebilir**
/// (docs/17 §8 — EC-REC-009). Yenileme eski kodu geçersizleştirir.
///
/// ## Katman sınırı — rules/01 §1 · rules/05 §8
///
/// Ekranda veritabanı erişimi, dosya erişimi veya iş kuralı yoktur; parolayı
/// ve kodu doğrulayan, transaction açan ve audit yazan taraf servislerdir.
/// Hata mesajları `Failure.userMessage`'dır (REQ-UX-008 · REQ-SEC-007).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/auth/providers.dart';
import '../../core/result/result.dart';
import '../../data/files/text_file_writer.dart';
import '../auth/recovery_code_display.dart';
import '../common/form_message.dart';
import '../common/save_location_picker.dart';
import '../common/submit_button.dart';

class FinancialAccessSettingsScreen extends ConsumerWidget {
  /// Test için sabit anahtarlar.
  static const Key currentPasswordFieldKey = Key('fa_settings_current');
  static const Key newPasswordFieldKey = Key('fa_settings_new');
  static const Key newPasswordConfirmFieldKey = Key('fa_settings_new_confirm');
  static const Key changePasswordButtonKey = Key('fa_settings_change');
  static const Key regeneratePasswordFieldKey = Key('fa_settings_regen_pw');
  static const Key regenerateButtonKey = Key('fa_settings_regen');
  static const Key newCodeTextKey = Key('fa_settings_new_code');
  static const Key newCodeCopyButtonKey = Key('fa_settings_new_code_copy');
  static const Key newCodeSaveButtonKey = Key('fa_settings_new_code_save');
  static const Key newCodeSavedCheckboxKey = Key('fa_settings_new_code_saved');
  static const Key newCodeConfirmButtonKey = Key('fa_settings_new_code_ok');

  /// REQ-AUTH-022 — yeni kod dosyaya kaydedilebilir; testte enjekte edilir.
  final SaveLocationPicker savePicker;
  final TextFileWriter fileWriter;

  const FinancialAccessSettingsScreen({
    super.key,
    this.savePicker = pickSaveLocation,
    this.fileWriter = writeTextFile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStringsTr.financialAccessTitle)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  AppStringsTr.financialAccessSettingsDescription,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                const _ChangeDashboardPasswordSection(),
                const SizedBox(height: 32),
                const Divider(),
                const SizedBox(height: 16),
                _RegenerateRecoveryCodeSection(
                  savePicker: savePicker,
                  fileWriter: fileWriter,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --- Dashboard parolasını değiştir (docs/17 §9 · EC-DASH-008) ---------------

class _ChangeDashboardPasswordSection extends ConsumerStatefulWidget {
  const _ChangeDashboardPasswordSection();

  @override
  ConsumerState<_ChangeDashboardPasswordSection> createState() =>
      _ChangeDashboardPasswordSectionState();
}

class _ChangeDashboardPasswordSectionState
    extends ConsumerState<_ChangeDashboardPasswordSection> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _nextConfirm = TextEditingController();
  final _nextFocus = FocusNode();
  final _nextConfirmFocus = FocusNode();

  String? _message;
  bool _submitting = false;

  @override
  void dispose() {
    // BR-SEC-001: düz metin parola bellekte gereğinden uzun tutulmaz.
    _current.dispose();
    _next.dispose();
    _nextConfirm.dispose();
    _nextFocus.dispose();
    _nextConfirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _submitting = true;
    setState(() => _message = null);

    try {
      // docs/18 §2: değişiklik kaydı oturumdaki kullanıcıya bağlanır.
      final userId = (await ref.read(authServiceProvider).currentUser())?.id;
      final result = await ref
          .read(financialAccessProvider)
          .changePassword(
            current: _current.text,
            next: _next.text,
            userId: userId,
          );
      if (!mounted) return;

      switch (result) {
        case Ok<void>():
          _current.clear();
          _next.clear();
          _nextConfirm.clear();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(AppStringsTr.dashboardPasswordChanged),
            ),
          );
        case Err<void>(:final failure):
          // EC-DASH-008: mevcut parola yanlışsa değişiklik reddedilir.
          setState(() => _message = failure.userMessage);
      }
    } finally {
      _submitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStringsTr.changeDashboardPasswordTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: FinancialAccessSettingsScreen.currentPasswordFieldKey,
            controller: _current,
            obscureText: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: AppStringsTr.currentDashboardPasswordLabel,
              border: OutlineInputBorder(),
            ),
            validator: (value) => (value ?? '').isEmpty
                ? AppStringsTr.dashboardPasswordRequired
                : null,
            onFieldSubmitted: (_) => _nextFocus.requestFocus(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: FinancialAccessSettingsScreen.newPasswordFieldKey,
            controller: _next,
            focusNode: _nextFocus,
            obscureText: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: AppStringsTr.newDashboardPasswordLabel,
              border: OutlineInputBorder(),
            ),
            validator: (value) => (value ?? '').isEmpty
                ? AppStringsTr.dashboardPasswordRequired
                : null,
            onFieldSubmitted: (_) => _nextConfirmFocus.requestFocus(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: FinancialAccessSettingsScreen.newPasswordConfirmFieldKey,
            controller: _nextConfirm,
            focusNode: _nextConfirmFocus,
            obscureText: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: AppStringsTr.newDashboardPasswordConfirmLabel,
              border: OutlineInputBorder(),
            ),
            // Form seviyesi kontrol: iki alanın eşitliği (rules/05 §8).
            validator: (value) =>
                value == _next.text ? null : AppStringsTr.passwordMismatch,
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            FormMessage(_message!),
          ],
          const SizedBox(height: 24),
          SubmitButton(
            key: FinancialAccessSettingsScreen.changePasswordButtonKey,
            label: AppStringsTr.changeDashboardPasswordAction,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

// --- Yeni kurtarma kodu üret (docs/17 §8 · EC-REC-008/009) ------------------

class _RegenerateRecoveryCodeSection extends ConsumerStatefulWidget {
  final SaveLocationPicker savePicker;
  final TextFileWriter fileWriter;

  const _RegenerateRecoveryCodeSection({
    required this.savePicker,
    required this.fileWriter,
  });

  @override
  ConsumerState<_RegenerateRecoveryCodeSection> createState() =>
      _RegenerateRecoveryCodeSectionState();
}

class _RegenerateRecoveryCodeSectionState
    extends ConsumerState<_RegenerateRecoveryCodeSection> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();

  String? _message;
  bool _submitting = false;

  /// Üretilen **yeni** kodun düz metni — yalnızca ekran durumunda yaşar
  /// (REQ-AUTH-023 · BR-SEC-001).
  String? _code;

  /// "Kodu kaydettim" — onay verilmeden kod ekranı kapatılamaz (EC-REC-006
  /// deseni; kod bir daha gösterilemez).
  bool _saved = false;

  @override
  void dispose() {
    // BR-SEC-001: düz metin parola bellekte gereğinden uzun tutulmaz.
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _submitting = true;
    setState(() => _message = null);

    try {
      // docs/18 §2: yenileme kaydı oturumdaki kullanıcıya bağlanır.
      final userId = (await ref.read(authServiceProvider).currentUser())?.id;
      final result = await ref
          .read(recoveryCodeServiceProvider)
          .regenerate(currentPassword: _password.text, userId: userId);
      if (!mounted) return;

      switch (result) {
        case Ok<String>(:final value):
          _password.clear();
          setState(() => _code = value);
        case Err<String>(:final failure):
          // EC-REC-008: parola yanlışsa reddedilir, eski kod geçerli kalır.
          setState(() => _message = failure.userMessage);
      }
    } finally {
      _submitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = _code;

    if (code != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStringsTr.regenerateRecoveryCodeTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          RecoveryCodeDisplay(
            code: code,
            savedConfirmed: _saved,
            onSavedChanged: (value) => setState(() => _saved = value),
            savePicker: widget.savePicker,
            fileWriter: widget.fileWriter,
            codeKey: FinancialAccessSettingsScreen.newCodeTextKey,
            copyButtonKey: FinancialAccessSettingsScreen.newCodeCopyButtonKey,
            saveButtonKey: FinancialAccessSettingsScreen.newCodeSaveButtonKey,
            savedCheckboxKey:
                FinancialAccessSettingsScreen.newCodeSavedCheckboxKey,
          ),
          const SizedBox(height: 16),
          SubmitButton(
            key: FinancialAccessSettingsScreen.newCodeConfirmButtonKey,
            label: AppStringsTr.okAction,
            // Onay verilmeden kod ekrandan kaldırılmaz; kod bir daha
            // gösterilemez (REQ-AUTH-023).
            onPressed: _saved
                ? () async => setState(() {
                    _code = null;
                    _saved = false;
                  })
                : null,
          ),
        ],
      );
    }

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            AppStringsTr.regenerateRecoveryCodeTitle,
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            AppStringsTr.regenerateRecoveryCodeDescription,
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: FinancialAccessSettingsScreen.regeneratePasswordFieldKey,
            controller: _password,
            obscureText: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: AppStringsTr.currentDashboardPasswordLabel,
              border: OutlineInputBorder(),
            ),
            validator: (value) => (value ?? '').isEmpty
                ? AppStringsTr.dashboardPasswordRequired
                : null,
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            FormMessage(_message!),
          ],
          const SizedBox(height: 24),
          SubmitButton(
            key: FinancialAccessSettingsScreen.regenerateButtonKey,
            label: AppStringsTr.regenerateRecoveryCodeAction,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}
