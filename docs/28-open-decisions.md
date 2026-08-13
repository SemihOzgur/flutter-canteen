# 28 — Karar Kaydı (Decision Log)

> **Doküman sürümü:** v3 (revizyon: 2026-08-13)
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

## 3. Kararların faz üzerindeki etkisi

```text
Faz 0  →  ARTIK BOŞ. Bekleyen karar yok.
Faz 1  →  Riverpod + merkezî metin yapısı kurulur
Faz 2  →  Şema final; blokaj yok
Faz 3  →  Recovery code, finansal erişim kilidi, görsel politikası
Faz 5  →  Son alış fiyatı snapshot'ı, indirim yok, nakit yuvarlama yok
Faz 8  →  fl_chart; Raporlar kilit arkasında
Faz 9  →  ZIP yedek
Faz 10 →  CSV birincil + Excel abstraction
Faz 12 →  Inno Setup
```

---

## 4. Yeni karar gerekirse

Geliştirme sırasında kararlaştırılmamış bir konu ortaya çıkarsa:

1. Bu dokümana `OD-017`'den başlayarak yeni bir kayıt açılır.
2. `Decision / Options / Recommendation / Impact` formatı kullanılır.
3. Karar kapanmadan ilgili kod yazılmaz.
4. Kapandığında bu dokümandaki karar kaydına ve ilgili business rule'a dönüştürülür.
