/// Kimlik doğrulama ve kullanıcı yönetimi — **docs/17 §2, §3, §5, §6, §11**
///
/// ## Rol/yetki YOKTUR
///
/// BR-AUTH-002 · REQ-AUTH-013: tüm kullanıcılar aynı yetkilere sahiptir.
/// Bu serviste yetki kontrolü **bulunmaz** ve eklenmez; çoklu kullanıcının tek
/// faydası izlenebilirliktir (`rules/04 §2`).
///
/// ## Kapsam sınırı
///
/// Bu servis **kullanıcı oturumunu** yönetir. Dashboard parolası, finansal
/// erişim kilidi ve recovery code **ayrı bir konudur** (docs/17 §7–§8) ve bu
/// dosyaya sızdırılmaz — bunlar `FinancialAccessService` /
/// `RecoveryCodeService`'e aittir.
///
/// Tek istisna [logout]'tur: REQ-AUTH-004 logout'un finansal erişim kilidini de
/// kapatmasını gerektirir. Bu nedenle [FinancialAccessService] buraya
/// **enjekte edilir**; bağımlılık tek yönlüdür (finansal kilit servisi
/// `AuthService`'i tanımaz), böylece döngüsel bağımlılık oluşmaz.
///
/// ## Kilit servisi TEK ÖRNEK olmalıdır
///
/// Kilit durumu yalnızca bellektedir (BR-AUTH-016). Bu yüzden bu servise
/// verilen [FinancialAccessService], uygulamanın kilidi açan/soran örneğiyle
/// **aynı nesne** olmak zorundadır — ikinci bir örnek verilirse [logout] hayalet
/// bir nesneyi kapatır, gerçek kilit açık kalır ve REQ-AUTH-004/021 sessizce
/// ihlal edilir. Bağımlılık bu nedenle `required`'dır: opsiyonel olduğu sürece
/// bir provider tanımında atlanması derlenen ve testten geçen bir hata olurdu.
///
/// ## Transaction sınırı
///
/// rules/01 §5: transaction **yalnızca bu katmanda** açılır. Çok adımlı
/// işlemler (giriş → son giriş zamanı + oturum, kullanıcı oluşturma,
/// pasifleştirme) tek transaction içindedir.
library;

import '../../core/result/result.dart';
import '../../data/dao/daos.dart';
import '../../data/db/canteen_database.dart';
import '../../data/repositories/failures.dart';
import '../../domain/services/password_hasher.dart';
import 'auth_failures.dart';
import 'financial_access_service.dart';
import 'login_throttle.dart';
import 'session_service.dart';
import '../../domain/models/auth_user.dart';
import '../../data/dao/user_mapper.dart';

class AuthService {
  final CanteenDatabase _db;
  final UsersDao _users;
  final SessionService _session;
  final PasswordHasher _hasher;
  final LoginThrottle _throttle;
  final FinancialAccessService _financialAccess;
  final DateTime Function() _clock;

  /// [clock] `rules/06 §7` gereği enjekte edilir; verilmezse veritabanının
  /// saat kaynağı kullanılır — böylece tüm zaman damgaları tek kaynaktan gelir.
  ///
  /// [financialAccess] **zorunludur** ve uygulamadaki tek örnek olmalıdır:
  /// [logout], [login] ve [setActive] finansal erişim kilidini kapatır
  /// (REQ-AUTH-004 · REQ-AUTH-021 · BR-AUTH-016). Gerekçe için sınıf
  /// dokümantasyonuna bakın.
  AuthService({
    required CanteenDatabase db,
    required UsersDao users,
    required SessionService session,
    required FinancialAccessService financialAccess,
    PasswordHasher? hasher,
    LoginThrottle? throttle,
    DateTime Function()? clock,
  }) : _db = db,
       _users = users,
       _session = session,
       _hasher = hasher ?? PasswordHasher(),
       _throttle = throttle ?? LoginThrottle(),
       _financialAccess = financialAccess,
       _clock = clock ?? db.clock;

