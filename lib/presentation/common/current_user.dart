/// Oturumdaki kullanıcının id'si — audit kayıtlarının `user_id` alanı içindir.
///
/// docs/18 §2: denetim izi "kim, ne zaman, neyi değiştirdi" sorusunu
/// yanıtlar. Referans veri servisleri (`CategoryService`, `SupplierService`,
/// `VatRateService`) bunu opsiyonel `userId` parametresiyle alır; ekran onu
/// oturumdan okuyup iletir.
///
/// **Bu bir yetki kontrolü değildir** (BR-AUTH-002 · rules/04 §2): rol/yetki
/// sistemi yoktur, kullanıcı yalnızca izlenebilirlik için kaydedilir.
///
/// Oturum yoksa `null` döner ve işlem yine yapılır — kayıt kullanıcısız yazılır.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/auth/providers.dart';

Future<int?> currentUserId(WidgetRef ref) async =>
    (await ref.read(sessionServiceProvider).load())?.id;
