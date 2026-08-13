# 31 — Roadmap

> **Doküman sürümü:** v3 — **tüm kararlar kapandı, hiçbir faz bloke değil.**
> Recovery code ve genişletilmiş finansal erişim kilidi Faz 3'e eklendi.

## 1. Planlama ilkeleri

1. **Her faz çalışan bir şey bırakır.** Yarım kalan katman yok.
2. **Bağımlılık sırası önceliğin önündedir.** Satış ekranı en önemli ekran ama önce veri modeli gerekir.
3. **Riskli işler erken yapılır.** Migration ve backup, veri birikmeden önce doğrulanmalıdır.
4. **Her fazın Windows doğrulaması vardır** ([RSK-007](29-risks.md)).
5. ~~Açık kararlar fazı bloklar.~~ **Tüm kararlar kapandı; hiçbir faz bloke değil.**

---

## 2. Bağımlılık haritası

```text
Faz 0 (Kararlar) ✅ TAMAMLANDI
   ↓
Faz 1 (Temel) ──────────┐
   ↓                    │
Faz 2 (Veritabanı)      │   ← hiçbir faz açık karar tarafından bloke DEĞİL
   ↓                    │
Faz 3 (Ürün + Auth + Finansal erişim + Recovery) ─┤
   ↓                    │
Faz 4 (Barkod) ─────────┤
   ↓                    │
Faz 5 (SATIŞ) ◄─────────┘   ← ilk kullanılabilir sürüm burada
   ↓
Faz 6 (Stok + Audit)
   ↓
Faz 7 (İade/İptal)
   ↓
Faz 8 (Dashboard + Rapor)
   ↓
Faz 9 (Yedekleme) ← veri birikmeden önce mutlaka
   ↓
Faz 10 (Import/Export)
   ↓
Faz 11 (Test + Optimizasyon)
   ↓
Faz 12 (Windows Sürüm)
```

> **Faz 5 sonunda uygulama gerçek bir kantinde satış yapabilir hale gelir.**
> Faz 9'a kadar bunun **yedeklemesi yoktur** — Faz 5–8 arası gerçek kullanım önerilmez
> veya manuel dosya kopyalamayla desteklenmelidir.

---

## 3. Fazlar

### Faz 0 — ✅ TAMAMLANDI

| | |
|---|---|
| **Durum** | **Kapanmıştır.** Bekleyen karar yoktur. |
| **Çıktı** | 16 karar kapandı ([28 — Karar Kaydı](28-open-decisions.md)); v3 dokümantasyonu onaylandı |
| **Sonuç** | **Faz 1 doğrudan başlayabilir.** |

Kapanan kararlar: Drift+SQLite · Riverpod · salt'lı SHA-256 · KDV dahil · son alış fiyatı ·
integer miktar · indirim yok · nakit yuvarlama yok · CSV birincil · kasa/vardiya kapsam dışı ·
Türkçe + merkezî metin · ZIP yedek · Inno Setup · fl_chart · oturum kapsamlı kilit ·
1000px/JPEG85 yapılandırılabilir.

---

### Faz 1 — Temel altyapı

| | |
|---|---|
| **Amaç** | Uygulamanın iskeletinin kurulması |
| **Kapsam** | Proje yapısı ([03 §3](03-architecture.md))<br>Bağımlılıklar<br>Veri dizini çözümleme (Windows/macOS)<br>Single-instance lock<br>Loglama + hata yönetimi<br>Tema, router, temel navigasyon<br>**Riverpod kurulumu** + **merkezî Türkçe metin dosyası** (`app/l10n/app_strings_tr.dart`)<br>**`domain/` katmanı: Money, KDV (dahil formülü), hesaplama fonksiyonları + unit testleri**<br>Pencere durumu saklama |
| **Requirement** | ARCH-001…007, FIN-001…005/009, VAT-007/008, DATA-005/008, SEC-007, COMP-003, UX-006 |
| **Blokaj** | ✅ Yok |
| **Çıkış kriteri** | Uygulama açılıyor; `domain/` %100 test kapsamında; **KDV dahil formülü property testlerle doğrulanmış**; ikinci örnek engelleniyor; Windows'ta açılıyor |

---

### Faz 2 — Veritabanı

| | |
|---|---|
| **Amaç** | Kalıcılık katmanının kurulması |
| **Kapsam** | 15 tablonun şeması ([05 §2](05-database-architecture.md))<br>Index'ler<br>WAL + FULL + foreign_keys yapılandırması<br>Migration altyapısı ve v1 şeması<br>Seed (`Genel` kategorisi)<br>Repository/DAO iskeletleri<br>Repository testleri + migration test altyapısı |
| **Requirement** | DB-001…011, MIG-001…008, DATA-002, SEC-006, ARCH-004 |
| **Blokaj** | ✅ **Yok** — şema finaldir |
| **Çıkış kriteri** | 15 tablo oluşuyor, kısıtlar çalışıyor (barkod UNIQUE, tek aktif sepet, miktar > 0, ağırlık çifti), migration test altyapısı hazır, kritik sorgular index kullanıyor |

