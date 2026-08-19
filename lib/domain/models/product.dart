/// Ürün — docs/04-domain-model.md §3.5
///
/// Saf Dart: Flutter, Drift veya dosya sistemi bağımlılığı **yoktur**
/// (rules/01 §1).
///
/// - [salePrice] **KDV DAHİLDİR** (BR-VAT-003).
/// - [stockQuantity] türetilmiş önbellektir; otorite `stock_movements`'tır
///   (BR-STOCK-002) ve **negatif olabilir** (BR-STOCK-006).
library;

import '../../core/money/money.dart';

class Product {
  final int id;
  final String name;
  final String? description;
  final int categoryId;

  /// Serbest metin (BR-SUP-003).
  final String? brand;

  /// Serbest metin (BR-SUP-004).
  final String? salesUnit;

  /// Yalnızca açıklayıcı; hiçbir fiyat/stok hesabına girmez (rules/02 §8).
  final int? netWeightValue;
  final String? netWeightUnit;

  final Money purchasePrice;

  /// **KDV dahil** satış fiyatı.
  final Money salePrice;

  final int? vatRateId;
  final int stockQuantity;
  final int minimumStock;
  final int? supplierId;
  final String? shelfLocation;

  /// **Göreli** yol (rules/03 §8).
  final String? imagePath;

  final bool isFavorite;
  final bool isActive;

  /// UTC (BR-GEN-004).
  final DateTime createdAt;
  final DateTime updatedAt;

  const Product({
    required this.id,
    required this.name,
    required this.description,
    required this.categoryId,
    required this.brand,
    required this.salesUnit,
    required this.netWeightValue,
    required this.netWeightUnit,
    required this.purchasePrice,
    required this.salePrice,
    required this.vatRateId,
    required this.stockQuantity,
    required this.minimumStock,
    required this.supplierId,
    required this.shelfLocation,
    required this.imagePath,
    required this.isFavorite,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  /// **docs/13 §7 — kritik stok.**
  ///
  /// ```text
  /// minimum_stock > 0  AND  stock_quantity <= minimum_stock
  /// ```
  ///
  /// REQ-STOCK-011: `minimum_stock = 0` olan ürün kritik **sayılmaz** —
  /// kullanıcı o ürün için takip istemiyor demektir.
  ///
  /// Sınır dahildir: stok tam eşiğe düştüğünde ürün zaten kritiktir.
  ///
  /// Kural burada **tek** yerde yaşar (rules/01 §2): ürün listesi rozeti,
  /// satır ikonu ve stok ekranı aynı ifadeyi kullanır. Kopyalandığında biri
  /// `<` diğeri `<=` olur ve fark yalnızca eşikteki üründe görünür.
  bool get isCriticalStock => minimumStock > 0 && stockQuantity <= minimumStock;

  /// **BR-STOCK-007 — negatif stok bir HATA SİNYALİDİR**, gizlenmez.
  bool get isNegativeStock => stockQuantity < 0;
}

/// Henüz kaydedilmemiş ürün (id yok).
///
/// Başlangıç stoğu **burada yoktur**: stok yalnızca `stock_movements` üzerinden
/// oluşur (BR-STOCK-001) ve bunu yazan `StockService` **Faz 6** kapsamındadır.
class NewProduct {
  final String name;
  final String? description;
  final int categoryId;
  final String? brand;
  final String? salesUnit;
  final int? netWeightValue;
  final String? netWeightUnit;
  final Money purchasePrice;
  final Money salePrice;
  final int? vatRateId;
  final int minimumStock;
  final int? supplierId;
  final String? shelfLocation;
  final String? imagePath;
  final bool isFavorite;

  const NewProduct({
    required this.name,
    required this.categoryId,
    required this.salePrice,
    this.description,
    this.brand,
    this.salesUnit,
    this.netWeightValue,
    this.netWeightUnit,
    this.purchasePrice = Money.zero,
    this.vatRateId,
    this.minimumStock = 0,
    this.supplierId,
    this.shelfLocation,
    this.imagePath,
    this.isFavorite = false,
  });
}
