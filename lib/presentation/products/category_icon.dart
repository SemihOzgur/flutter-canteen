/// Kategori ikonu — **docs/21 §3 · OD-029 · REQ-CAT-008 · REQ-IMG-013**
///
/// ## Üç kademeli zincir
///
/// ```text
/// categories.icon_key dolu   →  katalogdan seçilen ikon
/// icon_key NULL, ad eşleşiyor →  addan türetilen ikon
/// ad da eşleşmiyor            →  nötr ürün ikonu
/// ```
///
/// ## Neden anahtar saklıyoruz, kod noktası değil
///
/// Veritabanında duran şey `'drink'`tir, `0xe1a5` değil (OD-029). Kod noktası
/// bir **uygulama ayrıntısıdır**: Material ikon seti değişirse eski kayıtlar
/// sessizce başka bir ikona işaret ederdi. Ayrıca kod noktasını veriden
/// okumak Flutter'ın ikon tree-shaking'ini kırar ve tüm ikon fontunu pakete
/// koymayı zorunlu kılar.
///
/// ## Addan türetme neden KALDIRILMADI
///
/// Kullanıcı ikon seçmek **zorunda değildir** (docs/10 §1.2a). 40 kategorili
/// bir kurulumda hepsini elle seçtirmek, kazandırdığından çok iş çıkarırdı.
/// Tahmin yalnızca bir yardımdır ve tahmin olduğu için **sessizce yanlış
/// olmaz**: eşleşme bulunamazsa nötr ikon kalır. Yanlış ikon göstermek hiç
/// ikon göstermemekten kötüdür — kasadaki kişi "Kalemler" kategorisinde
/// bardak görürse ekrana bir daha güvenmez.
///
/// Türkçe karşılaştırma `TurkishText.fold` ile yapılır: Dart'ın
/// `toLowerCase()` çağrısı locale bağımsızdır ve `'İÇECEK'` → `'i̇çecek'`
/// üretir, `'içecek'` değil.
library;

import 'package:flutter/material.dart';

import '../../domain/services/category_icon_keys.dart';

/// Seçilebilir bir kategori ikonu.
class CategoryIconOption {
  /// Veritabanında saklanan anahtar — **değişmez.**
  final String key;

  /// Kullanıcıya gösterilen ad.
  final String label;

  final IconData icon;

  const CategoryIconOption({
    required this.key,
    required this.label,
    required this.icon,
  });
}

/// Kullanıcının seçebileceği ikonlar — **`icon_key` bu kümeyle sınırlıdır.**
///
/// Bir anahtar buradan **çıkarılmaz**: veritabanında ona işaret eden
/// kategoriler kalmış olabilir ve o kayıtlar sessizce nötr ikona düşerdi.
/// Yeni anahtar eklemek serbesttir.
const List<CategoryIconOption> categoryIconCatalog = [
  CategoryIconOption(
    key: 'drink',
    label: 'Soğuk içecek',
    icon: Icons.local_drink_outlined,
  ),
  CategoryIconOption(
    key: 'coffee',
    label: 'Sıcak içecek',
    icon: Icons.coffee_outlined,
  ),
  CategoryIconOption(
    key: 'bakery',
    label: 'Unlu mamül',
    icon: Icons.bakery_dining_outlined,
  ),
  CategoryIconOption(
    key: 'sandwich',
    label: 'Tost / sandviç',
    icon: Icons.lunch_dining_outlined,
  ),
  CategoryIconOption(
    key: 'snack',
    label: 'Atıştırmalık',
    icon: Icons.cookie_outlined,
  ),
  CategoryIconOption(key: 'sweet', label: 'Tatlı', icon: Icons.cake_outlined),
  CategoryIconOption(
    key: 'icecream',
    label: 'Dondurma',
    icon: Icons.icecream_outlined,
  ),
  CategoryIconOption(
    key: 'fresh',
    label: 'Meyve / sebze',
    icon: Icons.eco_outlined,
  ),
  CategoryIconOption(
    key: 'dairy',
    label: 'Süt / kahvaltı',
    icon: Icons.egg_outlined,
  ),
  CategoryIconOption(
    key: 'stationery',
    label: 'Kırtasiye',
    icon: Icons.edit_outlined,
  ),
  CategoryIconOption(
    key: 'cleaning',
    label: 'Temizlik',
    icon: Icons.cleaning_services_outlined,
  ),
  CategoryIconOption(
    key: 'other',
    label: 'Diğer',
    icon: Icons.inventory_2_outlined,
  ),
];

/// Görselsiz ürün için nötr ikon — hiçbir eşleşme bulunamadığında.
const IconData fallbackCategoryIcon = Icons.inventory_2_outlined;

/// [key] için ikon; anahtar tanınmıyorsa `null`.
IconData? iconForCategoryKey(String? key) {
  if (key == null) return null;
  for (final option in categoryIconCatalog) {
    if (option.key == key) return option.icon;
  }
  return null;
}

/// Zincirin tamamı: seçilen ikon → addan türetme → nötr ikon.
///
/// [iconKey] veritabanından gelir ve **önceliklidir**: kullanıcı bir seçim
/// yaptıysa tahmin onu ezmez.
IconData categoryIconFor(String? categoryName, {String? iconKey}) =>
    iconForCategoryKey(iconKey) ??
    iconForCategoryKey(categoryIconKeyFromName(categoryName)) ??
    fallbackCategoryIcon;
