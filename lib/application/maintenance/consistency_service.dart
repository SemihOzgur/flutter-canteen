/// Veri tutarlılığı kontrolü — **docs/24 §3.3 · REQ-STOCK-012 · REQ-DATA-006/007
/// · REQ-DB-008**
///
/// ## Neden var
///
/// Şemada bilinçli olarak **denormalize** alanlar var (rules/03 §2):
/// `products.stock_quantity`, `sales.item_count`, `sale_items.returned_quantity`
/// … Bunlar kaynaklarıyla aynı transaction içinde güncellenir, ama bir hata
/// veya bozulma sonrası sapabilirler. Sapma **sessizdir**: stok yanlış
/// görünür, kimse fark etmez.
///
/// ## Otomatik düzeltme YOKTUR
///
/// rules/03 §2: *"Sapma bulunursa otomatik düzeltme yapılmaz — kullanıcı
/// onayıyla `adjustment` hareketi oluşturulur."* Sessizce düzeltmek sapmanın
/// **sebebini** gizler; kullanıcı stoğun neden yanlış olduğunu hiç öğrenemez.
/// Bu yüzden [run] yalnızca **okur**; düzeltme [repairStockQuantity] ile ve
/// yalnızca çağıran istediğinde yapılır.
///
/// ## Sorgular nerede
///
/// `rules/01 §1` application katmanında ham SQL'i yasaklar; denetim sorguları
/// `data/dao/consistency_dao.dart` içindedir. Aggregation SQL tarafındadır
/// (rules/01 §8) — 10.000 ürün ve 100.000 satış satırında da tek geçiştir.
/// Buradaki iş **karardır**: neyin sapma sayıldığı, neyin düzeltilebildiği ve
/// denetim kaydına ne yazıldığı.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../../core/result/result.dart';
import '../../data/dao/consistency_dao.dart';
import '../audit/audit_actions.dart';
import '../audit/audit_service.dart';
import '../stock/stock_service.dart';
import 'consistency_report.dart';

class ConsistencyService {
  final ConsistencyDao _dao;
  final StockService _stockService;
  final AuditService? _audit;

  /// Görsellerin bulunduğu dizin — `products.image_path` **görelidir**
  /// (rules/03 §8). `null` ise görsel kontrolü atlanır.
  final String? _imagesDirectory;

  final DateTime Function() _clock;

  ConsistencyService({
    required ConsistencyDao dao,
    required StockService stockService,
    required DateTime Function() clock,
    AuditService? audit,
    String? imagesDirectory,
  }) : _dao = dao,
       _stockService = stockService,
       _audit = audit,
       _imagesDirectory = imagesDirectory,
       _clock = clock;

  /// docs/24 §3.3'teki sekiz denetimi çalıştırır.
  ///
  /// [quick] `true` ise dosya sistemi ve `integrity_check` atlanır — yedek
  /// alma öncesi otomatik çalışan "hızlı sürüm" budur (docs/24 §3.3).
  Future<ConsistencyReport> run({bool quick = false}) async {
    final findings = <ConsistencyFinding>[];

    findings.addAll(await _checkStockQuantity());
    findings.addAll(await _checkSaleTotals());
    findings.addAll(await _checkSaleCounts());
    findings.addAll(await _checkReturnedQuantity());
    findings.addAll(await _checkForeignKeys());
    if (!quick) {
      findings.addAll(await _checkIntegrity());
      findings.addAll(await _checkImages());
    }

    final now = _clock().toUtc();
    final report = ConsistencyReport(
      findings: findings,
      runAtUtc: now,
      productsChecked: await _dao.countProducts(),
      salesChecked: await _dao.countSales(),
    );

    await _audit?.record(
      action: AuditActions.consistencyCheckRun,
      entityType: AuditEntities.system,
      at: now,
      // docs/18 §3 — bulunan sapma sayısı.
      metadata: {
        'finding_count': findings.length,
        'quick': quick,
        'products_checked': report.productsChecked,
        'sales_checked': report.salesChecked,
      },
    );

    return report;
  }

