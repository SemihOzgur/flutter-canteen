/// Finansal erişim kilidi — **docs/17 §7, §9 · BR-AUTH-008…014, BR-AUTH-016**
///
/// Dashboard ve Raporlar ekranları, kullanıcı oturumundan **ayrı** bir dashboard
/// parolası ister (BR-AUTH-013). Diğer ekranlar (satış, ürün, stok, kategori,
/// ayarlar) kilit kapsamı **dışındadır** (BR-AUTH-014 · EC-DASH-014) — bu servis
/// onlara hiçbir şekilde karışmaz.
///
/// ## Bu bir rol sistemi DEĞİLDİR
///
/// BR-AUTH-002 · BR-AUTH-008: dashboard parolası **sistemde tektir**, kullanıcıya
/// bağlı değildir ve rol/yetki anlamı taşımaz. Bu dosyada yetki kontrolü
/// bulunmaz ve eklenmez (`rules/04 §2`).
///
/// ## Kilit yalnızca bellektedir
///
/// BR-AUTH-016 · REQ-AUTH-021: kilit **oturum kapsamlıdır**. Bir kez açıldığında
/// logout veya uygulama kapanışına kadar açık kalır; durumu **veritabanına
/// yazılmaz.** Bu nedenle yeni bir uygulama açılışı (yeni servis örneği) daima
/// **kilitli** başlar (EC-DASH-006) ve `app_settings` içinde bir "kilit açık"
/// anahtarı **oluşturulmaz.**
///
/// ## BR-AUTH-012 — kilit görsel bir perde değildir
///
/// > "Parola doğrulanmadan finansal ekranların verisi **sorgulanmaz** ve
/// > gösterilmez." (docs/17 §7 · REQ-AUTH-019 · EC-DASH-001/012)
///
/// Bu kural **servis katmanında** zorlanır: finansal sorgular [guard] üzerinden
/// çalıştırılır ve kilit kapalıyken verilen fonksiyon **hiç çağrılmaz.**
/// Faz 8'in dashboard/rapor veri kaynakları tüketiciye doğrudan değil,
/// [FinancialGate] içine sarılarak verilir — böylece kilidi atlamak için
/// bilinçli olarak sarmalayıcıyı sökmek gerekir.
///
/// ## Kapsam sınırı
///
/// Recovery code akışı (docs/17 §8) bu dosyaya **ait değildir**;
/// `RecoveryCodeService`'e aittir — ona yalnızca üç kanca verilir:
/// [verifyPassword], [applyRecoveredPassword], [unlockAfterRecovery].
/// Bağımlılık tek yönlüdür (bu servis recovery servisini tanımaz), böylece
/// döngüsel bağımlılık oluşmaz. Dashboard/Rapor **ekranları** Faz 8
/// kapsamındadır (`docs/31` — "servis Faz 3'te hazır").
///
/// **Bu serviste henüz audit yazımı yoktur.** REQ-AUTH-020 (`docs/25` — Faz 3)
/// kilit açılışlarının ve başarısız denemelerin de yazılmasını ister
/// (`dashboardUnlocked` / `dashboardUnlockFailed` / `dashboardPasswordChanged`
/// — docs/18 §3); recovery olayları `RecoveryCodeService` tarafından **yazılır**,
/// kilit olayları henüz yazılmaz. Bu servis audit çağrısı **eklenecek** şekilde
/// tasarlanmıştır: tüm kilit geçişleri tek noktadan ([unlock], [lock],
/// [setPassword], [changePassword]) geçer.
///
/// ## Transaction sınırı
///
/// rules/01 §5: transaction **yalnızca bu katmanda** açılır. Hash ve salt iki
/// ayrı `app_settings` satırıdır ve **tek transaction** içinde yazılır; yarım
/// yazım hâlinde parola doğrulanamaz hâle gelirdi.
library;

import '../../core/result/result.dart';
import '../../data/dao/daos.dart';
import '../../data/db/app_setting_keys.dart';
import '../../data/db/canteen_database.dart';
import '../../domain/services/password_hasher.dart';
import 'financial_access_failures.dart';
import 'login_throttle.dart';

