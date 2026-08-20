/// Installer betiği denetimi — **docs/24 §5 · BR-DATA-001 · RSK-002**
///
/// Betik Windows'ta derlenir; burada **çalıştırılamaz.** Ama içeriği
/// okunabilir ve asıl tehlike bir derleme hatası değil, betiğe sessizce
/// eklenen bir satırdır:
///
/// > *"Kullanıcı verisi ASLA kurulum dizinine yazılmaz"* (BR-DATA-001) ve
/// > installer `%APPDATA%\CanteenApp\`'a **dokunmaz** (docs/24 §5).
///
/// Bu iki kural [RSK-002](../../docs/29-risks.md)'nin — *güncellemede veri
/// kaybı* — tek savunmasıdır. Bir `[UninstallDelete]` satırı yanlışlıkla
/// `{userappdata}` gösterirse, uygulamayı kaldıran kullanıcı **tüm satış
/// geçmişini** kaybeder ve bunu fark etmesi aylar sürer.
///
/// ## Kapsanan requirement'lar (Faz 11 izlenebilirliği)
///
/// - **REQ-COMP-001** — Windows 10 (1809+) / 11, x64 — *betikteki kısıt*
/// - **REQ-COMP-004** — güncelleme kullanıcı verisini korur — *betikteki niyet*
/// - **REQ-DATA-008** — kullanıcı verisi kurulum dizininde tutulmaz
///
/// ⚠️ Bu test betiğin **ne söylediğini** doğrular, kurulumun gerçekten
/// çalıştığını değil. Uçtan uca kanıt `docs/32` W5 (güncelleme veri
/// kaybetmiyor) ve W6 (veri `%APPDATA%`'da) ile, gerçek bir Windows
/// makinesinde alınır.
library;

import 'dart:io';

import 'package:canteen/core/version/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

String get script => File('installer/canteen.iss').readAsStringSync();

void main() {
  test('installer betiği repoda vardır', () {
    expect(
      File('installer/canteen.iss').existsSync(),
      isTrue,
      reason: 'Faz 12 çıkış kriteri kurulabilir bir sürümdür.',
    );
    expect(script.length, greaterThan(500));
  });

  group('BR-DATA-001 · RSK-002 — kullanıcı verisine DOKUNULMAZ', () {
    test('betik hiçbir yerde kullanıcı veri dizinine YAZMAZ', () {
      // Inno Setup'ta kullanıcı veri dizinini gösteren sabitler.
      const userDataConstants = [
        '{userappdata}',
        '{localappdata}',
        '{commonappdata}',
        '{userdocs}',
        '%APPDATA%',
      ];

      for (final constant in userDataConstants) {
        // Yorum satırları hariç: betik bu sabitlerin NEDEN kullanılmadığını
        // açıkça anlatır ve o açıklamanın kalması istenir.
        final offending = script
            .split('\n')
            .where((line) => !line.trimLeft().startsWith(';'))
            .where((line) => line.contains(constant))
            .toList();

        expect(
          offending,
          isEmpty,
          reason:
              '`$constant` installer betiğinde kullanılıyor. Kullanıcı '
              'verisi %APPDATA%\\CanteenApp\\ altındadır ve installer oraya '
              'dokunamaz (BR-DATA-001) — aksi hâlde bir güncelleme veya '
              'kaldırma tüm satış geçmişini siler (RSK-002).\n$offending',
        );
      }
    });

    test('UninstallDelete YALNIZCA kurulum dizinini hedefler', () {
      final section = _section('UninstallDelete');
      final targets = section
          .where((line) => line.contains('Name:'))
          .map((line) => line.split('Name:').last.trim())
          .toList();

      expect(targets, isNotEmpty, reason: 'Bölüm ayrıştırılamadı.');
      for (final target in targets) {
        expect(
          target,
          startsWith('"{app}'),
          reason: 'Kaldırma yalnızca {app} altını silebilir; bulunan: $target',
        );
      }
    });

    test('Files bölümü yalnızca {app} altına yazar', () {
      final destinations = _section('Files')
          .where((line) => line.contains('DestDir:'))
          .map((line) => line.split('DestDir:')[1].split(';')[0].trim())
          .toList();

      expect(destinations, isNotEmpty);
      for (final destination in destinations) {
        expect(destination, startsWith('"{app}'));
      }
    });
  });

  group('REQ-COMP-001 — platform kısıtı', () {
    test('Windows 10 1809 altına kurulmaz', () {
      // 10.0.17763 = Windows 10 1809. Yarım çalışan bir kurulum,
      // çalışmayan bir kurulumdan daha kötüdür.
      expect(script, contains('MinVersion=10.0.17763'));
    });

    test('yalnızca x64', () {
      expect(script, contains('ArchitecturesAllowed=x64compatible'));
      expect(script, contains('ArchitecturesInstallIn64BitMode=x64compatible'));
    });

    test('arayüz Türkçedir — V1 tek dil', () {
      expect(script, contains('Turkish.isl'));
    });
  });

  group('REQ-COMP-004 — güncelleme', () {
    test('dosyalar ignoreversion ile ÜZERİNE yazılır', () {
      // Aksi hâlde eski DLL'ler kalır ve sürüm karışımı oluşur.
      final files = _section('Files');
      expect(files, isNotEmpty);
      for (final line in files.where((l) => l.contains('Source:'))) {
        expect(line, contains('ignoreversion'), reason: line);
      }
    });

    test('uygulama açıkken kurulum ENGELLENİR', () {
      // Windows dosya kilitleme Unix'ten katıdır (rules/05 §6): çalışan
      // sürümün .exe'si kilitli olur ve kurulum yarıda kalır.
      expect(script, contains('InitializeSetup'));
      expect(script, contains('FindWindowByWindowName'));
    });
  });

  test('installer sürümü app_version.dart ile AYNIDIR', () {
    expect(
      script,
      contains('#define AppVersion     "$appVersion"'),
      reason:
          'Kurulum paketinin adı ve "Programlar ve Özellikler" kaydı bu '
          'sürümü gösterir; uygulamanın raporladığından farklı olamaz.',
    );
  });

  test('pencere başlığı ile installer\'ın aradığı ad AYNIDIR', () {
    // InitializeSetup çalışan örneği pencere BAŞLIĞINDAN bulur; başlık
    // değişirse kontrol sessizce işe yaramaz hâle gelir.
    final title = File('windows/runner/main.cpp').readAsStringSync();
    expect(title, contains('window.Create(L"Kantin Otomasyonu"'));
    expect(script, contains('#define AppName        "Kantin Otomasyonu"'));
  });
}

/// `[Bölüm]` altındaki **mantıksal** satırları döner.
///
/// Inno Setup satır sonundaki `\` ile devam eder; ham satırlar tek tek
/// okunsaydı `ignoreversion` gibi bayraklar ayrı satırda kalır ve
/// denetimden kaçardı.
List<String> _section(String name) {
  final lines = script.split('\n');
  final start = lines.indexWhere((l) => l.trim() == '[$name]');
  if (start < 0) return const [];

  final result = <String>[];
  final buffer = StringBuffer();
  for (var i = start + 1; i < lines.length; i++) {
    final line = lines[i].trim();
    if (line.startsWith('[') && line.endsWith(']')) break;
    if (line.isEmpty || line.startsWith(';')) continue;

    if (line.endsWith(r'\')) {
      buffer.write('${line.substring(0, line.length - 1).trim()} ');
      continue;
    }
    buffer.write(line);
    result.add(buffer.toString());
    buffer.clear();
  }
  if (buffer.isNotEmpty) result.add(buffer.toString());
  return result;
}