---

### Faz 3 — Ürün yönetimi, kimlik doğrulama ve finansal erişim

| | |
|---|---|
| **Amaç** | Satılacak veriyi girebilmek + erişim korumaları |
| **Kapsam** | Login + kurulum sihirbazı + oturum + kullanıcı yönetimi<br>**Parola hash'leme (salt'lı SHA-256)**<br>**Finansal erişim kilidi: belirleme, doğrulama, değiştirme, `FinancialAccessService`**<br>**Recovery code: üretim, gösterim, doğrulama, tek kullanımlık geçersizleştirme, yenileme**<br>Kategori CRUD (+ koşullu kalıcı silme)<br>Tedarikçi CRUD<br>KDV oranları yönetimi<br>**Ürün CRUD** (KDV dahil fiyat etiketi, satış birimi, net ağırlık)<br>Ürün silme/pasifleştirme ayrımı<br>Ürün listesi + arama + sayfalama<br>Barkod yönetimi (ürün formunda, çoklu barkod)<br>Görsel yükleme + optimizasyon<br>Favoriler |
| **Requirement** | AUTH-001…028, PROD-001…015, CAT-001…006, SUP-001…005, VAT-001/002/005, IMG-001…006/009/011, SEC-001/002, PERF-006, FIN-006, DASH-011/012, REP-014 |
| **Blokaj** | ✅ Yok |
| **Çıkış kriteri** | Kullanıcı giriş yapıp elle 50 ürün girebiliyor; barkodlar benzersiz; **veritabanında düz metin parola yok**; **parola olmadan Dashboard VE Raporlar rotaları açılmıyor**; **recovery code ile parola sıfırlanabiliyor ve kod tek kullanımlık**; görseller optimize ediliyor |
| **Not** | **En yüklü faz.** Alt fazlara bölünmesi önerilir: **3a** Auth + parola hash + finansal erişim kilidi + recovery code · **3b** Kategori/Tedarikçi/KDV · **3c** Ürün CRUD + barkod · **3d** Görsel + favori |

---

### Faz 4 — Barkod altyapısı

| | |
|---|---|
| **Amaç** | Scanner'ın güvenilir şekilde çalışması |
| **Kapsam** | HID klavye girişi işleyicisi (süre eşiği, buffer, `Enter` sonlandırıcı)<br>Barkod normalizasyonu ve checksum<br>Global/odaklı dinleme mantığı<br>Barkod tanılama ekranı<br>Widget testleri |
| **Requirement** | BARC-001/002/003/008/009/010/011 |
| **Blokaj** | Yok |
| **Çıkış kriteri** | **Gerçek scanner ile Windows'ta 50 ardışık okutma kayıpsız** (W1–W4); baştaki sıfırlar korunuyor; tanılama ekranı ham girdiyi gösteriyor |

---

### Faz 5 — Satış 🎯

| | |
|---|---|
| **Amaç** | Uygulamanın asıl işini yapması |
| **Kapsam** | Satış ekranı düzeni ([12 §1](12-sales-system.md))<br>Aktif sepet + kalıcılık + restore<br>Barkodla / aramayla / **kategori filtresiyle** / favoriyle / **barkodsuz tıklayarak** ekleme<br>Miktar (tam sayı) ve satır işlemleri<br>Satır fiyatı değiştirme (snapshot mantığı)<br>Stok uyarısı (negatif stok onay akışı)<br>Nakit hesaplama<br>**Atomik satış tamamlama + 5 snapshot alanı**<br>Satış numarası<br>Hızlı ürün ekleme (bilinmeyen barkod)<br>Klavye kısayolları ve odak yönetimi |
| **Requirement** | CART-001…009, SALE-001…012, BARC-004…007/012, STOCK-005, UX-001…005/010/014, PERF-001/002, DATA-001/003, FIN-007/008, VAT-003/004/009, AUTH-005/010 |
| **Blokaj** | ✅ Yok |
| **Çıkış kriteri** | Barkod → sepet → satış tamamlama faresiz çalışıyor; uygulama öldürülüp açıldığında sepet geri geliyor; transaction atomikliği testle kanıtlanmış; **5 snapshot alanının tamamı doğru yazılıyor**; **sepet toplamı = girilen fiyatların toplamı**; barkod→sepet < 100 ms |
| **Kilometre taşı** | ✅ **Uygulama gerçek satış yapabilir** |

