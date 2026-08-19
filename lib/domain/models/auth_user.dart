/// Oturum açmış kullanıcının **sır taşımayan** görünümü — BR-SEC-001.
///
/// ## Neden ayrı bir tip var
///
/// Drift'in ürettiği `User` satır tipi `passwordHash` ve `passwordSalt`
/// alanlarını taşır ve üretilen `toString()` **ikisini de basar**:
///
/// ```dart
/// ..write('passwordHash: $passwordHash, ')
/// ..write('passwordSalt: $passwordSalt, ')
/// ```
///
/// `rules/04 §8` hash ve salt'ın hiçbir log'a, audit kaydına, export'a veya
/// yedeğe yazılmasını yasaklar. O tip application sınırından dışarı çıkarsa
/// tek bir `'$user'` interpolasyonu sızıntı olur ve bunu hiçbir bekçi testi
/// güvenilir biçimde yakalayamaz.
///
/// Bu tip sırları **yapısal olarak** taşımaz: sızdıracak alan yoktur.
///
/// ## Bu bir "DTO katmanı" değildir
///
/// `rules/01 §3` gereksiz DTO/Mapper katmanını yasaklar; gerekçesi dönüşümün
/// **boş iş** olmasıdır. Buradaki dönüşüm boş iş değildir — iki sır alanını
/// düşürür. Ayrıca bu bir *katman* değil, **tek bir tiptir**: `Product`,
/// `Sale`, `Category` için karşılığı yoktur ve olmayacaktır, çünkü onlar sır
/// taşımaz. `users`, şemadaki tek sır taşıyan satır tipidir.
library;

/// Kullanıcının kimliği ve durumu — parola bilgisi **yoktur**.
class AuthUser {
  final int id;

  /// Normalize edilmiş kullanıcı adı (`AuthService.normalizeUsername`).
  final String username;

  final String displayName;
  final bool isActive;
  final DateTime? lastLoginAt;

  const AuthUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.isActive,
    this.lastLoginAt,
  });

  @override
  bool operator ==(Object other) =>
      other is AuthUser &&
      other.id == id &&
      other.username == username &&
      other.displayName == displayName &&
      other.isActive == isActive &&
      other.lastLoginAt == lastLoginAt;

  @override
  int get hashCode =>
      Object.hash(id, username, displayName, isActive, lastLoginAt);

  /// Sır içermediği için tam dökülebilir.
  @override
  String toString() =>
      'AuthUser(id: $id, username: $username, displayName: $displayName, '
      'isActive: $isActive)';
}
