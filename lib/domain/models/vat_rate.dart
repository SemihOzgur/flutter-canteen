/// KDV oranı — docs/04-domain-model.md §3.4
///
/// Saf Dart (rules/01 §1). Gerekçesi `domain/models/category.dart` başlığındaki
/// ile aynıdır: docs/04 §1 KDV oranını entity envanterinde sayar (#4).
///
/// - **BR-VAT-001:** oranlar veritabanında yönetilir; koda gömülmez.
/// - **docs/08 §3:** hiçbir oran **seed edilmez**; kullanıcı kendi oranlarını
///   tanımlar.
/// - **docs/08 §4:** oran kaydı **silinmez**; yalnızca pasifleştirilir.
library;

/// Yönetilebilir KDV oranı (BR-VAT-001).
class VatRate {
  final int id;

  /// Kullanıcının verdiği ad — örn. "Standart", "İndirimli".
  final String name;

  /// **Basis point tam sayı** (BR-FIN-002 · rules/02 §1):
  /// `%20 → 2000` · `%1 → 100` · `%0,5 → 50`.
  ///
  /// Şema `CHECK(rate_basis_points >= 0)` uygular (docs/05 §2.4).
  final int rateBasisPoints;

  /// docs/04 §3.4: **yalnızca bir kayıt** `true` olabilir.
  ///
  /// Ürüne oran atanmamışsa (`products.vat_rate_id IS NULL`) bu oran kullanılır
  /// (docs/08 §4).
  final bool isDefault;

  final bool isActive;

  /// UTC (BR-GEN-004).
  final DateTime createdAt;
  final DateTime updatedAt;

  const VatRate({
    required this.id,
    required this.name,
    required this.rateBasisPoints,
    required this.isDefault,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  bool operator ==(Object other) =>
      other is VatRate &&
      other.id == id &&
      other.name == name &&
      other.rateBasisPoints == rateBasisPoints &&
      other.isDefault == isDefault &&
      other.isActive == isActive &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    rateBasisPoints,
    isDefault,
    isActive,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'VatRate(id: $id, name: $name, rateBasisPoints: $rateBasisPoints, '
      'isDefault: $isDefault, isActive: $isActive)';
}
