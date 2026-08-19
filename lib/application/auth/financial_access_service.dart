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
/// Son ikisi **yalnızca** `RecoveryCodeService`'in üretebildiği bir yetenek
/// nesnesi ([RecoveryProof]) ister; ayrıntı için o iki metodun dokümantasyonuna
/// bakın. Bu servis recovery servisinin bir **örneğine** bağımlı değildir
/// (yalnızca kanıt tipini tanır), bu yüzden kurulum sırası hâlâ tek yönlüdür.
/// Dashboard/Rapor **ekranları** Faz 8 kapsamındadır (`docs/31` — "servis
/// Faz 3'te hazır").
///
/// ## Audit — REQ-AUTH-020 · docs/18 §3
///
/// Kilit olayları denetim kaydına yazılır: [actionUnlocked] ·
/// [actionUnlockFailed] · [actionPasswordChanged]. **Parola, hash ve salt asla
/// yazılmaz** (REQ-AUDIT-004 · rules/04 §8) — audit'e yalnızca olayın kendisi
/// ve `dashboardUnlockFailed` için ardışık deneme sayısı gider.
///
/// Genel `AuditService` Faz 6'da gelecek ve bu yazımı devralacaktır
/// (`docs/25` — REQ-AUDIT-012); REQ-AUTH-020 ise Faz 3'tedir, bu yüzden kilit
/// olaylarının yazımı burada başlar.
///
/// ## Transaction sınırı
///
/// rules/01 §5: transaction **yalnızca bu katmanda** açılır. Hash ve salt iki
/// ayrı `app_settings` satırıdır ve **tek transaction** içinde yazılır; yarım
/// yazım hâlinde parola doğrulanamaz hâle gelirdi.
library;

import '../audit/audit_actions.dart';
import 'dart:convert';

import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../data/dao/daos.dart';
import '../../data/db/app_setting_keys.dart';
import '../../data/db/canteen_database.dart';
import '../../domain/services/password_hasher.dart';
import 'financial_access_failures.dart';
import 'login_throttle.dart';
// Yalnızca [RecoveryProof] **tipi** için — bu servis `RecoveryCodeService`
// örneği tutmaz ve onu çağırmaz. Kanıt nesnesinin yapıcısı private olduğundan
// tip, onu üretebilen library'de yaşamak zorundadır (H4 gerekçesi).
import 'recovery_code_service.dart';

class FinancialAccessService {
  /// Throttle anahtarı — dashboard parolası **sistemde tektir** (BR-AUTH-008),
  /// kullanıcı başına değildir; bu yüzden tek sabit anahtar kullanılır.
  static const String throttleKey = AuditEntities.dashboard;

  /// Audit `entity_type` — dashboard parolası sistem geneli tek bir varlıktır,
  /// bu yüzden `entity_id` yoktur (docs/18 §2: sistem işlemlerinde `NULL`).
  ///
  /// Recovery olayları da aynı varlığa aittir; `RecoveryCodeService` bu sabiti
  /// yeniden kullanır (tek kaynak).
  static const String auditEntityType = AuditEntities.dashboard;

  /// docs/18 §3 — parola/hash/salt **yazılmaz**, yalnızca olayın kendisi.
  static const String actionUnlocked = AuditActions.dashboardUnlocked;
  static const String actionUnlockFailed = AuditActions.dashboardUnlockFailed;
  static const String actionPasswordChanged =
      AuditActions.dashboardPasswordChanged;

  final CanteenDatabase _db;
  final AppSettingsDao _settings;
  final AuditLogsDao _auditLogs;
  final PasswordHasher _hasher;
  final LoginThrottle _throttle;
  final DateTime Function() _clock;
  final AppLogger? _logger;

  /// BR-AUTH-016: kilit durumu **yalnızca bellekte**. Kalıcılaştırılmaz.
  bool _unlocked = false;

