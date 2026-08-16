/// Oturum kalıcılığı — **BR-AUTH-003 · REQ-AUTH-001/003/006/007**
///
/// Oturum `app_settings['session']` içinde JSON olarak tutulur (docs/17 §6):
///
/// ```json
/// { "userId": 1, "loginAt": 1786700625678 }
/// ```
///
/// - `loginAt` **UTC unix-millisecond**'tır (rules/03 §1).
/// - **Token üretilmez** — yerel uygulamada yanlış güvenlik hissi verir
///   (docs/17 §6, rules/04 §3).
/// - Oturum zaman aşımı **yoktur**.
/// - Ayrı dosya değil `app_settings` kullanılmasının nedeni: backup/restore ile
///   tutarlı davranış ve tek kalıcılık mekanizması (docs/17 §6).
///
/// ## Bozuk oturum uygulamayı çökertmez
///
/// EC-AUTH-004 / REQ-AUTH-007: oturum verisi okunamıyorsa **sessizce
/// temizlenir** ve oturum yok sayılır. Bu sınıf bu nedenle hiçbir koşulda
/// exception fırlatmaz.
library;

import 'dart:convert';

import '../../data/dao/daos.dart';
import '../../data/db/app_setting_keys.dart';
import '../../data/db/canteen_database.dart';

class SessionService {
  /// JSON alan adları — docs/17 §6.
  static const String userIdField = 'userId';
  static const String loginAtField = 'loginAt';

  final AppSettingsDao _settings;
  final UsersDao _users;
  final DateTime Function() _clock;

  /// [clock] `rules/06 §7` gereği enjekte edilir; verilmezse veritabanının
  /// saati kullanılır (tek zaman kaynağı).
  SessionService({
    required AppSettingsDao settings,
    required UsersDao users,
    required DateTime Function() clock,
  }) : _settings = settings,
       _users = users,
       _clock = clock;

  /// Oturumdaki kullanıcıyı döndürür; geçerli oturum yoksa `null`.
  ///
  /// Oturum şu durumlarda **geçersizdir** ve sessizce temizlenir:
  ///
  /// | Durum | Kaynak |
  /// |---|---|
  /// | JSON bozuk / alanlar eksik veya yanlış tipte | EC-AUTH-004 |
  /// | Kullanıcı veritabanında yok | REQ-AUTH-006 |
  /// | Kullanıcı pasifleştirilmiş | EC-AUTH-003 |
  Future<User?> load() async {
    final raw = await _settings.read(AppSettingKeys.session);
    if (raw == null) return null;

    final userId = _readUserId(raw);
    if (userId == null) {
      await clear();
      return null;
    }

    final user = await _users.findById(userId);
    if (user == null || !user.isActive) {
      await clear();
      return null;
    }
    return user;
  }

  /// Oturumu yazar. `loginAt` yazma anının UTC unix-millisecond değeridir.
  Future<void> save(int userId) async {
    final loginAt = _clock().toUtc().millisecondsSinceEpoch;
    await _settings.write(
      AppSettingKeys.session,
      jsonEncode({userIdField: userId, loginAtField: loginAt}),
    );
  }

  /// Oturumu siler. Logout ve geçersiz oturum temizliği bunu kullanır.
  Future<void> clear() => _settings.remove(AppSettingKeys.session);

  /// Ham oturum kaydından `userId`'yi çıkarır; okunamıyorsa `null`.
  ///
  /// EC-AUTH-004: burada **hiçbir hata yukarı taşınmaz.** Eksik alan, yanlış
  /// tip ve bozuk JSON aynı sonucu verir — oturum yok sayılır.
  static int? _readUserId(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return null;
    }

    if (decoded is! Map<String, Object?>) return null;

    final userId = decoded[userIdField];
    final loginAt = decoded[loginAtField];
    if (userId is! int || loginAt is! int) return null;

    return userId;
  }
}
