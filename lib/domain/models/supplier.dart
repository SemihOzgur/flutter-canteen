/// Tedarikçi — docs/04-domain-model.md §3.3
///
/// Saf Dart (rules/01 §1). Gerekçesi `domain/models/category.dart` başlığındaki
/// ile aynıdır: docs/04 §1 tedarikçiyi entity envanterinde sayar (#3) ve bu tip
/// Drift satır tipinin `data/` sınırından dışarı çıkmasını gereksiz kılar.
///
/// **Silinmez** (BR-SUP-002 · REQ-SUP-002): yalnızca pasifleştirilir. Bu kural
/// koda bir runtime kontrolü olarak değil, `SupplierService`'te silme metodunun
/// **hiç bulunmaması** olarak yansır.
library;

/// Ürünün opsiyonel tedarikçisi (BR-SUP-001 · REQ-SUP-004).
class Supplier {
  final int id;

  /// **Tek zorunlu alan** (REQ-SUP-001).
  ///
  /// Şemada benzersizlik kısıtı **yoktur** (docs/05 §2.3) — aynı adı taşıyan
  /// iki tedarikçi kaydı geçerlidir.
  final String name;

  final String? contactName;
  final String? phone;
  final String? email;
  final String? address;
  final String? note;

  /// Soft delete. Pasifleştirme bağlı ürünleri ve geçmiş stok girişlerini
  /// **etkilemez** (BR-SUP-002 · EC-SUP-001).
  final bool isActive;

  /// UTC (BR-GEN-004).
  final DateTime createdAt;
  final DateTime updatedAt;

  const Supplier({
    required this.id,
    required this.name,
    required this.contactName,
    required this.phone,
    required this.email,
    required this.address,
    required this.note,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  bool operator ==(Object other) =>
      other is Supplier &&
      other.id == id &&
      other.name == name &&
      other.contactName == contactName &&
      other.phone == phone &&
      other.email == email &&
      other.address == address &&
      other.note == note &&
      other.isActive == isActive &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    contactName,
    phone,
    email,
    address,
    note,
    isActive,
    createdAt,
    updatedAt,
  );

  @override
  String toString() => 'Supplier(id: $id, name: $name, isActive: $isActive)';
}
