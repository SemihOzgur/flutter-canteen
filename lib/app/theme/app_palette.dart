/// Uygulama paleti — **tek kaynak.**
///
/// Renkler burada toplanır çünkü aynı kategori dashboard'daki donut'ta,
/// yanındaki tabloda ve rapor ekranında **aynı** renkte görünmelidir.
/// Her ekran kendi rengini seçseydi, kullanıcı "mavi olan hangisiydi?"
/// diye tabloya bakmak zorunda kalırdı ve grafik iş görmezdi.
///
/// ## Renk tek başına anlam taşımaz
///
/// rules/05 §5: *"Renkle iletilen her durum ikon veya metinle de ifade
/// edilir."* Buradaki renkler **vurgudur**, bilgi taşıyıcısı değil —
/// kritik stok kartı kırmızı olduğu için değil, üzerinde "Kritik Stok"
/// yazdığı için anlaşılır.
///
/// Kontrast oranı en az 4.5:1 (rules/05 §7): koyu tonlar metin ve ikon
/// için, `container` tonları zemin için kullanılır.
library;

import 'package:flutter/material.dart';

/// Bir vurgu rengi ve onun sakin zemin karşılığı.
class AccentColor {
  /// Metin, ikon ve grafik çizgisi rengi — zemin üzerinde okunur.
  final Color foreground;

  /// Kart/rozet zemini — üzerine [foreground] yazılır.
  final Color background;

  const AccentColor(this.foreground, this.background);
}

abstract final class AppPalette {
  /// docs/15 §3.6 — kategori donut'u ve yanındaki tablo.
  ///
  /// Sekiz renk, docs/15'in "ilk 7 + Diğer" kuralına birebir yeter.
  /// Sıra sabittir: aynı kategori her açılışta aynı rengi alır.
  static const List<Color> categorical = [
    Color(0xFF1565C0), // mavi
    Color(0xFF2E7D32), // yeşil
    Color(0xFFEF6C00), // turuncu
    Color(0xFF6A1B9A), // mor
    Color(0xFF00838F), // turkuaz
    Color(0xFFC62828), // kırmızı
    Color(0xFF558B2F), // fıstık
    Color(0xFF4E342E), // kahve
  ];

  /// "Diğer" dilimi — gri kalır ki gerçek kategorilerle karışmasın.
  static const Color other = Color(0xFF757575);

  /// [index]'inci kategorinin rengi; liste dolarsa başa döner.
  static Color categoryColor(int index) =>
      categorical[index % categorical.length];

  // ── KPI vurguları (docs/15 §3.1) ────────────────────────────────────────
  static const AccentColor revenue = AccentColor(
    Color(0xFF0D47A1),
    Color(0xFFE3F2FD),
  );
  static const AccentColor profit = AccentColor(
    Color(0xFF1B5E20),
    Color(0xFFE8F5E9),
  );
  static const AccentColor saleCount = AccentColor(
    Color(0xFF4A148C),
    Color(0xFFF3E5F5),
  );
  static const AccentColor unitCount = AccentColor(
    Color(0xFF006064),
    Color(0xFFE0F7FA),
  );

  /// Kritik stok — dikkat ister ama hata değildir.
  static const AccentColor warning = AccentColor(
    Color(0xFFE65100),
    Color(0xFFFFF3E0),
  );

  /// Negatif stok — bir tutarsızlığa işaret eder.
  static const AccentColor danger = AccentColor(
    Color(0xFFB71C1C),
    Color(0xFFFFEBEE),
  );

  /// Sayı `0` iken kart **sakin** görünür (docs/15 §3.1) — dikkat çekmez.
  static const AccentColor calm = AccentColor(
    Color(0xFF37474F),
    Color(0xFFECEFF1),
  );

  // ── Ana ekran kutuları ──────────────────────────────────────────────────
  /// Ana ekrandaki eylem kutuları — **dolu renk, beyaz metin.**
  ///
  /// Hepsi Material 900 tonudur ve beyaz metinle kontrast oranı 4.5:1'in
  /// üzerindedir (rules/05 §7). Daha açık tonlar (600–700) daha canlı
  /// görünürdü ama beyaz metin okunmaz hâle gelirdi; kasa ekranı okunmak
  /// zorundadır.
  static const List<AccentColor> tiles = [
    AccentColor(Colors.white, Color(0xFF0D47A1)), // mavi
    AccentColor(Colors.white, Color(0xFF1B5E20)), // yeşil
    AccentColor(Colors.white, Color(0xFFBF360C)), // turuncu
    AccentColor(Colors.white, Color(0xFF4A148C)), // mor
    AccentColor(Colors.white, Color(0xFF006064)), // turkuaz
    AccentColor(Colors.white, Color(0xFFB71C1C)), // kırmızı
    AccentColor(Colors.white, Color(0xFF33691E)), // fıstık
    AccentColor(Colors.white, Color(0xFF3E2723)), // kahve
  ];
}
