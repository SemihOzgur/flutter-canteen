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

  final Map<String, _AttemptState> _states = <String, _AttemptState>{};

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
    final state = _states.putIfAbsent(key, _AttemptState.new);
    state.failures++;
    if (state.failures >= maxAttempts) {
      state.lockedUntil = now.add(lockDuration);
    }
  }

  /// Başarılı giriş sayacı sıfırlar.
  void reset(String key) => _states.remove(key);
}

class _AttemptState {
  int failures = 0;
  DateTime? lockedUntil;
}
