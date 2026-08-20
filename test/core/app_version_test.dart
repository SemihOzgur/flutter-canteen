/// Sürüm tek kaynağı — **docs/19 §2 · docs/24 §7**
///
/// ## Kapsanan requirement'lar (Faz 11 izlenebilirliği)
///
/// - **REQ-BKUP-003** — yedek metadata'sı uygulama sürümünü taşır
library;

import 'dart:io';

import 'package:canteen/core/version/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appVersion, pubspec.yaml ile AYNIDIR', () {
    // İkisi ayrı ayrı elle güncellenirse, yedeğin hangi sürümle alındığı
    // yanlış kaydedilir ve restore uyumluluğu bu bilgiye dayanır.
    final pubspec = File('pubspec.yaml').readAsLinesSync();
    final line = pubspec.firstWhere((l) => l.startsWith('version:'));
    final value = line.split(':')[1].trim();

    expect(
      value,
      '$appVersion+$appBuildNumber',
      reason:
          'pubspec.yaml `version: $value` diyor ama app_version.dart '
          '`$appVersion+$appBuildNumber` diyor. İkisi birlikte güncellenir.',
    );
  });

  test('sürüm etiketi kullanıcıya gösterilebilir bir metindir', () {
    expect(appVersionLabel, contains(appVersion));
    expect(appVersionLabel, startsWith('Sürüm'));
  });

  test('sürüm semantik biçimdedir', () {
    expect(appVersion, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    expect(appBuildNumber, matches(RegExp(r'^\d+$')));
  });
}
