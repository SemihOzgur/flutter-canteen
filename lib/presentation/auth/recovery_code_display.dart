/// Kurtarma kodunun **tek seferlik gösterimi** — docs/17 §4, §8 ·
/// REQ-AUTH-022/023/024 · BR-AUTH-017 · EC-REC-006/009
///
/// ```text
/// ┌────────────────────────────────────────────┐
/// │      A7K2 - M9QX - 4RTB - 8ZWD             │
/// │  ⚠ Bu kod bir daha GÖSTERİLMEYECEK.        │
/// │  [Kopyala]  [Dosyaya Kaydet]               │
/// │  ☐ Kodu kaydettim                          │
/// └────────────────────────────────────────────┘
/// ```
///
/// ## Neden ortak widget (rules/01 §3 karar testi)
///
/// 1. **Bugün en az iki somut kullanımı var mı?** Evet, üç: kurulum sihirbazı
///    Adım 3 (REQ-AUTH-022), kurtarma akışının son adımı (BR-AUTH-017 ·
///    EC-REC-006) ve Ayarlar'dan kod yenileme (REQ-AUTH-028 · EC-REC-009).
/// 2. Aksi hâlde "kopyala / dosyaya kaydet / kaydettim onayı" üçlüsü üç ekranda
///    kopyalanır ve biri kaçınılmaz olarak onayı veya uyarıyı atlar.
///
/// ## Düz metin kod
///
/// REQ-AUTH-023 · BR-SEC-001: kod **yalnızca** çağıranın ekran durumunda ve bu
/// widget'ın parametresinde yaşar. Log'a, ayara veya audit kaydına yazılmaz;
/// yalnızca kullanıcının seçtiği dosyaya (REQ-AUTH-022) yazılabilir.
///
/// ## Onay kutusu kimin sorumluluğunda
///
/// Onay durumu **çağıranda** tutulur: ilerleme butonu (Devam / Tamam) çağıranın
/// ekranına aittir ve onay verilmeden **pasif** olmalıdır (REQ-AUTH-024 ·
/// EC-REC-006). Bu widget yalnızca kutuyu gösterir ve değişikliği bildirir.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../application/auth/providers.dart';
import '../../data/files/text_file_writer.dart';
import '../common/form_message.dart';
import '../common/save_location_picker.dart';

class RecoveryCodeDisplay extends ConsumerWidget {
  /// Gösterilecek düz metin kod (`XXXX-XXXX-XXXX-XXXX`).
  final String code;

  /// "Kodu kaydettim" onayı — çağıranın durumundan gelir.
  final bool savedConfirmed;
  final ValueChanged<bool> onSavedChanged;

  /// REQ-AUTH-022 — ikisi de testte enjekte edilir; gerçek dialog açılmaz.
  final SaveLocationPicker savePicker;
  final TextFileWriter fileWriter;

  /// Çağıranın kendi test anahtarlarını verebilmesi için.
  final Key codeKey;
  final Key copyButtonKey;
  final Key saveButtonKey;
  final Key savedCheckboxKey;

  const RecoveryCodeDisplay({
    required this.code,
    required this.savedConfirmed,
    required this.onSavedChanged,
    required this.savePicker,
    required this.fileWriter,
    required this.codeKey,
    required this.copyButtonKey,
    required this.saveButtonKey,
    required this.savedCheckboxKey,
    super.key,
  });

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(AppStringsTr.setupRecoveryCodeCopied)),
    );
  }

  /// REQ-AUTH-022 — kodu kullanıcının seçtiği bir dosyaya yazar.
  ///
  /// Yazma işini data katmanı yapar; presentation dosya sistemine dokunmaz
  /// (rules/01 §1).
  ///
  /// Bu işlem **"Kodu kaydettim" onayının yerine geçmez** (REQ-AUTH-024):
  /// dosyaya yazmak kullanıcının kodu sakladığını kanıtlamaz.
  Future<void> _saveToFile(BuildContext context, WidgetRef ref) async {
    final path = await savePicker(AppStringsTr.setupRecoveryCodeSaveFileName);
    // Kullanıcı vazgeçti — sessizce dönülür, hata gösterilmez.
    if (path == null) return;

    String message;
    try {
      await fileWriter(path, AppStringsTr.recoveryCodeFileContents(code));
      message = AppStringsTr.setupRecoveryCodeSaved;
    } on Object catch (error) {
      // rules/04 §7: dosya yolu ve teknik hata kullanıcıya sızdırılmaz.
      // Kod da loglanmaz (rules/04 §8) — yalnızca hatanın kendisi.
      ref
          .read(appLoggerProvider)
          ?.error('Kurtarma kodu dosyaya yazılamadı', error: error);
      message = AppStringsTr.setupRecoveryCodeSaveFailed;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            code,
            key: codeKey,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ),
        const SizedBox(height: 16),
        // rules/05 §5: uyarı renkle değil, ikon + metinle de anlatılır.
        const FormMessage(
          AppStringsTr.setupRecoveryCodeWarning,
          kind: FormMessageKind.warning,
        ),
        const SizedBox(height: 16),
        // REQ-AUTH-022: kopyalama VE dosyaya kaydetme seçenekleri sunulur.
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: copyButtonKey,
              onPressed: () => _copy(context),
              icon: const Icon(Icons.copy_outlined),
              label: const Text(AppStringsTr.setupRecoveryCodeCopy),
            ),
            OutlinedButton.icon(
              key: saveButtonKey,
              onPressed: () => _saveToFile(context, ref),
              icon: const Icon(Icons.save_outlined),
              label: const Text(AppStringsTr.setupRecoveryCodeSaveToFile),
            ),
          ],
        ),
        const SizedBox(height: 8),
        CheckboxListTile(
          key: savedCheckboxKey,
          value: savedConfirmed,
          onChanged: (value) => onSavedChanged(value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: EdgeInsets.zero,
          title: const Text(AppStringsTr.setupRecoveryCodeSavedConfirm),
        ),
      ],
    );
  }
}
