# 28 — Karar Kaydı (Decision Log)

> **Doküman sürümü:** v5 (revizyon: 2026-08-19)
>
> ## ✅ AÇIK KARAR KALMAMIŞTIR.
>
> Proje sahibi tarafından kararlaştırılması gereken tüm konular kapanmıştır.
> Bu doküman artık bir **karar kaydıdır** — hangi kararın neden verildiğini ve neyi etkilediğini saklar.
>
> Geliştirme, hiçbir karar beklemeden başlayabilir.

---

## 1. Kapanan kararlar — özet

| ID | Konu | KARAR | Kapanma |
|---|---|---|---|
| OD-001 | Veritabanı teknolojisi | **Drift + SQLite** | v2 |
| OD-002 | State management | **Riverpod** | v3 |
| OD-003 | Parola saklama | **Salt'lı SHA-256**, düz metin hiçbir yerde yok | v2 |
| OD-004 | KDV dahil mi hariç mi | **Satış fiyatı KDV DAHİL** | v2 |
| OD-005 | Maliyet yöntemi | **Son alış fiyatı** + SaleItem snapshot'ı | v3 |
| OD-006 | Satış miktarı tipi | **INTEGER** | v2 |
| OD-007 | İndirim sistemi | **V1'de YOK** — fiyat override yeterli | v3 |
| OD-008 | Nakit yuvarlaması | **V1'de YOK** — yalnızca toplam/alınan/para üstü | v3 |
| OD-009 | Import/export formatı | **CSV birincil, Excel ikincil** (ayrı abstraction) | v3 |
| OD-010 | Kasa / vardiya | **V1 kapsamı dışı** | v2 |
| OD-011 | Lokalizasyon | **Türkçe**, metinler merkezî yapıda | v3 |
| OD-012 | Yedek formatı | **ZIP/archive, tek dosya** `.canteenbackup` | v3 |
| OD-013 | Windows installer | **Inno Setup** | v3 |
| OD-014 | Grafik kütüphanesi | **fl_chart** | v3 |
| OD-015 | Finansal erişim kilidi süresi | **Oturum boyunca** | v3 |
| OD-016 | Görsel optimizasyon | **1000 px / JPEG 85**, yapılandırılabilir teknik politika | v3 |
| **OD-017** | **Kurulumda KDV oranı** | **`%0 — KDV Yok` otomatik oluşturulur ve varsayılan olur** | **v4** |
| **OD-018** | **Kategori taşıma audit adı** | **`categoryProductsMoved`** | **v4** |
| **OD-019** | **Pasif KDV oranı varsayılan olabilir mi** | **Hayır — reddedilir** | **v4** |
| **OD-020** | **Kategori/tedarikçi/KDV yeniden aktifleştirme** | **Desteklenir** | **v4** |
| **OD-021** | **Barkod tamponu zaman aşımına uğradığında** | **Girdi "zehirlenir"; sonraki `Enter`'a kadar barkod üretilmez** | **v5** |

**Ek olarak v3'te kesinleşen iki yeni gereksinim** (açık karar olarak hiç durmadılar):

| Konu | KARAR |
|---|---|
| Dashboard parolası kurtarma | **Recovery code** — kurulumda üretilir, hash saklanır, tek kullanımlık |
| Finansal erişim kapsamı | **Dashboard + Raporlar** aynı kilit tarafından korunur |

---

## 2. Karar detayları

### OD-001 — Veritabanı: Drift + SQLite

**Neden:** Projenin iki en riskli alanı migration ve raporlama aggregation'ı; Drift ikisinde de en güçlü seçenek. Tip güvenli sorgular, yerleşik migration/şema test araçları, reaktif `Stream` sorguları, transaction desteği, Windows/macOS masaüstünde sorunsuz çalışma.

**Elenenler:** `sqflite_common_ffi` (tip güvenliği yok, migration elle), ham `sqlite3` (bakım maliyeti), Isar/Hive (relational aggregation zayıf — projenin en ağır işi tam olarak bu), ObjectBox (lisans + raporlama).

**Etki:** `data/` katmanının tamamı, [05](05-database-architecture.md), [06](06-database-migrations.md).

---

### OD-002 — State management: Riverpod

**Neden:** DI ve state yönetimi tek pakette; ayrı bir `get_it` gerekmiyor. Drift'in `Stream` tabanlı sorgularıyla doğal uyum — sepet, stok ve dashboard ekranları elle tazeleme kodu olmadan güncel kalır. Test'te `ProviderContainer` ile servis override kolay.

**Elenenler:** `provider` (DI zayıf), `bloc` (bu ölçek için tören fazlası), `signals` (küçük ekosistem).

**Etki:** Tüm `presentation/` ve `application/` katmanı. [03 §5](03-architecture.md).

---

### OD-003 — Parola saklama: salt'lı SHA-256

**Neden:** Yedek dosyası taşınabilirdir ve `users` tablosunu içerir. Düz metin parola saklanırsa yedeği eline geçiren herkes parolayı okur; asıl zarar bu uygulamada değil, kullanıcının aynı parolayı kullandığı diğer hesaplarda oluşur. Hash'leme bu riski tamamen kapatır ve geliştirme maliyeti pratikte sıfırdır.

**Kapsam dışı:** bcrypt/Argon2 (uzaktan saldırı yüzeyi yok), OAuth, JWT, MFA, sunucu tarafı kimlik doğrulama.

