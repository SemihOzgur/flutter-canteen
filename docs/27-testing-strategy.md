# 27 — Test Stratejisi

> **Doküman sürümü:** v3 — finansal erişim kilidi ve recovery code testleri; 10.000 ürünlük stres verisi.

> Bu doküman test **planıdır.** Test kodu bu aşamada yazılmaz.

## 1. Test felsefesi

Bu projede test yazmanın amacı kapsama yüzdesi değil, **para ve stok verisinin doğruluğunu garanti etmektir.**

Test yatırımının dağılımı, hatanın maliyetine göre belirlenir:

| Alan | Hatanın maliyeti | Test yatırımı |
|---|---|---|
| Para hesaplamaları | Kalıcı, yanlış finansal kayıt | 🔴 Çok yüksek |
| **KDV çıkarımı (dahil fiyattan)** | Yanlış matrah → yanlış kâr ve KDV beyanı | 🔴 Çok yüksek |
| **Snapshot alanları (5 adet)** | Geçmiş raporlar sessizce değişir | 🔴 Çok yüksek |
| Stok defteri | Sessizce yanlış stok; fark edilmesi haftalar sürer | 🔴 Çok yüksek |
| Satış transaction atomikliği | Yarım satış = kurtarılamaz veri | 🔴 Çok yüksek |
| İade/iptal mantığı | Yanlış ciro ve stok | 🔴 Çok yüksek |
| Backup/restore | Tüm verinin kaybı | 🔴 Çok yüksek |
| Migration | Tüm verinin kaybı | 🔴 Çok yüksek |
| Import validasyonu | Kirli veri | 🟡 Orta |
| Barkod input handler | Satış akışının kırılması | 🟡 Orta |
| Rapor sorguları | Yanlış karar | 🟡 Orta |
| UI düzeni | Rahatsızlık | 🟢 Düşük |
| Tema/renk | Yok | ⚪ Test edilmez |

---

## 2. Test piramidi

```text
              ╱╲          Manuel / Windows doğrulama
             ╱  ╲         (donanım, installer, DPI, klavye)
            ╱────╲
           ╱      ╲       Integration testi (~40)
          ╱        ╲      satış akışı, backup/restore, import, migration
         ╱──────────╲
        ╱            ╲    Repository / DB testi (~80)
       ╱              ╲   gerçek in-memory SQLite üzerinde
      ╱────────────────╲
     ╱                  ╲ Unit testi (~250)
    ╱                    ╲ para, KDV, stok hesabı, validasyon, kâr
   ╱──────────────────────╲
```

Widget testleri piramidin dışındadır ve **seçici** yazılır (§5).

---

## 3. Unit testler (domain katmanı)

Bağımlılıksız, hızlı, çok sayıda. Hedef: `domain/` katmanının **%100'ü.**

### 3.1 Para (`Money`)

| Test | Örnek |
|---|---|
| Metinden kuruşa çevirme | `"25,50"` → `2550`, `"25.50"` → `2550`, `"25"` → `2500`, `"₺1.234,56"` → `123456` |
| Geçersiz girdi | `"abc"`, `""`, `"25,5,5"` → hata |
| Formatlama | `2550` → `"₺25,50"`, `0` → `"₺0,00"`, `123400` → `"₺1.234,00"` |
| Half-up yuvarlama | `.5` daima yukarı; negatif değerlerde tutarlı |
| Taşma | Çok büyük değerlerde davranış |

### 3.2 KDV — **fiyat KDV dahil** (BR-VAT-003)

| Test |
|---|
| KDV çıkarma: `12000` @ 2000 bp → KDV `2000`, net `10000` |
| KDV çıkarma: `10000` @ 2000 bp → KDV `1667`, net `8333` |
| `0` bp → KDV `0`, net = brüt |
| Yuvarlama sınır durumları (`1`, `3`, `7` kuruşluk tutarlar) |
| **`net + kdv == brüt` invariant'ı** (property test, 10.000 rastgele tutar × oran) |
| **Regresyon koruması:** KDV'nin fiyatın *üzerine eklenmediğini* doğrulayan açık test |
| Farklı KDV oranlı satırların bir arada olduğu sepet toplamı |

### 3.3 Sepet hesabı

| Test |
|---|
| Satır toplamı = birim × miktar |
| Sepet toplamı = satır toplamları (kuruş sapması yok) |
| Fiyat override toplamı doğru etkiler |
| Boş sepet toplamı `0` |
| 200 satırlık sepet doğruluğu |

