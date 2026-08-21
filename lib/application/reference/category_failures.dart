/// Kategori yönetiminin ürettiği **beklenen iş hataları**.
///
/// rules/06 §7: beklenen iş hataları `Result`/`Failure` ile döner; exception
/// fırlatılmaz. Desen `application/auth/auth_failures.dart` ile aynıdır.
///
/// Mesajlar Türkçedir (REQ-UX-007), teknik detay içermez (REQ-SEC-007) ve
/// rules/05 §5 biçimindedir: **ne oldu + ne yapmalıyım.**
library;

import '../../core/result/result.dart';

abstract final class CategoryFailures {
  static const Failure nameRequired = Failure(
    code: 'category_name_required',
    userMessage: 'Kategori adı boş olamaz.',
  );

  /// REQ-CAT-005 · EC-CAT-003 — benzersizlik **pasif kategorileri de kapsar.**
  ///
  /// Kullanıcının en sık karşılaşacağı hâli budur: pasife aldığı bir kategorinin
  /// adını yeniden kullanmak ister. Mesaj bu yüzden nedeni açıkça söyler.
  static const Failure nameExists = Failure(
    code: 'category_name_exists',
    userMessage:
        'Bu kategori adı zaten kullanılıyor. Pasif kategoriler de aynı adı '
        'kullanamaz; farklı bir ad girin.',
  );

  /// OD-029 — katalog dışı anahtar veritabanına YAZILMAZ.
  ///
  /// Girerse hiçbir ekranda ikon göstermez ve kullanıcı nedenini anlayamaz;
  /// sessizce çalışmayan bir kayıt, açık bir hatadan kötüdür.
  static const Failure unknownIcon = Failure(
    code: 'category_icon_unknown',
    userMessage: 'Seçilen ikon tanınmıyor. Listeden bir ikon seçin.',
  );

  static const Failure notFound = Failure(
    code: 'category_not_found',
    userMessage: 'Kategori bulunamadı.',
  );

  /// BR-CAT-004 · EC-CAT-001 — `Genel` sistem kategorisi korunur.
  static const Failure systemProtected = Failure(
    code: 'category_system_protected',
    userMessage:
        '"Genel" sistem kategorisidir. Adı değiştirilemez, pasifleştirilemez '
        've silinemez.',
  );

  /// BR-CAT-002 · BR-CAT-005 · EC-CAT-006 — kullanımdaki kategori silinemez.
  ///
  /// Sayılar mesajda verilir: kullanıcı "neden silemiyorum?" sorusunu ekranı
  /// terk etmeden yanıtlayabilmelidir (rules/05 §5).
  static Failure inUse({
    required int productCount,
    required int saleItemCount,
  }) {
    final reasons = <String>[
      if (productCount > 0) '$productCount ürün bu kategoride',
      if (saleItemCount > 0) 'geçmiş satışlarda kullanılmış',
    ];
    return Failure(
      code: 'category_in_use',
      userMessage:
          'Bu kategori silinemez: ${reasons.join(', ')}. '
          'Kategoriyi pasife alabilirsiniz; mevcut ürünler etkilenmez.',
    );
  }

  /// REQ-CAT-004 — kaynak ve hedef aynı olamaz.
  static const Failure sameCategory = Failure(
    code: 'category_same_target',
    userMessage:
        'Ürünler zaten bu kategoride. Taşımak için farklı bir kategori seçin.',
  );

  /// docs/10 §1.3 — pasif kategoriye yeni ürün ataması yapılamaz.
  static const Failure targetInactive = Failure(
    code: 'category_target_inactive',
    userMessage:
        'Ürünler pasif bir kategoriye taşınamaz. '
        'Önce hedef kategoriyi aktifleştirin veya başka bir kategori seçin.',
  );
}
