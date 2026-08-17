/// Drift `users` satırını sır taşımayan domain görünümüne çevirir.
///
/// Yön **data → domain**'dir; domain katmanı Drift'i bilmez (rules/01 §1).
/// Eşlemenin işi `passwordHash` ve `passwordSalt` alanlarını **düşürmektir**
/// — bkz. [AuthUser] dokümantasyonu ve `rules/04 §8`.
library;

import '../../domain/models/auth_user.dart';
import '../db/canteen_database.dart';

extension UserToAuthUser on User {
  AuthUser toAuthUser() => AuthUser(
    id: id,
    username: username,
    displayName: displayName,
    isActive: isActive,
    lastLoginAt: lastLoginAt,
  );
}
