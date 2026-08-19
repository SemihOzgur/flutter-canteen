/// Hatalı giriş denemesi sayacı — **EC-AUTH-002 · REQ-AUTH-011**
///
/// "Ardışık 5 hatalı denemeden sonra 30 saniye bekleme" (docs/17 §3).
///
/// ## Neden bellekte
///
/// Sayaç **yalnızca bellekte** tutulur ve uygulama yeniden başlayınca sıfırlanır.
/// Bu, finansal erişim kilidinin bellekte tutulmasıyla aynı yaklaşımdır
/// (BR-AUTH-016). Tehdit modeli dardır: yerel, ağsız, tek makine
/// (docs/17 §5) — kalıcı bir kilitleme tablosu, meşru kullanıcıyı kasada
/// kilitlemek dışında bir fayda sağlamaz ve şema değişikliği gerektirirdi.
///
/// Sayaç **anahtar başına** tutulur; login için anahtar normalize edilmiş
/// kullanıcı adıdır.
library;

class LoginThrottle {
  /// Ardışık hatalı deneme eşiği (docs/17 §3).
  static const int maxAttempts = 5;

  /// Eşik aşıldığında uygulanan bekleme (docs/17 §3).
  static const Duration lockDuration = Duration(seconds: 30);

  /// Eşiğe ulaşmamış bir kaydın bellekte tutulma süresi.
  ///
  /// Anahtar **kullanıcı girdisidir** ve var olmayan bir kullanıcı adı da kayıt
  /// açar (EC-AUTH-001 gereği bilinmeyen kullanıcı da hata sayılır). Temizlik
  /// olmasaydı map, girilen her farklı ad için büyürdü.
  static const Duration idleRetention = Duration(minutes: 5);

  final Map<String, _AttemptState> _states = <String, _AttemptState>{};

  /// Ne kilitli ne de yakın zamanda dokunulmuş kayıtları atar.
  void _prune(DateTime now) {
    _states.removeWhere((_, state) {
      final lockedUntil = state.lockedUntil;
      if (lockedUntil != null) return !now.isBefore(lockedUntil);
      return now.difference(state.lastFailureAt) > idleRetention;
    });
  }

  /// Yalnızca test ve tanı için — bellekte tutulan kayıt sayısı.
  int get trackedKeyCount => _states.length;

  /// Anahtar için **ardışık** hatalı deneme sayısı; kayıt yoksa `0`.
  ///
  /// Audit metadata'sı bu sayıyı ister (docs/18 §3 — `dashboardUnlockFailed` /
  /// `dashboardRecoveryFailed`: *"ardışık deneme sayısı"*). Salt okumadır;
  /// sayacı değiştirmez.
  int failureCount(String key) => _states[key]?.failures ?? 0;

  /// Anahtar için kalan bekleme süresi; bekleme yoksa `null`.
  ///
  /// Süre dolmuşsa sayaç **sıfırlanır** — bekleme sonrası kullanıcı yeniden
  /// tam hakla başlar.
  Duration? remainingLock(String key, DateTime now) {
    final state = _states[key];
    final lockedUntil = state?.lockedUntil;
    if (state == null || lockedUntil == null) return null;

    if (!now.isBefore(lockedUntil)) {
      _states.remove(key);
      return null;
    }
    return lockedUntil.difference(now);
  }

  /// Hatalı denemeyi kaydeder; eşiğe ulaşıldıysa beklemeyi başlatır.
  void registerFailure(String key, DateTime now) {
    _prune(now);

    final state = _states.putIfAbsent(key, () => _AttemptState(now));
    state.failures++;
    state.lastFailureAt = now;
    if (state.failures >= maxAttempts) {
      state.lockedUntil = now.add(lockDuration);
    }
  }

  /// Başarılı giriş sayacı sıfırlar.
  void reset(String key) => _states.remove(key);
}

class _AttemptState {
  _AttemptState(this.lastFailureAt);

  int failures = 0;
  DateTime? lockedUntil;
  DateTime lastFailureAt;
}
