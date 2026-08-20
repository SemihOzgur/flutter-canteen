/// Düşük çözünürlük uyarısı — **EC-SYS-008 · docs/23 §4**
///
/// > *"Ekran çözünürlüğü 1366×768'in altında → Uyarı gösterilir; uygulama
/// > açılır ama düzen bozulabilir."*
///
/// **Engelleyici değildir.** docs/23 §4 bu çözünürlüğü *"desteklenmez"*
/// sayar ama uygulamayı kapatmaz: kasadaki bir makine küçük ekranlıysa,
/// satışı durdurmak uyarı vermekten çok daha pahalıdır. Kullanıcı ne
/// olduğunu bilir ve çalışmaya devam eder.
///
/// Ölçüm **pencerenin** boyutudur, ekranın değil — kullanıcı pencereyi
/// küçültmüş de olabilir ve düzen aynı şekilde bozulur.
library;

import 'package:flutter/material.dart';

import '../../app/l10n/app_strings_tr.dart';

/// docs/23 §4 — tam işlevsellik için gereken en küçük çözünürlük.
const Size minimumSupportedSize = Size(1366, 768);

/// [child]'ı sarar; pencere [minimumSupportedSize]'ın altındaysa üstüne
/// kapatılabilir bir uyarı çubuğu ekler.
class LowResolutionNotice extends StatefulWidget {
  final Widget child;

  const LowResolutionNotice({required this.child, super.key});

  @override
  State<LowResolutionNotice> createState() => _LowResolutionNoticeState();
}

class _LowResolutionNoticeState extends State<LowResolutionNotice> {
  /// Kullanıcı uyarıyı kapattıysa bir daha gösterilmez — pencereyi her
  /// yeniden boyutlandırışında geri gelen bir çubuk, uyarıyı bilgi olmaktan
  /// çıkarıp engele dönüştürürdü (rules/05 §5).
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final tooSmall =
        size.width < minimumSupportedSize.width ||
        size.height < minimumSupportedSize.height;

    if (!tooSmall || _dismissed) return widget.child;

    final theme = Theme.of(context);
    return Column(
      children: [
        Material(
          color: theme.colorScheme.tertiaryContainer,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
              child: Row(
                children: [
                  // rules/05 §5 — renkle iletilen her durum ikon/metinle de
                  // ifade edilir.
                  Icon(
                    Icons.warning_amber_outlined,
                    size: 20,
                    color: theme.colorScheme.onTertiaryContainer,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppStringsTr.lowResolutionWarning(
                        size.width.round(),
                        size.height.round(),
                      ),
                      key: const Key('low_resolution_warning'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                  // Tooltip KULLANILMAZ: bu çubuk `MaterialApp.builder`
                  // içinde, yani Navigator/Overlay'in ÜSTÜNDE yaşar ve
                  // Tooltip bir Overlay atası ister — üzerine gelindiğinde
                  // uygulama çökerdi. Görünür metin ayrıca erişilebilirlik
                  // açısından da daha iyidir (rules/05 §7).
                  TextButton(
                    key: const Key('low_resolution_dismiss'),
                    style: TextButton.styleFrom(
                      foregroundColor: theme.colorScheme.onTertiaryContainer,
                    ),
                    onPressed: () => setState(() => _dismissed = true),
                    child: const Text(AppStringsTr.lowResolutionDismiss),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
