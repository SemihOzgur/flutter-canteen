/// Finansal erişim kapısı — **docs/17 §7 · docs/22 F9 · BR-AUTH-012/013/016 ·
/// REQ-AUTH-015/019/021 · EC-DASH-001…004/012/013**
///
/// ```text
/// ┌──────────────────────────────────┐
/// │  🔒 Finansal Erişim              │
/// │  Dashboard ve Raporlar için      │
/// │  parola gerekiyor.               │
/// │  Parola: [________________]      │  ← odak
/// │  [Şifremi unuttum]               │
/// │        [Vazgeç]  [Aç]            │
/// └──────────────────────────────────┘
/// ```
///
/// ## Dialog kilidi AÇMAKTAN başka bir şey yapmaz — BR-AUTH-012
///
/// > "Parola doğrulanmadan finansal ekranların verisi **sorgulanmaz.**"
///
/// Bu dosyada hiçbir finansal sorgu, hesaplama veya veri kaynağı **yoktur**;
/// burada yalnızca `FinancialAccessService.unlock` çağrılır. Sorguyu asıl
/// engelleyen mekanizma servis katmanındaki `guard`/`FinancialGate`'tir
/// (`rules/04 §4` — "kilit görsel bir perde değildir"). Bu ekran o kapının
/// yalnızca **anahtarını** ister: kilit açılmadan çağıran ekran veri yüklemeye
/// hiç başlamaz, açıldıktan sonra bile sorgular yine kapıdan geçer.
///
/// ## Kullanım — [ensureFinancialAccess]
///
/// ```dart
/// // Faz 8: Dashboard/Raporlar açılmadan ÖNCE:
/// if (!await ensureFinancialAccess(context, ref)) return; // EC-DASH-003
/// ```
///
/// ## Katman sınırı — rules/01 §1 · rules/05 §8
///
/// Burada veritabanı erişimi, dosya erişimi veya iş kuralı yoktur; kullanıcı
/// bilgisi sır taşımayan `AuthUser` olarak alınır ve yalnızca audit kaydının
/// `user_id`'si için kullanılır (docs/18 §2).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/auth/providers.dart';
import '../../core/result/result.dart';
import '../../data/files/text_file_writer.dart';
import '../common/form_message.dart';
import '../common/save_location_picker.dart';
import '../common/submit_button.dart';
import 'recovery_flow_screen.dart';

/// Finansal erişimi güvence altına alır; kilit açıksa **hiçbir şey sormaz.**
///
/// | Durum | Sonuç | Kaynak |
/// |---|---|---|
/// | Kilit zaten açık | `true` — parola tekrar sorulmaz | EC-DASH-004/013 · BR-AUTH-016 |
/// | Doğru parola girildi | `true` | docs/22 F9 |
/// | Kurtarma akışı başarıyla tamamlandı | `true` — kilit servis tarafından açılır | docs/17 §8 |
/// | Vazgeç / `Esc` | `false` — **kilit kapalı kalır** | EC-DASH-003 |
///
/// Çağıran `false` dönüşünde ekranı **açmaz** ve veri yüklemez.
///
/// [savePicker] ve [fileWriter] kurtarma akışının yeni kod adımına geçilir
/// (REQ-AUTH-022); testte enjekte edilir, üretimde varsayılanlar kullanılır.
Future<bool> ensureFinancialAccess(
  BuildContext context,
  WidgetRef ref, {
  SaveLocationPicker savePicker = pickSaveLocation,
  TextFileWriter fileWriter = writeTextFile,
}) async {
  // BR-AUTH-016 · EC-DASH-004: oturum boyunca bir kez sorulur.
  if (ref.read(financialAccessProvider).isUnlocked) return true;

  final unlocked = await showDialog<bool>(
    context: context,
    builder: (_) =>
        FinancialAccessDialog(savePicker: savePicker, fileWriter: fileWriter),
  );

  // `Esc` veya bariyer ile kapatma da vazgeçmedir (EC-DASH-003).
  return unlocked ?? false;
}

class FinancialAccessDialog extends ConsumerStatefulWidget {
  /// Test ve odak doğrulaması için sabit anahtarlar.
  static const Key passwordFieldKey = Key('financial_access_password_field');
  static const Key submitButtonKey = Key('financial_access_submit');
  static const Key cancelButtonKey = Key('financial_access_cancel');
  static const Key forgotButtonKey = Key('financial_access_forgot');