class FinancialAccessService {
  /// Throttle anahtarı — dashboard parolası **sistemde tektir** (BR-AUTH-008),
  /// kullanıcı başına değildir; bu yüzden tek sabit anahtar kullanılır.
  static const String throttleKey = 'dashboard';

  final CanteenDatabase _db;
  final AppSettingsDao _settings;
  final PasswordHasher _hasher;
  final LoginThrottle _throttle;
  final DateTime Function() _clock;

  /// BR-AUTH-016: kilit durumu **yalnızca bellekte**. Kalıcılaştırılmaz.
  bool _unlocked = false;

  /// [clock] `rules/06 §7` gereği enjekte edilir; verilmezse veritabanının saat
  /// kaynağı kullanılır — böylece tüm zaman damgaları tek kaynaktan gelir.
  FinancialAccessService({
    required CanteenDatabase db,
    required AppSettingsDao settings,
    PasswordHasher? hasher,
    LoginThrottle? throttle,
    DateTime Function()? clock,
  }) : _db = db,
       _settings = settings,
       _hasher = hasher ?? PasswordHasher(),
       _throttle = throttle ?? LoginThrottle(),
       _clock = clock ?? db.clock;

  // --- Kilit durumu -------------------------------------------------------

  /// Finansal erişim açık mı (BR-AUTH-016).
  ///
  /// Yeni bir servis örneği daima `false` başlar — uygulama kapanışı kilidi
  /// sıfırlar (EC-DASH-006 · REQ-AUTH-021).
  bool get isUnlocked => _unlocked;

  /// Kilidi kapatır.
  ///
  /// Logout bunu çağırır (REQ-AUTH-004 · BR-AUTH-004 · EC-DASH-005); kullanıcı
  /// tekrar giriş yaptığında parola yeniden sorulur.
  void lock() => _unlocked = false;

  /// Recovery akışının **son adımı** — docs/17 §8: *"Finansal erişim kilidi
  /// AÇILIR (kullanıcı zaten doğruladı)"*.
  ///
  /// Yalnızca `RecoveryCodeService` çağırır ve **yalnızca** kodu doğrulayıp
  /// parolayı sıfırlayan transaction commit olduktan sonra: kilit bellekte
  /// tutulduğu için (BR-AUTH-016) rollback onu geri alamazdı — transaction
  /// içinde açılsaydı EC-REC-005'te başarısız bir kurtarma kilidi açık
  /// bırakırdı.
  ///
  /// Bekleme sayacı da sıfırlanır: kullanıcı kimliğini recovery code ile
  /// kanıtlamıştır ve parola artık yenidir; eski hatalı denemelerin cezası
  /// sürmez.
  void unlockAfterRecovery() {
    _throttle.reset(throttleKey);
    _unlocked = true;
  }

  // --- Parola kurulumu ve doğrulaması --------------------------------------

  /// Dashboard parolası belirlenmiş mi (BR-AUTH-009).
  Future<bool> isConfigured() async {
    final hash = await _settings.read(AppSettingKeys.dashboardPasswordHash);
    if (hash == null) return false;
    return await _settings.read(AppSettingKeys.dashboardPasswordSalt) != null;
  }

  /// İlk kurulum — sihirbaz Adım 2 (REQ-AUTH-016 · EC-DASH-011).
  ///
  /// Parola **yalnızca** salt'lı SHA-256 hash olarak `app_settings` içine
  /// yazılır (BR-AUTH-009/011 · BR-SEC-001); düz metin hiçbir satıra, log'a veya
  /// hata mesajına yazılmaz.
  ///
  /// Parola zaten belirlenmişse **reddedilir** — mevcut parolayı bilmeden
  /// değiştirme yolu bırakılmaz (BR-AUTH-010). Değiştirme için
  /// [changePassword], unutulmuşsa recovery code akışı kullanılır.
  ///
  /// EC-DASH-009: dashboard parolasının kullanıcı parolasıyla aynı olması
  /// **serbesttir**; burada karşılaştırma yapılmaz (uyarı bir UI konusudur).
  ///
  /// Parola politikası (uzunluk, karmaşıklık) **kapsam dışıdır** (docs/17 §5);
  /// yalnızca boş olmama kontrolü yapılır.
  Future<Result<void>> setPassword(String password) async {
    if (password.isEmpty) {
      return const Err(FinancialAccessFailures.passwordRequired);
    }

    final secret = _hasher.hash(password);

    return _db.transaction(() async {
      // Kontrol ve yazım aynı transaction içinde: iki eşzamanlı kurulum
      // birbirinin parolasını sessizce ezemez.
      if (await isConfigured()) {
        return const Err<void>(FinancialAccessFailures.alreadyConfigured);
      }
      await _writeSecret(secret);
      return const Ok<void>(null);
    });
  }

