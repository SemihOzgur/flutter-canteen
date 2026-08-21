/// Kategori ikonu **anahtarları** — OD-029 · REQ-CAT-008
///
/// Saf Dart: Flutter import'u **yoktur** (rules/01 §1). Anahtarın hangi
/// ikona karşılık geldiği bir presentation ayrıntısıdır ve
/// `presentation/products/category_icon.dart` içindedir; burada yalnızca
/// **hangi anahtarların geçerli olduğu** ve adın hangi anahtara işaret
/// ettiği yaşar.
///
/// Bu ayrım zorunludur: `CategoryService` yazmadan önce anahtarı doğrular
/// (katalog dışı anahtar veritabanına girerse hiçbir ekranda ikon göstermez)
/// ve application katmanı Flutter'a bağlanamaz.
library;

import 'turkish_text.dart';

/// Veritabanında saklanabilecek anahtarlar — `categories.icon_key` bu
/// kümeyle sınırlıdır.
///
/// Bir anahtar buradan **çıkarılmaz**: ona işaret eden kategoriler kalmış
/// olabilir ve o kayıtlar sessizce nötr ikona düşerdi. Yeni anahtar eklemek
/// serbesttir.
const List<String> categoryIconKeys = [
  'drink',
  'coffee',
  'bakery',
  'sandwich',
  'snack',
  'sweet',
  'icecream',
  'fresh',
  'dairy',
  'stationery',
  'cleaning',
  'other',
];

/// [key] geçerli bir katalog anahtarı mı?
bool isKnownCategoryIconKey(String key) => categoryIconKeys.contains(key);

/// Kategori adında aranan sözcük → katalog anahtarı.
///
/// Sıra **önemlidir**: "sıcak içecek" hem `içecek` hem `sıcak` içerir;
/// daha özel olan önce gelir, yoksa çay fincanı yerine kola bardağı çıkardı.
const List<(List<String>, String)> _nameRules = [
  (['sıcak içecek', 'kahve', 'çay', 'salep'], 'coffee'),
  (
    ['soğuk içecek', 'gazoz', 'kola', 'meşrubat', 'içecek', 'su', 'ayran'],
    'drink',
  ),
  (['dondurma'], 'icecream'),
  (['tatlı', 'çikolata', 'şeker', 'kek', 'pasta'], 'sweet'),
  (['unlu', 'simit', 'poğaça', 'börek', 'ekmek'], 'bakery'),
  (['tost', 'sandviç', 'hamburger', 'sıcak'], 'sandwich'),
  (['atıştırmalık', 'cips', 'kuruyemiş', 'bisküvi'], 'snack'),
  (['meyve', 'sebze'], 'fresh'),
  (['süt', 'kahvaltı', 'peynir', 'yoğurt'], 'dairy'),
  (['kırtasiye', 'kalem', 'defter'], 'stationery'),
  (['temizlik', 'hijyen', 'kağıt'], 'cleaning'),
];

/// Kategori **adından** türetilen anahtar; eşleşme yoksa `null`.
///
/// Karşılaştırma [TurkishText.fold] ile yapılır: Dart'ın `toLowerCase()`
/// çağrısı locale bağımsızdır ve `'İÇECEK'` → `'i̇çecek'` üretir,
/// `'içecek'` değil — büyük harfli adlarda eşleşme sessizce başarısız olurdu.
String? categoryIconKeyFromName(String? categoryName) {
  if (categoryName == null) return null;
  final folded = TurkishText.fold(categoryName);
  if (folded.isEmpty) return null;

  for (final (keywords, key) in _nameRules) {
    for (final keyword in keywords) {
      if (folded.contains(TurkishText.fold(keyword))) return key;
    }
  }
  return null;
}
