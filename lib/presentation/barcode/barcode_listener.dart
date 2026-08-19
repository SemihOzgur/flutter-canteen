/// Barkod dinleyici — **docs/11 §2 · REQ-BARC-003/011**
///
/// Scanner HID klavye emülasyonu yaptığı için (rules/02 §10) girdi normal tuş
/// olayı olarak gelir. Bu widget alt ağacındaki tuş olaylarını [BarcodeInputHandler]'a
/// besler ve bir barkod tamamlandığında [onScan]'i çağırır.
///
/// ## Karakterler yutulmaz
///
/// Karakter olayları `ignored` döner: alttaki metin alanı onları görmeye devam
/// eder. Satış ekranında kullanıcı okuttuğunda arama kutusunda metni görür;
/// yazdığında da normal davranış bozulmaz. Yalnızca **barkodu tamamlayan
/// `Enter`** tüketilir — aksi hâlde okuma hem sepete eklenir hem de formu
/// gönderirdi.
///
/// ## Modal açıkken dinleme kapalıdır — REQ-BARC-011
///
/// `ModalRoute.isCurrent` alttaki rotanın üstünde bir şey olup olmadığını
/// söyler. Dialog açıkken okutulan barkodun arkadaki ekrana ürün eklemesi
/// (EC-BARC-005) kabul edilemez; tampon da temizlenir ki dialog kapandığında
/// yarım bir okuma tamamlanmasın.
///
/// ⚠️ **Bu widget bir rotanın İÇİNDE olmalıdır.** `Navigator`'ın üstüne
/// (örn. `MaterialApp.builder`) konursa `ModalRoute.of` `null` döner ve
/// dialog algılanamaz — okuma arkadaki ekrana giderdi. Yanlış yerleştirme
/// sessiz kalmasın diye `assert` ile yakalanır. docs/11 §2 zaten "satış
/// ekranında global dinleme" der: kapsam ekrandır, uygulama değil.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/services/barcode_input_handler.dart';

class BarcodeListener extends StatefulWidget {
  /// Barkod tamamlandığında çağrılır — ham değer, normalize edilmemiş.
  final ValueChanged<String> onScan;

  /// Tanılama ekranı her tuş olayından sonra durumu göstermek için kullanır.
  final VoidCallback? onInputChanged;

  /// `false` ise dinleme tamamen kapalıdır (ekran kendi kararını verebilir).
  final bool enabled;

  /// Alt ağaçta odaklanacak başka bir şey yoksa dinleyici odağı kendisi alır.
  final bool autofocus;

  /// Test ve tanılama için enjekte edilebilir.
  final BarcodeInputHandler? handler;

  final Widget child;

  const BarcodeListener({
    required this.onScan,
    required this.child,
    this.onInputChanged,
    this.enabled = true,
    this.autofocus = true,
    this.handler,
    super.key,
  });

  @override
  State<BarcodeListener> createState() => _BarcodeListenerState();
}

class _BarcodeListenerState extends State<BarcodeListener> {
  late final BarcodeInputHandler _handler =
      widget.handler ?? BarcodeInputHandler();

  /// REQ-BARC-011 · EC-BARC-005 — üstte bir modal varsa dinleme kapalıdır.
  ///
  /// **İkinci savunma hattıdır.** Rota içinde `showDialog` zaten kendi odak
  /// kapsamını açtığı için tuş olayları bu düğüme ulaşmaz; mutasyon testi bu
  /// kontrolü kaldırınca hiçbir test kırılmıyor. Yine de duruyor: kilit bir
  /// 🔴 gereksinimin (REQ-BARC-011) Flutter'ın odak davranışındaki örtük bir
  /// ayrıntıya bırakılması, o davranış değiştiğinde sessizce ihlale dönüşürdü.
  /// Ayrıca tamponu temizler — dialog kapandığında yarım okuma tamamlanmasın.
  bool get _isTopmost => ModalRoute.of(context)?.isCurrent ?? true;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (!widget.enabled || !_isTopmost) {
      // Yarım kalmış bir okuma dialog kapandığında tamamlanmamalıdır.
      _handler.reset();
      return KeyEventResult.ignored;
    }

    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final result = _handler.handleEnter();
      widget.onInputChanged?.call();

      if (result.isScanned) {
        widget.onScan(result.barcode!);
        // Yalnızca barkodu tamamlayan `Enter` tüketilir.
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    final character = event.character;
    // Kontrol tuşları (Shift, ok tuşları …) `character` üretmez; barkod
    // yalnızca yazdırılabilir karakterlerden oluşur.
    if (character == null || character.isEmpty) return KeyEventResult.ignored;
    if (character.codeUnitAt(0) < 0x20) return KeyEventResult.ignored;

    _handler.handleCharacter(character);
    widget.onInputChanged?.call();

    // Karakter YUTULMAZ: alttaki metin alanı görmeye devam eder.
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    assert(
      ModalRoute.of(context) != null,
      'BarcodeListener bir rotanın içinde olmalıdır; aksi hâlde '
      'ModalRoute.of null döner ve modal algılanamaz (REQ-BARC-011).',
    );

    return Focus(
      autofocus: widget.autofocus,
      // Odak sırasını bozmaz: `Tab` ile bu düğüme gelinmez.
      skipTraversal: true,
      onKeyEvent: _onKeyEvent,
      child: widget.child,
    );
  }
}
