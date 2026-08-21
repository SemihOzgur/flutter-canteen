/// Kategori ikonu eşlemesi — **docs/21 §3 · REQ-IMG-009**
///
/// > *"Görseli bulunamayan ürün hata göstermez; **kategori ikonuyla**
/// > gösterilir."*
library;

import 'package:canteen/presentation/products/category_icon.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('kategori adından ikon türetilir', () {
    test('içecek kategorileri', () {
      expect(categoryIconFor('İçecekler'), Icons.local_drink_outlined);
      expect(categoryIconFor('Soğuk İçecek'), Icons.local_drink_outlined);
      expect(categoryIconFor('Su'), Icons.local_drink_outlined);
    });

    test('SIRA — "Sıcak İçecek" içecek değil KAHVE ikonudur', () {
      // Ad hem "içecek" hem "sıcak" içeriyor; daha özel kural önce gelmeli,
      // yoksa çay bardağı yerine kola bardağı çıkardı.
      expect(categoryIconFor('Sıcak İçecekler'), Icons.coffee_outlined);
      expect(categoryIconFor('Çay & Kahve'), Icons.coffee_outlined);
    });

    test('yiyecek kategorileri', () {
      expect(categoryIconFor('Atıştırmalık'), Icons.cookie_outlined);
      expect(categoryIconFor('Unlu Mamüller'), Icons.bakery_dining_outlined);
      expect(categoryIconFor('Tostlar'), Icons.lunch_dining_outlined);
      expect(categoryIconFor('Tatlılar'), Icons.cake_outlined);
      expect(categoryIconFor('Dondurma'), Icons.icecream_outlined);
    });

    test('yiyecek DIŞI kategoriler', () {
      expect(categoryIconFor('Kırtasiye'), Icons.edit_outlined);
      expect(categoryIconFor('Temizlik'), Icons.cleaning_services_outlined);
    });
  });

  group('Türkçe harf katlaması', () {
    test('BÜYÜK harfli ad da eşleşir', () {
      // Dart'ın toLowerCase() çağrısı locale bağımsızdır: 'İÇECEK' →
      // 'i̇çecek'. Katlama yapılmasaydı büyük harfli kategori adları
      // sessizce eşleşmezdi.
      expect(categoryIconFor('İÇECEKLER'), Icons.local_drink_outlined);
      expect(categoryIconFor('ATIŞTIRMALIK'), Icons.cookie_outlined);
    });

    test('şapkasız yazım da eşleşir', () {
      expect(categoryIconFor('Icecekler'), Icons.local_drink_outlined);
      expect(categoryIconFor('atistirmalik'), Icons.cookie_outlined);
    });
  });

  group('eşleşme yoksa NÖTR ikon kalır', () {
    test('bilinmeyen kategori', () {
      // Yanlış ikon göstermektense nötr ikon göstermek yeğdir: kasadaki
      // kişi "Kalemler"de bardak görürse ekrana güvenmez.
      expect(categoryIconFor('Zımba Telleri'), fallbackCategoryIcon);
      expect(categoryIconFor('Genel'), fallbackCategoryIcon);
    });

    test('null ve boş ad', () {
      expect(categoryIconFor(null), fallbackCategoryIcon);
      expect(categoryIconFor(''), fallbackCategoryIcon);
      expect(categoryIconFor('   '), fallbackCategoryIcon);
    });
  });

  test('aynı ad her zaman AYNI ikonu verir', () {
    // Determinizm (rules/07): ikon rastgele veya sıraya bağlı seçilmez.
    for (var i = 0; i < 5; i++) {
      expect(categoryIconFor('İçecekler'), categoryIconFor('İçecekler'));
    }
  });
}