  /// [clock] `rules/06 §7` gereği enjekte edilir; verilmezse veritabanının saat
  /// kaynağı kullanılır — böylece tüm zaman damgaları tek kaynaktan gelir.
  ///
  /// [auditLogs] **zorunludur**: REQ-AUTH-020 kilit olaylarının yazılmasını
  /// ister. Opsiyonel olsaydı bir provider tanımında unutulduğunda denetim izi
  /// sessizce kaybolurdu ve hiçbir test bunu yakalamazdı.
  ///
  /// [logger] yalnızca **audit yazımı başarısız olursa** kullanılır
  /// (REQ-AUDIT-007); parola, hash veya salt loglanmaz (rules/04 §8).
  FinancialAccessService({
    required CanteenDatabase db,
    required AppSettingsDao settings,
    required AuditLogsDao auditLogs,
    PasswordHasher? hasher,
    LoginThrottle? throttle,
    DateTime Function()? clock,
    AppLogger? logger,
  }) : _db = db,
       _settings = settings,
       _auditLogs = auditLogs,
       _hasher = hasher ?? PasswordHasher(),
       _throttle = throttle ?? LoginThrottle(),
       _clock = clock ?? db.clock,
       _logger = logger;

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
  /// ## Neden [RecoveryProof] isteniyor
  ///
  /// Bu metot dashboard parolasını **sormadan** kilidi açar. Serbestçe
  /// çağrılabilir olsaydı, servis Riverpod ile presentation'a açıldığı anda
  /// `ref.read(...).unlockAfterRecovery()` derlenen, testten geçen bir
  /// **BR-AUTH-012/013 bypass'ı** olurdu. [RecoveryProof]'un yapıcısı
  /// `RecoveryCodeService` library'sine private'tır: kanıtı yalnızca kurtarma
  /// kodunu doğrulamış olan akış üretebilir, presentation üretemez.
  ///
  /// Çağrı **yalnızca** kodu doğrulayıp parolayı sıfırlayan transaction commit
  /// olduktan sonra yapılır: kilit bellekte tutulduğu için (BR-AUTH-016)
  /// rollback onu geri alamazdı — transaction içinde açılsaydı EC-REC-005'te
  /// başarısız bir kurtarma kilidi açık bırakırdı.
  ///
  /// Bekleme sayacı da sıfırlanır: kullanıcı kimliğini recovery code ile
  /// kanıtlamıştır ve parola artık yenidir; eski hatalı denemelerin cezası
  /// sürmez.
  ///
  /// Ayrı bir `dashboardUnlocked` kaydı **yazılmaz**: docs/22 F10 bu akışın
  /// denetim kaydını `dashboardRecoveryUsed` olarak tanımlar ve o kayıt
  /// kurtarma transaction'ı içinde zaten yazılmıştır (docs/18 §3). Aynı
  /// kullanıcı eylemi için ikinci bir satır denetim izini çoğaltırdı.
  void unlockAfterRecovery(RecoveryProof proof) {
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
  ///
  /// Audit yazılmaz: docs/18 §3 kurulumda parola belirlemek için bir action
  /// tanımlamaz (`dashboardPasswordChanged` docs/17 §9'daki **değiştirme**
  /// akışına aittir). Kurulum sihirbazı sistemin ilk anıdır; denetlenecek bir
  /// "önceki durum" yoktur. `RecoveryCodeService.generateInitial` ile aynı
  /// gerekçe.
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
  ///
  /// Audit (REQ-AUTH-020 · docs/17 §7 · docs/22 F9):
  ///
  /// | Sonuç | Kayıt |
  /// |---|---|
  /// | Doğru parola | [actionUnlocked] |
  /// | Yanlış parola | [actionUnlockFailed] + ardışık deneme sayısı |
  /// | Bekleme sırasında (EC-DASH-002) | **kayıt yok** — parola denenmedi bile |
  /// | Parola hiç kurulmamış | **kayıt yok** — denemeyle ilgili değil |
  ///
  /// [userId] verilirse kayıt kullanıcıya bağlanır (docs/18 §2); kilit ekranı
  /// oturum açıkken kullanıldığı için normalde doludur.
  Future<Result<void>> unlock(String password, {int? userId}) async {
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
      await _writeAudit(
        action: actionUnlockFailed,
        now: now,
        userId: userId,
        // docs/18 §3: `dashboardUnlockFailed` → ardışık deneme sayısı.
        metadata: {'attempts': _throttle.failureCount(throttleKey)},
      );
      return const Err(FinancialAccessFailures.wrongPassword);
    }

    _throttle.reset(throttleKey);
    _unlocked = true;
    await _writeAudit(action: actionUnlocked, now: now, userId: userId);
    return const Ok(null);
  }

