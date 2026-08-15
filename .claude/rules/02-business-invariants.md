# 02 — Business Invariants (Para, KDV, Stok, Satış, Ürün)

> Kaynak: `docs/07-financial-rules.md` · `08-vat-rules.md` · `09-product-management.md`
> `11-barcode-system.md` · `12-sales-system.md` · `13-stock-system.md` · `14-returns-and-cancellation.md`
>
> **Bu dosyadaki hiçbir kural Claude tarafından değiştirilemez.** Değişiklik gerekiyorsa
> [`00-source-of-truth.md §3`](00-source-of-truth.md) protokolü işletilir.

---

## 1. PARA

### Mutlak kural

> **Floating point ile para hesabı YASAKTIR.**

| Konu | Kural |
|---|---|
| Saklama | **Tam sayı kuruş** (minor unit), 64-bit signed integer |
| Örnek | `₺25,50` → `2550` · `₺0,05` → `5` · `₺1.234,00` → `123400` |
| Oranlar | **Basis point** tam sayı: %20 → `2000`, %0,5 → `50` |
| Yuvarlama | **Half-up**, yalnızca **satır seviyesinde** |
| Ara sonuçlar | Yuvarlanmaz |
| Toplam | Yuvarlanmış satır değerlerinin **toplamıdır** |

**Invariant:** `Σ(satır tutarları) == genel toplam` — kullanıcı fişteki satırları elle
toplayınca tutmalıdır.

### Domain ↔ Presentation ayrımı

```text
domain/       → yalnızca int (kuruş). double ASLA kullanılmaz.
presentation/ → ₺25,50 biçimlendirmesi (tr_TR) — sadece gösterim
```

Formatlama bir **presentation concern**'üdür; domain formatlanmış string üretmez.

### Girdi kabulü

Kullanıcı `25,50` · `25.50` · `25` · `₺25,50` yazabilir → hepsi `2550`'ye normalize edilir.
Belirsiz ayırıcılar `tr_TR` kuralına göre yorumlanır.

---

## 2. KDV — SATIŞ FİYATI KDV DAHİLDİR

> **BR-VAT-003.** Bu proje sahibinin kesin kararıdır.

### Tek geçerli formül

```text
lineTotalMinor = unitPriceMinor × quantity            (KDV DAHİL brüt)
lineVatMinor   = roundHalfUp( lineTotalMinor × vatBp / (10000 + vatBp) )
lineNetMinor   = lineTotalMinor − lineVatMinor        (matrah)
```

> **Kaynak: `docs/08-vat-rules.md` §2.**
> Buradaki formül yalnızca **geliştirici referansı** amacıyla tekrarlanmıştır.
> **Çelişki halinde `docs/08-vat-rules.md` geçerlidir.**

### Doğrulanmış örnek

```text
Ürün satış fiyatı : ₺120,00  → 12000   (KDV dahil)
KDV oranı         : %20      → 2000 bp

grandTotal        = 12000    ← müşteri ₺120,00 öder
vatComponent      =  2000    ← ₺20,00
taxExclusiveSub   = 10000    ← ₺100,00
```

### Alan anlamları

| Alan | Anlam |
|---|---|
| `Product.salePrice` | **KDV dahil** |
| `SaleItem.unitPrice` | **KDV dahil** snapshot |
| `Sale.grandTotal` | **KDV dahil** — müşteriden alınan tutar |
| `Sale.subtotal` | **KDV hariç** matrah |
| `Sale.vatTotal` | KDV bileşeni |

**Invariant:** `subtotal + vatTotal == grandTotal`

### Yasaklar

| ❌ | |
|---|---|
| Fiyatın **üzerine** KDV eklemek | En kritik regresyon riski — açık test yazılır |
| KDV oranını koda gömmek | Oranlar `vat_rates` tablosundan gelir |
| Kurulumda KDV oranı seed etmek | Kullanıcı kendi oranlarını tanımlar |
| KDV'yi UI'da hesaplamak | Tek merkezî domain implementasyonu |

KDV oranı tanımlı değilse: `vat = 0`, `net = total` (BR-VAT-005).

---

## 3. SNAPSHOT KURALI

> **Geçmiş satışlar mevcut ürün verisinden yeniden hesaplanamaz.**

`SaleItem` satış anında **beş** snapshot alanı yazar:

| Alan | İçerik |
|---|---|
| `product_name_snapshot` | Satış anındaki ürün adı |
| `unit_price_minor` | Satış anındaki birim fiyat (**KDV dahil**) |
| `purchase_price_snapshot_minor` | Satış anındaki **alış fiyatı** |
| `vat_rate_snapshot_bp` | Satış anındaki KDV oranı |
| `category_id_snapshot` | Satış anındaki kategori |

