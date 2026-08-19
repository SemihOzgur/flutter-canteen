/// Görsel dosyası seçici — **docs/21 §2** ("Dosya seçici (jpg, jpeg, png, webp)")
///
/// ## Neden yeni paket eklenmedi
///
/// `file_selector` zaten bir bağımlılıktır (REQ-AUTH-022 · `rules/01 §7`) ve
/// **açma** dialogunu da sunar. `rules/01 §7` sorusu (3) — "mevcut bir
/// bağımlılık bunu zaten sağlıyor mu?" — evet olduğu için ikinci bir paket
/// eklenmez.
///
/// ## Neden burada
///
/// Dosya **seçmek** bir UI işidir; **okumak/yazmak** değildir. Seçilen yolun
/// doğrulanması, optimize edilmesi ve diske yazılması `data/files/` altındadır
/// (`rules/01 §1`). Emsal: `save_location_picker.dart`.
///
/// ⚠️ Uzantı filtresi yalnızca **kolaylıktır**: gerçek doğrulama dosya
/// içeriğinden yapılır (REQ-IMG-005 · `ImageFormatDetector`). Kullanıcı "tüm
/// dosyalar" seçip `.jpg` adlı bir metin dosyası verse bile reddedilir.
library;

import 'package:file_selector/file_selector.dart' as file_selector;

/// Kullanıcıya görsel dosyası sorar; iptal edilirse `null`.
typedef ImageFilePicker = Future<String?> Function();

/// Üretim uygulaması — yerel açma dialogu.
Future<String?> pickImageFile() async {
  final file = await file_selector.openFile(
    acceptedTypeGroups: const [
      file_selector.XTypeGroup(
        label: 'Görsel',
        extensions: ['jpg', 'jpeg', 'png', 'webp'],
      ),
    ],
  );
  return file?.path;
}
