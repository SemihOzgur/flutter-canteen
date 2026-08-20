# 32 — Elle Test Borcu ve Bilinçli Test Boşlukları

> **Bu doküman bir source of truth DEĞİLDİR.** Business kuralı içermez, hiçbir
> kararı değiştirmez. Otomatik testin **kapsayamadığı** ya da bilinçli olarak
> **kapsamadığı** her şeyin tek listesidir.
>
> **Amaç:** uygulama tamamlandığında (Faz 12) buradaki her satır tek tek
> yürütülür. Hiçbir madde "muhtemelen çalışıyordur" diye kapatılmaz.

---

## 1. Nasıl okunur

| İşaret | Anlamı |
|---|---|
| ⬜ | Henüz yapılmadı |
| ✅ | Yapıldı ve geçti |
| 🚫 | Otomatik test **edilemez** — sebebi yazılıdır |
| ⚠️ | Kapsam dışı bırakıldı — karar bekliyor |

Her maddede **neden otomatik test edilmediği** yazılıdır. Sebebi olmayan bir
madde bu listeye girmez; "unuttum" ile "edilemez" aynı yere yazılmaz.

---

## 2. Durum özeti

| Faz | Konu | Otomatik | Elle test |
|---|---|---|---|
| 1–2 | Altyapı, veritabanı | ✅ | ✅ (kullanıcı doğruladı) |
| 3 | Ürün, auth, finansal kilit | ✅ | ✅ (kullanıcı doğruladı) |
| 4 | Barkod | ✅ | ⬜ **donanım gerekiyor** |
| 5 | Satış | ✅ | ⬜ |
| 6 | Stok + audit | ✅ | ⬜ |
| 7 | İade, iptal, satış geçmişi | ✅ | ⬜ |
| 9 | Yedekleme ve geri yükleme | ✅ | ⬜ |
| 8 | Dashboard | ✅ | ⬜ |
| 10–12 | Import, optimizasyon, Windows | — | — |

---

## 3. Faz 5 — Satış ekranı

> Ön koşul: en az üç ürün — biri **barkodlu**, biri **favori**, biri **stoğu 0**.

| # | Senaryo | Beklenen | Kural |
|---|---|---|---|
| A1 | ⬜ Barkod okut | Ürün **ara onay olmadan** sepete girer | REQ-BARC-004 |
| A2 | ⬜ Aynı barkodu tekrar okut | Yeni satır açılmaz, miktar artar | REQ-BARC-005 |
| A3 | ⬜ Kayıtlı olmayan barkod okut | Hızlı ürün dialogu; barkod **dolu ve salt okunur**; kaydet → **otomatik sepete** | REQ-BARC-006/007 |
| A4 | ⬜ Ürün kartına / favoriye tıkla, `Alt+1` | Sepete girer | REQ-CART-009 · REQ-BARC-012 |
| A5 | ⬜ **Sepet satırına tıkla, sonra yazmaya başla** | Odak arama kutusuna döner, **ilk karakter kaybolmaz** | REQ-UX-002/003 |
| A6 | ⬜ Stoğu 0 olan ürün ekle | Uyarı çıkar; `Devam Et` satar, `İptal`/`Esc` eklemez | BR-STOCK-006 |
| A7 | ⬜ `F2` ile satır fiyatını değiştir | Satır fiyatı değişir, rozet çıkar, **ürünün fiyatı değişmez** | BR-SALE-003 |
| A8 | ⬜ `F4` → toplamdan az tutar gir | `Tamamla` **pasif** kalır | BR-SALE-008 |
| A9 | ⬜ `F12` | Fiş no görünür, sepet boşalır, **odak aramaya döner** | REQ-SALE-006 |
| A10 | ⬜ `Ctrl+Del` · `F1` · `F3` | Onay sorar · kısayol listesi · Ürünler açılır | REQ-UX-009/010 |
| A11 | ⬜ Sepet doluyken uygulamayı **kapat-aç** | Sepet aynen geri gelir | REQ-CART-003 |

**En kritik: A1, A5, A9.** Üçü birlikte REQ-UX-001'in *"3 ürünlük satış,
faresiz, 10 saniyeden kısa"* hedefini oluşturur ve ancak elle ölçülebilir.

---

## 4. Faz 6 — Stok ve audit

> Ana ekran → **Stok**

