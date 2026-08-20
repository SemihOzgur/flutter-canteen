/// İade — docs/04-domain-model.md §3.10 · docs/14
///
/// Saf Dart (rules/01 §1).
///
/// ## Neden ayrı bir entity
///
/// docs/14 §1: **kısmi iade tek bir satış durumuyla ifade edilemez.** Bir
/// satıştan farklı tarihlerde birden fazla kısmi iade yapılabilir; her biri
/// kendi tarihine, tutarına ve sebebine sahiptir. `sales.status` bunların
/// **özetidir**, kendisi değil.
///
/// ## Tutar orijinal snapshot'tan gelir — BR-RET-005
///
/// Müşteri ₺25'e aldığı ürünü, ürün ₺30 olduğunda iade ettiğinde **₺25** geri
/// alır. Bu, fiyat snapshot mimarisinin (rules/02 §3) doğrudan sonucudur.
library;

import '../../core/money/money.dart';
import '../enums/return_type.dart';

class SaleReturn {
  final int id;
  final int saleId;

  /// Tam mı kısmi mi — bu **tek iadenin** kapsamıdır, satışın değil.
  final ReturnType type;

  final Money total;
  final String? reason;
  final int userId;

  /// UTC. **İade bu tarihe raporlanır** (BR-RET-008 · docs/14 §5): para
  /// kasadan bugün çıkmıştır; orijinal satışın tarihi değişmez.
  final DateTime createdAtUtc;

  const SaleReturn({
    required this.id,
    required this.saleId,
    required this.type,
    required this.total,
    required this.reason,
    required this.userId,
    required this.createdAtUtc,
  });
}

class SaleReturnItem {
  final int id;
  final int returnId;
  final int saleItemId;
  final int quantity;

  /// **Orijinal satış snapshot'ı** — güncel fiyat değil (BR-RET-005).
  final Money unitPrice;

  final Money lineTotal;

  const SaleReturnItem({
    required this.id,
    required this.returnId,
    required this.saleItemId,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });
}

/// Henüz kaydedilmemiş iade satırı.
///
/// Fiyat **taşımaz**: servis onu `sale_items.unit_price_minor`'dan okur.
/// Çağırana bırakılsaydı ekran güncel fiyatı gönderebilir ve BR-RET-005
/// sessizce ihlal edilirdi.
class ReturnLineRequest {
  final int saleItemId;
  final int quantity;

  const ReturnLineRequest({required this.saleItemId, required this.quantity});
}

/// Henüz kaydedilmemiş iade başlığı.
class NewReturn {
  final int saleId;
  final ReturnType type;
  final Money total;
  final String? reason;
  final int userId;
  final DateTime createdAtUtc;

  const NewReturn({
    required this.saleId,
    required this.type,
    required this.total,
    required this.reason,
    required this.userId,
    required this.createdAtUtc,
  });
}

/// Henüz kaydedilmemiş iade satırı — fiyat **servis tarafından** doldurulur.
class NewReturnItem {
  final int saleItemId;
  final int quantity;
  final Money unitPrice;
  final Money lineTotal;

  const NewReturnItem({
    required this.saleItemId,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });
}