  /// REQ-DATA-007 · OD-026 — sapmayı **kullanıcı onayıyla** kapatır.
  ///
  /// [physicalQuantity] kullanıcının onayladığı gerçek miktardır; verilmezse
  /// **defterin** değeri kullanılır (BR-STOCK-001 — defter otoritedir).
  ///
  /// Sapma iki şeyden biri olabilir ve hangisi olduğunu yalnızca kullanıcı
  /// bilir: önbellek bozulmuştur ya da bir hareket yazılamamıştır. Servis
  /// kendi başına taraf seçmez — bu yüzden [run] bunu **asla** kendiliğinden
  /// çağırmaz (rules/03 §2).
  Future<Result<int>> repairStockQuantity({
    required ConsistencyFinding finding,
    required int userId,
    required String reason,
    int? physicalQuantity,
  }) async {
    if (!finding.isRepairable || finding.entityId == null) {
      return const Err(StockFailuresRef.notRepairable);
    }
    return _stockService.repairFromLedger(
      productId: finding.entityId!,
      physicalQuantity: physicalQuantity ?? int.parse(finding.expected),
      reason: reason,
      userId: userId,
    );
  }

  // --- Denetimler — sorgular DAO'da, KARAR burada -------------------------

  List<ConsistencyFinding> _map(List<DriftRow> rows, ConsistencyCheck check) =>
      [
        for (final row in rows)
          ConsistencyFinding(
            check: check,
            entityId: row.id,
            label: row.label,
            expected: row.expected,
            actual: row.actual,
          ),
      ];

  Future<List<ConsistencyFinding>> _checkStockQuantity() async =>
      _map(await _dao.stockQuantityDrift(), ConsistencyCheck.stockQuantity);

  Future<List<ConsistencyFinding>> _checkSaleTotals() async =>
      _map(await _dao.saleTotalDrift(), ConsistencyCheck.saleTotals);

  Future<List<ConsistencyFinding>> _checkSaleCounts() async =>
      _map(await _dao.saleCountDrift(), ConsistencyCheck.saleCounts);

  Future<List<ConsistencyFinding>> _checkReturnedQuantity() async => _map(
    await _dao.returnedQuantityDrift(),
    ConsistencyCheck.returnedQuantity,
  );

  Future<List<ConsistencyFinding>> _checkForeignKeys() async => [
    for (final violation in await _dao.foreignKeyViolations())
      ConsistencyFinding(
        check: ConsistencyCheck.foreignKeys,
        expected: 'referans bütünlüğü',
        actual: violation,
      ),
  ];

  Future<List<ConsistencyFinding>> _checkIntegrity() async {
    final result = await _dao.integrityCheck();
    if (result == 'ok') return const [];
    return [
      ConsistencyFinding(
        check: ConsistencyCheck.databaseIntegrity,
        expected: 'ok',
        actual: result,
      ),
    ];
  }

  /// `products.image_path` işaret ettiği dosya mevcut mu?
  ///
  /// Yol **görelidir** (rules/03 §8); mutlak yol veritabanına yazılmaz.
  Future<List<ConsistencyFinding>> _checkImages() async {
    final root = _imagesDirectory;
    if (root == null) return const [];

    final findings = <ConsistencyFinding>[];
    for (final product in await _dao.productsWithImages()) {
      final file = File(p.join(root, p.basename(product.imagePath)));
      if (!file.existsSync()) {
        findings.add(
          ConsistencyFinding(
            check: ConsistencyCheck.missingImage,
            entityId: product.id,
            label: product.name,
            expected: product.imagePath,
            actual: 'dosya yok',
          ),
        );
      }
    }
    return findings;
  }
}

/// [ConsistencyService.repairStockQuantity]'nin ürettiği tek özel hata.
///
/// `StockFailures` içine konmadı: bu bir **bakım** kısıtıdır, stok defterinin
/// bir kuralı değil.
abstract final class StockFailuresRef {
  static const Failure notRepairable = Failure(
    code: 'consistency_not_repairable',
    userMessage:
        'Bu sapma stok düzeltmesiyle kapatılamaz. Kaydı inceleyip elle '
        'düzeltmeniz gerekir.',
  );
}
