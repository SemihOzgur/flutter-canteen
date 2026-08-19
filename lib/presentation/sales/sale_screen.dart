/// Satış ekranı — **docs/12 · docs/23 §2–§4 · REQ-UX-001…005/010/014**
///
/// Uygulamanın kalbi: toplam kullanım süresinin %90'ı burada geçer.
///
/// ## Odak asla kaybolmaz — REQ-UX-002/003
///
/// docs/23 §3'ün kuralı tek bir yerde uygulanır ([_onKeyEvent]):
///
/// ```text
/// Varsayılan · dialog kapandı · satış tamamlandı · ürün eklendi
///        ▼
/// odak barkod/arama girişinde
/// ```
///
/// Kullanıcı sepette gezinirken **yazmaya başlarsa** odak otomatik olarak
/// arama girişine döner ve **girilen ilk karakter kaybolmaz.** Karakteri
/// yalnızca odaklamak yetmez: `requestFocus` bir sonraki frame'de etkili
/// olduğu için o tuş vuruşu hiçbir alana ulaşmaz ve sessizce yutulurdu.
/// Bu yüzden karakter metne **elle** eklenir. Kasadaki "neden barkod
/// çalışmıyor?" sorununun çözümü tam olarak budur.
///
/// ## Burada hesap YAPILMAZ
///
/// rules/05 §3 · rules/01 §2: ekran KDV, kâr veya toplam hesaplamaz. Tüm
/// para değerleri `Cart.totals` / `SaleService` üzerinden gelir; ekran
/// yalnızca biçimlendirir ve servisleri çağırır.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/l10n/app_strings_tr.dart';
import '../../app/router.dart';
import '../../application/product/product_draft.dart';
import '../../application/product/product_service.dart';
import '../../application/product/providers.dart';
import '../../application/reference/providers.dart';
import '../../application/sales/providers.dart';
import '../../core/money/money.dart';
import '../../core/money/money_formatter.dart';
import '../../core/result/result.dart';
import '../../domain/models/cart.dart';
import '../../domain/models/category.dart';
import '../../domain/models/product.dart';
import '../../domain/services/barcode_input_handler.dart';
import '../barcode/barcode_listener.dart';
import '../common/current_user.dart';
import 'cart_panel.dart';
import 'product_picker.dart';
import 'sale_dialogs.dart';

class SaleScreen extends ConsumerStatefulWidget {
  static const Key searchFieldKey = Key('sale_search_field');
  static const Key shortcutsButtonKey = Key('sale_shortcuts_button');

  /// Barkod zaman eşiklerinin saati — **rules/06 §7.**
  ///
  /// `DateTime.now()` domain sınırlarına parametre olarak geçirilir; aksi
  /// hâlde 35 ms/300 ms eşikleri yalnızca gerçek beklemeyle sınanabilir ve
  /// testler makinenin yüküne göre kırılgan olurdu. Üretimde `null`'dır.
  final DateTime Function()? clock;

  const SaleScreen({this.clock, super.key});

  @override
  ConsumerState<SaleScreen> createState() => _SaleScreenState();
}

