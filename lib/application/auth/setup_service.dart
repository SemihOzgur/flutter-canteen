/// Kurulum sihirbazının durumu — **docs/17 §4 · docs/22 F1 ·
/// REQ-AUTH-002/016/022/024 · EC-AUTH-008 · EC-DASH-011**
///
/// ## Neden tek bir sinyal gerekiyor
///
/// Sihirbazın üç zorunlu adımı (docs/17 §4) **üç ayrı transaction**'dır:
///
/// ```text
/// Adım 1  AuthService.createUser              → users satırı
/// Adım 2  FinancialAccessService.setPassword  → app_settings hash + salt
/// Adım 3  RecoveryCodeService.generateInitial → app_settings hash + salt
/// ```
///
/// Bunları tek transaction'a almak mümkün değildir: Adım 3'ün ürettiği kod
/// kullanıcıya **gösterilip onaylanmalıdır** (REQ-AUTH-024) ve transaction
/// içinde UI beklemesi yasaktır (rules/01 §5).
///
/// Dolayısıyla kurulum **yarım kalabilir**. Açılışta yalnızca "kullanıcı var mı"
/// sorulursa:
///
/// | Nerede kalındı | Yalnızca `needsSetup` ile sonuç |
/// |---|---|
/// | Adım 1'den sonra çökme | Login ekranı açılır; dashboard parolası **ve** kurtarma kodu yoktur |
/// | Adım 2'den sonra çökme | Kurtarma kodu yoktur; `isAvailable()` false olduğu için EC-REC-012 gereği "Şifremi unuttum" hiç gösterilmez — kullanıcı eksiği **fark etmez** ve REQ-AUTH-022/024 sessizce atlanmış olur |
///
/// Bu servis bootstrap'ın soracağı **tek soruyu** ([currentState]) üretir;
/// sihirbaz kaldığı adımdan devam edebilir.
///
/// ## rules/01 §3 — yeni sınıf gerekçesi (karar testi)
///
/// 1. **Bugün en az iki somut kullanımı var mı?** Açılış (bootstrap) yönlendirmesi
///    ve kurulum sihirbazının "sıradaki adım" mantığı — ikisi de Faz 3'te
///    gerçektir.
/// 2. **Bir servis testini anlamlı şekilde mümkün kılıyor mu?** Evet: yarım
///    kurulum senaryoları UI olmadan, doğrudan doğrulanabilir hâle gelir.
/// 3. **Neden mevcut bir servise eklenmedi?** Sinyal üç konuyu birden okur.
///    `AuthService`'e konsaydı, o dosyanın açıkça yazılı kapsam sınırı
///    ("dashboard parolası ve recovery code bu dosyaya sızdırılmaz") ihlal
///    edilirdi. Bu sınıf yeni bir katman/soyutlama değil, üç servisi okuyan ince
///    bir **okuma** servisidir; yazma yapmaz.
///
/// Kurulumun **adımlarını çalıştırmak** bu servisin işi değildir: her adım kendi
/// servisinde kalır ve orada test edilir.
library;

import 'auth_service.dart';
import 'financial_access_service.dart';
import 'recovery_code_service.dart';

/// Kurulumun tamamlanma durumu — sihirbazın hangi adımdan devam edeceği.
///
/// Sıra docs/17 §4'teki adım sırasıdır; her değer "ilk eksik adımı" gösterir.
enum SetupState {
  /// Üç zorunlu adım da tamamlanmış: uygulama normal açılabilir.
  complete,

  /// Adım 1 eksik — hiç kullanıcı yok (REQ-AUTH-002 · EC-AUTH-008).
  needsUser,

  /// Adım 2 eksik — dashboard parolası belirlenmemiş
  /// (REQ-AUTH-016 · EC-DASH-011 · BR-AUTH-009).
  needsDashboardPassword,

  /// Adım 3 eksik — kurtarma kodu üretilmemiş (REQ-AUTH-022 · BR-AUTH-015).
  needsRecoveryCode,
}

class SetupService {
  final AuthService _auth;
  final FinancialAccessService _financialAccess;
  final RecoveryCodeService _recoveryCode;

  SetupService({
    required AuthService auth,
    required FinancialAccessService financialAccess,
    required RecoveryCodeService recoveryCode,
  }) : _auth = auth,
       _financialAccess = financialAccess,
       _recoveryCode = recoveryCode;

  /// Kurulumun **ilk eksik adımı**; eksik yoksa [SetupState.complete].
  ///
  /// Adımlar docs/17 §4 sırasıyla kontrol edilir: bir adım eksikse sonrakine
  /// bakılmaz — sihirbaz zaten oradan devam edecektir.
  ///
  /// Kurtarma kodu için "kayıt var mı" ([RecoveryCodeService.isConfigured])
  /// sorulur, "kullanılabilir mi" değil: kullanılmış bir kod kurulumun
  /// yapılmadığı anlamına gelmez (EC-REC-010 — restore sonrası). Kullanılabilirlik
  /// ayrı bir sorudur ve EC-REC-012'ye aittir.
  Future<SetupState> currentState() async {
    if (await _auth.needsSetup()) return SetupState.needsUser;
    if (!await _financialAccess.isConfigured()) {
      return SetupState.needsDashboardPassword;
    }
    if (!await _recoveryCode.isConfigured()) {
      return SetupState.needsRecoveryCode;
    }
    return SetupState.complete;
  }

  /// Kurulum tamamlanmış mı — [currentState] üzerinden kısayol.
  Future<bool> isComplete() async =>
      await currentState() == SetupState.complete;
}
