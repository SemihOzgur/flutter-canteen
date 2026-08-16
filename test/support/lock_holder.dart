/// Çapraz-süreç kilit testi için yardımcı süreç.
///
/// `instance_lock_test.dart` bu dosyayı ayrı bir süreç olarak başlatır ve
/// REQ-ARCH-005'in **gerçekten çapraz-süreç** çalıştığını doğrular.
///
/// Kullanım:
/// ```
/// dart run test/support/lock_holder.dart <lockPath> [hold|try]
/// ```
/// - `hold` : kilidi alır ve stdin kapanana kadar tutar
/// - `try`  : kilidi almayı dener ve sonucu yazıp çıkar
library;

import 'dart:io';

import 'package:canteen/core/single_instance/instance_lock.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Kullanım: lock_holder.dart <lockPath> [hold|try]');
    exitCode = 2;
    return;
  }

  final lockPath = args[0];
  final mode = args.length > 1 ? args[1] : 'try';

  final lock = InstanceLock(lockFilePath: lockPath);
  final result = lock.tryAcquire();

  stdout.writeln(
    result == InstanceLockResult.acquired ? 'ACQUIRED' : 'ALREADY_RUNNING',
  );
  await stdout.flush();

  if (mode == 'hold' && result == InstanceLockResult.acquired) {
    // Kilidi, üst süreç stdin'i kapatana kadar tut.
    await stdin.drain<void>();
  }

  lock.release();
}
