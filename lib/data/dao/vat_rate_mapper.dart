/// Drift `vat_rates` satırını domain [VatRate]'ine çevirir.
///
/// Yön **data → domain** (rules/01 §1). Desen `user_mapper.dart` ile aynıdır.
library;

import '../../domain/models/vat_rate.dart';
import '../db/canteen_database.dart' as db;

extension VatRateRowToDomain on db.VatRate {
  VatRate toDomain() => VatRate(
    id: id,
    name: name,
    rateBasisPoints: rateBasisPoints,
    isDefault: isDefault,
    isActive: isActive,
    createdAt: createdAt,
    updatedAt: updatedAt,
  );
}
