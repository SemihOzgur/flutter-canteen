/// Kategori — docs/04-domain-model.md §3.2
///
/// Saf Dart: Flutter, Drift veya dosya sistemi bağımlılığı **yoktur**
/// (rules/01 §1). `Product` ve `Sale` ile aynı desendedir.
///
/// ## Bu bir "DTO katmanı" değildir
///
/// `rules/01 §3` gereksiz DTO/Mapper katmanını yasaklar. Bu tip bir dönüşüm
/// katmanı değil, **envanterdeki bir entity'nin kendisidir**: docs/04 §1
/// kategoriyi 15 entity'den biri olarak sayar (#2) ve ona ait yaşam döngüsü
/// ([isActive]), koruma ([isSystem]) ve silme politikası (docs/04 §5) tanımlar.
///
/// Karşılığı Drift'in ürettiği satır tipidir; o tip `data/` katmanına aittir ve
/// oradan dışarı çıkarsa presentation `package:drift` tiplerine bağlanır —
/// `rules/01 §1` bunu açıkça yasaklar. Eşleme `data/dao/category_mapper.dart`
/// içindedir ve yönü daima **data → domain**'dir.
///
/// > Not: `AuthUser`'ın gerekçesi bundan **farklıdır** ve burada geçerli
/// > değildir. Orada dönüşümün işi `passwordHash`/`passwordSalt` alanlarını
/// > düşürmektir (BR-SEC-001); kategori sır taşımaz ve bu tip hiçbir alanı
/// > gizlemez — satırın tamamını taşır.
library;

/// Ürünün zorunlu sınıflandırması (BR-CAT-001).
class Category {
  final int id;

  /// Sistem genelinde benzersizdir; benzersizlik **pasif kayıtları da kapsar**
  /// (REQ-CAT-005 · docs/05 §2.2 `UNIQUE(name)`).
  final String name;

  /// Satış ekranı sıralaması.
  final int sortOrder;

  /// `Genel` için `true` — BR-CAT-004: silinemez, pasifleştirilemez, adı
  /// değiştirilemez.
  final bool isSystem;

  /// Soft delete. Pasif kategoriye bağlı ürünler **etkilenmez** (BR-CAT-003).
  final bool isActive;

  /// UTC (BR-GEN-004).
  final DateTime createdAt;
  final DateTime updatedAt;

  const Category({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.isSystem,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  bool operator ==(Object other) =>
      other is Category &&
      other.id == id &&
      other.name == name &&
      other.sortOrder == sortOrder &&
      other.isSystem == isSystem &&
      other.isActive == isActive &&
      other.createdAt == createdAt &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    sortOrder,
    isSystem,
    isActive,
    createdAt,
    updatedAt,
  );

  @override
  String toString() =>
      'Category(id: $id, name: $name, sortOrder: $sortOrder, '
      'isSystem: $isSystem, isActive: $isActive)';
}
