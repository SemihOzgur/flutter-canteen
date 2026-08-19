/// Denetim kaydının **tek yazım noktası** — docs/18 §7 · REQ-AUDIT-001…007
///
/// ## Neden merkezî
///
/// Faz 3 ve 5'te her servis kendi `_writeAudit`'ini taşıyordu; desen birebir
/// aynıydı ve `ProductService` bunun Faz 6'da devredileceğini zaten not
/// etmişti. Kopyalanan bir desende iki şey sessizce bozulur: **yazım hatası
/// ana işlemi düşürebilir** (REQ-AUDIT-007) ve **bir sır sızabilir**
/// (REQ-AUDIT-004). İkisi de tek yerde kesin olarak çözülür.
///
/// ## İki garanti
///
/// **1 — REQ-AUDIT-007: audit yazımı ana işlemi ASLA düşürmez.**
/// docs/18 §7: *"denetim uğruna satış kaybetme"* kabul edilemez. Bu sınıftan
/// dışarı exception sızmaz; hata log dosyasına yazılır.
///
/// **2 — REQ-AUDIT-004: sır yazılamaz.**
/// `rules/04 §8` parola, hash, salt ve recovery code'un audit'e yazılmasını
/// yasaklar. Bu bir *hatırlama* kuralı olamaz: ileride biri `newValue`'ya
/// `{'password_hash': ...}` koyduğunda hiçbir şey uyarmazdı. [_forbiddenKey]
/// böyle bir alanı **düşürür** ve olayı log'a yazar — kayıt yine oluşur,
/// çünkü audit izini korumak sırrı yazmaktan daha önemli değildir ama izi
/// tamamen kaybetmek de doğru değildir.
///
/// ## Transaction
///
/// docs/18 §7: audit kaydı **kaydettiği işlemle aynı transaction** içinde
/// yazılır. Bu sınıf transaction **açmaz**; çağıran servis kendi
/// transaction'ının içinden çağırır (rules/01 §5). İstisna, docs/18 §7'nin
/// saydığı tek başına duran olaylardır (`userLoggedIn`, `backupCreated`).
library;

import 'dart:convert';

import '../../core/logging/app_logger.dart';
import '../../data/dao/daos.dart';
import 'audit_actions.dart';

class AuditService {
  final AuditLogsDao _auditLogs;
  final AppLogger? _logger;
  final DateTime Function() _clock;

  AuditService({
    required AuditLogsDao auditLogs,
    required DateTime Function() clock,
    AppLogger? logger,
  }) : _auditLogs = auditLogs,
       _logger = logger,
       _clock = clock;

  /// `rules/04 §8` — bu anahtarlar denetim kaydına **yazılamaz.**
  ///
  /// Eşleşme parça bazlıdır: `password_hash`, `dashboardSalt`,
  /// `recovery_code` gibi türevler de yakalanır.
  static const List<String> forbiddenKeyParts = [
    'password',
    'parola',
    'hash',
    'salt',
    'recovery',
    'secret',
    'token',
  ];

  static bool _forbiddenKey(String key) {
    final lower = key.toLowerCase();
    return forbiddenKeyParts.any(lower.contains);
  }

  /// Denetim kaydı yazar. **Hiçbir koşulda exception fırlatmaz**
  /// (REQ-AUDIT-007).
  ///
  /// [action] docs/18 §3'te tanımlı olmalıdır; tanımsız bir ad **yazılmaz**
  /// ve log'a düşer. Uydurma action denetim izini sessizce çatallaştırır
  /// (rules/00 §6 — dokümanda olmayan action üretilmez).
  Future<void> record({
    required String action,
    required String entityType,
    int? entityId,
    int? userId,
    Map<String, Object?>? oldValue,
    Map<String, Object?>? newValue,
    Map<String, Object?>? metadata,
    DateTime? at,
  }) async {
    try {
      if (!AuditActions.all.contains(action)) {
        _logger?.error(
          'Tanımsız denetim işlemi yazılmaya çalışıldı: $action. '
          'docs/18 §3 ve AuditActions güncellenmeden kayıt yazılmaz.',
        );
        return;
      }

      await _auditLogs.record(
        createdAt: (at ?? _clock()).toUtc(),
        action: action,
        entityType: entityType,
        userId: userId,
        entityId: entityId,
        oldValue: _encode(oldValue, action, 'old_value'),
        newValue: _encode(newValue, action, 'new_value'),
        metadata: _encode(metadata, action, 'metadata'),
      );
    } on Object catch (error, stackTrace) {
      // REQ-AUDIT-007 — ana işlem devam eder.
      _logger?.error(
        'Denetim kaydı yazılamadı ($action).',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  /// REQ-AUDIT-004 — yasak anahtarları **düşürerek** JSON'a çevirir.
  String? _encode(Map<String, Object?>? value, String action, String field) {
    if (value == null) return null;

    final safe = <String, Object?>{};
    final dropped = <String>[];
    for (final entry in value.entries) {
      if (_forbiddenKey(entry.key)) {
        dropped.add(entry.key);
      } else {
        safe[entry.key] = entry.value;
      }
    }

    if (dropped.isNotEmpty) {
      // ⚠️ Düşürülen **değer** loglanmaz — yalnızca anahtar adı. Değeri
      // loglamak yasağı log dosyasına taşımak olurdu (rules/04 §8).
      _logger?.error(
        'BR-SEC-001 ihlali engellendi: $action/$field içindeki '
        '${dropped.join(", ")} alanları denetim kaydına yazılmadı.',
      );
    }

    if (safe.isEmpty) return null;
    return jsonEncode(safe);
  }
}