**Etki:** BR-SEC-001, BR-AUTH-011. [17 §5](17-authentication.md).

---

### OD-004 — KDV: satış fiyatı KDV DAHİL

**Neden:** Kantin bir perakende noktasıdır; rafta yazan fiyat müşteriden alınan fiyattır. Kullanıcıdan KDV'siz fiyat hesaplaması istemek kasa mutabakatını bozar ve ürün girişini yavaşlatır.

**Tek geçerli formül:**
```text
lineVatMinor = roundHalfUp( lineTotalMinor × vatBp / (10000 + vatBp) )
lineNetMinor = lineTotalMinor − lineVatMinor
```

**Etki:** BR-VAT-003. [07 §4.2](07-financial-rules.md), [08](08-vat-rules.md), ürün formu, sepet, tüm finansal raporlar.

---

### OD-005 — Maliyet: son alış fiyatı + snapshot

**Karar:** Satış anında `sale_items.purchase_price_snapshot_minor` alanına ürünün **o andaki alış fiyatı** (`products.purchase_price_minor`) kopyalanır.

```text
Kâr = (KDV hariç matrah) − (purchase_price_snapshot_minor × quantity)
```

**Neden:** Kantinde ürün devir hızı yüksek, alış fiyatı değişimleri küçük adımlı. Ağırlıklı ortalama maliyetin getireceği doğruluk kazancı, getireceği karmaşıklığı (ek alan, her girişte yeniden hesaplama, negatif stokta tanımsızlık) karşılamaz.

**Kritik sonuç:** Ürünün alış fiyatı sonradan değişse bile **geçmiş satışların kârı değişmez.**

**Etki:** BR-FIN-004, BR-SALE-001. [07 §5](07-financial-rules.md).

---

### OD-006 — Satış miktarı: INTEGER

**Karar:** `cart_items.quantity`, `sale_items.quantity`, `return_items.quantity`, `stock_movements.quantity_delta` → tam sayı.

**Neden:** Kantin paketli ürün satar. Tartılı satış V1 kapsamı dışıdır. Ürünün gramaj bilgisi (`net_weight_value`) yalnızca açıklayıcıdır ve hesaba girmez.

**Etki:** BR-SALE-011. [30 §3.2](30-future-scope.md)'de genişleme yolu tanımlı.

---

### OD-007 — İndirim: V1'de yok

**Karar:** Ayrı bir indirim sistemi (kampanya, yüzde indirim, sabit indirim, indirim yetkisi) V1'de **geliştirilmez.** Satır fiyatı override mekanizması ([12 §4](12-sales-system.md)) yeterlidir.

**Veritabanı etkisi:** Hiçbir indirim entity'si (tablo) oluşturulmaz. `sales.discount_total_minor` tek bir tam sayı kolonu olarak kalır ve V1'de daima `0`'dır — bir entity değil, ileride kolon ekleme migration'ı gerektirmemesi için bırakılmış bir alandır.

**Etki:** [12](12-sales-system.md), [30 §3.3](30-future-scope.md).

---

### OD-008 — Nakit yuvarlaması: yok

**Karar:** Toplam tutar yuvarlanmaz. Nakit ekranı yalnızca üç değeri gösterir:

```text
Toplam:     ₺87,50
Alınan:     ₺100,00
Para üstü:  ₺12,50
```

**Etki:** Kayıtlar temiz kalır; `rounding_minor` gibi bir alan yoktur. [12 §5](12-sales-system.md).

---

### OD-009 — Import/export: CSV birincil, Excel ikincil

**Karar:** CSV (UTF-8 BOM, `;` ayırıcı) birincil formattır ve V1'de önceliklidir. Excel (`.xlsx`) desteği **ayrı bir abstraction arkasından** eklenir; CSV yolunu karmaşıklaştırmaz.

```text
ImportSource (arayüz)
├── CsvImportSource     ← V1 önceliği
└── ExcelImportSource   ← ikincil, aynı arayüz
```

**Neden:** CSV her koşulda çalışır ve büyük dosyalarda bellek açısından güvenlidir. Excel kütüphanelerinin bellek profili büyük dosyalarda risklidir; ayrı abstraction sayesinde sorun çıkarsa yalnızca o yol devre dışı bırakılır.

**Etki:** [20 §2](20-import-export.md).

---

### OD-010 — Kasa / vardiya: V1 dışı

**Karar:** Kasa açılışı, vardiya, kasa sayımı, kasa kapanışı, beklenen nakit ve kasa farkı V1 kapsamında **değildir** ve satış sistemini bloklamamalıdır.

**Etki:** Bu konulara ait hiçbir tablo, ekran, rapor veya dashboard bileşeni yoktur. [30 §3.1](30-future-scope.md).

---

### OD-011 — Lokalizasyon: Türkçe, merkezî metin yapısı

**Karar:** V1 tek dillidir (Türkçe). Çoklu dil altyapısı geliştirilmez. Ancak **UI metinleri widget'ların içine dağınık şekilde hard-code edilmez**; tek bir merkezî metin kaynağında toplanır.

```text
lib/app/l10n/
└── app_strings_tr.dart      ← tüm UI metinleri tek yerde
```