  /// REQ-AUTH-022 — kurtarma akışının yeni kod adımına geçirilir.
  final SaveLocationPicker savePicker;
  final TextFileWriter fileWriter;

  const FinancialAccessDialog({
    super.key,
    this.savePicker = pickSaveLocation,
    this.fileWriter = writeTextFile,
  });

  @override
  ConsumerState<FinancialAccessDialog> createState() =>
      _FinancialAccessDialogState();
}

class _FinancialAccessDialogState extends ConsumerState<FinancialAccessDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  /// Servisten gelen kullanıcıya gösterilebilir hata (EC-DASH-002).
  String? _message;
  bool _submitting = false;

  /// EC-REC-012: kullanılabilir kurtarma kaydı yoksa "Şifremi unuttum"
  /// **gösterilmez.** Varsayılan `false`'tur: cevap gelene kadar var olmayan
  /// bir kurtarma yolu önerilmez.
  bool _recoveryAvailable = false;

  @override
  void initState() {
    super.initState();
    _loadRecoveryAvailability();
  }

  Future<void> _loadRecoveryAvailability() async {
    final available = await ref.read(recoveryCodeServiceProvider).isAvailable();
    if (!mounted) return;
    setState(() => _recoveryAvailable = available);
  }

  @override
  void dispose() {
    // BR-SEC-001: düz metin parola bellekte gereğinden uzun tutulmaz.
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;

    _submitting = true;
    setState(() => _message = null);

    try {
      // docs/18 §2: kilit olayı oturumdaki kullanıcıya bağlanır.
      final userId = (await ref.read(authServiceProvider).currentUser())?.id;
      final result = await ref
          .read(financialAccessProvider)
          .unlock(_password.text, userId: userId);
      if (!mounted) return;

      switch (result) {
        case Ok<void>():
          _password.clear();
          Navigator.of(context).pop(true);
        case Err<void>(:final failure):
          // EC-DASH-002: bekleme süresi dahil mesaj servisten geldiği gibi.
          setState(() => _message = failure.userMessage);
      }
    } finally {
      _submitting = false;
    }
  }

  /// docs/17 §8 · docs/22 F10 — kurtarma akışı.
  ///
  /// Akış başarılıysa kilidi **servis** açar (`unlockAfterRecovery`); dialog
  /// yalnızca sonucu çağırana taşır.
  Future<void> _openRecovery() async {
    final recovered = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecoveryFlowScreen(
          savePicker: widget.savePicker,
          fileWriter: widget.fileWriter,
        ),
      ),
    );
    if (!mounted) return;

    if (recovered ?? false) {
      Navigator.of(context).pop(true);
      return;
    }

    // Kurtarmadan vazgeçildi: kullanıcı parola ekranında kalır, kilit kapalıdır.
    setState(() => _message = null);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.lock_outline),
      title: const Text(AppStringsTr.financialAccessTitle),
      content: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(AppStringsTr.financialAccessDescription),
              const SizedBox(height: 16),
              TextFormField(
                key: FinancialAccessDialog.passwordFieldKey,
                controller: _password,
                focusNode: _passwordFocus,
                // rules/05 §1 · docs/23 §3: dialog açıldığında odak ilk alandadır.
                autofocus: true,
                obscureText: true,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: AppStringsTr.dashboardPasswordLabel,
                  border: OutlineInputBorder(),
                ),
                validator: (value) => (value ?? '').isEmpty
                    ? AppStringsTr.dashboardPasswordRequired
                    : null,
                // Parola alanında `Enter` gönderir (docs/17 §3 deseni).
                onFieldSubmitted: (_) => _submit(),
              ),
              if (_recoveryAvailable) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    key: FinancialAccessDialog.forgotButtonKey,
                    onPressed: _openRecovery,
                    child: const Text(AppStringsTr.financialAccessForgotAction),
                  ),
                ),
              ],
              if (_message != null) ...[
                const SizedBox(height: 8),
                FormMessage(_message!),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: FinancialAccessDialog.cancelButtonKey,
          // EC-DASH-003: kilit kapalı kalır; başka bir yan etki yoktur.
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text(AppStringsTr.cancelAction),
        ),
        SubmitButton(
          key: FinancialAccessDialog.submitButtonKey,
          label: AppStringsTr.financialAccessUnlockAction,
          onPressed: _submit,
        ),
      ],
    );
  }
}