  /// Doğru parolayla kilidi açar (docs/17 §7).
  ///
  /// | Kural | Kaynak |
  /// |---|---|
  /// | Ardışık 5 hatalı denemede 30 sn bekleme | EC-DASH-002 · REQ-AUTH-011 |
  /// | Kilit yalnızca bellekte açılır | BR-AUTH-016 |
  /// | Bir kez açılınca oturum boyunca açık kalır | EC-DASH-004/013 |
  ///
  /// Kullanıcı parola ekranından **vazgeçerse** bu metot çağrılmaz ve kilit
  /// kapalı kalır (EC-DASH-003) — vazgeçmenin ayrı bir yan etkisi yoktur.
  Future<Result<void>> unlock(String password) async {
    final now = _clock().toUtc();

    final remaining = _throttle.remainingLock(throttleKey, now);
    if (remaining != null) {
      return Err(FinancialAccessFailures.tooManyAttempts(remaining));
    }

    final stored = await _readSecret();
    if (stored == null) {
      return const Err(FinancialAccessFailures.notConfigured);
    }

    if (!_hasher.verify(password, stored)) {
      _throttle.registerFailure(throttleKey, now);
      return const Err(FinancialAccessFailures.wrongPassword);
    }

    _throttle.reset(throttleKey);
    _unlocked = true;
    return const Ok(null);
  }

  /// Dashboard parolasını değiştirir (docs/17 §9 · BR-AUTH-010 · REQ-AUTH-018).
  ///
  /// EC-DASH-008: **mevcut parola yanlışsa değişiklik reddedilir.**
  ///
  /// Recovery code bu işlemden **etkilenmez** (docs/17 §9 — geçerli kalır) ve
  /// kilit durumu değişmez: parolayı değiştirmek tek başına finansal erişim
  /// açmaz, açık bir kilidi de kapatmaz.
  Future<Result<void>> changePassword({
    required String current,
    required String next,
  }) async {
    if (next.isEmpty) {
      return const Err(FinancialAccessFailures.passwordRequired);
    }

    final stored = await _readSecret();
    if (stored == null) {
      return const Err(FinancialAccessFailures.notConfigured);
    }
    if (!_hasher.verify(current, stored)) {
      return const Err(FinancialAccessFailures.currentPasswordWrong);
    }

    final secret = _hasher.hash(next);
    await _db.transaction(() => _writeSecret(secret));
    return const Ok(null);
  }

  /// Parolayı **yan etkisiz** doğrular: kilidi açmaz, sayaç işletmez.
  ///
  /// Ayarlar → "Yeni Kurtarma Kodu Üret" akışı bunu kullanır (docs/17 §8 ·
  /// EC-REC-008/009): orada istenen kimlik kanıtıdır, finansal ekranlara giriş
  /// değil. Kilidi açmak için [unlock] kullanılır.
  ///
  /// Parola belirlenmemişse `false` döner.
  Future<bool> verifyPassword(String password) async {
    final stored = await _readSecret();
    if (stored == null) return false;
    return _hasher.verify(password, stored);
  }

