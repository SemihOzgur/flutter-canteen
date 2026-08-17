/// İlk kurulum sihirbazı — **docs/17 §4 · docs/22 F1 ·
/// REQ-AUTH-002/016/022/024 · EC-AUTH-008 · EC-DASH-011 · EC-REC-006**
///
/// ```text
/// Adım 1  Kullanıcı hesabı      [ZORUNLU]  → AuthService.createUser
/// Adım 2  Dashboard parolası    [ZORUNLU]  → FinancialAccessService.setPassword
/// Adım 3  Kurtarma kodu         [ZORUNLU]  → RecoveryCodeService.generateInitial
///         ☐ "Kodu kaydettim" işaretlenmeden [Devam] PASİF (REQ-AUTH-024)
/// → Otomatik giriş → ana ekran
/// ```
///
/// docs/17 §4'ün Adım 4 (KDV oranları) ve Adım 5 (kategoriler) adımları
/// **atlanabilir**dir ve ilgili ekranlar Faz 3b kapsamındadır; bu ekran üç
/// zorunlu adımı yürütür.
///
/// ## Kaldığı adımdan devam eder
///
/// H6 · EC-AUTH-008: üç adım **üç ayrı transaction**'dır (Adım 3 kullanıcı
/// onayı beklediği için tek transaction'a alınamaz — rules/01 §5). Kurulum
/// yarım kalabilir; bu yüzden ekran sabit bir adımdan değil,
/// `SetupService.currentState()`'in bildirdiği **ilk eksik adımdan** başlar.
///
/// ## Otomatik giriş — docs/22 F1
///
/// Adım 1 başarılı olduğunda kullanıcı **hemen** giriş yapar: parola yalnızca o
/// anda bellektedir ve hemen ardından temizlenir (BR-SEC-001). Alternatif olan
/// "parolayı sihirbaz boyunca taşı, sonunda giriş yap" yaklaşımı düz metin
/// parolayı gereğinden uzun süre bellekte tutardı.
///
/// Kurulum yarım kalıp Adım 2'den devam edildiyse oturum yoktur; sihirbaz o
/// durumda giriş ekranına düşer.
///
/// ## Kurtarma kodunun düz metni
///
/// REQ-AUTH-023 · BR-SEC-001: düz metin kod **yalnızca** Adım 3'ün ekran
/// durumunda yaşar. Hiçbir dosyaya, log'a, ayara veya audit kaydına yazılmaz;
/// ekran kapandığında kaybolur ve bir daha gösterilemez (yalnızca hash'i
/// saklanır).
///
/// ## Katman sınırı — rules/01 §1 · rules/05 §8
///
/// Burada veritabanı sorgusu, dosya erişimi veya iş kuralı **yoktur.** Ekran
/// yalnızca form seviyesinde (boş alan, iki parola alanının eşitliği) kontrol
/// yapar; kalan her doğrulama servislerdedir ve mesajı `Failure.userMessage`
/// ile gelir (REQ-UX-008 — teknik detay gösterilmez).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../app/router.dart';
import '../../application/auth/providers.dart';
import '../../application/auth/setup_service.dart';
import '../../core/result/result.dart';
import '../common/form_message.dart';
import 'package:file_selector/file_selector.dart' as file_selector;

import '../../data/files/text_file_writer.dart';
import '../common/submit_button.dart';

/// Kullanıcıya kayıt konumu sorar; iptal edilirse `null`.
///
/// Enjekte edilebilir: widget testi gerçek işletim sistemi dialogu açmaz.
typedef SaveLocationPicker = Future<String?> Function(String suggestedName);

/// Üretim uygulaması — yerel kayıt dialogu.
Future<String?> pickSaveLocation(String suggestedName) async {
  final location = await file_selector.getSaveLocation(
    suggestedName: suggestedName,
  );
  return location?.path;
}