**Neden:** Hata mesajı tutarlılığı ([23 §6](23-ux-requirements.md)) zaten merkezî bir kaynak gerektiriyor. İleride `flutter_localizations` + ARB'ye geçiş, metinler zaten toplu olduğu için düşük maliyetli olur.

**Etki:** Tüm presentation katmanı. Faz 1'de kurulur.

---

### OD-012 — Yedek: ZIP/archive, tek dosya

**Karar:** `canteen_backup_<timestamp>.canteenbackup` — içerik standart ZIP.

```text
canteen_backup.canteenbackup
├── metadata.json      (schemaVersion, appVersion, createdAt, counts)
├── database.sqlite    (tutarlı snapshot)
├── checksums.json     (SHA-256)
└── images/
```

`archive` paketi ile deflate sıkıştırma, isolate içinde çalıştırılır. Uzantı `.canteenbackup` olsa da içerik standart ZIP'tir — acil durumda herhangi bir arşiv programıyla açılabilir (bilinçli kurtarılabilirlik kararı).

**Etki:** BR-DATA-002/003. [19](19-backup-restore.md). Backup/restore atomik ve güvenli protokolle tasarlanmıştır.

---

### OD-013 — Installer: Inno Setup

**Karar:**
- Kurulum: `C:\Program Files\CanteenApp\`
- Veri: `%APPDATA%\CanteenApp\` — installer **buraya asla dokunmaz** (BR-DATA-001)
- Güncelleme: yeni installer eskinin üzerine kurar; migration açılışta çalışır
- Otomatik güncelleme V1'de yok (offline ilkesiyle çelişir)

**Elenenler:** MSIX (konteynerlenmiş dosya sistemi veri dizini davranışını karmaşıklaştırır), portable ZIP (kısayol/kaldırma yok).

**Etki:** [24 §6](24-non-functional-requirements.md), Faz 12.

---

### OD-014 — Grafik: fl_chart

**Karar:** MIT lisanslı, masaüstünde sorunsuz, [15 §4](15-dashboard.md)'teki tüm grafik tiplerini (çizgi, sütun, donut) karşılıyor.

**Elenenler:** syncfusion (community lisans koşulları), graphic (küçük topluluk), elle `CustomPainter` (gereksiz iş).

---

### OD-015 — Finansal erişim kilidi: oturum boyunca

**Karar:** Dashboard parolası bir kez doğru girildiğinde erişim **oturum boyunca** açık kalır. Dashboard ve Raporlar ekranları arasında geçişte parola tekrar sorulmaz. Logout veya uygulama kapanışında kilit yeniden devreye girer.

**Neden:** Kilidin amacı kasadaki kişinin finansal veriyi görmesini engellemektir; kasa bilgisayarı gün boyu aynı oturumda kalır ve işletme sahibi günde birkaç kez bakar. Her geçişte parola sormak kullanılamaz bir deneyim yaratır.

**Etki:** BR-AUTH-016. Kilit durumu yalnızca bellekte tutulur; veritabanına yazılmaz.

---

### OD-016 — Görsel optimizasyon: 1000 px / JPEG 85 (yapılandırılabilir)

**Karar:** Bu değerler **business rule değil, yapılandırılabilir teknik politikadır.**

| Parametre | Başlangıç değeri |
|---|---|
| Maksimum boyut (uzun kenar) | 1000 px |
| JPEG kalitesi | 85 |
| Maksimum yükleme dosya boyutu | 10 MB |
| Desteklenen formatlar | jpg, jpeg, png, webp |

`app_settings['image_optimization']` üzerinden değiştirilebilir; koda sabit yazılmaz.

**Kesin olan kısım:** Optimizasyon **import sırasında** yapılır ve **orijinal büyük görsel saklanmaz.** Yalnızca optimize edilmiş dosya diskte tutulur.

**Etki:** BR-IMG-002. [21](21-image-storage.md).

---

### OD-017 — Kurulumda `%0 — KDV Yok` oranı oluşturulur

**Karar:** İlk kurulumda `%0 — KDV Yok` adında tek bir KDV oranı **otomatik oluşturulur** ve
`is_default = true` olarak işaretlenir. Kullanıcının KDV takibi için hiçbir şey tanımlaması
gerekmez. Kullanıcı dilediği zaman Ayarlar → KDV Oranları'ndan yeni oran ekleyebilir, mevcut
oranı düzenleyebilir ve ürün eklerken/düzenlerken ürünün oranını değiştirebilir.

**Çözülen çelişki:** [08 §3](08-vat-rules.md) kendi içinde tutarsızdı — aynı bölüm hem
"Hiçbir KDV oranı önceden seed edilmez" diyor, hem de "Kullanıcı hiç oran tanımlamazsa
`%0 — KDV Yok` adında tek bir varsayılan oran oluşturulur" diyordu. İkincisinin **kim
tarafından ve ne zaman** yapılacağı hiçbir dokümanda tanımlı değildi.

**Neden bu yön:** BR-VAT-001'in koruduğu şey **mevzuata bağlı bir değeri koda yazmamaktır**
— yani `%20`, `%10`, `%1` gibi oranların varsayılması. `%0` mevzuata bağlı bir oran değil,
KDV aritmetiğinin **nötr elemanıdır**: `vat = total × 0 / (10000 + 0) = 0`. Seed edilmesi
hiçbir vergi varsayımı yapmaz; yalnızca "KDV takip etmeyen kantin" senaryosunu kurulumdan
itibaren çalışır kılar. Alternatif — kullanıcıyı kurulumda oran tanımlamaya zorlamak —
KDV takip etmek istemeyen kullanıcıya anlamsız bir adım dayatırdı.

**Etki:** BR-VAT-001 ve BR-VAT-005 metni güncellendi · REQ-VAT-002 ve REQ-VAT-005 güncellendi ·
[08 §3](08-vat-rules.md) seed politikası yeniden yazıldı · `.claude/rules/02 §2` yasak
listesinden "Kurulumda KDV oranı seed etmek" çıkarıldı · `Seed.apply` `%0 — KDV Yok` oranını
`Genel` kategorisiyle aynı idempotent yolla oluşturur.

---

### OD-018 — Kategori taşıma audit action adı: `categoryProductsMoved`

**Karar:** Kategori birleştirme (ürünleri başka kategoriye taşıma) işleminin audit action adı
**`categoryProductsMoved`**'dur.

**Çözülen çelişki:** [10 §1.4](10-category-brand-supplier.md) bu olayı `categoryMerge` olarak
adlandırıyordu; [18 §3](18-audit-log.md) ise `categoryProductsMoved` diyordu. `audit_logs.action`
kalıcı bir literal olduğu için iki ad aynı anda geçerli olamaz.

**Neden bu yön:** Audit action adları [18](18-audit-log.md)'in kendi konusudur ve orada bir
tabloda sistematik olarak listelenmiştir; [10 §1.4](10-category-brand-supplier.md)'teki geçiş
parantez içi bir yan nottur. Ayrıca ad, yapılan işi daha doğru anlatır: "merge" kaynak
kategorinin yok olduğunu ima eder, oysa kategori silinmez — yalnızca ürünleri taşınır ve
kendisi pasifleştirilebilir.

**Etki:** [10 §1.4](10-category-brand-supplier.md) düzeltildi. [18](18-audit-log.md) zaten doğruydu.

---

### OD-019 — Pasif KDV oranı varsayılan yapılamaz

**Karar:** `is_active = false` olan bir KDV oranı **varsayılan olarak atanamaz**; işlem
kullanıcıya görünür bir hata ile reddedilir.

**Neden:** Varsayılan oran araması aktiflik filtreler (`is_default AND is_active`). Pasif bir
oranın varsayılan yapılmasına izin verilseydi, sistem "varsayılan oran yok" durumuna düşer ve
[08 §4](08-vat-rules.md) gereği **KDV sessizce %0 kabul edilirdi.** Kullanıcı bir oran seçtiğini
sanırken ürünlerinin KDV'si sıfırlanırdı. Para davranışındaki sessiz değişiklik kabul edilemez;
hata görünür olmalıdır.

**Etki:** [08 §4](08-vat-rules.md)'e kural eklendi. REQ-VAT-010 eklendi.

---

### OD-020 — Kategori, tedarikçi ve KDV oranı yeniden aktifleştirilebilir

**Karar:** Pasifleştirilmiş kategori, tedarikçi ve KDV oranı **yeniden aktifleştirilebilir.**
Audit action'ları: `categoryActivated` · `supplierActivated` · `vatRateActivated`.

**Neden:** Dokümanlar bu üç entity için yalnızca pasifleştirmeyi tanımlıyordu; yeniden
aktifleştirme hiçbir yerde geçmiyordu (yalnızca ürün için `productActivated` vardı). Bu,
pasifleştirmeyi tek yönlü ve geri alınamaz yapıyordu: yanlışlıkla pasifleştirilen bir kategori
kalıcı olarak kullanılamaz hale gelirdi. Kategori adı benzersizliği pasif kayıtları da
kapsadığı için (REQ-CAT-005) kullanıcı aynı adla yenisini de oluşturamazdı — yani hatadan
çıkış yolu yoktu.

`Genel` sistem kategorisi zaten pasifleştirilemediği için (BR-CAT-004) bu karardan etkilenmez.

**Etki:** REQ-CAT-007, REQ-SUP-006, REQ-VAT-011 eklendi · [10 §1.1, §2.1](10-category-brand-supplier.md)
tabloları güncellendi · [18 §3](18-audit-log.md)'e üç action eklendi.

---

### OD-021 — Zaman aşımına uğrayan barkod tamponu girdiyi "zehirler"

**Karar:** Barkod tamponu 300 ms zaman aşımına uğradığında yalnızca temizlenmez; girdi
**zehirlenmiş** sayılır ve **sonraki `Enter`'a kadar hiçbir barkod üretilmez.** `Enter`
geldiğinde zehir temizlenir ve normal `Enter` olarak işlenir.

**Çözülen çelişki:** [11 §2](11-barcode-system.md) akış şeması zaman aşımında "buffer'ı
temizle, **yeni giriş başlat**" diyordu. [26](26-edge-cases.md) EC-BARC-002 ise aynı durum
için "buffer temizlenir; **işlem yapılmaz**" diyordu. İkisi aynı anda doğru olamaz.

**Neden bu yön:** Şemadaki davranış uzun okumalarda sessizce **kırpılmış barkod** üretir.
40 karakterlik bir kod 10 ms aralıkla okutulduğunda 400 ms sürer; tampon ~300 ms'de sıfırlanır
ve kalan ~10 karakter geçerli bir barkod gibi döner. Faz 5'te bilinmeyen barkod "yeni ürün"
ekranını açacağı için bu, **yanlış barkodla ürün oluşturulmasına** yol açardı.

Kayıp okuma ile yanlış okuma arasındaki asimetri belirleyicidir: kullanıcı okumanın
gerçekleşmediğini **görür ve tekrar okutur**; kırpılmış barkod ise sessizdir ve yanlış veri
üretir. EC-BARC-002'nin "işlem yapılmaz" ifadesi zaten bu yönü işaret ediyordu.

**Etki:** [11 §2](11-barcode-system.md) akışı düzeltildi · EC-BARC-002 netleştirildi ·
EC-BARC-008 eklendi · `BarcodeInputHandler` zehirli durumu uygular.

### OD-022 — `barcodeSnapshot` ürünün **birincil** barkodudur

**Karar:** `SaleItem.barcodeSnapshot` satış anında ürünün **birincil barkodunu** taşır;
ürünün hiç barkodu yoksa `NULL` olur. "Okutulan barkod" hedefinden **vazgeçilmiştir.**

**Çözülen çelişki:** [04 §3.9](04-domain-model.md) alanı *"okutulan barkod"* olarak
tanımlıyordu. Ancak [05 §2.7](05-database-architecture.md)'deki `cart_items` tablosu
okutulan barkodu taşıyacak bir kolon içermiyor — sepet hangi barkodun okutulduğunu
**hatırlayamaz**, üstelik çökme sonrası aynen geri yüklenmesi de gerekir (REQ-CART-003).
İki doküman aynı anda sağlanamıyordu.

**Seçenekler:**

| | Seçenek | Sonuç |
|---|---|---|
| **A** | `04 §3.9` düzeltilir: "ürünün birincil barkodu" | Şema değişmez, migration yok |
| B | `cart_items`'a `scanned_barcode` kolonu eklenir | Şema değişikliği + migration; sepet kalıcılığı büyür |

**Neden A:** Alan **yalnızca raporlama amaçlıdır** — hiçbir para, stok, KDV veya durum
hesabına girmez. Tek barkodlu üründe (V1'de neredeyse her ürün) iki seçenek **aynı değeri**
üretir; fark yalnızca aynı ürünün birden fazla barkodu olduğunda görünür ve orada da
kaybedilen şey "hangi ambalaj okutuldu" ayrıntısıdır. Şema *final* kararını
([rules/03 §1](../.claude/rules/03-data-and-persistence.md)) bir raporlama ayrıntısı için
bozmak orantısızdır. B ileride geriye dönük olarak eklenebilir; A bunu engellemez.

**Etki:** [04 §3.9](04-domain-model.md) alan açıklaması düzeltildi ·
`SaleService` birincil barkodu yazar · `ProductRepository.barcodesOf` sırası
**sözleşmenin parçası** oldu (birincil başta) — sırasız bir sonuç aynı ürünün
satışlarında rastgele snapshot üretirdi.

---

### OD-023 — Fiyat override audit action adı: `salePriceOverridden`

**Karar:** Satış sırasındaki fiyat değişikliğinin audit action adı **`salePriceOverridden`**'dır.

**Çözülen çelişki:** [12 §4](12-sales-system.md) `salePriceOverride`, [18 §3](18-audit-log.md)
ise `salePriceOverridden` yazıyordu. Audit action adları [18](18-audit-log.md)'in konusudur
(rules/00 §1 — her doküman kendi konusunda bağlayıcıdır), bu yüzden `12 §4` düzeltilmiştir.

**Neden önemli:** `audit_logs.action` **kalıcı veridir**. İki ad arasında salınmak, denetim
izini action adına göre filtreleyen her sorguyu sessizce eksik sonuç verir hâle getirirdi.

**Etki:** [12 §4](12-sales-system.md) düzeltildi · `SaleService.actionPriceOverridden`.

### OD-024 — Kısayol çelişkilerinde `23-ux-requirements.md` bağlayıcıdır

**Karar:** Satış ekranında sepeti temizleme kısayolu **`Ctrl+Del`**, Ürünler ekranına
gidiş **`F3`**'tür. Genel kural: bir kısayol iki dokümanda farklı tanımlanırsa
[23 §2](23-ux-requirements.md) geçerlidir.

**Çözülen çelişki:**

| Konu | [12](12-sales-system.md) | [23 §2](23-ux-requirements.md) | Uygulanan |
|---|---|---|---|
| Sepeti temizle | `Esc` (uzun) | `Ctrl+Del` | **`Ctrl+Del`** |
| Ürünler ekranı | `F9` (§1 düzeni) | `F3` | **`F3`** |

**Neden 23:** Klavye kısayolları bir **etkileşim** konusudur ve `rules/00 §1` her
dokümanı kendi konusunda bağlayıcı sayar; kısayolların konusu `23`'tür. Ayrıca `Esc`
aynı tabloda zaten *"geri / dialog kapat"*tır — "uzun basış" ile ayrıştırmak masaüstü
uygulamasında bulunmayan bir etkileşimdir ve `Esc`'in tek anlamlı davranışını
belirsizleştirirdi. `12 §1`'deki `F9` bir ASCII düzen çiziminde geçen tek bir etikettir;
`23 §2` ise kısayol **tablosudur**.

**Etki:** [12 §1](12-sales-system.md) ve [12 §3](12-sales-system.md) düzeltildi ·
`SaleScreen` kısayolları `23 §2`'yi uygular.

### OD-025 — `waste` hareketi birim maliyeti SAKLAR

**Karar:** Fire hareketi `unit_cost` alanını **yazar**; değer kullanıcıdan değil, fire
anındaki `products.purchase_price_minor` değerinden gelir.

**Çözülen çelişki:** [13 §2](13-stock-system.md) hareket tipleri tablosu `waste` satırında
`unit_cost` sütununu ❌ işaretliyor. Ama aynı dokümanın [§6](13-stock-system.md)'sı
*"Fire tutarı (`qty × unitCost`) kâr raporunda **gider olarak** gösterilir"* diyor.
Alan yazılmazsa §6 uygulanamaz.

**Neden saklanır:** Alternatif, fire tutarını rapor anında ürünün **güncel** alış
fiyatından türetmektir. Bu, snapshot ilkesini ihlal eder (`rules/02 §3`): alış fiyatı
sonradan değişince geçmiş fire giderleri de değişir ve kapanmış bir ayın kârı kendiliğinden
oynar. Maliyet **olay anında** bilinir ve sonradan türetilemez — tıpkı
`sale_items.purchase_price_snapshot_minor` gibi.

**§2'deki ❌ nasıl okunmalı:** Sütun *"kullanıcı girer mi"* sorusunu yanıtlar. `stockEntry`
satırında ✅ *"girilebilir"* yazması bunu doğrular: orada değeri kullanıcı verir, fire'da
sistem türetir. İşaret **"alan boş bırakılır"** anlamına gelmez.

**Etki:** [13 §2](13-stock-system.md) sütun başlığı netleştirildi ·
`StockService.recordWaste` alış fiyatını yazar · fire raporu (Faz 8) bu alandan hesaplar.

### OD-026 — Tutarlılık sapmasını kapatan düzeltme deltayı DEFTERDEN hesaplar

**Karar:** `products.stock_quantity` sapması kapatılırken düzeltme miktarı **defterden**
(`Σ quantity_delta`) hesaplanır, önbellekten değil. Kullanıcı gerçek miktarı onaylar;
onaylanan miktar defterle **aynıysa hiç hareket yazılmaz**, yalnızca önbellek tazelenir.

**Doldurulan boşluk:** `rules/03 §2` ve [24 §3.3](24-non-functional-requirements.md)
*"her sapma için ayrı `adjustment` hareketi oluşturularak düzeltilir"* der ama sapmanın
**hangi tarafının** yanlış olduğunu ve deltanın neye göre hesaplanacağını söylemez.
Normal düzeltmenin kuralı (önbellekten hesapla — mevcut sapma **korunsun ve görünür kalsın**)
buraya uygulanınca düzeltme sapmayı yeniden üretir:

```text
Sapma: defter = 10, önbellek = 99
önbellekten:  delta = 10 − 99 = −89  →  defter −79, önbellek 10   ❌ hâlâ ayrı
defterden:    delta = 10 − 10 =   0  →  hareket yok, önbellek 10  ✅ tutar
```

**Neden hareket yazılmayabilir:** Sapma iki şeyden biridir — önbellek bozulmuştur (rafta
defterin dediği kadar var) veya bir hareket yazılamamıştır (rafta önbelleğin dediği kadar var).
Birincisinde ortada bir **stok olayı yoktur**; hareket yazmak denetim izine gerçekleşmemiş bir
olay eklerdi ve "bu ürünün stoğu neden 12?" sorusunun cevabını bozardı (BR-STOCK-010).
Hangisi olduğunu yalnızca kullanıcı bilir, bu yüzden miktarı **o onaylar** (rules/03 §2 —
otomatik düzeltme yok).

**Neden önbellek doğrudan yazılabiliyor:** Yazım yine `StockService` üzerindendir
(`rules/02 §4` korunur) ve defterle aynı transaction içindedir. `stock_quantity` türetilmiş
bir **önbellektir** (BR-STOCK-002); onu kaynağıyla eşitlemek bir stok değişikliği değil,
önbellek tazelemesidir.

**Etki:** `StockService.repairFromLedger` eklendi (normal `recordAdjustment` davranışı
**değişmedi**) · `ConsistencyService.repairStockQuantity` bunu çağırır ·
denetim kaydı `metadata.source = "consistencyRepair"` taşır.

### OD-027 — `restore_in_progress` işareti veritabanının DIŞINDA tutulur

**Karar:** Yarım kalan geri yükleme işareti `app_settings` yerine veri dizinindeki
`restore_in_progress.json` **dosyasında** tutulur.

**Düzeltilen hata:** [19 §4](19-backup-restore.md) adım 10
*"`app_settings['restore_in_progress'] = {...}`"* der. Ama bu, tam da tespit etmesi
gereken senaryoda **işlemez**:

```text
adım 10  bayrak app_settings'e yazılır      → MEVCUT veritabanının içine
adım 13  canteen.sqlite → canteen.old_<ts>  → bayrak veritabanıyla birlikte gider
         ⚡ KESİNTİ — yerinde veritabanı YOK
