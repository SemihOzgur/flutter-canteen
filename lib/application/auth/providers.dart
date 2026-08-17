/// Kimlik doğrulama servislerinin provider'ları (OD-002 — Riverpod).
///
/// ## Neden `data/db/providers.dart` yanında değil
///
/// Bu dosya servisleri kurar; servisler **application** katmanına aittir ve
/// kurulum (construction) bilgisi de oradadır. `data/db/providers.dart` yalnızca
/// bağlantı, repository ve DAO'ları verir (rules/01 §1 — bağımlılık yönü daima
/// aşağı). Aynı desen: bir katmanın provider'ları o katmanda yaşar.
///
/// ## Kilit servisi TEK ÖRNEKTİR — doğruluk koşulu
///
/// BR-AUTH-016 · REQ-AUTH-021: finansal erişim kilidi **yalnızca bellektedir.**
/// Bu nedenle [financialAccessProvider] ile ilgili iki kural bu dosyada
/// bağlayıcıdır:
///
/// | Kural | İhlal edilirse |
/// |---|---|
/// | `autoDispose` **kullanılmaz** | Ekran değişince servis atılır; kilit ya kendiliğinden sıfırlanır ya da yeniden kurulup beklenmedik durumda kalır — BR-AUTH-013 sessizce delinir |
/// | `AuthService` ve `RecoveryCodeService` **aynı** örneği alır | `AuthService.logout()` hayalet bir nesneyi kapatır, gerçek kilit açık kalır (REQ-AUTH-004 ihlali) |
///
/// Riverpod'da `Provider` zaten container yaşamı boyunca tek örnek tutar ve
/// bağımlı provider'lar `ref.watch` ile **aynı** örneği alır. Kural bu yüzden
/// "kendiliğinden" sağlanır — ama sessizce bozulabilir olduğu için
/// `test/application/auth/providers_test.dart` bunu `identical` ile doğrular.
///
/// ## Bekleme sayaçları AYRI örneklerdir
///
/// docs/17 §3 (login), EC-DASH-002 (dashboard parolası) ve EC-REC-002 (kurtarma
/// kodu) üç ayrı bekleme sayacı tanımlar: biri diğerini kilitlememelidir —
/// kullanıcı kurtarma ekranına zaten parolayı unuttuğu için gelir.
///
/// Servisler sayaç verilmezse kendi örneklerini kurar, yani ayrılık bugün de
/// sağlanır. Sayaçların **açıkça** verilmesinin nedeni: tek bir örneği üçüne
/// birden bağlayan bir wiring hatası derlenir, çalışır ve hiçbir servis testi
/// onu yakalayamaz (servis testleri sayacı doğrudan enjekte eder). Açık
/// provider'lar bu görünmez hatayı test edilebilir hâle getirir.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/logging/app_logger.dart';
import '../../data/db/providers.dart';
import 'auth_service.dart';
import 'financial_access_service.dart';
import 'login_throttle.dart';
import 'recovery_code_service.dart';
import 'session_service.dart';
import 'setup_service.dart';

/// Uygulama log'u — `main.dart` `overrideWithValue` ile sağlar.
///
/// Testlerde ve override edilmediğinde `null`'dır: servisler log'u yalnızca
/// **audit yazımı başarısız olursa** kullanır (REQ-AUDIT-007) ve log'suz da
/// doğru çalışır. Bu yüzden `canteenDatabaseProvider` gibi hata fırlatmaz —
/// eksik log bir bug değil, eksik bağlantı bugtır.
final appLoggerProvider = Provider<AppLogger?>((ref) => null);

// --- Bekleme sayaçları (EC-AUTH-002 · EC-DASH-002 · EC-REC-002) -------------

/// Kullanıcı girişi sayacı — anahtar: normalize edilmiş kullanıcı adı.
final loginThrottleProvider = Provider<LoginThrottle>((ref) => LoginThrottle());

/// Dashboard parolası sayacı — anahtar tektir (BR-AUTH-008).
final dashboardThrottleProvider = Provider<LoginThrottle>(
  (ref) => LoginThrottle(),
);

/// Kurtarma kodu sayacı — dashboard parolasınınkinden **ayrıdır**.
final recoveryThrottleProvider = Provider<LoginThrottle>(
  (ref) => LoginThrottle(),
);

// --- Servisler ---------------------------------------------------------------

/// Oturum kalıcılığı (docs/17 §6).
final sessionServiceProvider = Provider<SessionService>(
  (ref) => SessionService(
    settings: ref.watch(appSettingsDaoProvider),
    users: ref.watch(usersDaoProvider),
    clock: ref.watch(canteenDatabaseProvider).clock,
  ),
);

/// Finansal erişim kilidi — **uygulamadaki tek örnek** (BR-AUTH-016).
///
/// `autoDispose` **değildir** ve olmamalıdır: kilit durumu yalnızca bellekte
/// yaşar, servis atılırsa kilit sessizce sıfırlanır.
final financialAccessProvider = Provider<FinancialAccessService>(
  (ref) => FinancialAccessService(
    db: ref.watch(canteenDatabaseProvider),
    settings: ref.watch(appSettingsDaoProvider),
    auditLogs: ref.watch(auditLogsDaoProvider),
    throttle: ref.watch(dashboardThrottleProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

/// Kullanıcı girişi ve kullanıcı yönetimi (docs/17 §2, §3, §11).
final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(
    db: ref.watch(canteenDatabaseProvider),
    users: ref.watch(usersDaoProvider),
    session: ref.watch(sessionServiceProvider),
    // REQ-AUTH-004: logout kilidi kapatır — kilit servisinin **aynı** örneği
    // olmak zorundadır.
    financialAccess: ref.watch(financialAccessProvider),
    throttle: ref.watch(loginThrottleProvider),
  ),
);

/// Dashboard parolası kurtarma akışı (docs/17 §8).
final recoveryCodeServiceProvider = Provider<RecoveryCodeService>(
  (ref) => RecoveryCodeService(
    db: ref.watch(canteenDatabaseProvider),
    settings: ref.watch(appSettingsDaoProvider),
    auditLogs: ref.watch(auditLogsDaoProvider),
    // Kurtarma başarılı olduğunda kilidi açan örnekle aynı olmalıdır.
    financialAccess: ref.watch(financialAccessProvider),
    throttle: ref.watch(recoveryThrottleProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

/// Kurulum sihirbazının hangi adımdan devam edeceğini söyleyen okuma servisi.
final setupServiceProvider = Provider<SetupService>(
  (ref) => SetupService(
    auth: ref.watch(authServiceProvider),
    financialAccess: ref.watch(financialAccessProvider),
    recoveryCode: ref.watch(recoveryCodeServiceProvider),
  ),
);

/// Kurulumun **ilk eksik adımı** — sihirbaz ekranı bunu izler.
///
/// Açılışta `main.dart` aynı soruyu bir kez sorar; sihirbaz ekranı adımlar
/// tamamlandıkça `ref.invalidate` ile tazeler (Faz 3a — sihirbaz adımı).
final setupStateProvider = FutureProvider<SetupState>(
  (ref) => ref.watch(setupServiceProvider).currentState(),
);