  /// Recovery akışının parola adımı — docs/17 §8 adım 1.
  ///
  /// ⚠️ Mevcut parola **sorulmaz**: çağıran (`RecoveryCodeService`) recovery
  /// code'u doğrulamış olmalıdır. Bu metot BR-AUTH-010'un istisnası değildir —
  /// BR-AUTH-015 zaten "parola recovery code ile sıfırlanabilir" der.
  ///
  /// Transaction **çağıranındır** (rules/01 §5): kurtarmanın dört adımı tek
  /// transaction'dır, bu yüzden burada yeni bir transaction açılmaz.
  Future<void> applyRecoveredPassword(String password) =>
      _writeSecret(_hasher.hash(password));

  // --- BR-AUTH-012 kapısı ---------------------------------------------------

  /// Finansal bir sorguyu kilidin **arkasında** çalıştırır.
  ///
  /// BR-AUTH-012 · REQ-AUTH-019 · EC-DASH-001/012: kilit kapalıyken [query]
  /// **hiç çağrılmaz** ve `Err` döner — arka planda hiçbir ciro/kâr/maliyet
  /// verisi yüklenmez. Bu davranış docs/27 §6.1b'deki *sorgu sayacı* testiyle
  /// doğrulanır.
  ///
  /// Kilit **yalnızca finansal** sorgular içindir; satış, ürün, stok gibi
  /// işlemler bu kapıdan geçmez (BR-AUTH-014 · EC-DASH-014).
  Future<Result<T>> guard<T>(Future<T> Function() query) async {
    if (!_unlocked) return Err<T>(FinancialAccessFailures.locked);
    return Ok(await query());
  }

  /// Bir finansal veri kaynağını kilidin arkasına koyar.
  ///
  /// Faz 8 tüketicilerine dashboard/rapor sorgu nesnesi **doğrudan** değil,
  /// yalnızca bu sarmalayıcı içinde verilir; böylece kilidi atlamak için
  /// sarmalayıcıyı bilinçli olarak sökmek gerekir ([FinancialGate]).
  FinancialGate<S> gate<S>(S source) => FinancialGate<S>._(this, source);

  // --- Yardımcılar ----------------------------------------------------------

  /// Saklanan hash + salt; parola belirlenmemişse `null`.
  Future<PasswordHash?> _readSecret() async {
    final hash = await _settings.read(AppSettingKeys.dashboardPasswordHash);
    final salt = await _settings.read(AppSettingKeys.dashboardPasswordSalt);
    if (hash == null || salt == null) return null;
    return PasswordHash(hash: hash, salt: salt);
  }

  /// Hash ve salt'ı yazar. Çağıran **transaction açmış olmalıdır**: ikisi
  /// birlikte yazılmazsa parola doğrulanamaz hâle gelir.
  Future<void> _writeSecret(PasswordHash secret) async {
    await _settings.write(AppSettingKeys.dashboardPasswordHash, secret.hash);
    await _settings.write(AppSettingKeys.dashboardPasswordSalt, secret.salt);
  }
}

/// Kilidin arkasına konmuş bir finansal veri kaynağı — **BR-AUTH-012**.
///
/// Sarılan kaynağa **yalnızca** [run] üzerinden erişilebilir; [run] da sorguyu
/// [FinancialAccessService.guard]'a devreder. Kilit kapalıyken sorgu fonksiyonu
/// çağrılmadan `Err` döner.
///
/// ```dart
/// // Faz 8 — tüketiciye kaynağın kendisi değil, kapısı verilir:
/// final gate = financialAccess.gate(dashboardQueries);
/// final result = await gate.run((q) => q.todayRevenue());
/// ```
///
/// Bu tip bir soyutlama katmanı **değildir** (rules/01 §3): tek işi, finansal
/// bir sorgunun kilidi atlamasını "unutulabilir bir çağrı" olmaktan çıkarıp
/// bilinçli bir eyleme dönüştürmektir.
class FinancialGate<S> {
  final FinancialAccessService _access;
  final S _source;

  const FinancialGate._(this._access, this._source);

  /// Kilit açıksa [query]'yi sarılan kaynakla çalıştırır; kapalıysa **çağırmaz.**
  Future<Result<T>> run<T>(Future<T> Function(S source) query) =>
      _access.guard(() => query(_source));
}
