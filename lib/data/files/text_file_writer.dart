/// Kullanıcının seçtiği yola düz metin dosyası yazar.
///
/// ## Neden burada
///
/// `rules/01 §1`: **presentation katmanı dosya sistemi erişimi içeremez.**
/// Kurulum sihirbazı kurtarma kodunu dosyaya kaydedebilir (REQ-AUTH-022);
/// konumu kullanıcı seçer (bu bir UI işidir), ama **yazma** buraya aittir.
///
/// ## Neden sınıf değil, fonksiyon
///
/// `rules/01 §3` karar testi:
///
/// 1. Bugün en az iki somut kullanımı var mı? — Hayır, tek kullanımı var.
/// 2. Bir servis testini anlamlı şekilde mümkün kılıyor mu? — **Evet:**
///    [TextFileWriter] tipi enjekte edilebilir olduğu için widget testi gerçek
///    diske yazmadan çalışır.
///
/// Ölçüt (2) karşılandığı için tip vardır; ölçüt (1) karşılanmadığı için
/// **sınıf, servis veya klasör hiyerarşisi kurulmaz.** Tek fonksiyon yeterlidir.
library;

import 'dart:io';

/// Enjekte edilebilir yazma işlemi — testler gerçek diske dokunmaz.
typedef TextFileWriter = Future<void> Function(String path, String contents);

/// Üretim uygulaması: dosyayı yazar ve diske **flush** eder.
///
/// `flush: true` bilinçlidir — kullanıcı kurtarma kodunu kaydettiğini
/// gördükten hemen sonra makineyi kapatabilir.
Future<void> writeTextFile(String path, String contents) =>
    File(path).writeAsString(contents, flush: true);