class SetupWizardScreen extends ConsumerWidget {
  /// Test ve odak doğrulaması için sabit anahtarlar.
  static const Key usernameFieldKey = Key('setup_username_field');
  static const Key displayNameFieldKey = Key('setup_display_name_field');
  static const Key passwordFieldKey = Key('setup_password_field');
  static const Key passwordConfirmFieldKey = Key(
    'setup_password_confirm_field',
  );
  static const Key dashboardPasswordFieldKey = Key('setup_dashboard_password');
  static const Key dashboardPasswordConfirmFieldKey = Key(
    'setup_dashboard_password_confirm',
  );
  static const Key recoveryCodeTextKey = Key('setup_recovery_code_text');
  static const Key recoveryCodeSavedCheckboxKey = Key('setup_recovery_saved');
  static const Key recoveryCodeCopyButtonKey = Key('setup_recovery_copy');
  static const Key recoveryCodeSaveButtonKey = Key('setup_recovery_save');

  /// Her adımın **tek** birincil butonu; aynı anda yalnızca biri ekrandadır.
  static const Key submitButtonKey = Key('setup_submit_button');

  /// REQ-AUTH-022 — kod dosyaya kaydedilebilir. İkisi de testte enjekte edilir.
  final SaveLocationPicker savePicker;
  final TextFileWriter fileWriter;