---

### Faz 6 — Stok yönetimi ve audit log

| | |
|---|---|
| **Amaç** | Stoğun izlenebilir ve yönetilebilir olması |
| **Kapsam** | Stok girişi ekranı<br>Fire ve düzeltme (sebep zorunlu)<br>Stok hareket geçmişi<br>Kritik/negatif stok görünürlüğü<br>Tutarlılık kontrolü<br>**Audit log altyapısı ve tüm yazım noktaları**<br>Tedarikçi detay ekranı |
| **Requirement** | STOCK-001…012, AUDIT-001…007/012/013, DATA-006/007, DB-008, SUP-003, PROD-008, SALE-004 |
| **Blokaj** | Yok |
| **Çıkış kriteri** | Her stok değişimi defterde görünüyor; `stock_quantity` = defter toplamı (property test); audit log kritik işlemleri kaydediyor ve **hiçbir kayıtta parola bulunmuyor** |

---

### Faz 7 — İade, iptal ve satış geçmişi

| | |
|---|---|
| **Amaç** | Hataların düzeltilebilmesi |
| **Kapsam** | Satış geçmişi listesi + filtreler + detay<br>Satış iptali<br>Tam ve kısmi iade (`Return` / `ReturnItem`)<br>Durum makinesi<br>Stok geri yazma |
| **Requirement** | RET-001…008/010/012, SALE-010, STOCK-006 |
| **Blokaj** | Yok |
| **Çıkış kriteri** | Kısmi iade sonrası durum doğru; iade tutarı snapshot fiyattan hesaplanıyor; iade edilmiş satış iptal edilemiyor; tüm işlemler atomik |

---

### Faz 8 — Dashboard ve raporlar

| | |
|---|---|
| **Amaç** | Verinin karara dönüşmesi |
| **Kapsam** | **Finansal erişim kapısının Dashboard ve Raporlar'a bağlanması** (servis Faz 3'te hazır)<br>Dashboard (KPI, grafikler, tarih aralıkları)<br>12 rapor<br>CSV dışa aktarma<br>Rapor altyapısı (filtre, sıralama, sayfalama) |
| **Requirement** | DASH-001…013, REP-001…013, RET-009/011, VAT-006, AUDIT-008…010, PERF-004/007, SEC-005, IMEX-014 |
| **Blokaj** | ✅ Yok |
| **Çıkış kriteri** | Dashboard 100k satırlık veriyle < 1 sn; **parola girilmeden hiçbir dashboard/rapor sorgusu çalışmıyor**; net ciro iptal/iadeleri doğru düşüyor; kâr KDV hariç matrahtan hesaplanıyor; CSV Türkçe Excel'de doğru açılıyor |

---

### Faz 9 — Yedekleme ve geri yükleme ⚠️

