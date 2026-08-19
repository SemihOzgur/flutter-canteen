/// Kayıt konumu seçici — **REQ-AUTH-022**
///
/// Kurtarma kodu bir dosyaya kaydedilebilir; konumu **kullanıcı seçer**
/// (uygulama düz metin kodu kendi veri dizinine yazmaz — BR-SEC-001 ·
/// `rules/04 §5`). Konum seçmek bir UI işidir, **yazmak** değildir: yazma
/// `data/files/text_file_writer.dart`'a aittir (`rules/01 §1`).
///
/// ## Neden ayrı dosyada
///
/// `rules/01 §3` karar testi:
///
/// 1. Bugün en az iki somut kullanımı var mı? — **Evet:** kurulum sihirbazı
///    Adım 3 (REQ-AUTH-022) ve kurtarma akışının yeni kod adımı
///    (BR-AUTH-017 · EC-REC-006), ayrıca Ayarlar'dan kod yenileme
///    (REQ-AUTH-028 · EC-REC-009).
/// 2. Testte enjekte edilebilir olması gerekiyor mu? — **Evet:** widget testi
///    gerçek işletim sistemi dialogunu açmaz.
///
/// Her iki ölçüt de karşılandığı için tip ortak bir yerde yaşar; sınıf veya
/// servis hiyerarşisi **kurulmaz**, tek typedef + tek fonksiyon yeterlidir.
library;

import 'package:file_selector/file_selector.dart' as file_selector;

/// Kullanıcıya kayıt konumu sorar; iptal edilirse `null`.
typedef SaveLocationPicker = Future<String?> Function(String suggestedName);

/// Üretim uygulaması — yerel kayıt dialogu.
Future<String?> pickSaveLocation(String suggestedName) async {
  final location = await file_selector.getSaveLocation(
    suggestedName: suggestedName,
  );
  return location?.path;
}