açılış   app_settings okunacak…             → okunacak veritabanı yok
         → boş bir veritabanı oluşur, bayrak hiç bulunmaz
         → REQ-BKUP-012 kurtarması HİÇ ÇALIŞMAZ
```

Başarılı restore'da da bayrak "kendiliğinden" kaybolur (yedeğin `app_settings`'i onu
içermez), yani mekanizma iki durumu birbirinden ayıramaz.

**Neden `migration_in_progress` için sorun değil:** Migration veritabanı **dosyasını
değiştirmez**, içeriğini dönüştürür. Bayrak orada hayatta kalır. Restore ise dosyanın
kendisini takas eder — kural aynı görünse de mekanizma farklıdır.

**Seçenekler:**

| | Seçenek | Sonuç |
|---|---|---|
| **A** | Veri dizininde işaret dosyası | Veritabanı hiç açılmadan okunabilir; dosya takasından etkilenmez |
| B | Bayrağı yedeğin kendi `app_settings`'ine yazmak | Restore edilen yedek "yarım restore" işaretli açılırdı — anlamsız |
| C | Ayrı bir durum veritabanı | İkinci bir kalıcılık mekanizması, ikinci bir bozulma kaynağı (docs/12 §2.1 aynı gerekçeyle reddetti) |

**Neden A:** Kurtarmanın çalışması gereken an, veritabanının **açılamadığı** andır. İşaretin
veritabanından bağımsız olması bir tercih değil, ön koşuldur.

**Etki:** [19 §4](19-backup-restore.md) adım 10 ve 20 düzeltildi ·
`AppPaths.restoreMarkerFile` eklendi · `AppSettingKeys.restoreInProgress` **artık
kullanılmıyor** ama kaldırılmadı: yayınlanmış bir anahtarın silinmesi eski kurulumlarda
okunamayan bir kalıntı bırakırdı.

### OD-028 — İptal, **iptal tarihine** raporlanır; "brüt ciro" iptalleri İÇERİR

**Karar (iki parça):**

1. `net = satış − iptal − iade` formülündeki **"satış" tüm satışlardır**, iptal edilmişler
   dâhil. `docs/14 §5`'in "Brüt ciro"yu `completed + partiallyReturned + returned` olarak
   tanımlaması **hatalıdır** — o tanımla iptal iki kez düşerdi.
2. Bir iptal, orijinal satışın tarihine değil, **`sales.cancelled_at`** tarihine raporlanır.

**Çözülen çelişki (1):** [02 BR-RET-007](02-product-and-business-requirements.md)
`net = satış − iptal − iade` der. `docs/14 §5` ise "Brüt ciro"yu iptal edilmişleri **hariç
tutarak** tanımlar. İkisi birlikte uygulanırsa:

```text
net = (tüm − iptal) − iptal − iade      ❌ iptal İKİ KEZ düşer
```

`docs/02` hiyerarşinin en üstündedir (rules/00 §1), dolayısıyla `docs/14 §5` düzeltilir.
Ayrıca [16 R1](16-reporting.md)'in özet şeridi *"brüt ciro · iptal · iade · net ciro"*
gösterir; bu dört sayının toplanabilir olması ancak brüt iptalleri içerdiğinde mümkündür.

**Doldurulan boşluk (2):** `docs/14 §5` iade için tarih sorusunu açıkça çözer
(BR-RET-008 — **iade tarihi**) ama iptal için **hiçbir şey söylemez.** İptal orijinal satışın
gününden düşülürse, 1 Ağustos'ta yapılıp 5 Ağustos'ta iptal edilen bir satış **1 Ağustos'un
kapanmış cirosunu geriye dönük değiştirir.** Bu, iadeler için açıkça reddedilmiş olan
davranışın ta kendisidir:

> *"Alternatif (orijinal satış gününü düzeltmek) geçmiş kapanmış günleri değiştirir ve
> kabul edilemez."* — docs/14 §5

Aynı gerekçe iptal için de geçerlidir ve **veri zaten mevcuttur**: `sales.cancelled_at`
şemada tanımlıdır (docs/05 §2.8) ve Faz 7'de doldurulmaktadır. Farklı davranmak için bir
sebep yoktur.

**Sonuç — rapor aritmetiği:**

```text
brüt ciro (dönem)  = Σ grandTotal        · completed_at aralıkta        · TÜM durumlar
iptal     (dönem)  = Σ grandTotal        · cancelled_at aralıkta        · status=cancelled
iade      (dönem)  = Σ return_items.line_total · returns.created_at aralıkta
────────────────────────────────────────────────────────────────────────
net ciro           = brüt − iptal − iade
```

**Etki:** [14 §5](14-returns-and-cancellation.md) düzeltildi · BR-RET-008'in yanına iptal
tarihi kuralı eklendi · Faz 8 rapor sorguları bu aritmetiği uygular ·
`ix_sales_status_date` yanında `cancelled_at` üzerinden filtreleme gerekir.

---

## 3. Kararların faz üzerindeki etkisi

```text
Faz 0  →  ARTIK BOŞ. Bekleyen karar yok.
Faz 1  →  Riverpod + merkezî metin yapısı kurulur
Faz 2  →  Şema final; blokaj yok
Faz 3  →  Recovery code, finansal erişim kilidi, görsel politikası
Faz 5  →  Son alış fiyatı snapshot'ı, indirim yok, nakit yuvarlama yok,
          barkod snapshot'ı birincil barkoddur (OD-022)
