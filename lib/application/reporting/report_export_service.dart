/// Rapor dışa aktarma — **docs/16 §2 · REQ-REP-011 · REQ-IMEX-014 ·
/// REQ-AUDIT-010 · BR-AUTH-012**
///
/// ## Kilit burada da geçerlidir
///
/// Dışa aktarma bir **rapor sorgusudur**: parola doğrulanmadan çalışmaz
/// (BR-AUTH-012). Kilidi yalnızca ekranda uygulamak, "dışa aktar" düğmesini
/// kilidin etrafından dolaşan bir yol hâline getirirdi.
///
/// ## Dışa aktarma FİLTRELENMİŞ TÜM sonucu kapsar
///
/// docs/16 §2: *"yalnızca görünen sayfayı değil."* Sayfalama bir gösterim
/// ayrıntısıdır; kullanıcı 1.284 satırlık raporu dışa aktardığında 50 satır
/// almamalıdır.
library;

import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../core/result/result.dart';
import '../../data/files/csv_writer.dart';
import '../../domain/services/report_metrics.dart';
import '../../domain/services/report_period.dart';
import '../audit/audit_actions.dart';
import '../audit/audit_service.dart';
import 'dashboard_service.dart';

/// docs/16 §3 — dışa aktarılabilir rapor türleri.
///
/// Katalogdaki 12 raporun Faz 8'de veri katmanı hazır olanları. Kalanlar
/// kendi veri kaynaklarını Faz 10/11'de kazanır; burada **uydurma bir rapor
/// üretilmez** (rules/00 §6).
enum ExportableReport {
  /// R2 — ürün satış raporu.
  productSales,

  /// R6 — kategori raporu.
  categorySales,
}

class ReportExportService {
  final DashboardService _dashboard;
  final AuditService? _audit;
  final DateTime Function() _clock;

  ReportExportService({
    required DashboardService dashboard,
    required DateTime Function() clock,
    AuditService? audit,
  }) : _dashboard = dashboard,
       _audit = audit,
       _clock = clock;

  /// Raporu CSV metnine çevirir.
  ///
  /// Dönen metin **BOM ile başlar** ve `;` ile ayrılır (rules/03 §7).
  /// Kilit kapalıysa sorgu **çalışmaz** ve `Err` döner.
  Future<Result<String>> exportCsv({
    required ExportableReport report,
    required ReportPeriod period,
  }) async {
    // Kilit kontrolü BURADA TEKRARLANMAZ.
    //
    // `_dashboard` çağrılarının hepsi zaten kapının arkasındadır; kilit
    // kapalıyken `rows` `Err` döner ve metot audit yazımına **hiç
    // ulaşmaz**. Ayrı bir `isUnlocked` kontrolü eklenmişti; mutasyon testi
    // (X1) onu kaldırdığında hiçbir test kırılmadı — çünkü gerçekten
    // gereksizdi. "Audit kaydı bile yazılmasın" gerekçesi de yanlıştı:
    // o güvenceyi sağlayan şey aşağıdaki erken `return`'dür (rules/06 §7 —
    // ölü kod bırakılmaz, yanlış yorum ise daha kötüdür).
    final rows = switch (report) {
      ExportableReport.productSales => await _productRows(period),
      ExportableReport.categorySales => await _categoryRows(period),
    };
    if (rows.isErr) return Err(rows.failureOrNull!);

    final csv = CsvWriter.encode(rows.valueOrNull!);

    await _audit?.record(
      action: AuditActions.dataExported,
      entityType: AuditEntities.system,
      at: _clock().toUtc(),
      // docs/18 §3 — rapor türü, filtreler, satır sayısı.
      metadata: {
        'report': report.name,
        'from': period.fromUtc.toIso8601String(),
        'to': period.toUtc.toIso8601String(),
        // Başlık satırı sayılmaz.
        'row_count': rows.valueOrNull!.length - 1,
      },
    );

    return Ok(csv);
  }

  /// docs/16 R2 — ürün satış raporu.
  Future<Result<List<List<Object?>>>> _productRows(ReportPeriod period) async {
    final result = await _dashboard.productBreakdown(period);
    if (result.isErr) return Err(result.failureOrNull!);

    return Ok([
      const ['Ürün', 'Adet', 'Ciro (KDV dahil)', 'Kâr (KDV hariç)'],
      for (final product in result.valueOrNull!)
        [
          product.name,
          product.unitCount,
          MoneyFormatter.format(Money(product.revenueMinor)),
          MoneyFormatter.format(Money(product.profitMinor)),
        ],
    ]);
  }

  /// docs/16 R6 — kategori raporu.
  Future<Result<List<List<Object?>>>> _categoryRows(ReportPeriod period) async {
    final result = await _dashboard.categoryBreakdown(period);
    if (result.isErr) return Err(result.failureOrNull!);

    return Ok([
      const ['Kategori', 'Adet', 'Ciro (KDV dahil)'],
      for (final category in result.valueOrNull!)
        [
          category.name,
          category.unitCount,
          MoneyFormatter.format(Money(category.revenueMinor)),
        ],
    ]);
  }

  /// docs/16 §2 — özet şeridi.
  Future<Result<ReportSummary>> summary(ReportPeriod period) =>
      _dashboard.summary(period);
}

/// Kilit kapalıyken dönen hata.
///
/// `FinancialAccessService`'in kendi hatalarıyla aynı anlamı taşır; ayrı
/// tanımlanmasının sebebi dışa aktarmanın **audit yazmadan** durmasıdır.
abstract final class FinancialAccessFailuresRef {
  static const Failure locked = Failure(
    code: 'report_export_locked',
    userMessage: 'Rapor dışa aktarmak için finansal erişim parolası gerekiyor.',
  );
}