| # | Senaryo | Beklenen | Kural |
|---|---|---|---|
| B1 | ⬜ Stok ekranını aç | Negatif ve kritik stok listeleri görünür | docs/13 §7 |
| B2 | ⬜ `minimum stok = 0` olan ürün | Kritik listede **görünmez** | REQ-STOCK-011 |
| B3 | ⬜ Aramadan **normal stoklu** ürün bul | Fire/Düzeltme düğmeleri gelir | docs/13 §6 |
| B4 | ⬜ Fire → sebep **boş** → Kaydet | Reddedilir | BR-STOCK-010 |
| B5 | ⬜ Fire → hazır sebep seç → Kaydet | Stok düşer | REQ-STOCK-009 |
| B6 | ⬜ Düzeltme → sayım sonucu gir | Stok o değere gelir | REQ-DATA-007 |
| B7 | ⬜ Stok Girişi → aynı ürünü iki kez ekle | Miktar artar | docs/13 §5 |
| B8 | ⬜ Girişte alış fiyatını değiştir | *"Ürünün alış fiyatı da güncellensin mi?"* sorulur | BR-STOCK-009 |
| B9 | ⬜ B8'de **`Esc`** bas | Ürünün fiyatı **değişmez**; giriş yine yeni fiyatla kaydolur | REQ-STOCK-008 |
| B10 | ⬜ Girişi Kaydet | Stok artar, toplam doğru | REQ-STOCK-007 |
| B11 | ⬜ Geçmiş (saat ikonu) | Hareketler listelenir; **Düzenle/Sil yok** | REQ-STOCK-003 |
| B12 | ⬜ Bir harekette geri-ok → sebep gir | Ters kayıt oluşur, **orijinal durur** | docs/13 §10 |
| B13 | ⬜ Ana ekran → Veri Tutarlılığı Kontrolü → Çalıştır | *"Sapma bulunamadı"* | REQ-STOCK-012 |
| B14 | ⬜ Ayarlar → Tedarikçiler → satıra tıkla | Ürünleri + stok girişleri görünür | REQ-SUP-003 |
| B15 | ⬜ Ürün listesi | Kritik/negatif stoklu ürünlerde ⚠ ikon + rozet metni | docs/13 §7 |

---

## 5. Faz 7 — İade, iptal, satış geçmişi

> Ana ekran → **Satış Geçmişi**

| # | Senaryo | Beklenen | Kural |
|---|---|---|---|
| E1 | ⬜ Geçmişi aç | Satışlar listelenir | REQ-SALE-010 |
| E2 | ⬜ Fiş numarasıyla ara | Filtrelenir | REQ-SALE-010 |
| E3 | ⬜ Durum filtresi | Yalnızca o durumdakiler | REQ-SALE-010 |
| E4 | ⬜ Satışa tıkla | Detay; satırlar **satış anındaki** ad ve fiyatla | REQ-SALE-003 |
| E5 | ⬜ Satışı İptal Et → sebep **boş** | Reddedilir | docs/14 §3 |
| E6 | ⬜ Sebep gir → iptal et | Stok geri döner, satış listede **kalır** | REQ-RET-002 · BR-GEN-002 |
| E7 | ⬜ Başka satışta İade Oluştur | Miktar `+` **kalanla sınırlı**, tutar canlı | BR-RET-003/005 |
| E8 | ⬜ Kısmi iade kaydet | Durum *"Kısmen iade edildi"* | REQ-RET-007 |
| E9 | ⬜ Aynı satışa bak | **İptal düğmesi artık pasif** | BR-RET-001 |
| E10 | ⬜ Kalanı da iade et | *"İade edildi"*, iki düğme de pasif | REQ-RET-007 |

---

## 6. Faz 9 — Yedekleme ve geri yükleme

> Ana ekran → **Yedekleme**

| # | Senaryo | Beklenen | Kural |
|---|---|---|---|
| D1 | ⬜ Yedek Oluştur | Dosya oluşur, listede boyutuyla görünür | REQ-BKUP-001 |
| D2 | ⬜ Bir yedekte Geri Yükle | Karşılaştırmalı özet gelir | REQ-BKUP-007 |
| D3 | ⬜ Yanlış onay metni yaz | Düğme **pasif** | REQ-BKUP-008 |
| D4 | ⬜ `GERİ YÜKLE` yaz | Düğme etkinleşir | REQ-BKUP-008 |
| D5 | ⬜ **`Esc`** bas | Geri yükleme **başlamaz** | REQ-BKUP-008 |
| D6 | ⬜ Yedeği bir editörle **boz**, geri yüklemeyi dene | *"Yedek dosyası bozulmuş"*; özet ekranı **hiç açılmaz** | REQ-BKUP-006 |
| D7 | ⬜ 7 gün yedeksiz bırak (veya sistem saatini ileri al) | Satış ekranı üstünde sarı çubuk | REQ-BKUP-016 |
| D8 | ⬜ Geri yüklemeyi **tamamla**, uygulamayı yeniden başlat | Login ekranı gelir; satış sayacı yedektekine çekilmiş | REQ-BKUP-015/020 |
| D9 | ⬜ Yedeği **başka bir makinede** aç | Geri yükleme çalışır | docs/31 Faz 9 çıkış kriteri |
| D10 | ⬜ Yedeği bir arşiv programıyla aç | `metadata.json` · `database.sqlite` · `checksums.json` · `images/` | docs/19 §2 |

