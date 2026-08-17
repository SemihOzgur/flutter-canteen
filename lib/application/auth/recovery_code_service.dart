/// Dashboard parolası kurtarma — **docs/17 §8 · BR-AUTH-015/017 ·
/// REQ-AUTH-022…028 · EC-REC-001…012**
///
/// Kurtarma kodu **yalnızca dashboard parolasına** aittir; kullanıcı parolası
/// için kurtarma yolu yoktur (docs/17 §1). Bu servis rol/yetki kavramı
/// içermez (BR-AUTH-002).
///
/// ## Düz metin kod yalnızca dönüş değerinde yaşar
///
/// BR-SEC-001 · REQ-AUTH-023: düz metin kod **hiçbir yere** yazılmaz — ne
/// `app_settings`'e, ne audit kaydına, ne log dosyasına, ne yedeğe. Üretildiği
/// anda çağırana döndürülür (UI onu bir kez gösterir) ve serviste tutulmaz;
/// veritabanına yalnızca salt'lı SHA-256 hash'i gider.
///
/// ## Saklama (docs/17 §8)
///
/// ```text
/// app_settings['dashboard_recovery_hash']    → SHA-256(kod + salt)
/// app_settings['dashboard_recovery_salt']    → rastgele salt
/// app_settings['dashboard_recovery_used_at'] → kullanıldıysa UTC ms, yoksa yok
/// ```
///
/// ## Neden tek transaction
///
/// EC-REC-004/005 · docs/17 §8: kurtarmanın **dört adımı** (parola güncelleme,
/// eski kodu geçersizleştirme, yeni kod üretimi, audit) tek transaction'dır.
/// Biri başarısızsa hiçbiri uygulanmaz; eski parola ve eski kod geçerli kalır.
///
/// **BR-AUTH-017 neden var:** kod tek kullanımlık olduğu için yenisi
/// üretilmezse kullanıcı ikinci kez parola unuttuğunda kalıcı olarak
/// kilitlenirdi (docs/17 §8).
library;

import 'dart:convert';
import 'dart:math';

import '../../core/logging/app_logger.dart';
import '../../core/result/result.dart';
import '../../data/dao/daos.dart';
import '../../data/db/app_setting_keys.dart';
import '../../data/db/canteen_database.dart';
import '../../domain/services/password_hasher.dart';
import '../../domain/services/recovery_code.dart';
import 'financial_access_failures.dart';
import 'financial_access_service.dart';
import 'login_throttle.dart';
import 'recovery_code_failures.dart';

class RecoveryCodeService {
  /// Throttle anahtarı — recovery code **sistemde tektir** (dashboard
  /// parolası gibi, BR-AUTH-008), kullanıcı başına değildir.
  ///
  /// Dashboard parolasının anahtarından ([FinancialAccessService.throttleKey])
  /// ayrıdır: parola denemeleri kurtarma denemelerini kilitlememelidir —
  /// kullanıcı buraya zaten parolayı unuttuğu için gelir.
  static const String throttleKey = 'dashboard_recovery';

  /// Audit `entity_type` — dashboard parolası sistem geneli tek bir varlıktır,
  /// bu yüzden `entity_id` yoktur (docs/18 §2: sistem işlemlerinde `NULL`).
  static const String auditEntityType = 'dashboard';

  /// docs/18 §3 — kod değeri **yazılmaz**, yalnızca olayın kendisi.
  static const String actionRecoveryUsed = 'dashboardRecoveryUsed';
  static const String actionRecoveryFailed = 'dashboardRecoveryFailed';
  static const String actionRecoveryRegenerated =
      'dashboardRecoveryRegenerated';

  final CanteenDatabase _db;
  final AppSettingsDao _settings;
  final AuditLogsDao _auditLogs;
  final FinancialAccessService _financialAccess;
  final PasswordHasher _hasher;
  final LoginThrottle _throttle;
  final Random _random;
  final DateTime Function() _clock;
  final AppLogger? _logger;