Ayrıca `original_unit_price_minor` (fiyat override'ı raporlamak için) ve `barcode_snapshot`.

### Kurallar

- Bu alanlar yazıldıktan sonra **immutable**'dır.
- Ürünün adı, fiyatı, alış fiyatı, KDV oranı veya kategorisi sonradan değişirse
  **geçmiş satış değişmez.**
- Raporlar geçmiş veriyi `products` tablosundan **JOIN ile türetmez**; snapshot alanlarını kullanır.
- KDV raporları `vat_rate_snapshot_bp` üzerinden gruplanır — `vat_rates`'e JOIN yapılmaz.

### Maliyet ve kâr

```text
purchase_price_snapshot_minor  ← satış anındaki products.purchase_price_minor kopyası
Kâr = (KDV hariç matrah) − (purchase_price_snapshot_minor × quantity)
```

Kâr **daima KDV hariç matrah** üzerinden hesaplanır (KDV işletmenin geliri değildir).

---

## 4. STOK

### Defter modeli

> Stok basit bir integer değişken **değildir.** `stock_movements` **source of truth**'tur.

| Kural | |
|---|---|
| `products.stock_quantity` | Türetilmiş **önbellek**; defterle **aynı transaction** içinde güncellenir |
| Invariant | `stock_quantity == Σ stock_movements.quantity_delta` |
| Hareket kaydı | Yazıldıktan sonra **UPDATE/DELETE edilmez** |
| Düzeltme | Ters yönde **yeni hareket** ile yapılır |
| `quantity_delta` | Asla `0` olamaz |
| `resulting_stock` | Her harekette kaydedilir |

### Hareket tipleri

`initial` · `stockEntry` · `sale` · `saleCancellation` · `return` · `waste` · `adjustment` · `importAdjustment`

### Sebep/referans zorunluluğu

> **Her stok hareketi bir sebep veya referans taşır** (BR-STOCK-010).

| Hareket | Taşıdığı |
|---|---|
| `sale` / `saleCancellation` / `return` | `reference_type` + `reference_id` |
| `stockEntry` | tedarikçi + (opsiyonel belge no) |
| `waste` / `adjustment` | **zorunlu sebep metni** |
| `importAdjustment` | import referansı |

"Bu ürünün stoğu neden 12?" sorusu **defterden geriye dönük yanıtlanabilmelidir.**

### Tek yazım noktası

`stock_quantity` **yalnızca** `StockService` üzerinden değişir. Başka hiçbir kod yolu bu alana yazmaz.
(Aksi halde [RSK-008](../../docs/29-risks.md) gerçekleşir: sessiz stok sapması.)

---

## 5. NEGATİF STOK

> **BR-STOCK-006 — Stok 0 veya altındayken satış OTOMATİK ENGELLENMEZ.**

```text
Stok <= 0 olan ürün sepete ekleniyor
        ▼
⚠ "Bu ürünün stoğu tükenmiş."
   [İptal]        [Devam Et]
        ▼
Kullanıcı "Devam Et" derse → satış yapılır → stok negatife düşer (0 → -1)
```

| Kural | |
|---|---|
| Satışı bloklamak | ❌ **YASAK** |
| Negatif stok | ✅ Geçerli bir durumdur |
| Görünürlük | Dashboard + stok raporunda **ayrıca listelenir** |
| Uyarı kapatma | Ayarlardan kapatılabilir; satır yine de işaretlenir |

> Bu bir **business rule**'dur. "Daha güvenli olur" gerekçesiyle engelleyici hale getirilemez.

---

## 6. SATIŞ TRANSACTION'I

> **Yarım satış kesinlikle oluşamaz.**

Tek atomik transaction içinde:

```text
BEGIN
  1. Satış numarası üret (sayaç aynı transaction içinde artar)
  2. sales satırı
  3. Her satır için:
       sale_items (5 snapshot alanı + KDV çıkarımı)
       stock_movements (type=sale, delta=-qty, resulting_stock)
       products.stock_quantity güncelle
  4. Aktif sepeti kapat (status=closed)
  5. Yeni boş aktif sepet oluştur
  6. audit_logs
COMMIT
```

- Herhangi bir adımda hata → **tam rollback**, sepet korunur.
- Transaction içinde dosya I/O veya UI beklemesi **yoktur**.
- Çift gönderim (butona üst üste basma) **tek satış** üretir.

---

## 7. İADE VE İPTAL

Her ikisi de **atomik**tir.

| | Satış İptali | İade |
|---|---|---|
| Kapsam | Satışın tamamı | Satırların bir kısmı veya tamamı |
| Kayıt | `sales.status = cancelled` | `returns` + `return_items` |
| Tekrarlanabilir | ❌ | ✅ kalan miktar kadar |
| Ön koşul | Hiç iade yapılmamış olmalı | Satış `cancelled` olmamalı |

### Kurallar

- **Kısmi iade desteklenir** (`Return` / `ReturnItem` entity'leri).
- İade tutarı **orijinal `unit_price_minor` snapshot'ından** hesaplanır — güncel fiyat kullanılmaz.
- Bir satırın toplam iadesi satılan miktarı **aşamaz**.
- Stok defterine **pozitif hareket** yazılır; orijinal satış hareketi silinmez.
- **Satış geçmişi silinmez** — yalnızca durum değişir:
  `completed → partiallyReturned → returned` veya `completed → cancelled`.
- İade **iade tarihine** göre raporlanır; orijinal satışın tarihi/tutarı değişmez (BR-RET-008).
- Raporlar **net** değer gösterir: `net = satış − iptal − iade`.

---

## 8. MİKTAR

> **BR-SALE-011 — Satış miktarı POZİTİF TAM SAYIDIR.**

| | |
|---|---|
| Ondalık miktar | ❌ Yok |
| Tartılı ürün | ❌ Yok |
| Kilogram bazlı satış | ❌ Yok |
| `quantity` tipi | `INTEGER`, `CHECK(quantity > 0)` |

Ürünün `net_weight_value` / `net_weight_unit` alanları (örn. 150 g) **yalnızca açıklayıcıdır**
ve hiçbir fiyat/stok hesabına girmez.

> Gelecekte tartılı satış eklenebilir; ancak **V1 mimarisi bunun için karmaşıklaştırılmaz.**
> `quantity_milli` gibi alanlar bugün oluşturulmaz.

---

## 9. ÜRÜN

### Zorunlu alanlar

`name` · `salePrice` (KDV dahil) · `purchasePrice` · `category`

### Kurallar

| Konu | Kural |
|---|---|
| Alış fiyatı | Hızlı eklemede boş bırakılabilir → `0` kaydedilir (asla `null`) |
| Kategori | Zorunlu; seçilmezse `Genel` sistem kategorisi |
| Barkod | **Zorunlu değil** — ürün barkodsuz olabilir |
| Çoklu barkod | Bir ürünün 0, 1 veya N barkodu olabilir |
| Barkod benzersizliği | **Global UNIQUE** — pasif ürünler dahil |
| Satış fiyatı | `>= 0` (0 = ikram ürünü) |
| Başlangıç stoğu | Doğrudan yazılmaz; `initial` stok hareketi oluşturur |

### Silme politikası

```text
Hiç satılmamış VE hiç stok hareketi yok  →  KALICI SİLİNEBİLİR (BR-PROD-014)
Aksi halde                               →  YALNIZCA PASİFLEŞTİRME (BR-PROD-009)
```

Geçmiş satış kayıtlarını bozacak hiçbir silme yapılamaz.
Aynı mantık kategoriler için de geçerlidir (BR-CAT-005).

### Favoriler

- `Product.isFavorite` boolean **yeterlidir.**
- Ayrı `Favorite` entity **oluşturulmaz.**
- Favoriler satış ekranında hızlı erişilebilir olmalıdır (özellikle barkodsuz ürünler için).

---

## 10. BARKOD

### Donanım yaklaşımı

> **HID Keyboard Emulation.** Uygulama cihaza özel SDK **kullanmaz.**

- Referans doğrulama cihazı: **Sunlux RH10** — ancak uygulama bu modele **bağımlı değildir.**
- USB veya Bluetooth, keyboard-emulation destekleyen **her scanner** çalışmalıdır.
- Scanner işletim sistemi tarafından klavye olarak görülür.

### Ayırt etme

Karakterler arası süre eşiği + `Enter`/`CR` sonlandırıcı ile klavye yazımından ayrılır
(`docs/11 §2` — eşik değerleri).

### Bilinmeyen barkod akışı — korunmalıdır

```text
Barkod okutuldu
      ▼
Local database'de ara
      ▼
BULUNDU     → doğrudan sepete ekle (ara onay YOK)
BULUNAMADI  → "Yeni Ürün" ekranı açılır
              → barkod alanı OTOMATİK DOLU
              → kullanıcı ad + fiyat girer
              → kaydet → ürün OTOMATİK sepete eklenir
```

### Diğer kurallar

- Barkodlar **metin** olarak saklanır; **baştaki sıfırlar korunur** (sayıya çevrilmez).
- Aynı ürün tekrar okutulursa yeni satır açılmaz; miktar artar.
- **Barkodsuz ürünler** satış ekranından arama / kategori filtresi / favoriler üzerinden
  **tıklanarak** sepete eklenir.

---

## 11. V1'DE YAPILMAYACAKLAR

> Bu bölüm **yeni business rule üretmez.** `docs/` içinde zaten kesinleşmiş kararların
> rule seviyesindeki korumasıdır — implementation sırasında sessizce ihlal edilmelerini engeller.

### 11.1 İndirim

- V1'de **ayrı discount/indirim sistemi yoktur.**
- `discounts` entity/tablosu **oluşturulmaz.**
- İndirim UI'ı veya indirim workflow'u **eklenmez.**
- Fiyat override mekanizması (bu dosya §12 · `docs/12 §4`) bu ihtiyacı karşılar.
- `sales.discount_total_minor` alanı şemada mevcuttur ve **V1'de daima `0`**'dır.

**Kaynak:** `docs/28-open-decisions.md` → **OD-007**

### 11.2 Nakit yuvarlama

- V1'de **nakit yuvarlama yoktur.**
- `rounding_minor` gibi alanlar **oluşturulmaz.**
- Satış ödeme akışında yalnızca şu üç değer bulunur:

```text
Toplam
Alınan
Para üstü
```

**Kaynak:** `docs/28-open-decisions.md` → **OD-008**

### 11.3 Kasa / vardiya

- V1'de **kasa açılışı/kapanışı yoktur.**
- **Vardiya yönetimi yoktur.**
- **Kasa sayımı yoktur.**
- **Kasa farkı hesabı yoktur.**
- Bu kapsamı genişletecek entity / table / service / UI **oluşturulmaz.**

**Kaynak:** `docs/28-open-decisions.md` → **OD-010** ve `docs/30-future-scope.md` §3.1

### 11.4 Ayrı Brand / Unit / Payment entity'leri

- **`Brand`** ayrı entity/table **değildir** → `products.brand` serbest metin.
- **`Unit`** ayrı entity/table **değildir** → `products.sales_unit` serbest metin.
- **`Payment`** ayrı entity/table **değildir** → `sales.cash_received_minor` + `change_minor`.
- V1 mevcut domain modelindeki alanlar üzerinden çalışır.
- Gelecekte entity'ye dönüşüm gerekirse **migration yolu `docs/` içinde tanımlıdır** — bugün uygulanmaz.

**Kaynak:** `docs/04-domain-model.md` §1 · BR-SUP-003 · BR-SUP-004

### 11.5 Favorite

- **`Favorite`** ayrı entity/table **değildir.**
- Mevcut ürün modelindeki favorite yaklaşımı (`products.is_favorite`) kullanılır.
- Kullanıcıya özel favori kümesi V1'de yoktur (rol sistemi olmadığı için gereksizdir).

**Kaynak:** `docs/04-domain-model.md` §1 · BR-PROD-008

### 11.6 Bu bölümün statüsü

Yukarıdakilerden birine ihtiyaç duyulduğu düşünülüyorsa:

```text
🛑 DUR  →  00-source-of-truth.md §5.2
           Kapsam genişletme kararı proje sahibinindir.
           İlgili OD güncellenmeden implementasyon yapılmaz.
```

`docs/30-future-scope.md`, bu maddelerin ileride nasıl eklenebileceğini zaten analiz etmiştir;
**o analiz bir uygulama izni değildir.**

---

## 12. AKTİF SEPET

| Kural | |
|---|---|
| Aynı anda | **Tek** aktif sepet |
| Kalıcılık | Her değişiklikte veritabanına yazılır |
| Çökme sonrası | Aynen geri yüklenir |
| Stok etkisi | **YOK** — sepet stok rezerve etmez |
| Ciro/rapor etkisi | **YOK** |
| Boş sepet | Satış tamamlanamaz |

> **Aktif sepet ile tamamlanmış satış kesinlikle ayrı veri yapılarındadır** (`carts` ↔ `sales`).
> Bu ayrım mimariyle zorlanır; tek tabloda birleştirilemez.

Satış sırasında satır fiyatı değiştirilebilir — ancak bu `Product.salePrice`'ı **değiştirmez**
ve `original_unit_price_minor` ile birlikte audit log'a yazılır.