  /// Kullanıcı adı normalizasyonu — REQ-AUTH-012 · EC-AUTH-006.
  ///
  /// Kullanıcı adı büyük/küçük harf duyarsızdır; veritabanına **daima
  /// normalize edilmiş** hâliyle yazılır (docs/04 §3.1).
  ///
  /// ## Neden `toLowerCase()` yetmiyor
  ///
  /// Dart'ın `toLowerCase()`'i locale bağımsızdır ve Türkçe'nin noktalı/noktasız
  /// `i` ayrımını bozar:
  ///
  /// ```text
  /// 'IŞIL'.toLowerCase()   → işil    ≠  ışıl
  /// 'KISMET'.toLowerCase() → kismet  ≠  kısmet
  /// ```
  ///
  /// Türkçe-Q klavyede `ı` tuşu **Caps Lock açıkken `I` üretir**. Bu haliyle
  /// `ışıl` veya `kısmet` adlı bir kasiyer kasada giriş yapamaz ve EC-AUTH-001
  /// gereği nedenini de göremezdi.
  ///
  /// ## Seçilen kural
  ///
  /// `I` · `ı` · `İ` · `i` **tek bir karaktere** (`i`) indirgenir; kalan
  /// karakterler locale bağımsız küçük harfe çevrilir. Böylece kullanıcı adı
  /// hangi klavye düzeni ve Caps Lock durumuyla yazılırsa yazılsın aynı hesaba
  /// çözülür.
  ///
  /// Bedeli: yalnızca noktalı/noktasız `i` ile ayrışan iki ad (`ıra` ↔ `ira`)
  /// **aynı hesap** sayılır ve ikisi bir arada var olamaz. Proje sahibi kararı:
  /// kantinde bir kasiyerin Caps Lock yüzünden kilitlenmesi, böyle bir ad
  /// çiftinin aynı kantinde bulunmasından çok daha olasıdır.
  static String normalizeUsername(String username) {
    final buffer = StringBuffer();

    for (final rune in username.trim().runes) {
      switch (rune) {
        // I (U+0049) · ı (U+0131) · İ (U+0130) · i (U+0069)
        case 0x0049:
        case 0x0131:
        case 0x0130:
        case 0x0069:
          buffer.write('i');
        // Birleşik nokta (U+0307) — `'İ'.toLowerCase()` bunu üretir; yukarıda
        // `İ` zaten `i`'ye indiği için burada kalanı atılır.
        case 0x0307:
          break;
        default:
          buffer.write(String.fromCharCode(rune).toLowerCase());
      }
    }

    return buffer.toString();
  }

  // --- Kurulum ------------------------------------------------------------

  /// Hiç kullanıcı yoksa `true` — kurulum sihirbazının **Adım 1'i** eksiktir
  /// (REQ-AUTH-002 · EC-AUTH-008).
  ///
  /// ⚠️ Bu, kurulumun tamamlandığı anlamına **gelmez**: sihirbazın Adım 2
  /// (dashboard parolası) ve Adım 3 (kurtarma kodu) adımları ayrı
  /// transaction'lardır ve yarım kalabilir. Açılışta karar verecek olan
  /// bootstrap bu metodu değil, `SetupService.currentState()`'i sorar.
  Future<bool> needsSetup() async => (await _users.countAll()) == 0;

  // --- Giriş / çıkış ------------------------------------------------------

  /// Kullanıcı girişi.
  ///
  /// | Kural | Kaynak |
  /// |---|---|
  /// | Kullanıcı adı küçük harfe normalize edilir | REQ-AUTH-012 · EC-AUTH-006 |
  /// | Hatalı kullanıcı adı ve hatalı parola **aynı** mesajı döndürür | EC-AUTH-001 |
  /// | Ardışık 5 hatalı denemeden sonra 30 sn bekleme | EC-AUTH-002 |
  /// | Başarılı girişte `lastLoginAt` güncellenir ve oturum yazılır | docs/17 §6 |
  ///
  /// Pasif kullanıcı da **aynı genel hatayı** alır: aksi hâlde kullanıcı adının
  /// sistemde var olduğu sızardı.
  Future<Result<AuthUser>> login(String username, String password) async {
    final key = normalizeUsername(username);
    final now = _clock().toUtc();

    final remaining = _throttle.remainingLock(key, now);
    if (remaining != null) {
      return Err(AuthFailures.tooManyAttempts(remaining));
    }

    final user = await _users.findByUsername(key);
    if (user == null || !user.isActive || !_verify(password, user)) {
      _throttle.registerFailure(key, now);
      return const Err(AuthFailures.invalidCredentials);
    }

    _throttle.reset(key);

    // BR-AUTH-016 · REQ-AUTH-021: kilit **oturum kapsamlıdır.** Yeni bir oturum
    // başlıyorsa kilit kapalı başlamalıdır.
    //
    // `logout()` tek başına yetmez: oturum logout dışı yollarla da düşebilir —
    // kullanıcı pasifleştirilir (EC-AUTH-003), oturum verisi bozulur
    // (EC-AUTH-004), Faz 9'da restore yapılır. O yollardan biriyle oturumu
    // düşen kullanıcının açtığı kilit, sıradaki kullanıcıya devredilirdi:
    // A kilidi açar → A pasifleşir → B giriş yapar → B parolasız Dashboard
    // görürdü.
    _financialAccess.lock();

    // Son giriş zamanı ve oturum birlikte yazılır; yarım bir giriş durumu
    // oluşmaz (rules/01 §5 — transaction sınırı application katmanındadır).
    await _db.transaction(() async {
      await _users.touchLastLogin(user.id, now);
      await _session.save(user.id);
    });

    // Güncel satır döndürülür: lastLoginAt/updatedAt taze olsun.
    return Ok((await _users.findById(user.id) ?? user).toAuthUser());
  }