  const SetupWizardScreen({
    super.key,
    this.savePicker = pickSaveLocation,
    this.fileWriter = writeTextFile,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final setupState = ref.watch(setupStateProvider);

    return Scaffold(
      appBar: AppBar(title: const Text(AppStringsTr.setupTitle)),
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
                  AppStringsTr.setupDescription,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                setupState.when(
                  data: (state) => _SetupWizardFlow(
                    initialStep: state,
                    savePicker: savePicker,
                    fileWriter: fileWriter,
                  ),
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  // REQ-SEC-007: teknik detay kullanıcıya gösterilmez.
                  error: (_, _) =>
                      const FormMessage(AppStringsTr.unexpectedErrorMessage),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Adımlar arasında ilerleyen akış.
///
/// Başlangıç adımı servisten gelir; sonraki adımlara geçiş yereldir — her adım
/// kendi transaction'ını zaten kalıcılaştırmıştır, bu yüzden durumu yeniden
/// sorgulamak gerekmez (ve sorgulanırsa ekran gereksiz yere yeniden kurulurdu).
class _SetupWizardFlow extends ConsumerStatefulWidget {
  final SetupState initialStep;
  final SaveLocationPicker savePicker;
  final TextFileWriter fileWriter;

  const _SetupWizardFlow({
    required this.initialStep,
    required this.savePicker,
    required this.fileWriter,
  });

  @override
  ConsumerState<_SetupWizardFlow> createState() => _SetupWizardFlowState();
}

class _SetupWizardFlowState extends ConsumerState<_SetupWizardFlow> {
  late SetupState _step = widget.initialStep;

  void _goTo(SetupState next) => setState(() => _step = next);

  /// Kurulum tamamlandı — docs/22 F1: **otomatik giriş → ana ekran.**
  ///
  /// Oturum Adım 1'de açılır. Kurulum yarım kalıp Adım 2'den devam edildiyse
  /// oturum yoktur; o durumda giriş ekranına düşülür (REQ-AUTH-001).
  Future<void> _finish() async {
    final user = await ref.read(authServiceProvider).currentUser();
    if (!mounted) return;

    unawaited(
      Navigator.of(
        context,
      ).pushReplacementNamed(user == null ? AppRoutes.login : AppRoutes.home),
    );
  }

  @override
  Widget build(BuildContext context) {
    return switch (_step) {
      SetupState.needsUser => _UserStep(
        onCompleted: () => _goTo(SetupState.needsDashboardPassword),
      ),
      SetupState.needsDashboardPassword => _DashboardPasswordStep(
        onCompleted: () => _goTo(SetupState.needsRecoveryCode),
      ),
      SetupState.needsRecoveryCode => _RecoveryCodeStep(
        onCompleted: _finish,
        savePicker: widget.savePicker,
        fileWriter: widget.fileWriter,
      ),
      SetupState.complete => _CompletedStep(onCompleted: _finish),
    };
  }
}

/// Adımların ortak yerleşimi: başlık, adım sayacı, açıklama ve içerik.
class _StepLayout extends StatelessWidget {
  final String stepCounter;
  final String title;
  final String description;
  final List<Widget> children;

  const _StepLayout({
    required this.stepCounter,
    required this.title,
    required this.description,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          stepCounter,
          style: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(description, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 24),
        ...children,
      ],
    );
  }
}

// --- Adım 1 — kullanıcı hesabı (docs/17 §4) ---------------------------------

class _UserStep extends ConsumerStatefulWidget {
  final VoidCallback onCompleted;

  const _UserStep({required this.onCompleted});

  @override
  ConsumerState<_UserStep> createState() => _UserStepState();
}

class _UserStepState extends ConsumerState<_UserStep> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _displayName = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();

  final _usernameFocus = FocusNode();
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
    _usernameFocus.dispose();
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
      final auth = ref.read(authServiceProvider);
      final created = await auth.createUser(
        username: _username.text,
        password: _password.text,
        displayName: _displayName.text,
      );
      if (!mounted) return;

      switch (created) {
        case Err<int>(:final failure):
          setState(() => _message = failure.userMessage);
          return;
        case Ok<int>():
          break;
      }

      // docs/22 F1 — otomatik giriş. Başarısız olursa kurulum yine ilerler;
      // sihirbaz sonunda giriş ekranına düşer (REQ-AUTH-001).
      await auth.login(_username.text, _password.text);

      // Düz metin parola artık gerekmiyor.
      _password.clear();
      _passwordConfirm.clear();

      if (!mounted) return;
      widget.onCompleted();
    } finally {
      _submitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: _StepLayout(
        stepCounter: AppStringsTr.setupStepCounterUser,
        title: AppStringsTr.setupStepUser,
        description: AppStringsTr.setupUserStepDescription,
        children: [
          TextFormField(
            key: SetupWizardScreen.usernameFieldKey,
            controller: _username,
            focusNode: _usernameFocus,
            // rules/05 §1: ilk alan açılışta odaklıdır.
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
            key: SetupWizardScreen.displayNameFieldKey,
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
            key: SetupWizardScreen.passwordFieldKey,
            controller: _password,
            focusNode: _passwordFocus,
            obscureText: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: AppStringsTr.passwordLabel,
              border: OutlineInputBorder(),
            ),
            validator: (value) =>
                (value ?? '').isEmpty ? AppStringsTr.passwordRequired : null,
            onFieldSubmitted: (_) => _passwordConfirmFocus.requestFocus(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: SetupWizardScreen.passwordConfirmFieldKey,
            controller: _passwordConfirm,
            focusNode: _passwordConfirmFocus,
            obscureText: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: AppStringsTr.passwordConfirmLabel,
              border: OutlineInputBorder(),
            ),
            // Form seviyesi kontrol: iki alanın eşitliği (rules/05 §8).
            validator: (value) =>
                value == _password.text ? null : AppStringsTr.passwordMismatch,
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            FormMessage(_message!),
          ],
          const SizedBox(height: 24),
          SubmitButton(
            key: SetupWizardScreen.submitButtonKey,
            label: AppStringsTr.continueAction,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

// --- Adım 2 — dashboard parolası (REQ-AUTH-016 · EC-DASH-011) ---------------

class _DashboardPasswordStep extends ConsumerStatefulWidget {
  final VoidCallback onCompleted;

  const _DashboardPasswordStep({required this.onCompleted});

  @override
  ConsumerState<_DashboardPasswordStep> createState() =>
      _DashboardPasswordStepState();
}

class _DashboardPasswordStepState
    extends ConsumerState<_DashboardPasswordStep> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  final _passwordFocus = FocusNode();
  final _passwordConfirmFocus = FocusNode();

  String? _message;
  bool _submitting = false;

  @override
  void dispose() {
    // BR-SEC-001: düz metin parola bellekte gereğinden uzun tutulmaz.
    _password.dispose();
    _passwordConfirm.dispose();
    _passwordFocus.dispose();
    _passwordConfirmFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    // EC-DASH-011: boş parola ile kurulum ilerlemez.
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _submitting = true;
    setState(() => _message = null);

    try {
      final result = await ref
          .read(financialAccessProvider)
          .setPassword(_password.text);
      if (!mounted) return;

      switch (result) {
        case Ok<void>():
          _password.clear();
          _passwordConfirm.clear();
          widget.onCompleted();
        case Err<void>(:final failure):
          setState(() => _message = failure.userMessage);
      }
    } finally {
      _submitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: _StepLayout(
        stepCounter: AppStringsTr.setupStepCounterDashboardPassword,
        title: AppStringsTr.setupStepDashboardPassword,
        description: AppStringsTr.setupDashboardStepDescription,
        children: [
          TextFormField(
            key: SetupWizardScreen.dashboardPasswordFieldKey,
            controller: _password,
            focusNode: _passwordFocus,
            autofocus: true,
            obscureText: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: AppStringsTr.dashboardPasswordLabel,
              border: OutlineInputBorder(),
            ),
            validator: (value) => (value ?? '').isEmpty
                ? AppStringsTr.dashboardPasswordRequired
                : null,
            onFieldSubmitted: (_) => _passwordConfirmFocus.requestFocus(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: SetupWizardScreen.dashboardPasswordConfirmFieldKey,
            controller: _passwordConfirm,
            focusNode: _passwordConfirmFocus,
            obscureText: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: AppStringsTr.dashboardPasswordConfirmLabel,
              border: OutlineInputBorder(),
            ),
            validator: (value) =>
                value == _password.text ? null : AppStringsTr.passwordMismatch,
            onFieldSubmitted: (_) => _submit(),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            FormMessage(_message!),
          ],
          const SizedBox(height: 24),
          SubmitButton(
            key: SetupWizardScreen.submitButtonKey,
            label: AppStringsTr.continueAction,
            onPressed: _submit,
          ),
        ],
      ),
    );
  }
}

// --- Adım 3 — kurtarma kodu (REQ-AUTH-022/024 · EC-REC-006) -----------------

class _RecoveryCodeStep extends ConsumerStatefulWidget {
  final Future<void> Function() onCompleted;
  final SaveLocationPicker savePicker;
  final TextFileWriter fileWriter;

  const _RecoveryCodeStep({
    required this.onCompleted,
    required this.savePicker,
    required this.fileWriter,
  });

  @override
  ConsumerState<_RecoveryCodeStep> createState() => _RecoveryCodeStepState();
}

class _RecoveryCodeStepState extends ConsumerState<_RecoveryCodeStep> {
  /// Düz metin kod — **yalnızca ekranda yaşar** (REQ-AUTH-023 · BR-SEC-001).
  ///
  /// Hiçbir dosyaya, log'a, ayara veya audit kaydına yazılmaz; ekran
  /// kapandığında kaybolur ve bir daha gösterilemez.
  String? _code;

  String? _message;
  bool _loading = true;

  /// REQ-AUTH-024 · EC-REC-006 — onay verilmeden [Devam] pasiftir.
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    unawaited(_generate());
  }

  Future<void> _generate() async {
    setState(() {
      _loading = true;
      _message = null;
    });

    final result = await ref
        .read(recoveryCodeServiceProvider)
        .generateInitial();
    if (!mounted) return;

    setState(() {
      _loading = false;
      switch (result) {
        case Ok<String>(:final value):
          _code = value;
        case Err<String>(:final failure):
          _message = failure.userMessage;
      }
    });
  }

  Future<void> _copy() async {
    final code = _code;
    if (code == null) return;

    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppStringsTr.setupRecoveryCodeCopied)),
    );
  }

