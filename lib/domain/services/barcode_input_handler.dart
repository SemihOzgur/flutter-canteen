/// Barkod giriş işleyicisi — **docs/11 §2 · REQ-BARC-001/002/008**
///
/// Scanner HID klavye emülasyonu yapar (rules/02 §10): işletim sistemi onu
/// klavye olarak görür, uygulama da normal tuş girdisi alır. Ayırt etme
/// **karakterler arası süreye** ve `Enter` sonlandırıcısına dayanır.
///
/// | Ölçüt | Değer | Kaynak |
/// |---|---|---|
/// | Karakterler arası azami süre | 35 ms | docs/11 §2 |
/// | Asgari uzunluk | 4 | docs/11 §2 |
/// | Azami uzunluk | 64 | docs/11 §2 |
/// | Buffer zaman aşımı | 300 ms | docs/11 §2 |
/// | Sonlandırıcı | `Enter` / `CR` | zorunlu |
///
/// ## Neden zamanlayıcı yok
///
/// Sınıf saf Dart'tır ve **hiçbir `Timer` kurmaz**: zaman aşımı her olayda
/// saat okunarak değerlendirilir. Böylece davranış `rules/06 §7`'nin istediği
/// gibi deterministiktir — test sahte bir saatle 35 ms ile 36 ms arasındaki
/// farkı hiçbir gerçek beklemeye girmeden doğrulayabilir.
///
/// ## Neden barkod yalnızca `Enter`'da tamamlanır
///
/// docs/11 §2 sonlandırıcıyı **zorunlu** kılar. Uzunluğa bakıp erken
/// tamamlamak, 13 haneli bir barkodun 13. karakterinde tetiklenip 14 haneli
/// bir okumayı ikiye bölerdi.
library;

/// Bir tuş olayının işlenme sonucu.
enum BarcodeInputOutcome {
  /// Karakter tamponlandı; çağıranın yapacağı bir şey yok.
  buffered,

  /// `Enter` bir barkodu tamamladı.
  scanned,

  /// `Enter` barkod tamamlamadı — çağıran bunu **normal** `Enter` olarak
  /// işlemelidir (form gönderimi vb.).
  passThrough,
}

class BarcodeInputResult {
  final BarcodeInputOutcome outcome;

  /// Yalnızca [BarcodeInputOutcome.scanned] için doludur.
  final String? barcode;

  const BarcodeInputResult._(this.outcome, [this.barcode]);

  static const BarcodeInputResult buffered = BarcodeInputResult._(
    BarcodeInputOutcome.buffered,
  );
  static const BarcodeInputResult passThrough = BarcodeInputResult._(
    BarcodeInputOutcome.passThrough,
  );

  bool get isScanned => outcome == BarcodeInputOutcome.scanned;
}

class BarcodeInputHandler {
  /// docs/11 §2 — insan yazımı 80–300 ms, scanner < 15 ms.
  static const Duration maxInterCharacterGap = Duration(milliseconds: 35);

  /// docs/11 §2 — sonlandırıcı gelmezse tampon atılır.
  static const Duration bufferTimeout = Duration(milliseconds: 300);

  static const int minLength = 4;
  static const int maxLength = 64;

  final DateTime Function() _clock;

  final StringBuffer _buffer = StringBuffer();
  DateTime? _startedAt;
  DateTime? _lastCharacterAt;

  BarcodeInputHandler({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// Tampondaki ham girdi — tanılama ekranı bunu gösterir (REQ-BARC-010).
  String get buffer => _buffer.toString();

  bool get isBuffering => _buffer.isNotEmpty;

  void reset() {
    _buffer.clear();
    _startedAt = null;
    _lastCharacterAt = null;
  }

  /// Bir karakter geldi.
  ///
  /// **Asla barkod döndürmez** — tamamlama yalnızca [handleEnter] iledir.
  BarcodeInputResult handleCharacter(String character) {
    if (character.isEmpty) return BarcodeInputResult.buffered;

    final now = _clock();
    final last = _lastCharacterAt;
    final started = _startedAt;

    // Tampon bayatladıysa yeni bir giriş başlar: kullanıcı yavaş yazmaya
    // başlamış ve sonlandırıcı hiç gelmemiş olabilir.
    final staleBuffer =
        started != null && now.difference(started) > bufferTimeout;

    // İnsan hızında bir aralık, o ana kadarki tamponu geçersiz kılar.
    final slowGap = last != null && now.difference(last) > maxInterCharacterGap;

    if (staleBuffer || slowGap) reset();

    _buffer.write(character);
    _startedAt ??= now;
    _lastCharacterAt = now;

    // docs/11 §2 — azami uzunluk aşılırsa tampon temizlenir. Barkod
    // olamayacak kadar uzun bir dizi, sonraki gerçek okumayı kirletmemelidir.
    if (_buffer.length > maxLength) reset();

    return BarcodeInputResult.buffered;
  }

  /// `Enter` / `CR` geldi.
  ///
  /// Tampon geçerli bir barkodsa [BarcodeInputOutcome.scanned] döner ve
  /// tampon temizlenir; aksi hâlde [BarcodeInputOutcome.passThrough] döner —
  /// çağıran `Enter`'ı normal şekilde işlemelidir.
  BarcodeInputResult handleEnter() {
    final started = _startedAt;
    final value = _buffer.toString();
    final now = _clock();

    final tooShort = value.length < minLength;
    final stale = started == null || now.difference(started) > bufferTimeout;

    reset();

    if (tooShort || stale) return BarcodeInputResult.passThrough;
    return BarcodeInputResult._(BarcodeInputOutcome.scanned, value);
  }
}