  /// [random] ve [clock] `rules/06 §7` gereği enjekte edilir; verilmezse
  /// üretim değerleri kullanılır ([Random.secure] ve veritabanının saati).
  ///
  /// [logger] yalnızca **audit yazımı başarısız olursa** kullanılır
  /// (REQ-AUDIT-007); kod, parola, hash veya salt loglanmaz (rules/04 §8).
  RecoveryCodeService({
    required CanteenDatabase db,
    required AppSettingsDao settings,
    required AuditLogsDao auditLogs,
    required FinancialAccessService financialAccess,
    PasswordHasher? hasher,
    LoginThrottle? throttle,
    Random? random,
    DateTime Function()? clock,
    AppLogger? logger,
  }) : _db = db,
       _settings = settings,
       _auditLogs = auditLogs,
       _financialAccess = financialAccess,
       _hasher = hasher ?? PasswordHasher(),
       _throttle = throttle ?? LoginThrottle(),
       _random = random ?? Random.secure(),
       _clock = clock ?? db.clock,
       _logger = logger;

  // --- Durum sorguları ------------------------------------------------------

  /// Sistemde bir recovery kaydı var mı (kullanılmış olsa bile).
  Future<bool> isConfigured() async => await _readStored() != null;

  /// Kullanılabilir bir kurtarma kodu var mı — **EC-REC-012**.
  ///
  /// `false` ise finansal erişim ekranında **"Şifremi unuttum" gösterilmez**:
  /// eski bir kurulumda recovery kaydı hiç olmayabilir. Parola değiştirme yolu
  /// (mevcut parolayla) her hâlükârda açık kalır.
  Future<bool> isAvailable() async {
    if (await _readStored() == null) return false;
    return await _readUsedAt() == null;
  }

  // --- Kurulum sihirbazı Adım 3 (REQ-AUTH-022) ------------------------------

  /// İlk kodu üretir ve **düz metnini döndürür** — kurulum sihirbazı Adım 3.
  ///
  /// Dönen değer kullanıcıya **bir kez** gösterilir (REQ-AUTH-022/024); servis
  /// onu saklamaz, yalnızca hash'ini yazar (REQ-AUTH-023).
  ///
  /// Kod zaten üretilmişse **reddedilir**: yenileme, mevcut dashboard
  /// parolasını gerektiren ayrı bir akıştır ([regenerate] · EC-REC-008/009).
  /// Aksi hâlde parolayı bilmeyen biri geçerli kodu sessizce değiştirebilirdi.
  ///
  /// Audit yazılmaz: docs/18 §3 kurulumda kod üretimi için bir action
  /// tanımlamaz (REQ-AUDIT-001 "§3'te listelenen tüm işlemler" der) — kurulum
  /// sihirbazı zaten sistemin ilk anıdır ve denetlenecek bir "önceki durum"
  /// yoktur.
  Future<Result<String>> generateInitial() {
    return _db.transaction(() async {
      // Kontrol ve yazım aynı transaction içinde: iki eşzamanlı kurulum
      // birbirinin kodunu sessizce ezemez.
      if (await _readStored() != null) {
        return const Err<String>(RecoveryCodeFailures.alreadyConfigured);
      }
      return Ok(await _storeNewCode());
    });
  }

  // --- Kurtarma akışı (docs/17 §8) ------------------------------------------