Faz 6  →  Fire birim maliyeti saklar (OD-025); sapma düzeltmesi defterden (OD-026)
Faz 8  →  fl_chart; Raporlar kilit arkasında; iptal, iptal tarihine
          raporlanır ve brüt ciro iptalleri içerir (OD-028)
Faz 9  →  ZIP yedek; restore işareti veritabanı dışında (OD-027)
Faz 10 →  CSV birincil + Excel abstraction
Faz 12 →  Inno Setup
v1.1   →  Kategori ikonu; şema v2 (OD-029)
```

### OD-029 — Kategoriye **ikon alanı** eklenir (`categories.icon_key`, şema v2)

**Karar:** `categories` tablosuna `icon_key TEXT NULL` kolonu eklenir. Kullanıcı Kategori
Yönetimi'nden sabit bir katalogdan ikon seçer; seçmezse alan `NULL` kalır ve ikon **kategori
adından türetilir** (bugünkü davranış). Şema **v1 → v2**'ye çıkar ve ilk gerçek migration
adımı yayınlanır.

**Çözülen boşluk:** [21 §3](21-image-storage.md) ve REQ-IMG-009 *"görseli olmayan ürün
**kategori ikonuyla** gösterilir"* der ama `categories` tablosunda ikon **yoktur**
([05 §2.2](05-database-architecture.md)). Uygulama bu boşluğu kategori adından tahmin ederek
kapatıyordu; tahmin "Kalemler", "Raf 3", "Diğer" gibi adlarda nötr ikona düşer ve kullanıcı
bunu **düzeltemez.**

**Options:**

| | Yaklaşım | Sonuç |
|---|---|---|
| **A** | Kolon eklenmez; ikon addan türetilmeye devam eder | Şema değişmez. Ama ikon kullanıcı denetiminde değildir ve adı eşleşmeyen her kategori nötr ikonda kalır. |
| **B** | `icon_key TEXT NULL` — **sabit katalogdan anahtar** (`drink`, `coffee`, `bakery` …) | Anahtar anlamlıdır ve sürümler arası taşınabilir. Flutter'ın ikon tree-shaking'i korunur. `NULL` kalabildiği için mevcut kategoriler bozulmaz. |
| **C** | `icon_codepoint INTEGER` — herhangi bir Material ikon kod noktası | En esnek. Ancak tree-shaking kırılır (`--no-tree-shake-icons` zorunlu, paket büyür), veritabanında anlamsız bir sayı durur ve ikon seti değişirse eski kayıtlar sessizce başka bir şeye işaret eder. |

**Recommendation: B.**

- Kod noktası bir **uygulama ayrıntısıdır**; veritabanı iş verisi tutar. `'drink'` on yıl sonra
  da okunabilir, `0xe1a5` okunamaz.
- Tree-shaking kırmak, bir kategori ikonu için tüm Material ikon fontunu pakete koymak demektir.
- **Addan türetme KALDIRILMAZ**, `NULL` durumunun karşılığı olarak kalır: 40 kategorili bir
  kurulumda kullanıcı hepsini elle seçmek zorunda bırakılmaz. Zincir şudur:

```text
icon_key dolu      → seçilen ikon
icon_key NULL      → kategori ADINDAN türetilen ikon
ad da eşleşmiyor   → nötr ürün ikonu
```

**Neden v2 ve migration — v1'i düzenlemek değil:** [rules/03 §3](../.claude/rules/03-data-and-persistence.md)
koşulsuzdur: *"Şema doğrudan değiştirilemez. Her değişiklik versiyonlu bir migration adımıdır."*
v1.0.0 henüz yayınlanmamış olsa da geliştirme veritabanları v1 şemasıyla duruyor; `onCreate`'i
değiştirmek onları versiyon numarası aynı kaldığı için **sessizce eski şemada bırakırdı.**
Ayrıca bu, bugüne kadar yalnızca sentetik adımlarla test edilmiş migration altyapısının
**gerçek bir adımla** çalıştığını kanıtlar.

**Impact:**

| Doküman | Değişiklik |
|---|---|
| [04 §3.2](04-domain-model.md) | `Category` entity'sine `iconKey` alanı |
| [05 §2.2](05-database-architecture.md) | `categories.icon_key TEXT NULL`; şema versiyonu 2 |
| [06](06-database-migrations.md) | v1 → v2 adımı; ilk yayınlanmış migration |
| [10 §1](10-category-brand-supplier.md) | Kategori formunda ikon seçici |
| [21 §3](21-image-storage.md) | Görselsiz ürün ikonu zinciri netleşir |
| [25](25-functional-requirements.md) | REQ-CAT-009 · REQ-IMG-013 |
| [27](27-testing-strategy.md) | v1 → v2 migration testi (veri koruma) |

Kapsam etkisi: **v1 mimarisi genişlemez.** Yeni tablo, yeni entity ve yeni servis yoktur;
mevcut `Category` bir alan kazanır.

---

---

## 4. Yeni karar gerekirse

Geliştirme sırasında kararlaştırılmamış bir konu ortaya çıkarsa:

1. Bu dokümana `OD-030`'dan başlayarak yeni bir kayıt açılır.
2. `Decision / Options / Recommendation / Impact` formatı kullanılır.
3. Karar kapanmadan ilgili kod yazılmaz.
4. Kapandığında bu dokümandaki karar kaydına ve ilgili business rule'a dönüştürülür.
