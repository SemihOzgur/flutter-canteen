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
/// docs/08 §3 (OD-017):
///   "Kurulumda yalnızca nötr `%0 — KDV Yok` oranı oluşturulur ve varsayılan
///    olur." Mevzuata bağlı oranlar (%20, %10 …) **seed EDİLMEZ** —
///   BR-VAT-001'in yasakladığı budur. `%0` mevzuat değil, KDV aritmetiğinin
///   nötr elemanıdır: `vat = total × 0 / (10000 + 0) = 0`.
///
/// ## Seed edilmeyenler
///
/// - **Mevzuata bağlı KDV oranları** — kullanıcı kendi oranlarını tanımlar.
/// - **Kullanıcı seed EDİLMEZ** — kurulum sihirbazı Faz 3 kapsamındadır.
///
/// Seed **idempotenttir**: her açılışta çalışır, yalnızca eksikse yazar.
library;

import 'package:drift/drift.dart';

import 'canteen_database.dart';

abstract final class Seed {
  /// `Genel` sistem kategorisinin adı. Değiştirilemez (BR-CAT-004).
  static const String generalCategoryName = 'Genel';

  /// Kurulumda oluşturulan nötr KDV oranının adı (docs/08 §3 · OD-017).
  ///
  /// Kategori adının aksine bu ad **değiştirilebilir** — kullanıcı oranı
  /// düzenleyebilir (OD-017). Bu yüzden seed koşulu ada bakamaz; bkz.
  /// [_applyNeutralVatRate].
  static const String neutralVatRateName = '%0 — KDV Yok';

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

    if (existing != null) {
      // Kategori zaten var; KDV oranı seed'i **yine de** denenir — ikisi
      // bağımsız kayıtlardır ve biri diğerinin eksikliğini maskeleyemez.
      await _applyNeutralVatRate(db, nowUtc: nowUtc);
      return;
    }

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

    await _applyNeutralVatRate(db, nowUtc: nowUtc);
  }

  /// docs/08 §3 · OD-017 — nötr `%0 — KDV Yok` oranı.
  ///
  /// ## Neden koşul "tablo boş", "bu adda kayıt yok" değil
  ///
  /// `Genel` kategorisinin adı değiştirilemez (BR-CAT-004), bu yüzden onun
  /// seed'i adla arayabilir. KDV oranının adı ise **değiştirilebilir**
  /// (OD-017: "kullanıcı mevcut oranı düzenleyebilir"). Adla arasaydık,
  /// kullanıcı oranı `KDV Yok` olarak yeniden adlandırdığında bir sonraki
  /// açılışta **ikinci bir `%0` oranı** oluşurdu ve varsayılan devredilirdi.
  ///
  /// Oranlar silinemediği için (docs/08 §4) "tablo boş" yalnızca **temiz
  /// kurulumda** doğrudur; bu da seed'in tam olarak çalışmasını istediğimiz
  /// andır. Kullanıcının kendi oranlarını tanımladığı bir veritabanına
  /// hiçbir koşulda ek kayıt yazılmaz.
  static Future<void> _applyNeutralVatRate(
    CanteenDatabase db, {
    required DateTime nowUtc,
  }) async {
    final anyRate = await (db.select(db.vatRates)..limit(1)).getSingleOrNull();
    if (anyRate != null) return;

    await db
        .into(db.vatRates)
        .insert(
          VatRatesCompanion.insert(
            name: neutralVatRateName,
            rateBasisPoints: 0,
            isDefault: const Value(true),
            createdAt: nowUtc,
            updatedAt: nowUtc,
          ),
        );
  }
}