  /// REQ-AUTH-022 — kodu kullanıcının seçtiği bir dosyaya yazar.
  ///
  /// Konumu **kullanıcı** seçer: uygulama düz metin kurtarma kodunu kendi veri
  /// dizinine yazmaz (BR-SEC-001 · rules/04 §5). Yazma işini data katmanı yapar
  /// — presentation dosya sistemine dokunmaz (rules/01 §1).
  ///
  /// Bu işlem **"Kodu kaydettim" onayının yerine geçmez** (REQ-AUTH-024):
  /// dosyaya yazmak kullanıcının kodu gördüğünü ve sakladığını kanıtlamaz.
  Future<void> _saveToFile() async {
    final code = _code;
    if (code == null) return;

    final path = await widget.savePicker(
      AppStringsTr.setupRecoveryCodeSaveFileName,
    );
    // Kullanıcı vazgeçti — sessizce dönülür, hata gösterilmez.
    if (path == null) return;

    String message;
    try {
      await widget.fileWriter(
        path,
        AppStringsTr.recoveryCodeFileContents(code),
      );
      message = AppStringsTr.setupRecoveryCodeSaved;
    } on Object catch (error) {
      // rules/04 §7: dosya yolu ve teknik hata kullanıcıya sızdırılmaz.
      // Kod da loglanmaz (rules/04 §8) — yalnızca hatanın kendisi.
      ref
          .read(appLoggerProvider)
          ?.error('Kurtarma kodu dosyaya yazılamadı', error: error);
      message = AppStringsTr.setupRecoveryCodeSaveFailed;
    }

    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = _code;

    return _StepLayout(
      stepCounter: AppStringsTr.setupStepCounterRecoveryCode,
      title: AppStringsTr.setupStepRecoveryCode,
      description: AppStringsTr.setupRecoveryStepDescription,
      children: [
        if (_loading)
          const Center(child: CircularProgressIndicator())
        else if (code == null) ...[
          FormMessage(_message ?? AppStringsTr.setupRecoveryCodeUnavailable),
          const SizedBox(height: 24),
          SubmitButton(
            key: SetupWizardScreen.submitButtonKey,
            label: AppStringsTr.retryAction,
            onPressed: _generate,
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SelectableText(
              code,
              key: SetupWizardScreen.recoveryCodeTextKey,
              textAlign: TextAlign.center,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // rules/05 §5: uyarı renkle değil, ikon + metinle de anlatılır.
          const FormMessage(
            AppStringsTr.setupRecoveryCodeWarning,
            kind: FormMessageKind.warning,
          ),
          const SizedBox(height: 16),
          // REQ-AUTH-022: kopyalama VE dosyaya kaydetme seçenekleri sunulur.
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: SetupWizardScreen.recoveryCodeCopyButtonKey,
                onPressed: _copy,
                icon: const Icon(Icons.copy_outlined),
                label: const Text(AppStringsTr.setupRecoveryCodeCopy),
              ),
              OutlinedButton.icon(
                key: SetupWizardScreen.recoveryCodeSaveButtonKey,
                onPressed: _saveToFile,
                icon: const Icon(Icons.save_outlined),
                label: const Text(AppStringsTr.setupRecoveryCodeSaveToFile),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            key: SetupWizardScreen.recoveryCodeSavedCheckboxKey,
            value: _saved,
            onChanged: (value) => setState(() => _saved = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text(AppStringsTr.setupRecoveryCodeSavedConfirm),
          ),
          const SizedBox(height: 16),
          SubmitButton(
            key: SetupWizardScreen.submitButtonKey,
            label: AppStringsTr.continueAction,
            // REQ-AUTH-024 · EC-REC-006: onay yoksa buton PASİF.
            onPressed: _saved ? widget.onCompleted : null,
          ),
        ],
      ],
    );
  }
}

// --- Kurulum zaten tamam (yeniden açılış) -----------------------------------

/// Üç adım da tamamlanmışken sihirbaz açılırsa (örn. kurulum başka bir yolla
/// bitmişse) kullanıcı burada kilitlenmez; uygulamaya devam eder.
class _CompletedStep extends StatelessWidget {
  final Future<void> Function() onCompleted;

  const _CompletedStep({required this.onCompleted});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(AppStringsTr.setupComplete, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          AppStringsTr.setupCompleteDescription,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        SubmitButton(
          key: SetupWizardScreen.submitButtonKey,
          label: AppStringsTr.continueAction,
          onPressed: onCompleted,
        ),
      ],
    );
  }
}
