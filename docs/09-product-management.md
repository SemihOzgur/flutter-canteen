# 09 — Ürün Yönetimi

## 1. Alan zorunlulukları

| Alan | Durum | Varsayılan | Not |
|---|---|---|---|
| Ürün adı | 🔴 Zorunlu | — | 1–120 karakter, baştaki/sondaki boşluk kırpılır |
| **Satış fiyatı (KDV Dahil)** | 🔴 Zorunlu | — | `>= 0`. **Etiket böyle görünür** — girilen tutar müşteriden alınan tutardır (BR-VAT-003) |
| Alış fiyatı | 🔴 Zorunlu | `₺0,00` | Boş bırakılırsa 0 kabul edilir (BR-PROD-002) |
| Kategori | 🔴 Zorunlu | `Genel` | Seçilmezse varsayılan kategori (BR-PROD-003) |
| Açıklama | ⚪ Opsiyonel | — | Maks. 500 karakter |
| Marka | ⚪ Opsiyonel | — | Serbest metin + otomatik tamamlama (BR-SUP-003) |
| **Satış birimi** | ⚪ Opsiyonel | — | Öneri listesi: adet, paket, kutu, koli. Açıklayıcı (BR-PROD-011) |
| **Net ağırlık / gramaj** | ⚪ Opsiyonel | — | Değer + birim (g, kg, ml, lt) — ikisi birlikte doldurulur (BR-PROD-011) |
| KDV oranı | ⚪ Opsiyonel | Varsayılan oran | Bkz. [08](08-vat-rules.md) |
| Tedarikçi | ⚪ Opsiyonel | — | |
| Raf konumu | ⚪ Opsiyonel | — | Maks. 50 karakter |
| Görsel | ⚪ Opsiyonel | — | Bkz. [21](21-image-storage.md) |
| Barkod(lar) | ⚪ Opsiyonel | — | 0..N adet, global benzersiz |
| Stok | ⚙️ Sistem | `0` | Elle düzenlenemez — yalnızca stok hareketiyle değişir |
| Minimum stok | ⚙️ Kullanıcı | `0` | `0` ise kritik stok uyarısı verilmez |
| Aktif | ⚙️ Sistem | `true` | |
| Favori | ⚙️ Kullanıcı | `false` | |
| Oluşturma / güncelleme tarihi | ⚙️ Sistem | now | |

> **Önemli:** Ürün formundaki "Stok" alanı **düzenlenebilir değildir.** Yeni ürün eklerken girilen
> başlangıç stoğu, `initial` tipinde bir stok hareketi oluşturur — doğrudan `stock_quantity` yazımı yapılmaz.
> Bu, BR-STOCK-003 invariant'ının ilk günden korunmasını sağlar.

### Satış birimi ve gramaj ayrımı

Bu iki alan farklı şeyleri anlatır ve karıştırılmamalıdır:

```text
Ürün:          Cips
Net ağırlık:   150 g        ← ambalajın içindeki miktar (açıklayıcı)
Satış birimi:  adet         ← nasıl satıldığı

Satışta miktar daima TAM SAYI'dır (BR-SALE-011): 1 adet, 2 adet, 3 adet.
Gramaj hiçbir fiyat veya stok hesabına girmez.
```

Tartılı satış (kg/gram bazlı ondalık miktar) **V1 kapsamında değildir**; ileride eklenebilir
([30 §3.2](30-future-scope.md)).

---

## 2. Ürün ekleme akışları

### 2.1 Hızlı ekleme (barkod okutuldu, ürün bulunamadı)

En kritik akış — kasada, müşteri beklerken gerçekleşir.

```text
Barkod okutuldu → bulunamadı
        ▼
┌─────────────────────────────────────────────┐
│  YENİ ÜRÜN (Hızlı)                          │
│  Barkod: 8691234567890  (dolu, salt okunur) │
│  Ürün adı:      [____________]  ← odak      │
│  Satış fiyatı (KDV Dahil): [_________]      │
│  Alış fiyatı:   [____________]  (boş = ₺0)  │
│  Kategori:      [Genel      ▾]              │
│  Başlangıç stoğu: [0]                       │
│                                             │
│  [Detaylı düzenle]     [Kaydet ve Sepete Ekle] │
└─────────────────────────────────────────────┘
```

- Yalnızca 4 zorunlu alan gösterilir → satış akışı kesilmez.
- `Enter` bir sonraki alana, son alanda `Enter` kaydeder.
- Kaydedildiğinde ürün **otomatik sepete eklenir** (BR-BARC-005) ve odak barkod girişine döner.
- `Esc` iptal eder; barkod kaybolmaz, kullanıcı tekrar okutabilir.

### 2.2 Detaylı ekleme (Ürünler ekranı)

