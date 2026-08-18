/// Tedarikçi yönetiminin ürettiği **beklenen iş hataları**.
///
/// rules/06 §7 · desen: `application/auth/auth_failures.dart`.
///
/// **Silme hatası yoktur** — BR-SUP-002 · REQ-SUP-002 gereği `SupplierService`
/// silme metodu **sunmaz**; reddedilecek bir çağrı da yoktur.
library;

import '../../core/result/result.dart';

abstract final class SupplierFailures {
  /// REQ-SUP-001 — yalnızca ad zorunludur; boş olamaz.
  static const Failure nameRequired = Failure(
    code: 'supplier_name_required',
    userMessage: 'Tedarikçi adı boş olamaz.',
  );

  static const Failure notFound = Failure(
    code: 'supplier_not_found',
    userMessage: 'Tedarikçi bulunamadı.',
  );
}
