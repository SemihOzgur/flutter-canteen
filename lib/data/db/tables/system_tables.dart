/// Sistem tabloları — docs/05-database-architecture.md §2.11–2.12
///
/// `audit_logs` · `app_settings`
library;

import 'package:drift/drift.dart';

import '../converters.dart';
import 'reference_tables.dart';

/// docs/05 §2.11 · docs/18
///
/// **Audit log ≠ business history** (rules/03 §9). Stok geçmişinin otoritesi
/// `stock_movements`, satış geçmişinin otoritesi `sales`/`sale_items`'tır.
///
/// **Parola, recovery code, hash ve salt ASLA yazılmaz** (rules/04 §8).
/// Yalnızca **değişen alanların** eski/yeni değeri saklanır.
@TableIndex.sql('CREATE INDEX ix_audit_date ON audit_logs (created_at)')
@TableIndex.sql(
  'CREATE INDEX ix_audit_entity ON audit_logs (entity_type, entity_id)',
)
class AuditLogs extends Table {
  @override
  String get tableName => 'audit_logs';

  IntColumn get id => integer().autoIncrement()();

  IntColumn get createdAt => integer().map(const UtcMillisConverter())();

  IntColumn get userId => integer().nullable().references(Users, #id)();

  TextColumn get action => text()();

  TextColumn get entityType => text()();

  IntColumn get entityId => integer().nullable()();

  /// JSON — yalnızca değişen alanlar.
  TextColumn get oldValue => text().nullable()();

  /// JSON — yalnızca değişen alanlar.
  TextColumn get newValue => text().nullable()();

  TextColumn get metadata => text().nullable()();
}

/// docs/05 §2.12 — anahtar/değer ayar deposu.
///
/// Kritik anahtarlar `app_settings` içinde **hash olarak** tutulur; düz metin
/// parola veya recovery code hiçbir koşulda yazılmaz (BR-SEC-001 · REQ-DB-010).
class AppSettings extends Table {
  @override
  String get tableName => 'app_settings';

  TextColumn get key => text()();

  TextColumn get value => text()();

  IntColumn get updatedAt => integer().map(const UtcMillisConverter())();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