class _SaleScreenState extends ConsumerState<SaleScreen> {
  /// Enjekte edilen saatle **bir kez** kurulur; her build'de yeni işleyici
  /// üretmek tamponu sıfırlardı.
  late final BarcodeInputHandler? _barcodeHandler = widget.clock == null
      ? null
      : BarcodeInputHandler(clock: widget.clock);

  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'saleSearch');

  Cart? _cart;
  int? _userId;
  List<Product> _products = const [];
  List<Product> _favorites = const [];
  List<Category> _categories = const [];
  int? _selectedCategoryId;
  int? _selectedLineId;
  bool _busy = false;
  bool _loading = true;

  /// docs/13 §4 — "Aynı satış içinde aynı ürün için uyarı bir kez gösterilir."
  final Set<int> _stockWarned = <int>{};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // --- Yükleme -------------------------------------------------------------

  Future<void> _bootstrap() async {
    final userId = await currentUserId(ref);
    if (!mounted) return;
    if (userId == null) {
      // Oturum yoksa satış yapılamaz: `carts.user_id` ve `sales.user_id`
      // zorunludur ve izlenebilirlik user_id'ye dayanır (docs/18 §2).
      Navigator.of(context).pushReplacementNamed(AppRoutes.login);
      return;
    }

    final cart = await ref.read(cartServiceProvider).ensureActive(userId);
    if (!mounted) return;
    setState(() {
      _userId = userId;
      _cart = cart;
      _loading = false;
    });

    // EC-CART-010 — açılışta düşen satırlar sessizce kaybolmaz.
    if (cart.hasDroppedLines) {
      _notify(AppStringsTr.saleCartRepaired(cart.droppedLineCount));
    }
    await _reloadCatalog();
    _focusSearch();
  }

  Future<void> _reloadCatalog() async {
    // rules/01 §1 — ekran `data/` katmanını tanımaz; okuma da application
    // katmanından geçer.
    final products = ref.read(productServiceProvider);
    final query = _search.text.trim();

    // rules/01 §8 — listeler sayfalanır; tüm kayıtlar belleğe alınmaz.
    final results = query.isEmpty
        ? await products.list(categoryId: _selectedCategoryId, limit: 120)
        : await products.search(query, limit: 60);
    final favorites = await products.list(onlyFavorites: true, limit: 9);
    final categories = await ref
        .read(categoryServiceProvider)
        .list(onlyActive: true);

    if (!mounted) return;
    setState(() {
      _products = results;
      _favorites = favorites;
      _categories = categories;
    });
  }

  // --- Odak — REQ-UX-002/003 ----------------------------------------------

  void _focusSearch() {
    if (!mounted) return;
    _searchFocus.requestFocus();
  }

  /// Arama kutusunu temizler ve odağı geri verir.
  ///
  /// docs/23 §3'teki "ürün eklendi → odak barkod girişinde" adımı budur.
  void _resetSearch() {
    _search.clear();
    _focusSearch();
    unawaited(_reloadCatalog());
  }

  // --- Sepet işlemleri -----------------------------------------------------

  /// Ürünü sepete ekler — **docs/11 §4.1 · REQ-BARC-004/005 · REQ-CART-009.**
  ///
  /// BR-STOCK-006: stok uyarısı **engelleyici değildir** ve satırdan *önce*
  /// sorulur; kullanıcı vazgeçerse sepette hiçbir değişiklik olmaz. Uyarı
  /// aynı satış içinde ürün başına bir kez gösterilir (docs/13 §4).
  Future<void> _addProduct(Product product, {bool fromScan = false}) async {
    final cart = _cart;
    if (cart == null || _busy) return;

    // docs/11 §4.3 — pasif ürün okutuldu.
    if (!product.isActive) {
      if (!await showInactiveProductDialog(
        context,
        productName: product.name,
      )) {
        _focusSearch();
        return;
      }
      final activated = await ref
          .read(productServiceProvider)
          .activate(product.id, userId: _userId!);
      if (activated.isErr) {
        _notify(activated.failureOrNull!.userMessage);
        _focusSearch();
        return;
      }
    }

    if (product.stockQuantity <= 0 && !_stockWarned.contains(product.id)) {
      if (!mounted) return;
      final proceed = await showStockWarningDialog(
        context,
        productName: product.name,
        stockQuantity: product.stockQuantity,
      );
      // Uyarı bir kez gösterilir — kullanıcı vazgeçse bile: aksi hâlde aynı
      // ürünü tekrar denemek her seferinde aynı dialogu açardı.
      _stockWarned.add(product.id);
      if (!proceed) {
        _focusSearch();
        return;
      }
    }

    final result = await ref
        .read(cartServiceProvider)
        .addProduct(cartId: cart.id, productId: product.id);
    if (!mounted) return;

    if (result.isErr) {
      _notify(result.failureOrNull!.userMessage);
    } else {
      setState(() {
        _cart = result.valueOrNull;
        // Yeni/güncellenen satır seçili olsun ki `+`/`-`/`Del` doğrudan
        // çalışsın (docs/23 §2).
        _selectedLineId = _cart!.lines
            .where((l) => l.productId == product.id)
            .lastOrNull
            ?.id;
      });
    }
    if (fromScan) {
      // Okutmadan sonra stok değişmiş olabilir; kartlar tazelenir.
      unawaited(_reloadCatalog());
    }
    _resetSearch();
  }

  /// **REQ-BARC-004/005/006/007 — barkod okutuldu.**
  ///
  /// docs/11 §4: bulunan ürün **ara onay olmadan** sepete eklenir; bulunamayan
  /// barkod hızlı ürün ekleme dialogunu açar ve oluşan ürün otomatik sepete
  /// girer.
  Future<void> _onScan(String rawBarcode) async {
    final barcode = rawBarcode.trim();
    if (barcode.isEmpty || _busy) return;

    // Normalizasyon `ProductService` içindedir (docs/11 §3) — ekran barkodu
    // kendi başına dönüştürmez.
    final found = await ref.read(productServiceProvider).findByBarcode(barcode);
    if (!mounted) return;

    if (found != null) {
      await _addProduct(found, fromScan: true);
      return;
    }

    // docs/11 §4.2 — eşleşme yok.
    final draft = await showQuickProductDialog(context, barcode: barcode);
    if (!mounted) return;
    if (draft == null) {
      // "İptal edilirse: ürün oluşmaz, sepete bir şey eklenmez, barkod alanı
      // temizlenir."
      _resetSearch();
      return;
    }

    final created = await ref
        .read(productServiceProvider)
        .create(
          ProductDraft(name: draft.name, salePrice: draft.salePrice),
          userId: _userId!,
          barcodes: [draft.barcode],
          creationPath: ProductCreationPath.quick,
        );
    if (!mounted) return;
    if (created.isErr) {
      _notify(created.failureOrNull!.userMessage);
      _resetSearch();
      return;
    }

    final product = await ref
        .read(productServiceProvider)
        .findById(created.valueOrNull!.productId);
    if (!mounted || product == null) return;

    // Yeni ürünün stoğu tanım gereği `0`'dır; docs/11 §4.2 akışında stok
    // uyarısı YOKTUR ve olsaydı her hızlı eklemede çıkardı. Kullanıcı ürünü
    // elinde tutarken "stoğu tükenmiş" uyarısı almak akışı anlamsız keserdi.
    _stockWarned.add(product.id);

    // BR-BARC-005 — oluşan ürün OTOMATİK sepete eklenir.
    await _addProduct(product, fromScan: true);
  }

  Future<void> _changeQuantity(int lineId, int by) async {
    final cart = _cart;
    if (cart == null || _busy) return;
    final result = await ref
        .read(cartServiceProvider)
        .changeQuantity(cartId: cart.id, lineId: lineId, by: by);
    _applyCart(result);
  }

  Future<void> _removeLine(int lineId) async {
    final cart = _cart;
    if (cart == null || _busy) return;
    // REQ-UX-009 · docs/23 §1 — satır silmek geri alınabilir, onay istemez.
    final result = await ref
        .read(cartServiceProvider)
        .removeLine(cartId: cart.id, lineId: lineId);
    _applyCart(result);
  }

  /// docs/12 §4 — `F2`.
  Future<void> _editPrice(int lineId) async {
    final cart = _cart;
    if (cart == null || _busy) return;
    final line = cart.lines.where((l) => l.id == lineId).firstOrNull;
    if (line == null) return;

    final price = await showPriceOverrideDialog(
      context,
      productName: line.productName,
      listPrice: line.listPrice,
      currentPrice: line.unitPrice,
    );
    if (!mounted || price == null) {
      _focusSearch();
      return;
    }

    final result = await ref
        .read(cartServiceProvider)
        .overridePrice(cartId: cart.id, lineId: lineId, unitPrice: price);
    _applyCart(result);
  }

  Future<void> _clearCart() async {
    final cart = _cart;
    final userId = _userId;
    if (cart == null || userId == null || cart.isEmpty || _busy) return;

    if (!await showClearCartDialog(context)) {
      _focusSearch();
      return;
    }
    final cleared = await ref
        .read(cartServiceProvider)
        .clear(cartId: cart.id, userId: userId);
    if (!mounted) return;
    setState(() {
      _cart = cleared;
      _selectedLineId = null;
      _stockWarned.clear();
    });
    _focusSearch();
  }

  void _applyCart(Result<Cart> result) {
    if (!mounted) return;
    if (result.isErr) {
      _notify(result.failureOrNull!.userMessage);
    } else {
      setState(() {
        _cart = result.valueOrNull;
        if (_cart!.lines.every((l) => l.id != _selectedLineId)) {
          _selectedLineId = _cart!.lines.lastOrNull?.id;
        }
      });
    }
    _focusSearch();
  }

  // --- Satış tamamlama -----------------------------------------------------

  /// `F4` → nakit hesaplama, ardından tamamlama (docs/12 §5).
  Future<void> _completeWithCash() async {
    final cart = _cart;
    if (cart == null || cart.isEmpty || _busy) return;
    final received = await showCashDialog(context, total: cart.totals.gross);
    if (!mounted) return;
    if (received == null) {
      _focusSearch();
      return;
    }
    await _complete(cashReceived: received);
  }

  /// `F12` — **docs/12 §6.**
  ///
  /// EC-SALE-008 · REQ-SALE-008: `_busy` bayrağı butonu ve kısayolu kilitler.
  /// Bu **ikinci** savunmadır; asıl koruma `SaleService` içindedir — UI'ya
  /// güvenmek "üç kez basınca üç satış" hatasını bir widget ayrıntısına
  /// bağımlı kılardı.
  Future<void> _complete({Money? cashReceived}) async {
    final cart = _cart;
    final userId = _userId;
    if (cart == null || userId == null || cart.isEmpty || _busy) return;

    setState(() => _busy = true);
    try {
      final result = await ref
          .read(saleServiceProvider)
          .complete(
            cartId: cart.id,
            userId: userId,
            cashReceived: cashReceived,
          );
      if (!mounted) return;

      if (result.isErr) {
        _notify(result.failureOrNull!.userMessage);
        return;
      }

      final receipt = result.valueOrNull!;
      setState(() {
        // docs/12 §6.3 — sepet boşalır; servis yeni aktif sepeti zaten açtı.
        _cart = receipt.newCart;
        _selectedLineId = null;
        _stockWarned.clear();
      });
      _notify(
        receipt.change == null
            ? AppStringsTr.saleCompletedMessage(
                receipt.saleNumber,
                MoneyFormatter.format(receipt.grandTotal),
              )
            : AppStringsTr.saleCompletedWithChange(
                receipt.saleNumber,
                MoneyFormatter.format(receipt.grandTotal),
                MoneyFormatter.format(receipt.change!),
              ),
      );
      // Satış stoğu düşürdü; ürün kartları tazelenir.
      unawaited(_reloadCatalog());
    } finally {
      if (mounted) setState(() => _busy = false);
      // docs/23 §3 — satış tamamlandı → odak barkod girişinde.
      _focusSearch();
    }
  }

  // --- Klavye — docs/23 §2 -------------------------------------------------

  /// Seçili satırı `↑`/`↓` ile değiştirir.
  void _moveSelection(int delta) {
    final lines = _cart?.lines ?? const <CartLine>[];
    if (lines.isEmpty) return;
    final current = lines.indexWhere((l) => l.id == _selectedLineId);
    final next = (current < 0 ? 0 : current + delta).clamp(0, lines.length - 1);
    setState(() => _selectedLineId = lines[next].id);
  }

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final pressed = HardwareKeyboard.instance;

    // --- Her zaman etkin kısayollar ---------------------------------------
    if (key == LogicalKeyboardKey.f1) {
      unawaited(showShortcutsDialog(context).then((_) => _focusSearch()));
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f12) {
      unawaited(_complete());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f4) {
      unawaited(_completeWithCash());
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f2 && _selectedLineId != null) {
      unawaited(_editPrice(_selectedLineId!));
      return KeyEventResult.handled;
    }
    // docs/23 §2 — sepeti temizle. docs/12 §3'teki "Esc (uzun)" yerine
    // `Ctrl+Del` kullanılır: `Esc` docs/23 §2'de "geri / dialog kapat"tır ve
    // ikisi aynı tuşta çakışırdı.
    if (key == LogicalKeyboardKey.delete && pressed.isControlPressed) {
      unawaited(_clearCart());
      return KeyEventResult.handled;
    }
    // Alt+1…9 → favori ekle.
    if (pressed.isAltPressed) {
      final index = _digitIndex(key);
      if (index != null && index < _favorites.length) {
        unawaited(_addProduct(_favorites[index]));
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }

    // --- Arama kutusu BOŞKEN etkin kısayollar ------------------------------
    //
    // `+`, `-` ve `Del` yazdırılabilir/metin tuşlarıdır. Arama kutusunda metin
    // varken bunları yakalamak arama yazmayı imkânsız kılardı; kutu boşken ise
    // kasiyerin akışı "okut → + → +" şeklindedir ve kısayol tam oradadır.
    if (_search.text.isEmpty && _selectedLineId != null) {
      if (key == LogicalKeyboardKey.add ||
          key == LogicalKeyboardKey.numpadAdd ||
          key == LogicalKeyboardKey.equal) {
        unawaited(_changeQuantity(_selectedLineId!, 1));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.minus ||
          key == LogicalKeyboardKey.numpadSubtract) {
        unawaited(_changeQuantity(_selectedLineId!, -1));
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.delete) {
        unawaited(_removeLine(_selectedLineId!));
        return KeyEventResult.handled;
      }
    }

    // --- REQ-UX-003: yazmaya başlayınca odak arama kutusuna DÖNER ----------
    //
    // Karakter yalnızca odaklanarak kurtarılamaz: `requestFocus` bir sonraki
    // frame'de etkili olur ve o tuş vuruşu hiçbir alana ulaşmadan kaybolurdu.
    if (!_searchFocus.hasFocus &&
        !pressed.isControlPressed &&
        !pressed.isAltPressed &&
        !pressed.isMetaPressed) {
      final character = event.character;
      if (character != null &&
          character.isNotEmpty &&
          character.codeUnitAt(0) >= 0x20) {
        _searchFocus.requestFocus();
        _search
          ..text = _search.text + character
          ..selection = TextSelection.collapsed(offset: _search.text.length);
        unawaited(_reloadCatalog());
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  static int? _digitIndex(LogicalKeyboardKey key) {
    const digits = [
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
      LogicalKeyboardKey.digit5,
      LogicalKeyboardKey.digit6,
      LogicalKeyboardKey.digit7,
      LogicalKeyboardKey.digit8,
      LogicalKeyboardKey.digit9,
    ];
    final index = digits.indexOf(key);
    return index < 0 ? null : index;
  }

  // --- Görünüm -------------------------------------------------------------

  void _notify(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          // docs/12 §6.3 — 3 saniye görünür; kullanıcı hiçbir şeye tıklamak
          // zorunda kalmaz.
          duration: const Duration(seconds: 3),
        ),
      );
  }

  /// `Enter` — aramadaki ilk ürünü ekler (docs/23 §2).
  void _submitSearch() {
    final first = _products.firstOrNull;
    if (first != null) unawaited(_addProduct(first));
  }

  @override
  Widget build(BuildContext context) {
    final cart = _cart;

    // ⚠️ Dinleyici ve kısayol yakalayıcı **tüm ekranı** sarar, yalnızca
    // `body`'yi değil. Arama kutusu `AppBar`'dadır ve odak varsayılan olarak
    // ORADADIR (REQ-UX-002); yalnızca `body` sarılsaydı tuş olayları
    // dinleyiciye hiç ulaşmaz ve **scanner tam da normal durumda çalışmazdı.**
    return Focus(
      onKeyEvent: _onKeyEvent,
      skipTraversal: true,
      child: BarcodeListener(
        handler: _barcodeHandler,
        onScan: (barcode) => unawaited(_onScan(barcode)),
        // Odak arama kutusunun; dinleyici onu çalmaz.
        autofocus: false,
        child: Scaffold(
          appBar: AppBar(
            title: SizedBox(
              height: 44,
              child: TextField(
                key: SaleScreen.searchFieldKey,
                controller: _search,
                focusNode: _searchFocus,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: AppStringsTr.saleSearchHint,
                  prefixIcon: Icon(Icons.qr_code_scanner),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (_) => unawaited(_reloadCatalog()),
                onSubmitted: (_) => _submitSearch(),
              ),
            ),
            actions: [
              IconButton(
                key: SaleScreen.shortcutsButtonKey,
                tooltip: AppStringsTr.saleShortcutsTitle,
                icon: const Icon(Icons.keyboard),
                onPressed: () => unawaited(
                  showShortcutsDialog(context).then((_) => _focusSearch()),
                ),
              ),
              IconButton(
                tooltip: AppStringsTr.homeProductsAction,
                icon: const Icon(Icons.inventory_2_outlined),
                onPressed: () => unawaited(
                  Navigator.of(context).pushNamed(AppRoutes.products).then((_) {
                    // docs/23 §3 — başka ekrandan dönüldü → odak arama
                    // girişinde.
                    _focusSearch();
                    unawaited(_reloadCatalog());
                  }),
                ),
              ),
            ],
          ),
          body: _loading || cart == null
              ? const Center(child: CircularProgressIndicator())
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: ProductPicker(
                        favorites: _favorites,
                        categories: _categories,
                        products: _products,
                        selectedCategoryId: _selectedCategoryId,
                        searching: _search.text.trim().isNotEmpty,
                        onSelectCategory: (id) {
                          setState(() => _selectedCategoryId = id);
                          unawaited(_reloadCatalog());
                        },
                        onPickProduct: (product) =>
                            unawaited(_addProduct(product)),
                        onOpenProducts: () => unawaited(
                          Navigator.of(context).pushNamed(AppRoutes.products),
                        ),
                      ),
                    ),
                    // rules/05 §2 · REQ-UX-005 — sepet paneli hiçbir
                    // çözünürlükte gizlenmez veya sekmeye dönüşmez. Genişlik
                    // ekranın ~%38'idir (docs/12 §1) ve alt sınırı vardır:
                    // 1366×768'de daralır ama korunur (docs/23 §4).
                    SizedBox(
                      width: (MediaQuery.sizeOf(context).width * 0.38).clamp(
                        320.0,
                        520.0,
                      ),
                      child: CartPanel(
                        cart: cart,
                        selectedLineId: _selectedLineId,
                        onSelectLine: (id) =>
                            setState(() => _selectedLineId = id),
                        onChangeQuantity: (id, by) =>
                            unawaited(_changeQuantity(id, by)),
                        onRemoveLine: (id) => unawaited(_removeLine(id)),
                        onEditPrice: (id) => unawaited(_editPrice(id)),
                        onComplete: () => unawaited(_complete()),
                        onCash: () => unawaited(_completeWithCash()),
                        onClear: () => unawaited(_clearCart()),
                        busy: _busy,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
