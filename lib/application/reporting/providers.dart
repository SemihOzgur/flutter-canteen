/// Rapor servislerinin provider'ları (OD-002 — Riverpod).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dao/reporting_dao.dart';
import '../../data/db/providers.dart';
import '../../data/files/report_file.dart';
import '../auth/providers.dart';
import '../audit/providers.dart';
import 'dashboard_service.dart';
import 'report_export_service.dart';

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

/// docs/16 §2 — rapor dışa aktarma. **Kilidin arkasındadır** (BR-AUTH-012).
final reportExportServiceProvider = Provider<ReportExportService>(
  (ref) => ReportExportService(
    dashboard: ref.watch(dashboardServiceProvider),
    audit: ref.watch(auditServiceProvider),
    clock: ref.watch(canteenDatabaseProvider).clock,
  ),
);

/// CSV metnini diske yazar — testlerde override edilir.
///
/// Ayrı bir provider olmasının sebebi `rules/01 §1`: ekran `dart:io`
/// görmemelidir. Bir servis hiyerarşisi kurmaya değmez (rules/01 §3).
typedef ReportFileWriter = Future<bool> Function(String path, String contents);

final reportFileWriterProvider = Provider<ReportFileWriter>(
  (ref) => writeReportFile,
);
