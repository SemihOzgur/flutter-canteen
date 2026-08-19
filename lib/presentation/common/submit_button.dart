/// Form gönderme butonu — **rules/05 §5 · REQ-UX-013**
///
/// > "Yükleme göstergesi 300 ms'den kısa işlemler için gösterilmez
/// > (titreşim etkisi)."
///
/// Bu davranış her formda tekrarlanacağı için tek yerde yaşar: buton kendi
/// meşguliyetini bilir, göstergeyi **yalnızca** işlem eşiği aştığında açar ve
/// meşgulken ikinci basışı yutar (çift gönderim koruması).
///
/// ## rules/01 §3 — karar testi
///
/// 1. **Bugün en az iki somut kullanımı var mı?** Evet: kurulum sihirbazının üç
///    adımı ve giriş ekranı.
/// 2. Aksi hâlde aynı zamanlayıcı mantığı dört ekranda kopyalanır ve biri
///    kaçınılmaz olarak eşiği unutur.
///
/// Burada iş kuralı, veritabanı erişimi veya hesaplama **yoktur** (rules/05 §8);
/// yalnızca gönderim eylemi çağrılır.
library;

import 'dart:async';

import 'package:flutter/material.dart';

class SubmitButton extends StatefulWidget {
  /// rules/05 §5 — bu süreden kısa işlemler gösterge göstermez.
  static const Duration progressDelay = Duration(milliseconds: 300);

  final String label;

  /// `null` verilirse buton **pasiftir.**
  ///
  /// Kurulum sihirbazının Adım 3'ü bunu kullanır: "Kodu kaydettim" onayı
  /// verilmeden ilerlenemez (REQ-AUTH-024 · EC-REC-006).
  final Future<void> Function()? onPressed;

  const SubmitButton({required this.label, required this.onPressed, super.key});

  @override
  State<SubmitButton> createState() => _SubmitButtonState();
}

class _SubmitButtonState extends State<SubmitButton> {
  bool _busy = false;
  bool _showProgress = false;
  Timer? _progressTimer;

  @override
  void dispose() {
    _progressTimer?.cancel();
    super.dispose();
  }

  Future<void> _run() async {
    final action = widget.onPressed;
    // Çift gönderim (butona üst üste basma) tek çalıştırma üretir.
    if (action == null || _busy) return;

    setState(() => _busy = true);
    _progressTimer = Timer(SubmitButton.progressDelay, () {
      if (mounted && _busy) setState(() => _showProgress = true);
    });

    try {
      await action();
    } finally {
      _progressTimer?.cancel();
      // Başarılı gönderim ekranı değiştirmiş olabilir.
      if (mounted) {
        setState(() {
          _busy = false;
          _showProgress = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !_busy;

    return FilledButton(
      onPressed: enabled ? _run : null,
      child: _showProgress
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(widget.label),
              ],
            )
          : Text(widget.label),
    );
  }
}