---

## 6b. Faz 8 — Dashboard

> Ana ekran → **Dashboard** (finansal erişim parolası sorulur)

| # | Senaryo | Beklenen | Kural |
|---|---|---|---|
| G1 | ⬜ Dashboard'a bas, **Vazgeç** de | Ekran **hiç açılmaz** | EC-DASH-003 |
| G2 | ⬜ Parolayı gir | Dashboard açılır, KPI'lar dolar | BR-AUTH-013 |
| G3 | ⬜ Raporlar'a geç (Faz 8c) | Parola **tekrar sorulmaz** | BR-AUTH-016 |
| G4 | ⬜ Çıkış yap, tekrar gir, Dashboard'a bas | Parola **yeniden sorulur** | REQ-AUTH-021 |
| G5 | ⬜ Dönem düğmelerini değiştir | Rakamlar yeniden hesaplanır | docs/15 §2 |
| G6 | ⬜ Bir satışı iade et, Dashboard'a dön | Net ciro düşer, ayrıntıda iade görünür | BR-RET-007 |
| G7 | ⬜ Bir satışı iptal et | Net ciro düşer; **brüt aynı kalır** | OD-028 |
| G8 | ⬜ KDV oranı tanımlı bir ürün sat | Kâr **KDV hariç** matrahtan; brüt cirodan değil | REQ-VAT-009 |
| G9 | ⬜ 100.000 satış satırıyla aç | **< 1 saniye** | docs/15 §5 |
| G10 | ⬜ Raporlar → CSV Olarak Kaydet → dosyayı **Türkçe Excel'de aç** | Sütunlar ayrı, Türkçe karakterler bozulmamış | rules/03 §7 |
| G11 | ⬜ Adı `=1+1` olan bir ürün oluştur, sat, raporu dışa aktar, Excel'de aç | Hücre **metin** olarak görünür, hesaplanmaz | REQ-SEC-005 |

> **G9 elle ölçülmelidir.** Otomatik testlerde 10.000 ürünle veri yolu ölçüldü
> (16 ms) ama dashboard'un 100k satırlık gerçek yükü ve ekran boyaması
> ölçülmedi.

---

## 7. Windows'a özgü — W1…W15 · RSK-018

> **Faz 4'ten beri birikiyor.** macOS'ta çalışan bir şeyin Windows'ta
> çalıştığı **varsayılamaz** (rules/05 §6). Bu bölüm Faz 12'nin çıkış
> kriteridir.

| # | Senaryo | Neden macOS'ta yapılamaz |
|---|---|---|
| W1 | ⬜ Gerçek scanner ile **50 ardışık okutma, kayıpsız** | Donanım |
| W2 | ⬜ Bluetooth scanner | Donanım |
| W3 | ⬜ **Türkçe Q/F klavye** düzeninde alfanümerik barkod | RSK-006 — `ı` tuşu Caps Lock'ta `I` üretir |
| W4 | ⬜ Scanner + form alanı etkileşimi | Donanım |
| W5 | ⬜ v1.0.0 → v1.0.1 güncellemesi veri kaybetmiyor | Installer |
| W6 | ⬜ Veri `%APPDATA%`'da, kurulum dizininde **değil** | Platform yolu |
| W7 | ⬜ DPI %100 / %125 / %150 | Platform |
| W8 | ⬜ 1366×768 ve 1920×1080'de tam işlevsel | Fiziksel ekran |
| W9 | ⬜ Satış sırasında **elektrik kesintisi** | Fiziksel |
| W10 | ⬜ Disk dolu senaryosu | Fiziksel |
| W11 | ⬜ **İkinci uygulama örneği reddediliyor** | POSIX `flock` **süreç** bazlı, Windows `LockFile` **handle** bazlıdır — tek süreçte kanıtlanamaz |
| W12 | ⬜ **Restore sırasında dosya kilitleme** | Windows Unix'ten katıdır: açık DB dosyası taşınamaz. Yedekleme için **kritik** |
| W13 | ⬜ 260 karakter yol sınırı | Platform |
| W14 | ⬜ Antivirüs `.canteenbackup` dosyasını engellemiyor | Platform |
| W15 | ⬜ Türkçe karakterli / boşluklu kullanıcı adı | Kısmen otomatikleştirildi — bkz. §9 |

### Faz 8 — ortam bağımlı

| # | Senaryo | Neden |
|---|---|---|
| F1 | ⬜ Sistem saatini **UTC olmayan** bir dilime alıp gece yarısına yakın (00:30 / 23:30) satış yap, dashboard'da "Bugün" doğru mu? | UTC makinede otomatik test kayma üretemez (BR-GEN-004) |

