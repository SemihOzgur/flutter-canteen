/// Dashboard parolası kurtarma akışı — **docs/17 §8 · docs/22 F10 ·
/// BR-AUTH-015/017 · REQ-AUTH-025/026/027 · EC-REC-001…006/011**
///
/// ```text
/// Adım 1  Kurtarma kodu girilir
/// Adım 2  Yeni dashboard parolası belirlenir  → tek transaction (servis)
/// Adım 3  YENİ kurtarma kodu bir kez gösterilir
///         ☐ "Kodu kaydettim" işaretlenmeden ekran KAPANMAZ (EC-REC-006)
/// → Finansal erişim kilidi açılır (servis açar) → çağırana `true` döner
/// ```
///
/// ## Neden kod ve parola birlikte gönderiliyor
///
/// docs/17 §8 kurtarmayı **tek transaction** olarak tanımlar (EC-REC-004/005):
/// parola güncelleme, eski kodun geçersizleşmesi, yeni kod üretimi ve audit
/// kaydı bölünemez. Bu yüzden servis tek bir giriş noktası sunar
/// (`resetPasswordWithCode`) ve kodu **yan etkisiz doğrulayan public bir metot
/// bilinçli olarak yoktur** — öyle bir metot kod tahmin etmek için bir oracle
/// olurdu. Ekran bu nedenle kodu Adım 1'de toplar, Adım 2'de parolayla birlikte
/// gönderir; kod hatalıysa kullanıcı mesajla birlikte Adım 1'e döner.
///
/// ## Kod girişi tek alandır
///
/// EC-REC-011: kod **normalize edilerek** karşılaştırılır (tire ve harf durumu
/// esnek), bu yüzden dört ayrı kutu yerine tek alan kullanılır — kullanıcı
/// kodu dosyadan veya panodan olduğu gibi yapıştırabilir. Biçim, alanın
/// ipucunda gösterilir.
///
/// ## Düz metin kod ve parola
///
/// REQ-AUTH-023 · BR-SEC-001: girilen kod, yeni parola ve üretilen yeni kod
/// **yalnızca** bu ekranın durumunda yaşar; log'a, ayara veya audit kaydına
/// yazılmaz. Ekran kapandığında kaybolur.
///
/// ## Katman sınırı — rules/01 §1 · rules/05 §8
///
/// Burada veritabanı erişimi, dosya erişimi veya iş kuralı yoktur. Ekran
/// yalnızca form seviyesinde (boş alan, iki parolanın eşitliği) kontrol yapar;
/// kalan her doğrulama servistedir ve mesajı `Failure.userMessage` ile gelir
/// (REQ-UX-008 · REQ-SEC-007).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/auth/providers.dart';
import '../../application/auth/recovery_code_failures.dart';
import '../../core/result/result.dart';
import '../../data/files/text_file_writer.dart';
import '../common/form_message.dart';
import '../common/save_location_picker.dart';
import '../common/step_layout.dart';
import '../common/submit_button.dart';
import 'recovery_code_display.dart';

/// Akışın adımları (docs/17 §8).
enum _RecoveryStep { code, password, newCode }

class RecoveryFlowScreen extends ConsumerStatefulWidget {
  /// Test ve odak doğrulaması için sabit anahtarlar.
  static const Key codeFieldKey = Key('recovery_code_field');
  static const Key passwordFieldKey = Key('recovery_new_password_field');
  static const Key passwordConfirmFieldKey = Key(
    'recovery_new_password_confirm_field',
  );
  static const Key newCodeTextKey = Key('recovery_new_code_text');
  static const Key newCodeSavedCheckboxKey = Key('recovery_new_code_saved');
  static const Key newCodeCopyButtonKey = Key('recovery_new_code_copy');
  static const Key newCodeSaveButtonKey = Key('recovery_new_code_save');

  /// Her adımın **tek** birincil butonu; aynı anda yalnızca biri ekrandadır.
  static const Key submitButtonKey = Key('recovery_submit_button');

  /// REQ-AUTH-022 — yeni kod dosyaya kaydedilebilir; ikisi de testte enjekte
  /// edilir.
  final SaveLocationPicker savePicker;
  final TextFileWriter fileWriter;

  const RecoveryFlowScreen({
    super.key,
    this.savePicker = pickSaveLocation,
    this.fileWriter = writeTextFile,
  });

