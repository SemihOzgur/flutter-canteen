/// Drift `suppliers` satırını domain [Supplier]'ına çevirir.
///
/// Yön **data → domain** (rules/01 §1). Desen `user_mapper.dart` ile aynıdır.
library;

import '../../domain/models/supplier.dart';
import '../db/canteen_database.dart' as db;

extension SupplierRowToDomain on db.Supplier {
  Supplier toDomain() => Supplier(
    id: id,
    name: name,
    contactName: contactName,
    phone: phone,
    email: email,
    address: address,
    note: note,
    isActive: isActive,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
