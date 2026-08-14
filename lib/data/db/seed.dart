/// Kurulum seed'i — **BR-PROD-003 · BR-CAT-004**
///
/// docs/02 BR-PROD-003:
///   "Kurulumda `Genel` kategorisi oluşturulur ve kullanıcı seçim yapmazsa
///    varsayılan olarak kullanılır."
///
/// docs/02 BR-CAT-004:
///   "`Genel` kategorisi sistem kategorisidir; silinemez, pasifleştirilemez,
///    adı değiştirilemez."
///
/// ## Seed edilmeyenler
///
/// - **KDV oranları seed EDİLMEZ** (rules/02 §2) — kullanıcı kendi oranlarını
///   tanımlar.
/// - **Kullanıcı seed EDİLMEZ** — kurulum sihirbazı Faz 3 kapsamındadır.
///
/// Seed **idempotenttir**: her açılışta çalışır, yalnızca eksikse yazar.
library;

import 'package:drift/drift.dart';

import 'canteen_database.dart';

abstract final class Seed {
  /// `Genel` sistem kategorisinin adı. Değiştirilemez (BR-CAT-004).
  static const String generalCategoryName = 'Genel';

  /// Eksik sistem verisini tamamlar. Var olan kaydı **değiştirmez.**
  static Future<void> apply(
    CanteenDatabase db, {
    required DateTime nowUtc,
  }) async {
    final existing =
        await (db.select(db.categories)
              ..where((c) => c.name.equals(generalCategoryName))
              ..limit(1))
            .getSingleOrNull();

    if (existing != null) return;

    await db
        .into(db.categories)
        .insert(
          CategoriesCompanion.insert(
            name: generalCategoryName,
            isSystem: const Value(true),
            sortOrder: const Value(0),
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
          // UNIQUE(name) ile yarış durumunda da çoğalma olmaz.
          mode: InsertMode.insertOrIgnore,
        );
  }
}