  @override
  ConsumerState<RecoveryFlowScreen> createState() => _RecoveryFlowScreenState();
}

class _RecoveryFlowScreenState extends ConsumerState<RecoveryFlowScreen> {
  final _codeFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();

  final _code = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  final _passwordConfirmFocus = FocusNode();

  _RecoveryStep _step = _RecoveryStep.code;

  /// Servisten gelen kullanıcıya gösterilebilir hata.
  String? _message;
  bool _submitting = false;

  /// BR-AUTH-017 ile üretilen **yeni** kodun düz metni — yalnızca burada yaşar.
  String? _newCode;

  /// EC-REC-006 — onay verilmeden ekran kapanmaz.
  bool _saved = false;

  @override
  void dispose() {
    // BR-SEC-001: düz metin kod ve parola bellekte gereğinden uzun tutulmaz.
    _code.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    _passwordConfirmFocus.dispose();
    super.dispose();
  }

  void _goToPasswordStep() {
    if (!(_codeFormKey.currentState?.validate() ?? false)) return;
    setState(() {
      _message = null;
      _step = _RecoveryStep.password;
    });
  }

  /// docs/17 §8 — kod + yeni parola tek transaction'da işlenir.
  Future<void> _reset() async {
    if (_submitting) return;
    if (!(_passwordFormKey.currentState?.validate() ?? false)) return;

    _submitting = true;
    setState(() => _message = null);

    try {
      // docs/18 §2: kurtarma kaydı oturumdaki kullanıcıya bağlanır.
      final userId = (await ref.read(authServiceProvider).currentUser())?.id;
      final result = await ref
          .read(recoveryCodeServiceProvider)
          .resetPasswordWithCode(
            code: _code.text,
            newPassword: _password.text,
            userId: userId,
          );
      if (!mounted) return;

      switch (result) {
        case Ok<String>(:final value):
          // Düz metin parola artık gerekmiyor (BR-SEC-001).
          _password.clear();
          _passwordConfirm.clear();
          _code.clear();
          setState(() {
            _newCode = value;
            _step = _RecoveryStep.newCode;
          });
        case Err<String>(:final failure):
          setState(() {
            _message = failure.userMessage;
            // Koda ait hatalarda (yanlış/kullanılmış/bekleme/kayıt yok) kullanıcı
            // kodu düzeltmelidir → Adım 1. Parolaya ait hatalarda bu adımda
            // kalınır. EC-REC-002/003/012.
            if (_isCodeFailure(failure)) _step = _RecoveryStep.code;
          });
      }
    } finally {
      _submitting = false;
    }
  }

  /// Hata **koda** mı ait (Adım 1'e dönülür), parolaya mı (Adım 2'de kalınır)?
  ///
  /// EC-REC-002/003/012 · EC-DASH-011: kullanıcı yanlış, kullanılmış veya
  /// tanımsız kodu ancak Adım 1'de düzeltebilir; boş parola hatası ise
  /// bulunduğu adıma aittir.
  static bool _isCodeFailure(Failure failure) =>
      failure.code == RecoveryCodeFailures.invalidCode.code ||
      failure.code == RecoveryCodeFailures.alreadyUsed.code ||
      failure.code == RecoveryCodeFailures.notConfigured.code ||
      failure.code == RecoveryCodeFailures.tooManyAttempts(Duration.zero).code;

