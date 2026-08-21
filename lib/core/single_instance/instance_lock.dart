/// Single-instance kilidi.
///
/// BR-GEN-005 / REQ-ARCH-005 / REQ-DATA-005:
///   Aynı veri dizini üzerinde aynı anda birden fazla uygulama örneği çalışamaz.
///
/// İki örnek aynı SQLite dosyasına yazarsa aktif sepet, satış numarası sayacı ve
/// bellek önbelleği bozulur ([RSK-003](docs/29-risks.md)).
///
/// ## Mekanizma
///
/// 1. Veri dizininde `app.lock` dosyası açılır.
/// 2. **İşletim sistemi düzeyinde exclusive lock** alınır — asıl koruma budur.
///    Süreç çökse bile işletim sistemi kilidi serbest bırakır; bu nedenle
///    "stale lock" kalıcı olarak takılı kalmaz.
/// 3. Tanılama amacıyla dosyaya PID yazılır.
///
/// Windows'ta dosya kilitleri Unix'ten katıdır; bu davranış manuel test
/// **W11** ile doğrulanır (docs/27 §8).
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Kilit alma sonucu.
enum InstanceLockResult {
  /// Kilit alındı; uygulama çalışabilir.
  acquired,

  /// Başka bir örnek çalışıyor.
  alreadyRunning,
}

class InstanceLock {
  final String lockFilePath;
  final int Function() _pidProvider;

  RandomAccessFile? _handle;

  InstanceLock({required this.lockFilePath, int Function()? pidProvider})
    : _pidProvider = pidProvider ?? (() => pid);

  /// Kilidin bu örnek tarafından tutulup tutulmadığı.
  bool get isHeld => _handle != null;

  /// Kilidi almayı dener.
  ///
  /// Başarılıysa dosyaya PID yazılır ve kilit, [release] çağrılana veya süreç
  /// sonlanana kadar tutulur.
  InstanceLockResult tryAcquire() {
    if (isHeld) return InstanceLockResult.acquired;

    Directory(p.dirname(lockFilePath)).createSync(recursive: true);

    final file = File(lockFilePath);
    final handle = file.openSync(mode: FileMode.write);

    try {
      handle.lockSync(FileLock.exclusive);
    } on FileSystemException {
      handle.closeSync();
      return InstanceLockResult.alreadyRunning;
    }

    try {
      // Önceki (stale) içerik üzerine yazılır — kilit bizde olduğu için güvenlidir.
      handle
        ..setPositionSync(0)
        ..truncateSync(0)
        ..writeStringSync('${_pidProvider()}')
        ..flushSync();
    } on FileSystemException {
      // PID yazılamaması kilidi geçersiz kılmaz; kilit yine bizdedir.
    }

    _handle = handle;
    return InstanceLockResult.acquired;
  }

  /// Kilidi bırakır. Süreç sonlandığında işletim sistemi de bırakır.
  void release() {
    final handle = _handle;
    if (handle == null) return;
    _handle = null;
    try {
      handle.unlockSync();
    } on FileSystemException {
      // Süreç sonlanıyorsa kilit zaten bırakılmış olabilir.
    }
    try {
      handle.closeSync();
    } on FileSystemException {
      // yok sayılır
    }
  }

  /// Kilit dosyasındaki PID — tanılama amaçlıdır.
  /// Dosya yoksa veya okunamıyorsa `null`.
  int? readRecordedPid() {
    final handle = _handle;
    if (handle != null) {
      try {
        handle.setPositionSync(0);
        return int.tryParse(
          utf8.decode(handle.readSync(handle.lengthSync())).trim(),
        );
      } on FileSystemException {
        return null;
      }
    }

    final file = File(lockFilePath);
    if (!file.existsSync()) return null;
    try {
      return int.tryParse(file.readAsStringSync().trim());
    } on FileSystemException {
      return null;
    }
  }
}
