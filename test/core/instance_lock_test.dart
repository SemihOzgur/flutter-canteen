/// Single-instance kilidi testleri.
///
/// BR-GEN-005 / REQ-ARCH-005 / REQ-DATA-005
///
/// **Kapsam notu:** Gerçek çapraz-süreç dışlama, işletim sistemi kilidine
/// dayanır ve manuel test **W11** ile doğrulanır (docs/27 §8). Buradaki testler
/// kilit dosyasının yaşam döngüsünü deterministik olarak doğrular.
library;

import 'dart:convert';
import 'dart:io';

import 'package:canteen/core/single_instance/instance_lock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late String lockPath;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('canteen_lock_');
    lockPath = p.join(temp.path, 'app.lock');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('kilit alınır ve dosya oluşturulur', () {
    final lock = InstanceLock(lockFilePath: lockPath, pidProvider: () => 4242);

    expect(lock.tryAcquire(), InstanceLockResult.acquired);
    expect(lock.isHeld, isTrue);
    expect(File(lockPath).existsSync(), isTrue);

    lock.release();
  });

  test('kilit dosyasına PID yazılır (tanılama)', () {
    final lock = InstanceLock(lockFilePath: lockPath, pidProvider: () => 4242);
    lock.tryAcquire();

    expect(lock.readRecordedPid(), 4242);

    lock.release();
  });

  test('release sonrası kilit yeniden alınabilir', () {
    final first = InstanceLock(lockFilePath: lockPath, pidProvider: () => 1001);
    expect(first.tryAcquire(), InstanceLockResult.acquired);
    first.release();
    expect(first.isHeld, isFalse);

    final second = InstanceLock(
      lockFilePath: lockPath,
      pidProvider: () => 1002,
    );
    expect(second.tryAcquire(), InstanceLockResult.acquired);
    expect(second.readRecordedPid(), 1002);

    second.release();
  });

  test('stale kilit dosyası (ölü sürecin PID\'i) engel oluşturmaz', () {
    // Çökmüş bir önceki oturumdan kalan dosya — OS kilidi zaten serbest.
    File(lockPath).writeAsStringSync('999999');

    final lock = InstanceLock(lockFilePath: lockPath, pidProvider: () => 5150);

    expect(
      lock.tryAcquire(),
      InstanceLockResult.acquired,
      reason: 'Stale lock uygulamayı kalıcı olarak kilitlememeli',
    );
    expect(lock.readRecordedPid(), 5150, reason: 'Eski PID üzerine yazılmalı');

    lock.release();
  });

  test('bozuk içerikli kilit dosyası kurtarılır', () {
    File(lockPath).writeAsStringSync('bozuk-icerik-!!');

    final lock = InstanceLock(lockFilePath: lockPath, pidProvider: () => 7);
    expect(lock.tryAcquire(), InstanceLockResult.acquired);
    expect(lock.readRecordedPid(), 7);

    lock.release();
  });

  test('aynı örnekte tekrar tryAcquire güvenlidir', () {
    final lock = InstanceLock(lockFilePath: lockPath, pidProvider: () => 321);

    expect(lock.tryAcquire(), InstanceLockResult.acquired);
    expect(lock.tryAcquire(), InstanceLockResult.acquired);
    expect(lock.isHeld, isTrue);

    lock.release();
  });

  test('kilit dosyası dizini yoksa oluşturulur', () {
    final nested = p.join(temp.path, 'a', 'b', 'app.lock');
    final lock = InstanceLock(lockFilePath: nested, pidProvider: () => 11);

    expect(lock.tryAcquire(), InstanceLockResult.acquired);
    expect(File(nested).existsSync(), isTrue);

    lock.release();
  });

  test('release tutulmayan kilitte güvenlidir', () {
    final lock = InstanceLock(lockFilePath: lockPath);
    expect(() => lock.release(), returnsNormally);
  });

  test('kilit dosyası yoksa readRecordedPid null döner', () {
    final lock = InstanceLock(lockFilePath: lockPath);
    expect(lock.readRecordedPid(), isNull);
  });

  group('çapraz-süreç dışlama — REQ-ARCH-005 / BR-GEN-005', () {
    test('ikinci SÜREÇ kilidi alamaz', () async {
      // 1. süreç kilidi alır ve tutar
      final holder = await Process.start('dart', [
        'run',
        'test/support/lock_holder.dart',
        lockPath,
        'hold',
      ]);

      final holderOutput = holder.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter());
      final firstLine = await holderOutput.first;
      expect(firstLine.trim(), 'ACQUIRED', reason: '1. süreç kilidi almalıydı');

      // 2. süreç aynı kilidi almayı dener → reddedilmeli
      final second = await Process.run('dart', [
        'run',
        'test/support/lock_holder.dart',
        lockPath,
        'try',
      ]);
      expect(
        second.stdout.toString().trim(),
        'ALREADY_RUNNING',
        reason: 'İkinci süreç kilidi ALMAMALIYDI — BR-GEN-005 ihlali!',
      );

      // 1. süreç bırakınca kilit yeniden alınabilmeli
      await holder.stdin.close();
      await holder.exitCode;

      final third = await Process.run('dart', [
        'run',
        'test/support/lock_holder.dart',
        lockPath,
        'try',
      ]);
      expect(
        third.stdout.toString().trim(),
        'ACQUIRED',
        reason: 'Kilit bırakıldıktan sonra yeniden alınabilmeliydi',
      );
    }, timeout: const Timeout(Duration(minutes: 2)));
  });
}
