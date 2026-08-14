/// Veri kaybettiren migration koruması — **REQ-MIG-007**.
///
/// docs/06 §2 kural 2:
///   "Veri kaybettiren işlem yasaktır (kolon silme, tablo silme) — bunun yerine
///    kolon kullanımdan kaldırılır (deprecated)."
///
/// Bu dosya iki şey yapar:
///
/// 1. `dropTable` / `dropColumn` gibi yardımcılar **sunulmaz** — kolay yol yok.
/// 2. [MigrationStep.sql] ile verilen her ifade [assertNonDestructive]
///    süzgecinden geçer; yıkıcı bir ifade **build/çalışma anında reddedilir.**
///
/// Koruma niyet düzeyindedir: kararlı bir geliştirici Drift API'siyle yıkıcı bir
/// işlem yine yazabilir. Amaç, bunun **kazara** veya "pratik olsun diye"
/// yapılmasını engellemektir.
library;

/// Yıkıcı bir SQL ifadesi migration'a girmeye çalıştığında fırlatılır.
class DestructiveMigrationError extends StateError {
  DestructiveMigrationError(super.message);
}

/// Reddedilen işlem kalıpları.
final List<({RegExp pattern, String label})> _destructivePatterns = [
  (
    pattern: RegExp(r'\bDROP\s+TABLE\b', caseSensitive: false),
    label: 'DROP TABLE',
  ),
  (
    pattern: RegExp(r'\bDROP\s+COLUMN\b', caseSensitive: false),
    label: 'DROP COLUMN',
  ),
  (pattern: RegExp(r'\bTRUNCATE\b', caseSensitive: false), label: 'TRUNCATE'),
  (
    pattern: RegExp(r'\bDELETE\s+FROM\b', caseSensitive: false),
    label: 'DELETE FROM',
  ),
];

/// SQL yorumlarını çıkarır — yorum içindeki `DROP TABLE` yanlış alarm üretmesin.
String _stripComments(String sql) {
  return sql
      .replaceAll(RegExp(r'--[^\n]*'), ' ')
      .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), ' ');
}

/// [sql] veri kaybettiren bir işlem içeriyorsa [DestructiveMigrationError] fırlatır.
void assertNonDestructive(String sql) {
  final normalized = _stripComments(sql);
  for (final entry in _destructivePatterns) {
    if (entry.pattern.hasMatch(normalized)) {
      throw DestructiveMigrationError(
        'REQ-MIG-007 ihlali: migration adımı veri kaybettiren bir işlem '
        'içeriyor (${entry.label}). Kolon/tablo silinmez; kullanımdan '
        'kaldırılır (deprecated). Bkz. docs/06 §2.',
      );
    }
  }
}