  @override
  Widget build(BuildContext context) {
    // EC-REC-006: yeni kod ekranı onay verilmeden kapanmaz — sistem geri tuşu
    // ve AppBar geri düğmesi dahil.
    final canLeave = _step != _RecoveryStep.newCode || _saved;

    return PopScope(
      canPop: canLeave,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(AppStringsTr.recoveryTitle),
          automaticallyImplyLeading: canLeave,
        ),
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: switch (_step) {
                _RecoveryStep.code => _buildCodeStep(),
                _RecoveryStep.password => _buildPasswordStep(),
                _RecoveryStep.newCode => _buildNewCodeStep(),
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCodeStep() {
    return Form(
      key: _codeFormKey,
      child: StepLayout(
        stepCounter: AppStringsTr.recoveryStepCounterCode,
        title: AppStringsTr.recoveryCodeStepTitle,
        description: AppStringsTr.recoveryCodeStepDescription,
        children: [
          TextFormField(
            key: RecoveryFlowScreen.codeFieldKey,
            controller: _code,
            // rules/05 §1: açılışta odak ilk alandadır.
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: AppStringsTr.recoveryCodeLabel,
              // EC-REC-011: biçim ipucu; giriş normalize edilerek doğrulanır.
              hintText: AppStringsTr.recoveryCodeHint,
              border: OutlineInputBorder(),
            ),
            validator: (value) => (value ?? '').trim().isEmpty
                ? AppStringsTr.recoveryCodeRequired
                : null,
            onFieldSubmitted: (_) => _goToPasswordStep(),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            FormMessage(_message!),
          ],
          const SizedBox(height: 24),
          SubmitButton(
            key: RecoveryFlowScreen.submitButtonKey,
            label: AppStringsTr.continueAction,
            onPressed: () async => _goToPasswordStep(),
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordStep() {
    return Form(
      key: _passwordFormKey,
      child: StepLayout(
        stepCounter: AppStringsTr.recoveryStepCounterPassword,
        title: AppStringsTr.recoveryPasswordStepTitle,
        description: AppStringsTr.recoveryPasswordStepDescription,
        children: [
          TextFormField(
            key: RecoveryFlowScreen.passwordFieldKey,
            controller: _password,
            autofocus: true,
            obscureText: true,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: AppStringsTr.newDashboardPasswordLabel,
              border: OutlineInputBorder(),
            ),
            validator: (value) => (value ?? '').isEmpty
                ? AppStringsTr.dashboardPasswordRequired
                : null,
            onFieldSubmitted: (_) => _passwordConfirmFocus.requestFocus(),
          ),
          const SizedBox(height: 16),
          TextFormField(
            key: RecoveryFlowScreen.passwordConfirmFieldKey,
            controller: _passwordConfirm,
            focusNode: _passwordConfirmFocus,
            obscureText: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              labelText: AppStringsTr.newDashboardPasswordConfirmLabel,
              border: OutlineInputBorder(),
            ),
            // Form seviyesi kontrol: iki alanın eşitliği (rules/05 §8).
            validator: (value) =>
                value == _password.text ? null : AppStringsTr.passwordMismatch,
            onFieldSubmitted: (_) => _reset(),
          ),
          if (_message != null) ...[
            const SizedBox(height: 16),
            FormMessage(_message!),
          ],
          const SizedBox(height: 24),
          SubmitButton(
            key: RecoveryFlowScreen.submitButtonKey,
            label: AppStringsTr.saveAction,
            onPressed: _reset,
          ),
        ],
      ),
    );
  }

  Widget _buildNewCodeStep() {
    final code = _newCode;
    if (code == null) {
      // Ulaşılamaz: bu adıma yalnızca kod üretildikten sonra geçilir.
      return const FormMessage(AppStringsTr.unexpectedErrorMessage);
    }

    return StepLayout(
      stepCounter: AppStringsTr.recoveryStepCounterNewCode,
      title: AppStringsTr.recoveryNewCodeStepTitle,
      description: AppStringsTr.recoveryNewCodeStepDescription,
      children: [
        RecoveryCodeDisplay(
          code: code,
          savedConfirmed: _saved,
          onSavedChanged: (value) => setState(() => _saved = value),
          savePicker: widget.savePicker,
          fileWriter: widget.fileWriter,
          codeKey: RecoveryFlowScreen.newCodeTextKey,
          copyButtonKey: RecoveryFlowScreen.newCodeCopyButtonKey,
          saveButtonKey: RecoveryFlowScreen.newCodeSaveButtonKey,
          savedCheckboxKey: RecoveryFlowScreen.newCodeSavedCheckboxKey,
        ),
        const SizedBox(height: 16),
        SubmitButton(
          key: RecoveryFlowScreen.submitButtonKey,
          label: AppStringsTr.okAction,
          // EC-REC-006: onay yoksa buton PASİF.
          onPressed: _saved
              // Kilit servis tarafından zaten açıldı (docs/17 §8 son adım);
              // çağırana yalnızca sonuç taşınır.
              ? () async => Navigator.of(context).pop(true)
              : null,
        ),
      ],
    );
  }
}
