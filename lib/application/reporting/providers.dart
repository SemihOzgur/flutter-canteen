/// Rapor servislerinin provider'ları (OD-002 — Riverpod).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dao/reporting_dao.dart';
import '../../data/db/providers.dart';
import '../auth/providers.dart';
import 'dashboard_service.dart';

final reportingDaoProvider = Provider<ReportingDao>(
  (ref) => ReportingDao(ref.watch(canteenDatabaseProvider)),
);

/// docs/15 — Dashboard verisi. **Finansal erişim kilidinin arkasındadır**
/// (BR-AUTH-012): kilit kapalıyken hiçbir sorgu çalışmaz.
final dashboardServiceProvider = Provider<DashboardService>(
  (ref) => DashboardService(
    // Kilit servisinin **aynı** örneği olmak zorundadır; ikinci bir örnek
    // "açık" durumu göremez ve kullanıcı parolayı iki kez sorulur bulurdu.
    access: ref.watch(financialAccessProvider),
    dao: ref.watch(reportingDaoProvider),
    sales: ref.watch(saleRepositoryProvider),
  ),
);
