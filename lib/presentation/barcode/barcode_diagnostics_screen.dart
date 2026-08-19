/// Barkod tanılama ekranı — **REQ-BARC-010 · docs/11**
///
/// "Scanner çalışmıyor" şikâyeti sahada en sık karşılaşılan sorundur ve
/// nedeni genelde uygulamada değildir: yanlış klavye düzeni (RSK-006), eksik
/// `Enter` sonlandırıcısı veya çok yavaş bir cihaz. Bu ekran **ham girdiyi**
/// gösterir ki sorun tahmin edilmek yerine görülebilsin.
///
/// Gösterilenler: okunan barkod, ham tampon, zehirli durum (OD-021),
/// checksum sonucu ve okuma geçmişi.
///
/// ## Kilit dışındadır
///
/// Finansal veri içermez (rules/04 §4 — kilit yalnızca Dashboard ve Raporlar).
library;

import 'package:flutter/material.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../domain/services/barcode_input_handler.dart';
import '../../domain/services/barcode_rules.dart';
import 'barcode_listener.dart';

class BarcodeDiagnosticsScreen extends StatefulWidget {
  static const Key bufferKey = Key('barcode_diag_buffer');
  static const Key lastScanKey = Key('barcode_diag_last_scan');
  static const Key poisonedKey = Key('barcode_diag_poisoned');
  static const Key clearKey = Key('barcode_diag_clear');

  const BarcodeDiagnosticsScreen({super.key});

  @override
  State<BarcodeDiagnosticsScreen> createState() =>
      _BarcodeDiagnosticsScreenState();
}

class _BarcodeDiagnosticsScreenState extends State<BarcodeDiagnosticsScreen> {
  final BarcodeInputHandler _handler = BarcodeInputHandler();
  final List<_ScanRecord> _history = [];

  void _onScan(String raw) {
    setState(() {
      _history.insert(0, _ScanRecord(raw: raw, at: DateTime.now()));
      // Bellek sınırı: tanılama ekranı gün boyu açık kalabilir.
      if (_history.length > 50) _history.removeLast();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final last = _history.isEmpty ? null : _history.first;

    return BarcodeListener(
      onScan: _onScan,
      onInputChanged: () => setState(() {}),
      child: Scaffold(
        appBar: AppBar(title: const Text(AppStringsTr.barcodeDiagnosticsTitle)),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(AppStringsTr.barcodeDiagnosticsDescription),
            const SizedBox(height: 24),

            _Field(
              label: AppStringsTr.barcodeDiagnosticsLastScan,
              value: last?.raw ?? AppStringsTr.barcodeDiagnosticsNoScanYet,
              valueKey: BarcodeDiagnosticsScreen.lastScanKey,
              monospace: true,
            ),
            if (last != null) ...[
              const SizedBox(height: 8),
              _Field(
                label: AppStringsTr.barcodeDiagnosticsLength,
                value: '${last.raw.length}',
              ),
              const SizedBox(height: 8),
              _Field(
                label: AppStringsTr.barcodeDiagnosticsChecksum,
                value: _checksumLabel(last.raw),
              ),
            ],

            const Divider(height: 40),

            _Field(
              label: AppStringsTr.barcodeDiagnosticsBuffer,
              value: _handler.buffer.isEmpty
                  ? AppStringsTr.barcodeDiagnosticsBufferEmpty
                  : _handler.buffer,
              valueKey: BarcodeDiagnosticsScreen.bufferKey,
              monospace: true,
            ),
            const SizedBox(height: 8),
            _Field(
              label: AppStringsTr.barcodeDiagnosticsPoisoned,
              value: _handler.isPoisoned
                  ? AppStringsTr.barcodeDiagnosticsPoisonedYes
                  : AppStringsTr.barcodeDiagnosticsPoisonedNo,
              valueKey: BarcodeDiagnosticsScreen.poisonedKey,
            ),

            const SizedBox(height: 24),
            Text(
              AppStringsTr.barcodeDiagnosticsThresholds(
                BarcodeInputHandler.maxInterCharacterGap.inMilliseconds,
                BarcodeInputHandler.bufferTimeout.inMilliseconds,
                BarcodeInputHandler.minLength,
                BarcodeInputHandler.maxLength,
              ),
              style: theme.textTheme.bodySmall,
            ),

            const Divider(height: 40),
            Row(
              children: [
                Text(
                  AppStringsTr.barcodeDiagnosticsHistory,
                  style: theme.textTheme.titleMedium,
                ),
                const Spacer(),
                TextButton.icon(
                  key: BarcodeDiagnosticsScreen.clearKey,
                  onPressed: _history.isEmpty
                      ? null
                      : () => setState(_history.clear),
                  icon: const Icon(Icons.clear_all),
                  label: const Text(AppStringsTr.barcodeDiagnosticsClear),
                ),
              ],
            ),
            if (_history.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(AppStringsTr.barcodeDiagnosticsNoScanYet),
              )
            else
              for (final record in _history)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.qr_code_2),
                  title: Text(
                    record.raw,
                    style: const TextStyle(fontFamily: 'monospace'),
                  ),
                  subtitle: Text(_time(record.at)),
                ),
          ],
        ),
      ),
    );
  }

  String _checksumLabel(String barcode) {
    final valid = BarcodeRules.isChecksumValid(barcode);
    if (valid == null) return AppStringsTr.barcodeDiagnosticsChecksumUnknown;
    return valid
        ? AppStringsTr.barcodeDiagnosticsChecksumValid
        : AppStringsTr.barcodeDiagnosticsChecksumInvalid;
  }

  static String _time(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }
}

class _ScanRecord {
  final String raw;
  final DateTime at;

  const _ScanRecord({required this.raw, required this.at});
}

class _Field extends StatelessWidget {
  final String label;
  final String value;
  final Key? valueKey;
  final bool monospace;

  const _Field({
    required this.label,
    required this.value,
    this.valueKey,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 200,
          child: Text(label, style: theme.textTheme.labelLarge),
        ),
        Expanded(
          child: Text(
            value,
            key: valueKey,
            style: monospace
                ? theme.textTheme.bodyMedium?.copyWith(fontFamily: 'monospace')
                : theme.textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}
