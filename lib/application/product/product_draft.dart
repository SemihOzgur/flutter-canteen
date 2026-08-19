/// Ürün formunun taşıdığı veri — **docs/09 §1**
///
/// ## Neden `NewProduct` yetmiyor
///
/// `domain/models/product.dart` içindeki `NewProduct` **doğrulanmış** ve
/// kaydedilmeye hazır bir üründür: kategori kesindir, metinler kırpılmıştır.
/// [ProductDraft] ise formdan gelen **ham** niyettir:
///
/// | | `ProductDraft` | `NewProduct` |
/// |---|---|---|
/// | Kategori | `null` olabilir → `Genel` (BR-PROD-003) | zorunlu |
/// | Metinler | kırpılmamış | kırpılmış |
/// | Doğrulama | yapılmamış | yapılmış |
///
/// Dönüşüm `ProductService` içinde, tek merkezî doğrulamadan geçerek yapılır.
///
/// ## Kapsam dışı alanlar
///
/// | Alan | Neden burada yok |
/// |---|---|
/// | `stockQuantity` | ⚙️ sistem alanı; yalnızca stok hareketiyle değişir (REQ-PROD-007) |
/// | `isActive` | ⚙️ sistem alanı; `deactivate` / `activate` ile değişir |
/// | `isFavorite` | Faz 3d (REQ-PROD-009) |
/// | `imagePath` | Faz 3d (REQ-IMG-*) |
///
/// Başlangıç stoğu ve barkodlar taslağın parçası **değildir**: ikisi de
/// yalnızca **oluşturma** anında anlamlıdır ve `ProductService.create`
/// parametreleridir. Taslakta dursalardı düzenleme akışında sessizce
/// yok sayılan alanlar olurlardı.
library;

import '../../core/money/money.dart';

class ProductDraft {
  final String name;
  final String? description;

  /// BR-PROD-003 — `null` ise `Genel` sistem kategorisi kullanılır.
  final int? categoryId;

  /// Serbest metin (BR-SUP-003).
  final String? brand;

  /// Serbest metin (BR-SUP-004) — açıklayıcıdır.
  final String? salesUnit;

  /// Milli hassasiyet (150 g → `150000`). Birimle **birlikte** doldurulur
  /// (BR-PROD-011).
  final int? netWeightValue;
  final String? netWeightUnit;

  /// BR-PROD-002 — boş bırakılabilir; varsayılan `0`, asla `null`.
  final Money purchasePrice;

  /// **KDV DAHİL** satış fiyatı (BR-VAT-003 · REQ-PROD-014).
  final Money salePrice;

  /// `null` ise varsayılan oran kullanılır (docs/08 §4).
  final int? vatRateId;

  final int minimumStock;
  final int? supplierId;
  final String? shelfLocation;

  const ProductDraft({
    required this.name,
    required this.salePrice,
    this.description,
    this.categoryId,
    this.brand,
    this.salesUnit,
    this.netWeightValue,
    this.netWeightUnit,
    this.purchasePrice = Money.zero,
    this.vatRateId,
    this.minimumStock = 0,
    this.supplierId,
    this.shelfLocation,
  });
}