  /// Oturumu sonlandırır (REQ-AUTH-004).
  ///
  /// **Aktif sepet SİLİNMEZ** (BR-AUTH-005 · REQ-AUTH-005) — sepet Faz 5'te
  /// eklenecek ve bu metot ona dokunmayacaktır.
  ///
  /// Finansal erişim kilidi **kapatılır** (REQ-AUTH-004 · REQ-AUTH-021 ·
  /// EC-DASH-005): tekrar giriş yapıldığında dashboard parolası yeniden sorulur.
  /// Kilit yalnızca bellekte olduğu için bu adım veritabanına dokunmaz ve
  /// başarısız olamaz; bu yüzden oturum temizliğinden **önce** yapılır.
  Future<void> logout() async {
    _financialAccess.lock();
    await _session.clear();
  }

  /// Geçerli oturumdaki kullanıcı; oturum yoksa/geçersizse `null`.
  Future<AuthUser?> currentUser() => _session.load();

  // --- Kullanıcı yönetimi (docs/17 §11) -----------------------------------

  /// Kullanıcı listesi — **REQ-AUTH-008 · docs/17 §11.**
  ///
  /// Varsayılan olarak **pasifler de** listelenir: kullanıcı silinmez, yalnızca
  /// pasifleşir (BR-AUTH-006) ve yönetim ekranı onu yeniden aktif edebilmelidir.
  /// [onlyActive] ile yalnızca aktif kullanıcılar istenir (örn. bir seçim
  /// listesi).
  ///
  /// ## Neden ham Drift satırı döndürülmüyor
  ///
  /// `users` satırı `passwordHash` ve `passwordSalt` taşır ve üretilen
  /// `toString()` ikisini de basar — böyle bir nesnenin presentation'a ulaşması
  /// rules/04 §8'in ("hash ve salt hiçbir log'a/mesaja yazılmaz") sessiz
  /// ihlalidir. Bu metot sırları düşüren [AuthUser] görünümünü döndürür ve UI'ın
  /// `UsersDao`'ya inmesini gereksiz kılar (rules/01 §1: presentation'da
  /// veritabanı erişimi yoktur).
  ///
  /// Sıralama kullanıcı adına göredir (DAO tarafında, SQL ile).
  Future<List<AuthUser>> listUsers({bool onlyActive = false}) async {
    final rows = onlyActive
        ? await _users.listActive()
        : await _users.listAll();
    return [for (final row in rows) row.toAuthUser()];
  }

