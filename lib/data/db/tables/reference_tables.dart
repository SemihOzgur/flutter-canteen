/// Referans tabloları — docs/05-database-architecture.md §2.1–2.4
///
/// `users` · `categories` · `suppliers` · `vat_rates`
library;

import 'package:drift/drift.dart';

import '../converters.dart';

/// docs/05 §2.1 — BR-AUTH-011 · BR-SEC-001
///
/// **Düz metin parola alanı YOKTUR** (REQ-DB-010). Yalnızca salt'lı SHA-256
/// hash'i ve salt saklanır. Bu kural `schema_test.dart` ile zorlanır.
@TableIndex.sql('CREATE UNIQUE INDEX ux_users_username ON users (username)')
class Users extends Table {
  @override
  String get tableName => 'users';

  IntColumn get id => integer().autoIncrement()();

  /// Küçük harfe normalize edilmiş kullanıcı adı.
  TextColumn get username => text()();

  /// SHA-256 (BR-AUTH-011). Düz metin parola asla saklanmaz.
  TextColumn get passwordHash => text()();

  /// Kayıt başına rastgele salt (BR-SEC-001).
  TextColumn get passwordSalt => text()();

  TextColumn get displayName => text()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  IntColumn get lastLoginAt =>
      integer().nullable().map(nullableUtcMillisConverter)();

  IntColumn get createdAt => integer().map(const UtcMillisConverter())();

  IntColumn get updatedAt => integer().map(const UtcMillisConverter())();
}

/// docs/05 §2.2 — BR-CAT-004: `Genel` sistem kategorisidir.
///
/// `UNIQUE(name)` pasif kayıtları da kapsar; kategori adı geri kullanılmaz.
@TableIndex.sql('CREATE UNIQUE INDEX ux_categories_name ON categories (name)')
class Categories extends Table {
  @override
  String get tableName => 'categories';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  /// `Genel` için `true` — silinemez, pasifleştirilemez, adı değiştirilemez.
  BoolColumn get isSystem => boolean().withDefault(const Constant(false))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  IntColumn get createdAt => integer().map(const UtcMillisConverter())();

  IntColumn get updatedAt => integer().map(const UtcMillisConverter())();
}

/// docs/05 §2.3
class Suppliers extends Table {
  @override
  String get tableName => 'suppliers';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  TextColumn get contactName => text().nullable()();

  TextColumn get phone => text().nullable()();

  TextColumn get email => text().nullable()();

  TextColumn get address => text().nullable()();

  TextColumn get note => text().nullable()();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  IntColumn get createdAt => integer().map(const UtcMillisConverter())();

  IntColumn get updatedAt => integer().map(const UtcMillisConverter())();
}

/// docs/05 §2.4 — BR-VAT-001: KDV oranları yönetilebilir.
///
/// **Kurulumda yalnızca nötr `%0 — KDV Yok` oranı seed edilir** (docs/08 §3 ·
/// OD-017). Mevzuata bağlı oranlar (%20, %10 …) seed EDİLMEZ — kullanıcı kendi
/// oranlarını tanımlar (rules/02 §2).
class VatRates extends Table {
  @override
  String get tableName => 'vat_rates';

  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text()();

  /// Basis point tam sayı (BR-FIN-002): %20 → 2000, %0,5 → 50.
  IntColumn get rateBasisPoints => integer()();

  BoolColumn get isDefault => boolean().withDefault(const Constant(false))();

  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  IntColumn get createdAt => integer().map(const UtcMillisConverter())();

  IntColumn get updatedAt => integer().map(const UtcMillisConverter())();

  @override
  List<String> get customConstraints => ['CHECK(rate_basis_points >= 0)'];
}
