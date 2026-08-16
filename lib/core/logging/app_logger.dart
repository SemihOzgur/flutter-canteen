/// Dosya tabanlı loglama.
///
/// REQ-SEC-007: Teknik hata detayları kullanıcıya gösterilmez, log dosyasına yazılır.
///
/// ```text
/// <veri dizini>/logs/app-YYYY-MM-DD.log     — 14 gün rotasyon
/// ```
///
/// ## Loglanması YASAK olanlar (BR-SEC-001 · rules/04 §8)
///
/// Hiçbir koşulda log dosyasına yazılmaz:
/// parola (düz metin veya hash) · salt · recovery code · tam veritabanı satırları ·
/// kişisel veri.
///
/// Bu sınıfın API'si bilinçli olarak dardır: yalnızca `String` mesaj ve hata nesnesi
/// kabul eder; rastgele nesne serileştirmesi yapmaz.
///
/// Bkz. docs/24-non-functional-requirements.md §7
library;

import 'dart:io';

import 'package:path/path.dart' as p;

enum LogLevel { info, warn, error }

class AppLogger {
  final String logsDirPath;
  final int retentionDays;
  final DateTime Function() _clock;

  AppLogger({
    required this.logsDirPath,
    this.retentionDays = 14,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Log dizinini hazırlar ve eski dosyaları temizler.
  Future<void> init() async {
    await Directory(logsDirPath).create(recursive: true);
    await _purgeExpired();
  }

  void info(String message) => _write(LogLevel.info, message);

  void warn(String message) => _write(LogLevel.warn, message);

  void error(String message, {Object? error, StackTrace? stackTrace}) =>
      _write(LogLevel.error, message, error: error, stackTrace: stackTrace);

  void _write(
    LogLevel level,
    String message, {
    Object? error,
    StackTrace? stackTrace,
  }) {
    final now = _clock();
    final buffer = StringBuffer()
      ..write(now.toIso8601String())
      ..write(' [')
      ..write(level.name.toUpperCase())
      ..write('] ')
      ..write(message);

    if (error != null) buffer.write('\n  error: $error');
    if (stackTrace != null) buffer.write('\n  stack: $stackTrace');
    buffer.writeln();

    try {
      File(currentLogFilePath(now)).writeAsStringSync(
        buffer.toString(),
        mode: FileMode.append,
        flush: false,
      );
    } on FileSystemException {
      // Loglama hiçbir koşulda ana işlemi başarısız kılmaz.
      // (rules/03 §9 kural 2 ile aynı ilke.)
    }
  }

  /// `app-YYYY-MM-DD.log`
  String currentLogFilePath([DateTime? at]) {
    final now = at ?? _clock();
    return p.join(logsDirPath, 'app-${_dateStamp(now)}.log');
  }

  static String _dateStamp(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _purgeExpired() async {
    final dir = Directory(logsDirPath);
    if (!dir.existsSync()) return;

    final threshold = _clock().subtract(Duration(days: retentionDays));

    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      final date = _dateFromFileName(name);
      if (date != null && date.isBefore(threshold)) {
        try {
          await entity.delete();
        } on FileSystemException {
          // Silinemeyen dosya loglamayı engellemez.
        }
      }
    }
  }

  static DateTime? _dateFromFileName(String name) {
    if (!name.startsWith('app-') || !name.endsWith('.log')) return null;
    final stamp = name.substring(4, name.length - 4);
    return DateTime.tryParse(stamp);
  }
}
