/// Ürün alan kuralları — **docs/09 §1 · BR-PROD-001…014**
///
/// Saf Dart (rules/01 §1): burada veritabanı, Flutter veya I/O yoktur. Alan
/// sınırları ve "büyük fiyat değişikliği" ölçütü **tek merkezî yerde** yaşar
/// (rules/01 §2); `ProductService`, import (Faz 10) ve ürün formu aynı kaynağı
/// kullanır.
library;

import '../../core/money/money.dart';

abstract final class ProductRules {
  /// docs/09 §1 — "1–120 karakter, baştaki/sondaki boşluk kırpılır".
  static const int nameMaxLength = 120;

  /// docs/09 §1 — "Maks. 500 karakter".
  static const int descriptionMaxLength = 500;

  /// docs/09 §1 — "Maks. 50 karakter".
  static const int shelfLocationMaxLength = 50;

  /// docs/09 §6 — "Maksimum 50 sonuç gösterilir".
  static const int searchResultLimit = 50;

  /// REQ-PROD-012 — satış fiyatı **%50'den fazla** değişirse onay istenir.
  static const int significantPriceChangePercent = 50;

  /// docs/09 §5 — "Öneri: **30'dan fazla** favori eklenirse kullanıcı uyarılır
  /// (ekran karmaşası)."
  ///
  /// Bir **uyarı eşiğidir**, kısıt değil: doküman "öneri" der ve favori
  /// eklemeyi engelleyen hiçbir kural yoktur (BR-PROD-008). Eşik burada
  /// yaşar ki servis ve gelecekteki satış ekranı (Faz 5) aynı sayıyı
  /// kullansın (rules/01 §2).
  static const int favoriteWarningThreshold = 30;

  /// docs/09 §1 · docs/04 §3.6 — gramaj birimi **önerileri**.
  ///
  /// ⚠️ Bu liste bir **kısıt değildir.** Doküman birimleri sayar ama "yalnızca
  /// bunlar geçerlidir" demez ve şemada da karşılık gelen bir `CHECK` yoktur
  /// (docs/05 §2.5 — oradaki tek kısıt çift kuralıdır). rules/00 §6 dokümanda
  /// olmayan bir kısıtı uydurmayı yasakladığı için servis birimi **reddetmez**;
  /// liste yalnızca formun seçeneklerini besler.
  ///
  /// Alan zaten hiçbir fiyat/stok hesabına girmez (BR-PROD-011).
  static const List<String> netWeightUnitSuggestions = ['g', 'kg', 'ml', 'lt'];

  /// docs/09 §1 — "Öneri listesi: adet, paket, kutu, koli". Serbest metindir
  /// (BR-SUP-004); kısıtlanmaz.
  static const List<String> salesUnitSuggestions = [
    'adet',
    'paket',
    'kutu',
    'koli',
  ];

  /// Baştaki/sondaki boşluk kırpılır; geriye bir şey kalmazsa `null`.
  ///
  /// Boş metin ile `null` arasında ayrım yapılmaz: kullanıcı bir alanı
  /// temizlediğinde veritabanında `''` değil `NULL` bulunmalıdır.
  static String? normalizeOptional(String? raw) {
    if (raw == null) return null;
    final trimmed = raw.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// BR-PROD-011 · EC-PROD-018 — değer ve birim ya birlikte dolu ya ikisi de boş.
  ///
  /// Şemada `CHECK((net_weight_value IS NULL) = (net_weight_unit IS NULL))`
  /// zaten vardır; bu kural onun **anlaşılır Türkçe karşılığını** verebilmek
  /// içindir. Ham `SqliteException` kullanıcıya gösterilemez (REQ-SEC-007).
  static bool isWeightPairValid(int? value, String? unit) =>
      (value == null) == (unit == null);

  /// REQ-PROD-012 — satış fiyatı %50'den fazla değişti mi?
  ///
  /// Yanlış kuruş/lira girişini yakalamak içindir (₺25,00 yerine ₺2.500,00).
  ///
  /// Hesap **tam sayı kuruş** üzerinden yapılır; oran karşılaştırması için bile
  /// `double` kullanılmaz (BR-FIN-001):
  ///
  /// ```text
  /// |yeni − eski| × 100 > eski × 50
  /// ```
  ///
  /// Eski fiyat `0` ise (ikram ürünü — EC-PROD-007) oran tanımsızdır: sıfırdan
  /// farklı her yeni fiyat **anlamlı değişikliktir**, `0 → 0` ise değişiklik
  /// yoktur.
  static bool isSignificantPriceChange(Money oldPrice, Money newPrice) {
    if (oldPrice.minor == newPrice.minor) return false;
    if (oldPrice.minor <= 0) return true;

    final delta = (newPrice.minor - oldPrice.minor).abs();
    return delta * 100 > oldPrice.minor * significantPriceChangePercent;
  }
}
