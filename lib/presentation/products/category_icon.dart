/// Kategori ikonu — **docs/21 §3 · REQ-IMG-009**
///
/// > *"Görsel yoksa veya okunamıyorsa **kategori ikonu** gösterilir — hata
/// > gösterilmez."*
///
/// ## Neden ada bakıyoruz
///
/// `categories` tablosunda ikon kolonu **yoktur** (docs/05 §2.2) ve kolon
/// eklemek bir şema kararıdır (rules/00 §3). Kategoriler kullanıcının
/// yazdığı serbest metindir; bu yüzden ikon **addan türetilir.**
///
/// Bu bir tahmindir ve tahmin olduğu için **sessizce yanlış olmaz**:
/// eşleşme bulunamazsa kategoriye özel bir renk ve nötr bir ürün ikonu
/// kalır. Yanlış ikon göstermektense nötr ikon göstermek yeğdir — kasadaki
/// kişi "Kalemler" kategorisinde bardak ikonu görürse ekrana güvenmez.
///
/// ## Türkçe eşleştirme
///
/// Karşılaştırma `TurkishText.fold` ile yapılır: Dart'ın `toLowerCase()`
/// çağrısı locale bağımsızdır ve `'İÇECEK'` → `'i̇çecek'` üretir, `'içecek'`
/// değil. Bu, eşleşmenin büyük harfli kategori adlarında sessizce
/// başarısız olmasına yol açardı.
library;

import 'package:flutter/material.dart';

import '../../domain/services/turkish_text.dart';

/// Kategori adında aranan anahtar sözcük → ikon.
///
/// Sıra **önemlidir**: "sıcak içecek" hem `içecek` hem `sıcak` içerir;
/// daha özel olan önce gelir.
const List<(List<String>, IconData)> _rules = [
  (['sıcak içecek', 'kahve', 'çay', 'salep'], Icons.coffee_outlined),
  (
    ['soğuk içecek', 'gazoz', 'kola', 'meşrubat', 'içecek', 'su', 'ayran'],
    Icons.local_drink_outlined,
  ),
  (['dondurma'], Icons.icecream_outlined),
  (['tatlı', 'çikolata', 'şeker', 'kek', 'pasta'], Icons.cake_outlined),
  (['unlu', 'simit', 'poğaça', 'börek', 'ekmek'], Icons.bakery_dining_outlined),
  (['tost', 'sandviç', 'hamburger', 'sıcak'], Icons.lunch_dining_outlined),
  (['atıştırmalık', 'cips', 'kuruyemiş', 'bisküvi'], Icons.cookie_outlined),
  (['meyve', 'sebze'], Icons.eco_outlined),
  (['süt', 'kahvaltı', 'peynir', 'yoğurt'], Icons.egg_outlined),
  (['kırtasiye', 'kalem', 'defter'], Icons.edit_outlined),
  (['temizlik', 'hijyen', 'kağıt'], Icons.cleaning_services_outlined),
];

/// Görselsiz ürün için nötr ikon — eşleşme bulunamadığında kullanılır.
const IconData fallbackCategoryIcon = Icons.inventory_2_outlined;

/// [categoryName] için ikon; eşleşme yoksa [fallbackCategoryIcon].
IconData categoryIconFor(String? categoryName) {
  if (categoryName == null) return fallbackCategoryIcon;
  final folded = TurkishText.fold(categoryName);
  if (folded.isEmpty) return fallbackCategoryIcon;

  for (final (keywords, icon) in _rules) {
    for (final keyword in keywords) {
      if (folded.contains(TurkishText.fold(keyword))) return icon;
    }
  }
  return fallbackCategoryIcon;
}
