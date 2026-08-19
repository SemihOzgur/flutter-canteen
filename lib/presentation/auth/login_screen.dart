/// Giriş ekranı — **docs/17 §3 · REQ-AUTH-001/011/012 · EC-AUTH-001/002/006**
///
/// ```text
/// ┌───────────────────────────────────┐
/// │      🏪  Kantin Otomasyonu        │
/// │   Kullanıcı adı  [____________]   │  ← odak
/// │   Parola         [____________]   │
/// │         [   Giriş Yap   ]         │
/// └───────────────────────────────────┘
/// ```
///
/// | Kural | Karşılığı |
/// |---|---|
/// | Açılışta odak kullanıcı adındadır | `autofocus` (rules/05 §1) |
/// | `Enter` sonraki alana; parolada giriş yapar | `TextInputAction` + `onFieldSubmitted` |
/// | Hangi alanın yanlış olduğu **söylenmez** | Mesaj servisten gelir (EC-AUTH-001) |
/// | 5 hatalı denemeden sonra bekleme süresi gösterilir | `Failure.userMessage` (EC-AUTH-002) |
/// | Kullanıcı adı büyük/küçük harf duyarsızdır | `AuthService.normalizeUsername` (EC-AUTH-006) |
///
/// ## Katman sınırı — rules/01 §1 · rules/05 §8
///
/// Burada veritabanı sorgusu, dosya erişimi veya iş kuralı **yoktur.** Ekran
/// yalnızca form seviyesinde (boş alan) kontrol yapar; kimlik doğrulamanın
/// tamamı `AuthService`'e aittir ve kullanıcı bilgisi sır taşımayan [AuthUser]
/// olarak döner.
///
/// ## Hata mesajı — REQ-UX-008 · REQ-SEC-007
///
/// Ekrana **yalnızca** `Failure.userMessage` basılır. Teknik detay, hata kodu
/// ve stack trace kullanıcıya gösterilmez; beklenmeyen hatalar için genel
/// mesaj kullanılır.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../app/router.dart';
import '../../application/auth/providers.dart';
import '../../core/result/result.dart';
import '../../domain/models/auth_user.dart';
import '../common/form_message.dart';
import '../common/submit_button.dart';

class LoginScreen extends ConsumerStatefulWidget {
  /// Test ve odak doğrulaması için sabit anahtarlar.
  static const Key usernameFieldKey = Key('login_username_field');
  static const Key passwordFieldKey = Key('login_password_field');
  static const Key submitButtonKey = Key('login_submit_button');

  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _usernameFocus = FocusNode();
  final _passwordFocus = FocusNode();

  /// Servisten gelen kullanıcıya gösterilebilir hata (EC-AUTH-001/002).
  String? _message;

  /// `Enter` ve buton aynı gönderimi paylaşır; çift çalıştırma engellenir.
  bool _submitting = false;

  @override
  void dispose() {
    _username.dispose();
    // BR-SEC-001: düz metin parola bellekte gereğinden uzun tutulmaz.
    _password.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
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
          .login(_username.text, _password.text);
      if (!mounted) return;

      switch (result) {
        case Ok<AuthUser>():
          // Parola başarıdan hemen sonra bellekten düşürülür.
          _password.clear();
          // Beklenmez: `pushReplacementNamed`'in future'ı yeni rota
          // kapanana kadar tamamlanmaz; beklenseydi gönderim durumu
          // (ve gösterge) sonsuza dek açık kalırdı.
          unawaited(Navigator.of(context).pushReplacementNamed(AppRoutes.home));
        case Err<AuthUser>(:final failure):
          // EC-AUTH-001: mesaj hangi alanın yanlış olduğunu **söylemez**;
          // ekran da mesajı belirli bir alana bağlamaz.
          setState(() => _message = failure.userMessage);
      }
    } finally {
      _submitting = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.storefront_outlined,
                    size: 64,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    AppStringsTr.appTitle,
                    style: theme.textTheme.titleLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStringsTr.loginDescription,
                    style: theme.textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  TextFormField(
                    key: LoginScreen.usernameFieldKey,
                    controller: _username,
                    focusNode: _usernameFocus,
                    // rules/05 §1: açılışta odak kullanıcı adı alanındadır.
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: AppStringsTr.usernameLabel,
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? AppStringsTr.usernameRequired
                        : null,
                    // docs/17 §3: `Enter` bir sonraki alana geçer.
                    onFieldSubmitted: (_) => _passwordFocus.requestFocus(),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: LoginScreen.passwordFieldKey,
                    controller: _password,
                    focusNode: _passwordFocus,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: AppStringsTr.passwordLabel,
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) => (value ?? '').isEmpty
                        ? AppStringsTr.passwordRequired
                        : null,
                    // docs/17 §3: parola alanında `Enter` giriş yapar.
                    onFieldSubmitted: (_) => _submit(),
                  ),
                  if (_message != null) ...[
                    const SizedBox(height: 16),
                    FormMessage(_message!),
                  ],
                  const SizedBox(height: 24),
                  SubmitButton(
                    key: LoginScreen.submitButtonKey,
                    label: AppStringsTr.loginTitle,
                    onPressed: _submit,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
