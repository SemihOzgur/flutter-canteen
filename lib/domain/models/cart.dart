/// Aktif sepet — docs/04-domain-model.md §3.8 · docs/12 §2
///
/// Saf Dart (rules/01 §1).
///
/// ## Sepet ≠ Satış — BR-CART-003
///
/// Bu model **hiçbir snapshot taşımaz.** Sepet satırı ürünün *güncel* verisine
/// bakan geçici bir görünümdür; kalıcı ve değişmez snapshot yalnızca satış
/// tamamlanırken `SaleItem`'a yazılır (rules/02 §3). [CartLine.productName] ve
/// [CartLine.vatRateBp] bu yüzden "o anki değer"dir — satışta yeniden okunur.
///
/// Sepetin stoğa, ciroya ve raporlara **etkisi yoktur** (BR-CART-004).
library;

import '../../core/money/money.dart';
import '../services/vat_calculator.dart';

/// Sepetteki bir satır.
///
/// Aynı ürün **aynı birim fiyatla** tek satırda birleşir; farklı fiyatla
/// ayrı satır açar (REQ-CART-006 · EC-CART-004). Bu invariant veritabanında
/// `UNIQUE(cart_id, product_id, unit_price_minor)` ile de zorlanır.
class CartLine {
  final int id;
  final int productId;

  /// Görüntüleme içindir — **snapshot değildir** (BR-CART-003).
  final String productName;

  /// BR-SALE-011 — pozitif tam sayı.
  final int quantity;

  /// **KDV dahil** uygulanan birim fiyat.
  final Money unitPrice;

  /// Ürünün **güncel** liste fiyatı (KDV dahil).
  ///
  /// [unitPrice] ile farkı iki ayrı şeyi anlatabilir; hangisi olduğunu
  /// [isPriceOverridden] söyler:
  /// - `true`  → kullanıcı bu satışa özel fiyat uyguladı (docs/12 §4)
  /// - `false` → ürünün fiyatı sepet dururken değişti (EC-CART-002)
  final Money listPrice;

  /// docs/12 §4 — satır fiyatı kullanıcı tarafından değiştirildi.
  final bool isPriceOverridden;

  /// Satış anında **yeniden okunur**; buradaki değer yalnızca gösterim içindir.
  final int vatRateBp;

  /// Ürünün güncel stoğu — **negatif olabilir** (BR-STOCK-006).
  final int stockQuantity;

  /// docs/12 §2.4 — pasifleşmiş ürün sepette kalır, satışı engellemez.
  final bool isProductActive;

  const CartLine({
    required this.id,
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.listPrice,
    required this.isPriceOverridden,
    required this.vatRateBp,
    required this.stockQuantity,
    required this.isProductActive,
  });

  /// EC-CART-002 — ürünün fiyatı sepet dururken değişti.
  ///
  /// Sepetteki fiyat **korunur**; kullanıcıya rozetle gösterilir ve kararı o
  /// verir (REQ-CART-007). Fiyatı kullanıcı değiştirdiyse bu "eskimişlik"
  /// değildir, bilinçli bir tercihtir — o yüzden override edilmiş satır
  /// hiçbir zaman bayat sayılmaz.
  bool get isPriceStale => !isPriceOverridden && unitPrice != listPrice;

  /// BR-STOCK-006 — satışı **engellemez**, yalnızca uyarır.
  bool get isOutOfStock => stockQuantity <= 0;

  /// KDV dahil satır tutarı.
  Money get lineTotal => unitPrice * quantity;

  /// BR-VAT-003 — KDV fiyatın **içinden** çıkarılır.
  ///
  /// Hesap `domain/services/vat_calculator`'a devredilir; sepette ikinci bir
  /// KDV formülü yoktur (rules/01 §2).
  VatBreakdown get breakdown => VatCalculator.forLine(
    unitPrice: unitPrice,
    quantity: quantity,
    vatRateBp: vatRateBp,
  );

  CartLine copyWith({
    int? quantity,
    Money? unitPrice,
    bool? isPriceOverridden,
  }) {
    return CartLine(
      id: id,
      productId: productId,
      productName: productName,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      listPrice: listPrice,
      isPriceOverridden: isPriceOverridden ?? this.isPriceOverridden,
      vatRateBp: vatRateBp,
      stockQuantity: stockQuantity,
      isProductActive: isProductActive,
    );
  }
}

/// Aynı anda **yalnızca bir** aktif sepet bulunur (BR-CART-001).
class Cart {
  final int id;
  final int userId;
  final List<CartLine> lines;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// EC-CART-010 — ürünü bulunamadığı için **gösterilemeyen** satır sayısı.
  ///
  /// Sıfırdan büyükse sepetin bir kısmı bozulmuştur: satırlar düşer ama
  /// sepetin kalanı korunur ve kullanıcı bilgilendirilir. Sessizce eksik bir
  /// sepet göstermek, kasada "ben bunu eklemiştim" durumuna yol açardı.
  final int droppedLineCount;

  const Cart({
    required this.id,
    required this.userId,
    required this.lines,
    required this.createdAt,
    required this.updatedAt,
    this.droppedLineCount = 0,
  });

  /// EC-CART-010 — kullanıcıya bildirilecek bir bozulma var mı?
  bool get hasDroppedLines => droppedLineCount > 0;

  bool get isEmpty => lines.isEmpty;
  bool get isNotEmpty => lines.isNotEmpty;

  /// Farklı satır sayısı — `sales.item_count`.
  int get itemCount => lines.length;

  /// Toplam adet — `sales.unit_count`.
  int get unitCount => lines.fold(0, (sum, line) => sum + line.quantity);

  /// BR-STOCK-006 — uyarı gösterilecek satırlar (satış engellenmez).
  Iterable<CartLine> get outOfStockLines => lines.where((l) => l.isOutOfStock);

  /// **REQ-SALE-012 — sepet toplamı girilen fiyatların toplamıdır.**
  ///
  /// `aggregate` yuvarlanmış **satır** değerlerini toplar (BR-FIN-004): fişteki
  /// satırlar elle toplandığında genel toplam tutar. Brüt tutar zaten
  /// `Σ (unitPrice × quantity)` olduğu için üzerine hiçbir ek yapılmaz.
  VatBreakdown get totals =>
      VatCalculator.aggregate(lines.map((line) => line.breakdown));
}
