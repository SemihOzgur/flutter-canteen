/// Drift `categories` satırını domain [Category]'sine çevirir.
///
/// Yön **data → domain**'dir; domain katmanı Drift'i bilmez (rules/01 §1).
/// Drift satır tipi ile domain tipi aynı adı taşıdığı için veritabanı tarafı
/// `db` ön adıyla içeri alınır.
///
/// Desen `user_mapper.dart` ile aynıdır; ancak burada eşleme hiçbir alanı
/// **düşürmez** — kategori sır taşımaz (bkz. `domain/models/category.dart`).
library;

import '../../domain/models/category.dart';
import '../db/canteen_database.dart' as db;

extension CategoryRowToDomain on db.Category {
  Category toDomain() => Category(
    id: id,
    name: name,
    sortOrder: sortOrder,
    isSystem: isSystem,
    isActive: isActive,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
