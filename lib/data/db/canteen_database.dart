/// Kantin veritabanı — 15 tablo.
///
/// docs/05-database-architecture.md §2 · docs/06-database-migrations.md
///
/// Bağlantı yapılandırması (WAL, `synchronous=FULL`, `foreign_keys=ON`,
/// `busy_timeout`, `temp_store=MEMORY`) ve **REQ-MIG-005 sürüm kapısı**
/// `database_opener.dart` içindedir.
library;

import 'package:drift/drift.dart';

// Üretilen `canteen_database.g.dart` bu library'nin bir `part`'ıdır ve enum
// tiplerini/dönüştürücüleri doğrudan kullanır. Bu import'lar onun içindir —
// kaldırılırsa üretilen kod derlenmez.
import '../../domain/enums/cart_status.dart';
import '../../domain/enums/return_type.dart';
import '../../domain/enums/sale_status.dart';
import '../../domain/enums/stock_movement_type.dart';
import '../../domain/enums/stock_reference_type.dart';
import 'converters.dart';
import 'migrations/migration_plan.dart';
import 'schema_version.dart';
import 'seed.dart';
import 'tables/cart_tables.dart';
import 'tables/product_tables.dart';
import 'tables/reference_tables.dart';
import 'tables/return_tables.dart';
import 'tables/sale_tables.dart';
import 'tables/stock_tables.dart';
import 'tables/system_tables.dart';

part 'canteen_database.g.dart';

@DriftDatabase(
  tables: [
    Users,
    Categories,
    Suppliers,
    VatRates,
    Products,
    ProductBarcodes,
    Carts,
    CartItems,
    Sales,
    SaleItems,
    Returns,
    ReturnItems,
    StockMovements,
    AuditLogs,
    AppSettings,
  ],
)
class CanteenDatabase extends _$CanteenDatabase {
  /// Yayınlanmış şema adımları. Faz 2'de boştur (yalnızca v1 vardır).
  final MigrationPlan migrationPlan;

  /// Zaman kaynağı — testlerde enjekte edilir (rules/06 §7, determinizm).
  final DateTime Function() clock;

  final int _schemaVersion;

  /// `beforeOpen` sırasında seed çalıştırılsın mı?
  ///
  /// Migration kurtarma akışı, veritabanını **incelemek** için seed'siz açar.
  final bool applySeed;

  CanteenDatabase(
    super.executor, {
    MigrationPlan? migrationPlan,
    DateTime Function()? clock,
    int schemaVersion = kSupportedSchemaVersion,
    this.applySeed = true,
  }) : migrationPlan = migrationPlan ?? MigrationPlan.empty,
       clock = clock ?? DateTime.now,
       _schemaVersion = schemaVersion;

  @override
  int get schemaVersion => _schemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      // Tablolar + 17 index (docs/05 §3) tek adımda oluşturulur.
      await m.createAll();
    },

    // REQ-MIG-004 — TÜM adımlar tek transaction içinde uygulanır.
    //
    // ⚠️ Drift `onUpgrade`'i **kendiliğinden transaction'a sarmaz**
    // (drift 2.34, `GeneratedDatabase.beforeOpen` → `onUpgrade` doğrudan
    // çağrılır). Sarılmazsa yarım uygulanmış bir migration kalıcı olur ve
    // REQ-MIG-003 ihlal edilir — SQLite'ta DDL de geri alınabilir olduğundan
    // transaction burada zorunludur.
    onUpgrade: (m, from, to) async {
      await transaction(() async {
        await migrationPlan.apply(m, this, from: from, to: to);
      });
    },

    beforeOpen: (details) async {
      // Drift, migration sırasında foreign key zorlamasını geçici olarak
      // kapatabilir; her açılışta yeniden garanti altına alınır (REQ-DB-001).
      await customStatement('PRAGMA foreign_keys = ON;');

      if (applySeed) {
        await Seed.apply(this, nowUtc: clock().toUtc());
      }
    },
  );
}
