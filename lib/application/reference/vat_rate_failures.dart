/// KDV oranı yönetiminin ürettiği **beklenen iş hataları**.
///
/// rules/06 §7 · desen: `application/auth/auth_failures.dart`.
///
/// **Silme hatası yoktur** — docs/08 §4 gereği oran kaydı silinemez ve
/// `VatRateService` silme metodu **sunmaz**.
library;

import '../../core/result/result.dart';

abstract final class VatRateFailures {
  static const Failure nameRequired = Failure(
    code: 'vat_rate_name_required',
    userMessage: 'KDV oranı adı boş olamaz.',
  );

  /// BR-FIN-002 — oran basis point tam sayıdır; negatif veya ikiden fazla
  /// ondalık basamak kabul edilmez (`%0,005` tam sayı bp değildir).
  static const Failure invalidRate = Failure(
    code: 'vat_rate_invalid',
    userMessage: 'KDV oranı geçersiz. Örnek: 20 veya 0,5',
  );

  static const Failure notFound = Failure(
    code: 'vat_rate_not_found',
    userMessage: 'KDV oranı bulunamadı.',
  );

  /// docs/08 §4: varsayılan oran, ürüne oran atanmamışsa **kullanılan** orandır.
  ///
  /// **BR-VAT-006 · REQ-VAT-010 · EC-VAT-001 (OD-019).**
  ///
  /// Pasif bir oran varsayılan yapılsaydı sistem "varsayılan oran yok" durumuna
  /// düşer ve KDV sessizce `%0` hesaplanırdı. Hata bu yüzden açıktır: sessiz
  /// KDV kaybı yerine görünür bir uyarı.
  static const Failure inactiveCannotBeDefault = Failure(
    code: 'vat_rate_inactive_default',
    userMessage:
        'Pasif bir KDV oranı varsayılan yapılamaz. Varsayılan olarak '
        'kullanımdaki oranlardan birini seçin.',
  );
}