  /// Recovery code ile dashboard parolasını sıfırlar — **REQ-AUTH-025/026/027**
  ///
  /// Başarılıysa **yeni** kurtarma kodunun düz metnini döndürür (BR-AUTH-017);
  /// UI onu bir kez gösterir ve "kaydettim" onayı alır (EC-REC-006).
  ///
  /// | Durum | Sonuç | Kaynak |
  /// |---|---|---|
  /// | Kod doğru | Parola sıfırlanır, kilit açılır, yeni kod döner | EC-REC-001/004 |
  /// | Kod kullanılmış | `alreadyUsed` — ayırt edici mesaj | EC-REC-002 |
  /// | Kod yanlış **veya biçimsiz** | `invalidCode` + sayaç | EC-REC-003 |
  /// | 5 ardışık hata | 30 sn bekleme | EC-REC-003 |
  /// | Herhangi bir adım patlar | Tam rollback | EC-REC-005 |
  ///
  /// Kod **normalize edilerek** karşılaştırılır: kullanıcı tireleri atabilir,
  /// küçük harf veya araya boşluk yazabilir (EC-REC-011).
  ///
  /// [userId] verilirse audit kaydı kullanıcıya bağlanır; kurtarma ekranı
  /// oturum açıkken kullanıldığı için normalde doludur (docs/18 §2).
  Future<Result<String>> resetPasswordWithCode({
    required String code,
    required String newPassword,
    int? userId,
  }) async {
    if (newPassword.isEmpty) {
      return const Err(FinancialAccessFailures.passwordRequired);
    }

    final now = _clock().toUtc();

    final remaining = _throttle.remainingLock(throttleKey, now);
    if (remaining != null) {
      return Err(RecoveryCodeFailures.tooManyAttempts(remaining));
    }

    // Doğrulama da transaction içindedir: iki eşzamanlı kurtarma aynı kodu
    // birlikte harcayamaz. Err dönen dallar hiçbir satır yazmaz.
    final result = await _db.transaction<Result<String>>(() async {
      final stored = await _readStored();
      if (stored == null) {
        return const Err<String>(RecoveryCodeFailures.notConfigured);
      }

      // EC-REC-011: karşılaştırma ve hash'leme daima kanonik form üzerinden.
      // `normalize` null dönerse biçim geçersizdir; bu, yanlış koddan
      // ayırt edilmez (oracle olmaması için).
      final canonical = RecoveryCode.normalize(code);
      if (canonical == null || !_hasher.verify(canonical, stored)) {
        return const Err<String>(RecoveryCodeFailures.invalidCode);
      }

      // EC-REC-002 — doğru ama tükenmiş kod. Kontrol doğrulamadan SONRA yapılır:
      // yanlış kod girene "bu kod kullanılmış" demek bilgi sızdırırdı.
      if (await _readUsedAt() != null) {
        return const Err<String>(RecoveryCodeFailures.alreadyUsed);
      }

      // docs/17 §8 — dört adım, tek transaction (EC-REC-004):
      // 1) dashboard parolası güncellenir
      await _financialAccess.applyRecoveredPassword(newPassword);
      // 2) kullanılan kod geçersizleşir (used_at = now)
      await _markUsed(now);
      // 3) YENİ kod üretilir (BR-AUTH-017) — `used_at` bu adımda temizlenir,
      //    aksi hâlde yeni kod doğduğu anda "kullanılmış" sayılırdı. Adım 2'nin
      //    kalıcı etkisi eski hash'in üzerine yazılmasıdır: eski kod bir daha
      //    hiçbir koşulda doğrulanamaz.
      final next = await _storeNewCode();
      // 4) audit — kod değeri YAZILMAZ (REQ-AUDIT-004)
      await _writeAudit(
        action: actionRecoveryUsed,
        now: now,
        userId: userId,
        metadata: {'usedAt': now.millisecondsSinceEpoch},
      );

      return Ok<String>(next);
    });

    switch (result) {
      case Ok<String>():
        // Kilit **commit'ten sonra** açılır: bellekteki durum rollback ile geri
        // alınamazdı (EC-REC-005). docs/17 §8 — "Finansal erişim kilidi AÇILIR".
        _throttle.reset(throttleKey);
        _financialAccess.unlockAfterRecovery();
      case Err<String>(:final failure):
        await _registerRejection(failure, now: now, userId: userId);
    }

    return result;
  }

  // --- Ayarlar → yeni kod üretme (REQ-AUTH-028 · EC-REC-008/009) ------------

  /// Mevcut dashboard parolasıyla **yeni** kod üretir ve düz metnini döndürür.
  ///
  /// docs/17 §8: kullanıcı kodu kaybederse, parolasını bildiği sürece Ayarlar
  /// üzerinden yenileyebilir. Mevcut kod **asla tekrar gösterilemez** (yalnızca
  /// hash'i saklanır) — bu yüzden "göster" değil "yenile" akışıdır.
  ///
  /// EC-REC-008: parola yanlışsa reddedilir ve **eski kod geçerli kalır.**
  /// EC-REC-009: parola doğruysa yeni kod üretilir, eski geçersizleşir.
  ///
  /// Finansal erişim kilidi bu akıştan **etkilenmez**: burada istenen kimlik
  /// kanıtıdır, dashboard'a giriş değil.
  Future<Result<String>> regenerate({
    required String currentPassword,
    int? userId,
  }) async {
    if (!await _financialAccess.isConfigured()) {
      return const Err(FinancialAccessFailures.notConfigured);
    }
    if (!await _financialAccess.verifyPassword(currentPassword)) {
      return const Err(FinancialAccessFailures.currentPasswordWrong);
    }

    final now = _clock().toUtc();

    return _db.transaction(() async {
      final next = await _storeNewCode();
      await _writeAudit(
        action: actionRecoveryRegenerated,
        now: now,
        userId: userId,
      );
      return Ok(next);
    });
  }