### 3.4 Stok defteri

| Test |
|---|
| Hareket dizisi → beklenen stok (senaryo tabloları) |
| `resulting_stock` her adımda doğru |
| Negatif sonuç izin verilir |
| Sıfır delta reddedilir |
| **Property test:** rastgele 1.000 hareket → `Σdelta == son stok` |

### 3.5 Kâr

| Test |
|---|
| **Kâr = KDV hariç matrah − maliyet** (BR-FIN-004, REQ-VAT-009) |
| Ürün satış fiyatı sonradan değişince geçmiş kâr değişmez |
| **Ürün alış fiyatı sonradan değişince geçmiş kâr değişmez** (maliyet snapshot'ı) |
| **KDV oranı sonradan değişince geçmiş kâr ve KDV değişmez** |
| İade sonrası net kâr doğru |
| Fire maliyeti kâra yansır |
| Alış fiyatı `0` olan ürün (kâr = matrahın tamamı) |

### 3.6 Parola hash'leme

| Test |
|---|
| Aynı parola + farklı salt → farklı hash |
| Doğru parola doğrulanır, yanlış parola reddedilir |
| **Hiçbir kod yolunda düz metin parola saklanmıyor** (kod taraması + DB kontrolü) |
| Dashboard parolası ile kullanıcı parolası birbirinden bağımsız doğrulanır |

### 3.7 Diğer

- Satış durumu hesaplama (`completed` / `partiallyReturned` / `returned`)
- Barkod normalizasyonu ve checksum
- Ürün validasyon kuralları
- Türkçe karakter duyarsız arama normalizasyonu
- Tarih aralığı hesaplama (bugün/bu hafta/bu ay, yerel saat, yaz saati)

---

## 4. Repository / veritabanı testleri

Gerçek SQLite (in-memory) üzerinde çalışır. Her test temiz şemayla başlar.

| Alan | Testler |
|---|---|
| Kısıtlar | Barkod UNIQUE ihlali, CHECK ihlalleri, foreign key ihlali |
| Aktif sepet tekliği | İkinci `active` sepet oluşturma denemesi başarısız olur |
| CRUD | Her repository için temel işlemler |
| Soft delete | Pasif kayıtların sorgulardan doğru filtrelenmesi |
| Snapshot alanları | Satış sonrası ürün güncellenince satırların değişmemesi |
| Index kullanımı | Kritik sorgular için `EXPLAIN QUERY PLAN` doğrulaması (index taraması yapılıyor mu) |
| Transaction | Rollback sonrası hiçbir yazımın kalmaması |
| Tarih | UTC saklama, yerel gösterim |

---

## 5. Widget testleri (seçici)

Yalnızca **davranışsal** ve kritik olanlar:

| Widget | Test |
|---|---|
| **Barkod input handler** | Hızlı giriş + Enter → barkod olayı; yavaş giriş → barkod değil; kısa giriş yok sayılır; zaman aşımı buffer'ı temizler; dialog açıkken dinlemez |
| Sepet paneli | Ekle/sil/miktar davranışları, toplam gösterimi |
| Odak yönetimi | Her işlem sonrası odağın barkod girişine dönmesi (REQ-UX-002/003) |
| Para giriş alanı | `,` ve `.` kabulü, geçersiz karakter engelleme |
| Miktar giriş alanı | Negatif/sıfır engelleme |

Görsel/piksel testleri (golden test) **yazılmaz** — bakım maliyeti değerinden yüksek.

---

## 6. Integration testleri

Gerçek veritabanı + servis katmanı. En yüksek değerli testler.

### 6.1 Satış akışı

| Senaryo |
|---|
| Barkod → sepet → satış → stok/ciro doğrulaması |
| **Atomiklik:** transaction ortasında hata enjekte → hiçbir kayıt oluşmaz |
| Çift gönderim → tek satış |
| Sepet restore: DB'ye sepet yaz → servisi yeniden başlat → sepet aynen gelir |
| Negatif stokla satış |
| Fiyat override → snapshot doğrulaması |
| 100 satırlık satış |

### 6.1b Finansal erişim kilidi ve recovery code

| Senaryo |
|---|
| Kilit kapalıyken **Dashboard** rotası açılıyor → parola ekranı gelir |
| Kilit kapalıyken **Raporlar** rotası açılıyor → parola ekranı gelir |
| **Parola girilmeden hiçbir dashboard/rapor sorgusunun çalışmadığı doğrulanır** (sorgu sayacı / mock repository ile) |
| **Kilit dışı ekranlar** (satış, ürün, stok, kategori, iade, ayarlar) parola sormaz |
| Doğru parola → kilit açılır, sorgular çalışır |
| Dashboard için açılan kilit **Raporlar için de geçerlidir** (ve tersi) |
| Yanlış parola 5 kez → bekleme uygulanır, audit kaydı oluşur |
| Logout → kilit sıfırlanır · Uygulama yeniden başlatma → kilit kapalı başlar |
| Parola değiştirme: mevcut parola yanlışsa reddedilir |
| Restore sonrası kilit kapanır ve yedekteki parola geçerli olur |
| **Recovery:** doğru kod → yeni parola belirlenir, kilit açılır |
| **Recovery:** kullanılmış kod tekrar denenirse reddedilir (`used_at` dolu) |
| **Recovery:** başarılı kullanım sonrası **yeni kod üretilir** ve eski geçersizleşir |
| **Recovery:** yanlış kod 5 kez → bekleme + audit kaydı |
| **Recovery:** parola + kod güncellemesi tek transaction; hata → hiçbiri değişmez |
| **Recovery kodu hiçbir yerde düz metin saklanmıyor** (DB + yedek + log taraması) |
| Ayarlar'dan yeni kod üretme: mevcut parola doğruysa üretilir, yanlışsa reddedilir |

### 6.2 İade / iptal

| Senaryo |
|---|
| Tam iptal → tüm stoklar geri |
| Kısmi iade → doğru miktar, doğru durum |
| Ardışık kısmi iadeler → `returned` durumuna geçiş |
| Fazla iade engelleme |
| İptal edilmiş satışta iade engelleme |
| İade transaction atomikliği |

### 6.3 Backup / restore

| Senaryo |
|---|
| Yedek al → veriyi değiştir → restore → orijinal veri geri gelir |
| Bozuk checksum → reddedilir, veri değişmez |
| **Yedek arşivinin hiçbir dosyasında düz metin parola bulunmadığı doğrulanır** |
| Eksik `metadata.json` → reddedilir |
| Eski şemalı yedek → restore + migration |
| Yeni şemalı yedek → reddedilir |
| Restore ortasında hata → geri alma |
| Eksik görselli yedek → restore devam eder |
| Zip-slip / zip bomb fixture'ları → reddedilir |
| Restore sonrası satış numarası sayacı düzeltmesi |

### 6.4 Migration

| Senaryo |
|---|
| Her `vN → vN+1` adımı ayrı ayrı |
| `v1 → vSON` tam zincir |
| **Veri koruma:** her adım öncesi örnek veri → sonrasında satır sayısı ve kritik alanlar doğrulanır |
| Adım ortasında hata → rollback |
| Migration sonrası `foreign_key_check` boş |
| Yarım migration → açılışta kurtarma |
| **v1 → v2** (OD-029): `icon_key` eklenir, mevcut kategoriler ve ürünler **aynen kalır** |
| **v1 → v2**: eklenen kolon `NULL` başlar; hiçbir kategori ikon kazanmış gibi görünmez |

### 6.5 Import / export

| Senaryo |
|---|
| Geçerli CSV → beklenen ürünler |
| Dosya içi duplicate barkod → ilgili satırlar reddedilir |
| Sistemde var olan barkod → her üç politika ayrı ayrı |
| Bozuk CSV → anlaşılır hata |
| Import ortasında hata → tam rollback |
| Export → import döngüsü (round-trip): veri kaybı olmamalı |
| Türkçe karakter round-trip |
| Formül enjeksiyonu kaçışı |

### 6.6 Veri bütünlüğü / kaos

| Senaryo |
|---|
| Transaction ortasında bağlantı kapatma → tutarlı durum |
| Tutarlılık kontrolü: bilinçli bozulmuş veriyi tespit ediyor mu |
| Aynı DB'ye ikinci bağlantı → lock davranışı |

---

## 7. Performans testleri

Yapay veri üreteci ile 5. yıl hacmi ([24 §1](24-non-functional-requirements.md)) oluşturulur:
**10.000 ürün, 15.000 barkod**, 200.000 satış, 600.000 satır, 700.000 stok hareketi.

| Ölçüm | Eşik |
|---|---|
| Barkod lookup | < 100 ms |
| Ürün arama (10.000 ürün) | < 150 ms |
| Satış transaction | < 50 ms |
| Dashboard (30 gün) | < 1 sn |
| Dashboard (1 yıl) | < 2 sn |
| Rapor (10k satır) | < 2 sn |
| Yedek alma | < 15 sn |
| 1.000 satır import | < 10 sn |
| Uygulama açılışı | < 3 sn |

Eşik aşılırsa build başarısız sayılır (CI'da çalıştırılırsa).

---

## 8. Manuel test — Windows

macOS'ta doğrulanamayan her şey. **Her faz sonunda tekrarlanır.**

| # | Test | Kabul |
|---|---|---|
| W1 | Gerçek barkod okuyucu ile 50 ardışık okutma | Hiçbiri kaybolmaz, karışmaz |
| W2 | EAN-13, EAN-8, UPC, Code 128 barkodları | Doğru okunur |
| W3 | Türkçe Q ve F klavye düzeninde alfanümerik barkod | Karakterler doğru |
| W4 | Bluetooth scanner (varsa) | USB ile aynı davranış |
| W5 | Kurulum → veri oluştur → yeni sürüm kur | Veri korunur |
| W6 | `%APPDATA%` altında veri oluşuyor | Kurulum dizininde veri yok |
| W7 | %100 / %125 / %150 DPI | Düzen bozulmaz |
| W8 | 1366×768 ve 1920×1080 | Satış ekranı tam işlevsel |
| W9 | Uygulama açıkken bilgisayarın fişini çekme | Veri tutarlı, sepet korunur |
| W10 | Yedek al → başka makinede restore | Tüm veri ve görseller gelir |
| W11 | İkinci örnek açma | Engellenir |
| W12 | Antivirüs ile birlikte çalışma | Yedek dosyası engellenmez |
| W13 | 8 saat kesintisiz kullanım | Bellek artışı yok, yavaşlama yok |
| W14 | Windows uyku/uyanma | Uygulama çalışmaya devam eder |
| W15 | Türkçe olmayan Windows kullanıcı adı / yolda boşluk | Veri dizini doğru çözülür |

---

## 9. macOS test kapsamı

macOS'ta çalıştırılan tüm otomatik testler + manuel UI doğrulaması.
**macOS'ta geçen bir test Windows'ta geçeceğini garanti etmez** — özellikle dosya kilitleme,
yol çözümleme ve klavye davranışında.

---

## 10. Test verisi

| Fixture | İçerik |
|---|---|
| `minimal` | 1 kullanıcı, 1 kategori, 3 ürün — hızlı unit/integration |
| `realistic` | 200 ürün, 15 kategori, 5 tedarikçi, 2.000 satış — UI ve rapor testleri |
| `stress` | 5. yıl hacmi — performans testleri |
| `corrupt/*` | Bozuk yedekler, hatalı CSV'ler, geçersiz görseller, zip-slip arşivi |
| `schema/vN.json` | Migration testleri için şema anlık görüntüleri |

---

## 11. Requirement → test eşlemesi

| Requirement grubu | Birincil test türü |
|---|---|
| REQ-FIN-*, REQ-VAT-* | Unit (property test dahil) |
| REQ-STOCK-* | Unit + integration |
| REQ-SALE-*, REQ-CART-* | Integration |
| REQ-RET-* | Integration |
| REQ-BKUP-* | Integration + bozuk fixture |
| REQ-MIG-* | Integration (şema anlık görüntüleriyle) |
| REQ-IMEX-* | Integration (fixture dosyalarıyla) |
| REQ-BARC-* | Widget + manuel donanım |
| REQ-PERF-* | Performans testi |
| REQ-UX-* | Widget + manuel |
| REQ-AUTH-015…028 | Integration (kilit + recovery) |
| REQ-COMP-* | Manuel (Windows) |
| REQ-SEC-* | Integration (kötü niyetli fixture) |

---

## 12. Çıkış kriterleri

Bir faz "tamamlandı" sayılmaz eğer:

1. Fazın 🔴 Must requirement'larının tamamı test edilmemişse,
2. İlgili edge-case'ler ([26](26-edge-cases.md)) test edilmemişse,
3. `flutter analyze` uyarısız geçmiyorsa,
4. Faz kapsamındaki Windows manuel testleri yapılmamışsa,
5. Performans eşikleri aşılıyorsa.

---

## Elle test borcu

Otomatik testin kapsayamadığı ve bilinçli olarak kapsamadığı her şey
[32 — Elle Test Borcu](32-manual-test-backlog.md) içinde tek listede tutulur.
Faz 12 çıkış kriteri o listenin tamamının kapanmasıdır.
