/// Açılışta hangi ekranın gösterileceği — **docs/03 §6 adım 7 · 9 · 10**
///
/// ```text
///  7. Kurulum kontrolü   → tamamlanmamışsa sihirbaz          [EC-AUTH-008 · H6]
///  9. Oturum yükle       → varsa ana ekran, yoksa login      [REQ-AUTH-001/006]
/// 10. Finansal kilit KAPALI başlar (bellekte)                [EC-DASH-006]
/// ```
///
/// ## Neden ayrı bir fonksiyon
///
/// `main()` unit test edilemez. Bu karar ise business davranışıdır: hiç kullanıcı
/// yokken login ekranı gösterilirse kullanıcı **hiçbir zaman** giremez
/// (EC-AUTH-008), yarım kalmış kurulumda sihirbaz atlanırsa dashboard parolası
/// veya kurtarma kodu sessizce hiç oluşmaz (REQ-AUTH-016/022). Karar `main()`
/// içinde kalsaydı yalnızca elle doğrulanabilirdi.
///
/// Fonksiyon yeni bir soyutlama katmanı **değildir** (rules/01 §3): durum
/// üretmez, servis sarmalamaz; iki servisin cevabını tek bir rota adına çevirir.
///
/// ## Adım 10 burada neden yok
///
/// Kilit **kapalı başlar** kuralı bir kod adımı gerektirmez: `FinancialAccessService`
/// bellekte `false` ile doğar ve durumu hiçbir yere yazılmaz (BR-AUTH-016).
/// Doğru davranış, kilidi açan bir satırın **bulunmamasıdır** — bu yüzden
/// burada da, `main.dart` içinde de kilidi açan bir çağrı yoktur ve
/// `test/app/startup_test.dart` bunu doğrular.
library;

import '../application/auth/session_service.dart';
import '../application/auth/setup_service.dart';
import 'router.dart';

/// Açılış rotasını çözer.
///
/// Sıra bağlayıcıdır: **önce kurulum, sonra oturum.** Kurulum yarım kalmışsa
/// (örn. kullanıcı oluşturulmuş ama dashboard parolası belirlenmemiş) sihirbaz
/// kaldığı adımdan devam eder; oturum varlığı bu kararı değiştirmez.
Future<String> resolveInitialRoute({
  required SetupService setup,
  required SessionService session,
}) async {
  if (await setup.currentState() != SetupState.complete) {
    return AppRoutes.setup;
  }

  // EC-AUTH-003/004: geçersiz oturum `load()` içinde sessizce temizlenir ve
  // `null` döner — burada ek bir kontrol gerekmez.
  final user = await session.load();
  return user == null ? AppRoutes.login : AppRoutes.home;
}