  // --- Yardımcılar ----------------------------------------------------------

  /// Saklanan kod hash'i + salt; kayıt yoksa `null`.
  Future<PasswordHash?> _readStored() async {
    final hash = await _settings.read(AppSettingKeys.dashboardRecoveryHash);
    final salt = await _settings.read(AppSettingKeys.dashboardRecoverySalt);
    if (hash == null || salt == null) return null;
    return PasswordHash(hash: hash, salt: salt);
  }

  /// Kodun kullanıldığı an; kullanılmamışsa `null`.
  ///
  /// Bozuk/okunamayan değer **kullanılmış** sayılır: tek kullanımlık olma
  /// kuralı (BR-AUTH-015) şüphe hâlinde koruyucu yönde yorumlanır.
  Future<DateTime?> _readUsedAt() async {
    final raw = await _settings.read(AppSettingKeys.dashboardRecoveryUsedAt);
    if (raw == null) return null;

    // Bozuk değer de "kullanılmış" sayılır; zamanı bilinmiyorsa epoch verilir.
    final millis = int.tryParse(raw) ?? 0;
    return DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
  }

  /// docs/17 §8 adım 2 — kullanılan kodu geçersizleştirir.
  Future<void> _markUsed(DateTime now) => _settings.write(
    AppSettingKeys.dashboardRecoveryUsedAt,
    now.toUtc().millisecondsSinceEpoch.toString(),
  );

  /// Yeni kod üretir, **hash'ini** saklar ve düz metnini döndürür.
  ///
  /// Çağıran transaction açmış olmalıdır: hash, salt ve `used_at` üç ayrı
  /// `app_settings` satırıdır; yarım yazım kurtarmayı kilitlerdi.
  Future<String> _storeNewCode() async {
    final canonical = RecoveryCode.generateCanonical(_random);
    final secret = _hasher.hash(canonical);

    await _settings.write(AppSettingKeys.dashboardRecoveryHash, secret.hash);
    await _settings.write(AppSettingKeys.dashboardRecoverySalt, secret.salt);
    // Yeni kod kullanılmamıştır.
    await _settings.remove(AppSettingKeys.dashboardRecoveryUsedAt);

    return RecoveryCode.format(canonical);
  }

  /// Reddedilen kurtarma denemesini sayacına ve audit'e işler.
  ///
  /// Yalnızca **kod denemesi** sayılır: yanlış/biçimsiz kod sayacı ilerletir
  /// (EC-REC-003). Kullanılmış kod ilerletmez — bu bir tahmin denemesi değil,
  /// doğru bilinen ama tükenmiş bir koddur; kullanıcıyı 30 sn bekletmenin
  /// güvenlik değeri yoktur. Kayıt yokluğu (EC-REC-012) da denemeyle ilgili
  /// değildir.
  Future<void> _registerRejection(
    Failure failure, {
    required DateTime now,
    int? userId,
  }) async {
    if (failure.code == RecoveryCodeFailures.invalidCode.code) {
      _throttle.registerFailure(throttleKey, now);
      await _writeAudit(
        action: actionRecoveryFailed,
        now: now,
        userId: userId,
        metadata: {'attempts': _throttle.failureCount(throttleKey)},
      );
      return;
    }

    if (failure.code == RecoveryCodeFailures.alreadyUsed.code) {
      await _writeAudit(
        action: actionRecoveryFailed,
        now: now,
        userId: userId,
        metadata: {'reason': 'alreadyUsed'},
      );
    }
  }

  /// Audit kaydı — **kod, parola, hash ve salt ASLA yazılmaz**
  /// (REQ-AUDIT-004 · rules/04 §8 · rules/03 §9/5).
  ///
  /// Kurtarma başarısıyla aynı transaction içinde çağrılır (rules/03 §9/1);
  /// reddedilen denemeler tek başına duran olaylardır ve kendi yazımlarını
  /// yaparlar (docs/18 §7 istisnası).
  ///
  /// REQ-AUDIT-007: audit yazımındaki bir hata ana işlemi **başarısız kılmaz** —
  /// yakalanır ve log dosyasına yazılır. Aksi hâlde "denetim uğruna kurtarmayı
  /// kaybetme" durumu oluşurdu.
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