Tüm alanlar, sekmeli düzen: **Genel · Fiyat & KDV · Stok · Barkodlar · Görsel**

### 2.3 Toplu ekleme

Excel/CSV import — bkz. [20](20-import-export.md).

---

## 3. Ürün düzenleme

| Değişiklik | Etki |
|---|---|
| Satış fiyatı | Yalnızca **bundan sonraki** satışları etkiler (BR-SALE-002). Audit log'a yazılır. |
| Alış fiyatı | Yalnızca bundan sonraki maliyet snapshot'larını etkiler. Audit log'a yazılır. |
| Kategori | Geçmiş satışlar `category_id_snapshot` taşıdığı için geçmiş kategori raporları değişmez. |
| Ad | Geçmiş satışlar `product_name_snapshot` taşır; değişmez. |
| Barkod ekleme/silme | Anında etkili. Silinen barkod global benzersizlik havuzundan çıkar. |
| KDV oranı | Yalnızca bundan sonraki satışları etkiler. |
| Görsel | Eski dosya orphan olarak işaretlenir ([21 §4](21-image-storage.md)). |

**Fiyat değişikliği onayı:** Satış fiyatı %50'den fazla değişiyorsa kullanıcıya onay sorulur
(yanlış kuruş/lira girişini yakalamak için).

---

## 4. Ürün silme ve pasifleştirme

Sistem, ürün "Sil" denildiğinde **önce geçmiş kullanımı kontrol eder** ve iki farklı davranış gösterir.

```text
Kullanıcı "Sil" der
        ▼
Bu ürünün hiç satışı VE hiç stok hareketi var mı?
        │
        ├── HAYIR (hiç kullanılmamış) ──────────────────► KALICI SİLME  [BR-PROD-014]
        │     "Bu ürün hiç satılmamış ve stok hareketi yok.
        │      Kalıcı olarak silinecek. Bu işlem geri alınamaz."
        │      [Vazgeç]  [Kalıcı Olarak Sil]
        │      → ürün + barkodları silinir, audit log'a yazılır
        │
        └── EVET (kullanılmış) ─────────────────────────► PASİFLEŞTİRME  [BR-PROD-009]
              "Bu ürün 47 satışta kullanılmış.
               Geçmiş kayıtların bozulmaması için ürün silinmez, pasife alınır.
               Pasif ürünler satış ekranında görünmez, raporlarda görünmeye devam eder."
              [Vazgeç]  [Pasife Al]
```

**Neden bu ayrım:** Kullanıcı yanlış bir ürün girdiğinde (yazım hatası, deneme kaydı) onu
kalıcı silebilmelidir. Ancak satılmış bir ürünü silmek geçmiş satış kayıtlarının snapshot'larını
anlamsızlaştırır ve raporları bozar — bu asla yapılmaz.

Kalıcı silme sonrası ürünün barkodları benzersizlik havuzundan **çıkar** ve başka ürüne atanabilir.

| Konu | Pasif ürün davranışı |
|---|---|
| Satış ekranı ürün listesi | Görünmez |
| Barkod okutma | Bulunur ama "Bu ürün pasif. Aktifleştirilsin mi?" sorulur (BR-BARC-007) |
| Ürün arama | Varsayılan gizli; "Pasifleri göster" filtresi ile görünür |
| Raporlar | Görünür |
| Stok raporu | "Pasif ürünler dahil" filtresi ile görünür |
| Sepette varken pasifleştirilirse | Sepette kalır, satış tamamlanabilir ([EC-PROD-004](26-edge-cases.md)) |

**Stoğu olan ürünün pasifleştirilmesi:** Uyarılır ("Bu ürünün 47 adet stoğu var") ama engellenmez.
Pasif ürünler stok değeri raporunda ayrı gösterilir.

---

## 5. Favoriler

- `Product.isFavorite` boolean; ayrı entity yok (bkz. [04 §1](04-domain-model.md)).
- Satış ekranında sabit bir "Favoriler" bölümünde gösterilir.
- Sıralama: kullanıcı tanımlı sürükle-bırak sırası → yoksa satış adedine göre.
- Ürün listesinde ve satış ekranında yıldız ikonu ile tek tıkla eklenip çıkarılır.
- **Ana kullanım amacı barkodsuz ürünlerdir** (tost, çay, poğaça).
- Öneri: 30'dan fazla favori eklenirse kullanıcı uyarılır (ekran karmaşası).

---

## 6. Ürün arama

Satış ekranı ve ürünler ekranı aynı arama davranışını paylaşır.

