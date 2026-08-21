/// Kategori ikonu eşlemesi — **docs/21 §3 · REQ-IMG-009**
///
/// > *"Görseli bulunamayan ürün hata göstermez; **kategori ikonuyla**
/// > gösterilir."*
library;

import 'package:canteen/domain/services/category_icon_keys.dart';
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

  group('OD-029 — SEÇİLEN ikon addan türetmeyi EZER', () {
    test('kullanıcı seçimi kazanır', () {
      // Adı "İçecekler" olan bir kategoriye kullanıcı bilerek kırtasiye
      // ikonu seçtiyse, tahmin onu geçersiz kılamaz.
      expect(
        categoryIconFor('İçecekler', iconKey: 'stationery'),
        Icons.edit_outlined,
      );
    });

    test('anahtar boşsa addan türetilir', () {
      expect(
        categoryIconFor('İçecekler', iconKey: null),
        Icons.local_drink_outlined,
      );
    });

    test('TANINMAYAN anahtar addan türetmeye düşer', () {
      // Katalogdan bir anahtar kaldırılırsa ona işaret eden eski kayıtlar
      // kalır; o kayıtlar boş kutu değil, makul bir ikon göstermelidir.
      expect(
        categoryIconFor('İçecekler', iconKey: 'silinmis_anahtar'),
        Icons.local_drink_outlined,
      );
    });

    test('tanınmayan anahtar VE eşleşmeyen ad → nötr ikon', () {
      expect(
        categoryIconFor('Zımba Telleri', iconKey: 'yok'),
        fallbackCategoryIcon,
      );
    });
  });

  group('katalog', () {
    test('her katalog girdisi geçerli bir anahtardır', () {
      for (final option in categoryIconCatalog) {
        expect(
          isKnownCategoryIconKey(option.key),
          isTrue,
          reason: '${option.key} domain listesinde yok.',
        );
      }
    });

    test('domain listesindeki her anahtarın bir ikonu vardır', () {
      // İki liste ayrı katmanlarda yaşıyor (biri Flutter'a bağlı, diğeri
      // değil); ayrışırlarsa geçerli bir anahtar ikonsuz kalırdı.
      for (final key in categoryIconKeys) {
        expect(
          iconForCategoryKey(key),
          isNotNull,
          reason: '$key için ikon tanımlı değil.',
        );
      }
      expect(categoryIconCatalog.length, categoryIconKeys.length);
    });

    test('anahtarlar benzersizdir', () {
      final keys = categoryIconCatalog.map((o) => o.key).toSet();
      expect(keys.length, categoryIconCatalog.length);
    });

    test('addan türetme YALNIZCA geçerli anahtar üretir', () {
      for (final name in const [
        'İçecekler',
        'Sıcak İçecek',
        'Unlu Mamüller',
        'Tatlılar',
        'Kırtasiye',
      ]) {
        final key = categoryIconKeyFromName(name);
        expect(key, isNotNull, reason: name);
        expect(isKnownCategoryIconKey(key!), isTrue, reason: '$name → $key');
      }
    });
  });

  test('aynı ad her zaman AYNI ikonu verir', () {
    // Determinizm (rules/07): ikon rastgele veya sıraya bağlı seçilmez.
    for (var i = 0; i < 5; i++) {
      expect(categoryIconFor('İçecekler'), categoryIconFor('İçecekler'));
    }
  });
}