  /// Yeni kullanıcı oluşturur ve id'sini döndürür.
  ///
  /// Parola **yalnızca** salt'lı SHA-256 hash olarak saklanır
  /// (BR-AUTH-011 · BR-SEC-001); düz metin hiçbir kolona, log'a veya hata
  /// mesajına yazılmaz.
  ///
  /// Parola politikası (uzunluk, karmaşıklık) **kapsam dışıdır** (docs/17 §5);
  /// yalnızca boş olmama kontrolü yapılır.
  Future<Result<int>> createUser({
    required String username,
    required String password,
    required String displayName,
  }) async {
    final normalized = normalizeUsername(username);
    if (normalized.isEmpty) return const Err(AuthFailures.usernameRequired);
    if (password.isEmpty) return const Err(AuthFailures.passwordRequired);

    final name = displayName.trim();
    if (name.isEmpty) return const Err(AuthFailures.displayNameRequired);

    final secret = _hasher.hash(password);
    final now = _clock().toUtc();

    return _db.transaction(() async {
      if (await _users.findByUsername(normalized) != null) {
        return const Err<int>(AuthFailures.usernameExists);
      }
      try {
        final id = await _users.insertUser(
          UsersCompanion.insert(
            username: normalized,
            passwordHash: secret.hash,
            passwordSalt: secret.salt,
            displayName: name,
            createdAt: now,
            updatedAt: now,
          ),
        );
        return Ok(id);
      } on Object catch (error) {
        // `ux_users_username` yarışı — kontrol ile insert arasında.
        final failure = mapConstraintFailure(error);
        if (failure == null) rethrow;
        return const Err<int>(AuthFailures.usernameExists);
      }
    });
  }

  /// Kullanıcının kendi parolasını değiştirir.
  ///
  /// docs/17 §11: mevcut parola sorulur. Kullanıcı parolası için **kurtarma
  /// akışı yoktur** (docs/17 §1) — recovery code yalnızca dashboard parolasına
  /// aittir.
  Future<Result<void>> changePassword({
    required int userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    if (newPassword.isEmpty) return const Err(AuthFailures.passwordRequired);

    final user = await _users.findById(userId);
    if (user == null) return const Err(AuthFailures.userNotFound);
    if (!_verify(currentPassword, user)) {
      return const Err(AuthFailures.currentPasswordWrong);
    }

    final secret = _hasher.hash(newPassword);
    await _users.updatePassword(
      userId,
      passwordHash: secret.hash,
      passwordSalt: secret.salt,
    );
    return const Ok(null);
  }

  /// Kullanıcıyı aktif/pasif yapar.
  ///
  /// BR-AUTH-006 · EC-AUTH-005: **son aktif kullanıcı pasifleştirilemez.**
  /// Kullanıcı hiçbir koşulda silinmez — satış, stok hareketi ve audit kayıtları
  /// kullanıcıya referans verir.
  ///
  /// Kontrol ve yazma tek transaction içindedir; aksi hâlde iki eşzamanlı
  /// pasifleştirme sistemi aktif kullanıcısız bırakabilirdi.
  Future<Result<void>> setActive(int userId, bool isActive) {
    return _db.transaction(() async {
      final user = await _users.findById(userId);
      if (user == null) return const Err<void>(AuthFailures.userNotFound);

      // Yalnızca aktif → pasif geçişi sistemi kullanıcısız bırakabilir.
      if (user.isActive && !isActive) {
        final activeCount = await _users.countActive();
        if (activeCount <= 1) {
          return const Err<void>(AuthFailures.lastActiveUser);
        }
      }

      await _users.setActive(userId, isActive);

      // EC-AUTH-003: pasifleştirilen kullanıcının oturumu **anında** düşer.
      // `SessionService.load` bunu zaten elerdi, ama o tembel bir kontroldür —
      // kullanıcıyı bellekte tutan bir ekran açık kalmaya devam ederdi.
      if (!isActive) {
        final hadSession = await _session.clearIfUser(userId);
        // Oturumu düşen kullanıcının açtığı kilit onunla birlikte kapanır;
        // login'deki savunma ile birlikte iki katman (BR-AUTH-016).
        if (hadSession) _financialAccess.lock();
      }

      return const Ok<void>(null);
    });
  }

  /// Görünen adı değiştirir (docs/17 §11 — serbest).
  Future<Result<void>> updateDisplayName(int userId, String displayName) async {
    final name = displayName.trim();
    if (name.isEmpty) return const Err(AuthFailures.displayNameRequired);

    final affected = await _users.updateDisplayName(userId, name);
    if (affected == 0) return const Err(AuthFailures.userNotFound);
    return const Ok(null);
  }

  /// Saklanan hash + salt ile doğrulama. Düz metin hiçbir yerde tutulmaz.
  bool _verify(String password, User user) => _hasher.verify(
    password,
    PasswordHash(hash: user.passwordHash, salt: user.passwordSalt),
  );
}