| | |
|---|---|
| **Amaç** | Verinin korunması |
| **Kapsam** | Yedek oluşturma (tutarlı DB snapshot'ı, tek dosya, checksum, metadata)<br>Doğrulama<br>Geri yükleme protokolü<br>Güvenlik yedeği + kurtarma<br>Yedek hatırlatması<br>Otomatik günlük yedek<br>Görsel bakım / orphan taraması |
| **Requirement** | BKUP-001…020, IMG-007/008/010/012, DATA-004, SEC-003/004 |
| **Blokaj** | ✅ Yok |
| **Çıkış kriteri** | Bozuk yedek reddediliyor; restore ortasında kesinti sonrası veri kurtarılıyor; yedek başka makinede açılıyor; **yedek içinde düz metin parola bulunmuyor**; restore sonrası dashboard kilidi kapanıyor |
| **Uyarı** | **Bu faz ertelenmemelidir.** Gerçek kullanım Faz 5'ten sonra başlayabilir; yedeksiz geçen her gün risktir ([RSK-005](29-risks.md)). Gerekirse Faz 6'dan sonraya çekilmelidir. |

---

### Faz 10 — Import / Export

| | |
|---|---|
| **Amaç** | Toplu veri girişi |
| **Kapsam** | Şablon indirme<br>CSV/Excel okuma<br>Sütun eşleştirme<br>Validasyon + önizleme<br>**Barkod çakışma politikaları (BR-IMEX-001/002)**<br>Atomik import<br>Sayım import'u<br>Tüm export'lar |
| **Requirement** | IMEX-001…013/015/016 |
| **Blokaj** | ✅ Yok |
| **Çıkış kriteri** | 1.000 satırlık dosya < 10 sn; export→import round-trip veri kaybetmiyor; dosya içi duplicate barkodlar reddediliyor; hata durumunda tam rollback |

---

### Faz 11 — Test, optimizasyon, sağlamlaştırma

| | |
|---|---|
| **Amaç** | Kalite kapısı |
| **Kapsam** | Test boşluklarının kapatılması<br>Performans testleri (5. yıl veri hacmi)<br>Edge-case doğrulaması ([26](26-edge-cases.md))<br>Bellek profilleme<br>Hata mesajlarının gözden geçirilmesi<br>Boş durumların tamamlanması<br>Kaos testleri (kesinti, disk dolu, bozuk dosya) |
| **Requirement** | PERF-003/005, UX-007…013, kalan tüm test kapsamı |
| **Blokaj** | Yok |
| **Çıkış kriteri** | Tüm 🔴 Must requirement'lar test edilmiş; performans eşikleri sağlanmış; `flutter analyze` temiz |

---

### Faz 12 — Windows sürümü

| | |
|---|---|
| **Amaç** | Kullanıcının bilgisayarına kurulabilmesi |
| **Kapsam** | Release derlemesi<br>Installer<br>Veri dizini doğrulaması<br>Güncelleme testi (v1.0.0 → v1.0.1)<br>DPI ve çözünürlük testleri<br>Uygulama ikonu, sürüm bilgisi<br>Kısa kullanım kılavuzu |
| **Requirement** | COMP-001…004 |
| **Blokaj** | ✅ Yok |
| **Çıkış kriteri** | Temiz Windows makinede kurulum çalışıyor; veri `%APPDATA%`'da; güncelleme veri kaybetmiyor (W5, W6); manuel test listesi W1–W15 tamamlanmış |
| **Kilometre taşı** | 🚀 **v1.0.0** |

---

## 4. Faz yükü dağılımı

| Faz | Requirement | Göreli büyüklük | Blokaj | Risk |
|---|---|---|---|---|
| 0 | — | — | ✅ tamamlandı | 🟢 |
| 1 | 18 | ▪▪ | ✅ yok | 🟢 |
| 2 | 21 | ▪▪▪ | ✅ yok | 🟡 Migration altyapısı |
| 3 | **69** | ▪▪▪▪▪▪▪▪ | ✅ yok | 🟡 **En yüklü — bölünmeli** |
| 4 | 7 | ▪▪ | ✅ yok | 🔴 Donanım bağımlı |
| 5 | 45 | ▪▪▪▪▪▪ | ✅ yok | 🔴 **En kritik — atomiklik** |
| 6 | 23 | ▪▪▪▪ | ✅ yok | 🟡 |
| 7 | 12 | ▪▪▪ | ✅ yok | 🟡 |
| 8 | 33 | ▪▪▪▪▪ | ✅ yok | 🟡 Performans |
| 9 | 27 | ▪▪▪▪ | ✅ yok | 🔴 **Veri kaybı riski** |
| 10 | 15 | ▪▪▪ | ✅ yok | 🟢 |
| 11 | 11 | ▪▪▪ | ✅ yok | 🟢 |
| 12 | 3 | ▪▪ | ✅ yok | 🟡 Platform sürprizleri |
| | **285** | | | |

> Takvim tahmini bilinçli olarak verilmemiştir — geliştirme kapasitesi bilinmiyor.
> Göreli büyüklükler planlama için kullanılabilir.

---

## 5. Kullanıcıya doğrulatılacak kalan sorular

> ✅ **Karar gerektiren soru kalmamıştır.** Önceki 12 sorunun tamamı yanıtlandı.

Aşağıdakiler karar değil, **geliştirme sırasında doğal olarak netleşecek operasyonel bilgilerdir**;
hiçbiri bir fazı bloke etmez:

| Konu | Ne zaman gerekir | Neden bloke etmez |
|---|---|---|
| Yaklaşık ürün sayısı ve günlük satış hacmi | Faz 11 (performans testi) | Mimari zaten 10.000+ ürün hedefine göre tasarlandı (REQ-PERF-008) |
| Mevcut ürün listesinin Excel'de olup olmadığı | Faz 10 | CSV birincil format; şablon indirme zaten var |
| Barkod okuyucu modeli | Faz 4 (donanım testi) | HID klavye emülasyonu destekleyen her cihaz çalışır; markaya bağımlılık yok |

---

## 6. Sürüm planı

| Sürüm | İçerik |
|---|---|
| **v1.0.0** | Faz 1–12; tüm 🔴 Must + çoğu 🟡 Should |
| v1.1.0 | Kalan 🟢 Could; kullanıcı geri bildirimleri |
| v1.2.0 | Fiş yazdırma veya indirim sistemi (kullanıcı önceliğine göre) |
| v2.0.0 | Yalnızca gerçek ihtiyaç doğarsa — kasa/vardiya, rol sistemi, tartılı satış veya backend |
