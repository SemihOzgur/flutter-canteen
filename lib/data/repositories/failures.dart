/// Data katmanının ürettiği **beklenen iş hataları**.
///
/// rules/06 §7: "Beklenen iş hataları `Result`/`Failure` ile döner; exception
/// fırlatılmaz." Beklenmeyen teknik hatalar `AppException` olarak kalır.
///
/// Mesajlar Türkçedir (REQ-UX-007) ve **teknik detay içermez** (REQ-SEC-007) —
/// SQL, dosya yolu veya kısıt adı kullanıcıya sızdırılmaz.
library;

import 'package:drift/native.dart' show SqliteException;

import '../../core/result/result.dart';

abstract final class DataFailures {
  static const Failure productNotFound = Failure(
    code: 'product_not_found',
    userMessage: 'Ürün bulunamadı.',
  );

  static const Failure saleNotFound = Failure(
    code: 'sale_not_found',
    userMessage: 'Satış bulunamadı.',
  );

  static const Failure stockMovementNotFound = Failure(
    code: 'stock_movement_not_found',
    userMessage: 'Stok hareketi bulunamadı.',
  );

  /// BR-PROD-005 — barkod global benzersizdir (pasif ürünler dahil).
  static const Failure barcodeExists = Failure(
    code: 'barcode_exists',
    userMessage: 'Bu barkod başka bir ürüne ait.',
  );

  static const Failure duplicateRecord = Failure(
    code: 'duplicate_record',
    userMessage: 'Bu kayıt zaten mevcut.',
  );

  /// BR-CART-001 — aynı anda yalnızca bir aktif sepet.
  static const Failure activeCartExists = Failure(
    code: 'active_cart_exists',
    userMessage: 'Zaten açık bir sepet var.',
  );

  static const Failure invalidReference = Failure(
    code: 'invalid_reference',
    userMessage: 'İlişkili kayıt bulunamadı.',
  );

  static const Failure constraintViolation = Failure(
    code: 'constraint_violation',
    userMessage: 'Kayıt geçerli değil.',
  );
}

/// SQLite kısıt ihlallerini **beklenen** iş hatasına çevirir.
///
/// Kısıt ihlali olmayan hatalar için `null` döner — çağıran `rethrow` yapar ve
/// hata beklenmeyen teknik hata olarak ele alınır.
///
/// Ayrıştırma kısıt/index **adına** göre yapılır; kullanıcıya gösterilen mesaj
/// asla SQLite metnini içermez.
Failure? mapConstraintFailure(Object error) {
  if (error is! SqliteException) return null;

  final detail = error.message.toLowerCase();

  if (detail.contains('ux_barcode') ||
      detail.contains('product_barcodes.barcode')) {
    return DataFailures.barcodeExists;
  }
  if (detail.contains('ux_carts_active')) {
    return DataFailures.activeCartExists;
  }
  if (detail.contains('foreign key')) {
    return DataFailures.invalidReference;
  }
  if (detail.contains('unique')) {
    return DataFailures.duplicateRecord;
  }
  if (detail.contains('check constraint')) {
    return DataFailures.constraintViolation;
  }
  return null;
}