  /// Dashboard parolasını değiştirir (docs/17 §9 · BR-AUTH-010 · REQ-AUTH-018).
  ///
  /// EC-DASH-008: **mevcut parola yanlışsa değişiklik reddedilir.**
  ///
  /// Recovery code bu işlemden **etkilenmez** (docs/17 §9 — geçerli kalır) ve
  /// kilit durumu değişmez: parolayı değiştirmek tek başına finansal erişim
  /// açmaz, açık bir kilidi de kapatmaz.
  ///
  /// docs/17 §9 · REQ-AUTH-020: değişiklik audit'e [actionPasswordChanged]
  /// olarak yazılır — **parola değeri yazılmaz.** Kayıt, parolayı yazan
  /// transaction'ın **içindedir** (rules/03 §9/1); reddedilen denemeler hiçbir
  /// şey değiştirmediği için kayıt üretmez (docs/18 §4 — "veriyi değiştiren
  /// işlemler").
  Future<Result<void>> changePassword({
    required String current,
    required String next,
    int? userId,
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
    final now = _clock().toUtc();

    await _db.transaction(() async {
      await _writeSecret(secret);
      await _writeAudit(
        action: actionPasswordChanged,
        now: now,
        userId: userId,
      );
    });
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
  /// ⚠️ Mevcut parola **sorulmaz**: [proof], çağıranın recovery code'u
  /// doğruladığının kanıtıdır. Bu metot BR-AUTH-010'un istisnası değildir —
  /// BR-AUTH-015 zaten "parola recovery code ile sıfırlanabilir" der.
  ///
  /// ## Neden [RecoveryProof] isteniyor
  ///
  /// Kanıtsız çağrılabilseydi, kod doğrulamadan dashboard parolasını yazan bir
  /// public metot presentation'a açılmış olurdu (BR-AUTH-010 bypass'ı).
  /// [RecoveryProof]'un yapıcısı `RecoveryCodeService` library'sine private'tır.
  ///
  /// ## Yarım yazım koruması
  ///
  /// Hash ve salt **iki ayrı** `app_settings` satırıdır; yalnızca biri yazılırsa
  /// dashboard parolası doğrulanamaz hâle gelir. Bu yüzden yazım artık
  /// çağıranın transaction açmış olmasına **güvenmez**: kendi transaction'ını
  /// açar. Kurtarma akışı gibi zaten bir transaction içindeyse Drift bunu
  /// **iç içe** çalıştırır (savepoint) — dış transaction geri alınırsa bu yazım
  /// da geri alınır, dolayısıyla EC-REC-004/005 atomikliği korunur. Transaction
  /// dışında çağrılırsa ikili yazım yine tek parça kalır.
  Future<void> applyRecoveredPassword(String password, RecoveryProof proof) {
    final secret = _hasher.hash(password);
    return _db.transaction(() => _writeSecret(secret));
  }

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

  /// Audit kaydı — **parola, hash ve salt ASLA yazılmaz**
  /// (REQ-AUDIT-004 · rules/04 §8 · rules/03 §9/5).
  ///
  /// REQ-AUDIT-007: audit yazımındaki bir hata ana işlemi **başarısız kılmaz** —
  /// yakalanır ve log dosyasına yazılır. Aksi hâlde denetim uğruna kilit açma
  /// veya parola değiştirme kaybedilirdi; [changePassword]'de kayıt parola
  /// yazımıyla aynı transaction içinde olduğu için hata yukarı taşınsaydı
  /// parolayı da geri alırdı.
  ///
  /// Deseni `RecoveryCodeService._writeAudit` ile birebir aynıdır; ikisi de
  /// Faz 6'da genel `AuditService`'e devredilecektir (REQ-AUDIT-012).
  Future<void> _writeAudit({
    required String action,
    required DateTime now,
    int? userId,
    Map<String, Object?>? metadata,
  }) async {
    try {
      await _auditLogs.record(
        createdAt: now,
        action: action,
        entityType: auditEntityType,
        userId: userId,
        metadata: metadata == null ? null : jsonEncode(metadata),
      );
    } on Object catch (error, stackTrace) {
      _logger?.error(
        'Denetim kaydı yazılamadı ($action).',
        error: error,
        stackTrace: stackTrace,
      );
    }
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
