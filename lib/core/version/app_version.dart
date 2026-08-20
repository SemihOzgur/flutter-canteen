/// Uygulama sürümü — **tek kaynak.**
///
/// Sürüm üç ayrı yerde görünür: yedek `metadata.json`'ında (docs/19 §2),
/// tanılama paketinde (docs/24 §7) ve kullanıcıya gösterilen "hakkında"
/// satırında. Üçü ayrı ayrı yazılsaydı, bir sürüm yükseltmesinde biri
/// güncellenmeden kalır ve **yedeğin hangi sürümle alındığı yanlış
/// kaydedilirdi** — restore uyumluluğunu bu bilgi belirler.
///
/// `pubspec.yaml`'daki `version:` alanıyla aynı tutulur; ikisinin
/// eşitliğini `test/core/app_version_test.dart` doğrular.
library;

/// Semantik sürüm — `pubspec.yaml` `version:` alanının sol yarısı.
const String appVersion = '1.0.0';

/// `pubspec.yaml` `version:` alanının sağ yarısı (build number).
const String appBuildNumber = '1';

/// Kullanıcıya gösterilen tam sürüm etiketi.
const String appVersionLabel = 'Sürüm $appVersion ($appBuildNumber)';