---

## 8. 🚫 Otomatik test EDİLEMEYENLER — sebepleriyle

Bunlar unutulmuş değil; test altyapısının **yapısal olarak** kapsayamadığı
şeylerdir. Her biri yukarıdaki elle test maddelerine bağlıdır.

| Konu | Neden edilemez | Nereye bağlı |
|---|---|---|
| Barkod karakterlerinin **metin alanına ulaşması** | Widget testinde `sendKeyEvent` metni `TextField`'a taşımaz; gerçek metin girişi platform kanalından gelir | W1 · W3 |
| **İkinci uygulama örneği** reddi | POSIX `flock` aynı süreçten alınan ikinci kilidi **kabul eder**; Windows reddeder. Test yalnızca "kilit alındı + PID yazıldı" kanıtlayabilir | W11 |
| **Yedek oluşturma / geri yükleme** widget testinde | `testWidgets`'in sahte zamanı gerçek dosya I/O'sunu ilerletmez; `tester.tap` + `runAsync` kilitlenir. **Servis katmanında 42 testle** ve gerçek dosya tabanlı veritabanıyla kapsanır | D1 · D8 |
| Barkod → sepet süresinin **uçtan uca** ölçümü | Ölçülen 16 ms **veri yoludur**; ekran boyaması ve scanner gecikmesi dahil değildir | W1 |
| `%APPDATA%` çözümlemesi ve 260 karakter sınırı | Platforma özgü | W6 · W13 |
| Golden (piksel) testleri | docs/27 §4 **yazılmayacağını** söyler — bilinçli karar | — |
| **Yerel gün sınırının UTC'den ayrıştığı** durum | Test makinesi **UTC saat diliminde** ise kayma diye bir şey oluşmaz ve testin ayırt edici gücü yoktur. Geliştirme makinesinde (`+03:00`) doğrulandı; CI UTC'de çalışırsa bu test sessizce güçsüzleşir | F1 |

---

## 9. Otomatikleştirilebilen kısımlar — yapıldı

Windows borcunun bir kısmı platformdan bağımsızdı ve otomatikleştirildi
(`test/core/platform_path_safety_test.dart`, 16 test):

- ✅ Türkçe karakterli ve boşluklu kök dizinlerde tüm klasörler oluşuyor
- ✅ Aynı yollarda **veritabanı açılıp yazılabiliyor** (`Şule Öztürk`,
  `çğıöşü ÇĞİÖŞÜ`, `O'Brien`, `a.b c.d`)
- ✅ Türetilen her yol kök dizinin **içinde** kalıyor (BR-DATA-001)
- ✅ Yollar elle string birleştirmiyor
- ✅ Kilit dosyasına PID yazılıyor (stale lock temizliğinin ön koşulu)

Kalan kısım (`%APPDATA%`, 260 karakter, gerçek çapraz-süreç kilit) W6/W11/W13
olarak durur.

---

## 10. ⚠️ Kapsam dışı bırakılanlar — karar bekliyor

Bunlar **hata değildir**: dokümanda geçtikleri hâlde bağlayıcı bir REQ'leri ve
acceptance criteria'ları yoktur. `rules/06 §6` gereği kapsam genişletme kararı
proje sahibinindir.

| Konu | Nerede geçiyor | Neden yapılmadı |
|---|---|---|
| `Ctrl+Z` — son sepet işlemini geri al | docs/23 §2 · docs/12 §3 kısayol tabloları | REQ'i yok; 10 adımlık geri alma yığını ister |
| `*` + sayı + `Enter` — miktarı doğrudan gir | docs/23 §2 · docs/12 §3 | REQ'i yok |
| `cartTakenOver` — aktif sepet varken farklı kullanıcı girişi | REQ-AUTH-010 (🟢 Could) | 🟢 Could; `AuditActions.futurePhaseActions` içinde kayıtlı |
| `migrationApplied` audit kaydı | docs/18 §3 | Şema v1'den başka sürüm yok; yazım noktası ilk v2 adımıyla eklenecek — bugün eklense **asla tetiklenmeyen ölü kod** olurdu (rules/06 §7) |
| Windows CI (`windows-latest`) | — | RSK-018'de öneri olarak duruyor; karar verilmedi |

---

## 11. Faz 12 kapanış kuralı

```text
Bu dokümandaki her ⬜ madde ✅ olmadan v1.0.0 yayınlanmaz.
```

🚫 maddeleri kapanmaz — onlar zaten bir elle test maddesine bağlıdır ve o
madde kapandığında kapsanmış sayılırlar.

⚠️ maddeleri ya kapsama alınır (docs/25'e REQ eklenerek) ya da
[30-future-scope.md](30-future-scope.md)'ye taşınır. Belirsiz bırakılmaz.