| Girdi | Davranış |
|---|---|
| Tamamen rakam + 8/12/13 hane | Önce barkod eşleşmesi denenir |
| Serbest metin | Ürün adında, sonra markada `contains` araması (büyük/küçük harf duyarsız, Türkçe karakter duyarsız: `ı/i`, `ş/s`, `ğ/g`, `ü/u`, `ö/o`, `ç/c`) |
| Boş | Kategori/favori listesi gösterilir |

- Sonuçlar **satış adedine göre** sıralanır (en çok satılan üstte) — kasada isabet oranını artırır.
- Arama 150 ms debounce ile çalışır.
- Maksimum 50 sonuç gösterilir.

---

## 7. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-PROD-001 | Ürün adı, satış fiyatı, alış fiyatı ve kategori olmadan ürün kaydedilemez. |
| REQ-PROD-002 | Alış fiyatı boş bırakılırsa `0` olarak kaydedilir. |
| REQ-PROD-003 | Kategori seçilmezse `Genel` kategorisi kullanılır. |
| REQ-PROD-004 | Bir ürüne birden fazla barkod eklenebilir. |
| REQ-PROD-005 | Sisteme daha önce kayıtlı bir barkod ikinci kez eklenemez; kullanıcıya barkodun hangi ürüne ait olduğu gösterilir. |
| REQ-PROD-006 | Satılmış veya stok hareketi olan ürün silinemez; yalnızca pasifleştirilebilir. |
| REQ-PROD-007 | Ürün formunda stok alanı doğrudan düzenlenemez; başlangıç stoğu bir stok hareketi oluşturur. |
| REQ-PROD-008 | Ürün fiyat değişiklikleri audit log'a eski ve yeni değeriyle yazılır. |
| REQ-PROD-009 | Ürün favorilere eklenip çıkarılabilir ve favoriler satış ekranında hızlı erişilebilir. |
| REQ-PROD-010 | Ürün arama Türkçe karakter ve büyük/küçük harf duyarsızdır. |
| REQ-PROD-011 | Net ağırlık değeri ve birimi alanlarından yalnızca biri doldurulmuş olarak kaydedilemez. |
| REQ-PROD-012 | Satış fiyatı %50'den fazla değiştirildiğinde kullanıcıdan onay alınır. |
| REQ-PROD-013 | Hiç satılmamış ve hiçbir stok hareketi bulunmayan ürün, kullanıcı onayıyla kalıcı olarak silinebilir. |
| REQ-PROD-014 | Ürün formundaki satış fiyatı alanı "KDV Dahil" olarak etiketlenir. |
| REQ-PROD-015 | Satış birimi ve net ağırlık alanları ayrı ayrı girilebilir ve yalnızca açıklayıcıdır. |

---

## 8. Acceptance criteria

**REQ-PROD-005**
```text
Given: "8691234567890" barkodu "Coca Cola 330ml" ürününe kayıtlı
When:  Kullanıcı "Su 500ml" ürününe aynı barkodu eklemeye çalışıyor
Then:  Kayıt reddedilir
And:   "Bu barkod zaten 'Coca Cola 330ml' ürününe ait" mesajı gösterilir
And:   Kullanıcıya o ürüne gitme seçeneği sunulur
```

**REQ-PROD-007**
```text
Given: Kullanıcı yeni ürün ekliyor ve başlangıç stoğu 50 giriyor
When:  Ürün kaydediliyor
Then:  products.stock_quantity = 50 olur
And:   type='initial', quantity_delta=50, resulting_stock=50 olan bir stok hareketi oluşur
And:   Ürünün stok geçmişinde bu hareket görünür
```

**REQ-PROD-006**
```text
Given: Bir üründe 12 adet geçmiş satış kaydı var
When:  Kullanıcı ürünü siliyor
Then:  Kalıcı silme seçeneği SUNULMAZ
And:   Ürün veritabanından silinmez, is_active = false olur
And:   Geçmiş satış raporları etkilenmez
And:   Ürün satış ekranındaki listede görünmez
```

**REQ-PROD-013**
```text
Given: Kullanıcı yanlışlıkla "Deneme Ürün" adında bir ürün eklemiş
And:   Bu ürün hiç satılmamış ve hiç stok hareketi yok
When:  Kullanıcı ürünü siliyor
Then:  "Kalıcı olarak silinecek" onayı gösterilir
When:  Onaylanıyor
Then:  Ürün ve barkodları veritabanından tamamen silinir
And:   Barkodları başka bir ürüne atanabilir hale gelir
And:   Audit log'a kalıcı silme kaydı yazılır
```

**REQ-PROD-014**
```text
Given: Kullanıcı yeni ürün ekliyor ve satış fiyatına 120 giriyor
When:  Ürün satılıyor
Then:  Sepette ₺120,00 gösterilir
And:   Müşteriden ₺120,00 alınır
And:   Fiyatın üzerine KDV eklenmez
```
