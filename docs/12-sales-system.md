# 12 — Satış Sistemi

> **Doküman sürümü:** v2 — KDV dahil fiyatlandırma ve tam sayı miktar kesinleşti.

Uygulamanın kalbi. Bu ekranda geçirilen süre toplam kullanım süresinin %90'ıdır.

**Bu ekranda geçerli iki kesin kural:**
- Ürün fiyatları **KDV dahildir** (BR-VAT-003) — sepet toplamı müşteriden alınan tutardır, üzerine hiçbir ek yapılmaz.
- Miktarlar **pozitif tam sayıdır** (BR-SALE-011) — ondalık miktar girilemez.

## 1. Ekran düzeni

```text
┌──────────────────────────────────────────────────────────────────────┐
│  🔍 BARKOD / ÜRÜN ARA           [F1 Yardım]  [F3 Ürünler] [Dashboard]│  ← daima odaklı
├───────────────────────────────────────┬──────────────────────────────┤
│  ⭐ FAVORİLER                          │  SEPET                       │
│  ┌──────┐┌──────┐┌──────┐┌──────┐     │  ┌────────────────────────┐  │
│  │ Çay  ││ Tost ││Poğaça││ Su   │     │  │ Coca Cola 330ml        │  │
│  └──────┘└──────┘└──────┘└──────┘     │  │ ₺25,00 × 2    ₺50,00 ✕ │  │
│                                        │  ├────────────────────────┤  │
│  KATEGORİLER                           │  │ Tost                   │  │
│  [Tümü][İçecek][Atıştırmalık][Sıcak]  │  │ ₺45,00 × 1    ₺45,00 ✕ │  │
│                                        │  └────────────────────────┘  │
│  ÜRÜNLER                               │                              │
│  ┌────────────────────────────────┐   │  Matrah          ₺79,17      │
│  │ Coca Cola 330ml       ₺25,00   │   │  KDV %20         ₺15,83      │
│  │ Su 500ml              ₺10,00   │   │  ──────────────────────────  │
│  │ Çikolata              ₺30,00   │   │  TOPLAM          ₺95,00      │
│  │ ...                            │   │                              │
│  └────────────────────────────────┘   │  [F4 Nakit]  [F12 TAMAMLA]   │
│                                        │  [Ctrl+Del Sepeti Temizle]   │
└───────────────────────────────────────┴──────────────────────────────┘
```

Sepet paneli genişliği ekranın ~%38'i. 1366×768'de de tam çalışır.

---

## 2. Aktif sepet (Cart)

### 2.1 Kalıcılık stratejisi

> **Karar: Aktif sepet, veritabanında `carts` / `cart_items` tablolarında tutulur.**

Değerlendirilen alternatifler:

| Seçenek | Değerlendirme |
|---|---|
| Yalnızca bellekte | ❌ Çökme/elektrik kesintisinde kaybolur — gereksinime aykırı |
| `shared_preferences` / JSON dosya | ❌ Atomik değil; yazma sırasında kesinti bozuk dosya bırakır. Ayrı bir kalıcılık mekanizması ayrı bir bozulma kaynağıdır. |
| **Veritabanı tabloları** | ✅ Aynı WAL/transaction garantileri; backup'a doğal dahil; sorgulanabilir |

Gerekçe: Sepet zaten ilişkisel bir veridir (ürün referansı, miktar, fiyat). Aynı dayanıklılık
garantilerinin ikinci bir mekanizmayla yeniden kurulmasına gerek yoktur.

### 2.2 Yazma stratejisi

Her sepet değişikliği (ekle, sil, miktar değiştir, fiyat değiştir) **anında** veritabanına yazılır.

```text
Kullanıcı sepete ürün ekledi
      ▼
UI hemen güncellenir (optimistic)
      ▼
Aynı frame'de DB yazımı (transaction)
      ▼
Yazma başarısızsa → UI geri alınır + hata gösterilir
```

Performans endişesi yok: tek satırlık INSERT/UPDATE, WAL modunda < 1 ms.

### 2.3 Sepet ≠ Satış

> **BR-CART-003 — bu ayrım kesindir ve mimariyle zorlanır.**

| | Aktif Sepet | Satış |
|---|---|---|
| Tablolar | `carts`, `cart_items` | `sales`, `sale_items` |
| Stoğa etkisi | ❌ Yok | ✅ Var |
| Raporlara etkisi | ❌ Yok | ✅ Var |
| Ciroya etkisi | ❌ Yok | ✅ Var |
| Silinebilir mi | ✅ Evet | ❌ Hayır |
| Fiyat snapshot'ı | Geçici (yeniden hesaplanabilir) | Kalıcı, değişmez |

Sepet **stok rezerve etmez** (BR-CART-004). Tek kullanıcılı sistemde rezervasyonun anlamı yoktur
ve sepette unutulan ürünlerin stoğu kilitlemesi zarar verir.

### 2.4 Restore akışı

```text
Uygulama açıldı
      ▼
status = 'active' olan cart var mı?
      ├── Yok  → boş sepet oluştur
      └── Var  → sepeti yükle
              ▼
        Sepetteki her ürün hâlâ mevcut mu?
              ├── Ürün silinmiş (imkânsız — hard delete yok) → n/a
              ├── Ürün pasifleşmiş → satırı işaretle, kullanıcıya bildir, satış engellenmez
              └── Ürünün fiyatı değişmiş → sepetteki fiyat KORUNUR, satır "fiyat güncellendi"
                    rozetiyle işaretlenir, kullanıcı isterse güncelleyebilir
              ▼
        "Yarım kalan satışınız geri yüklendi (3 ürün, ₺95,00)" bilgi çubuğu
```

**Fiyat davranışı gerekçesi:** Kullanıcı sepeti oluştururken müşteriye bir fiyat söylemiş olabilir.
Sepetteki fiyatı sessizce değiştirmek kasada tutarsızlık yaratır. Değişiklik **gösterilir**, kararı kullanıcı verir.

---

## 3. Sepet işlemleri

| İşlem | Kısayol | Davranış |
|---|---|---|
| Barkodla ekle | (okutma) | [11 §4](11-barcode-system.md) |
| Aramadan ekle | `Enter` | Seçili ürün eklenir |
| **Barkodsuz ürünü ekle** | tıklama | Ürün listesinden/kategori filtresinden doğrudan tıklanarak (BR-BARC-008) |
| Kategori filtresi | tıklama | Ürün listesini kategoriye göre daraltır |
| Favoriden ekle | `Alt+1..9` / tıklama | |
| Miktar artır | `+` veya `↑` | Seçili satır |
| Miktar azalt | `-` veya `↓` | 0'a düşerse satır silinir (onay sorulur) |
| Miktar doğrudan gir | `*` sonra sayı | "3× yaz" hızlı giriş |
| Satır sil | `Del` | Onay sorulmaz (geri alınabilir) |
| Son işlemi geri al | `Ctrl+Z` | Sepet işlemleri için, son 10 adım |
| Satır fiyatı değiştir | `F2` | §4 |
| Sepeti temizle | `Ctrl+Del` | Onay sorulur (OD-024) |
| Nakit hesapla | `F4` | §5 |
| Satışı tamamla | `F12` | §6 |

### Sepet satırı birleştirme kuralı

Aynı ürün, **aynı birim fiyatla** eklenirse tek satırda birleşir.
Fiyatı değiştirilmiş bir satır varken aynı ürün normal fiyatla eklenirse **ayrı satır** oluşur —
kullanıcı iki farklı fiyatı bilinçli olarak uygulamış demektir.

---

## 4. Satış sırasında fiyat değiştirme

```text
Satırda F2
      ▼
┌────────────────────────────────────┐
│ Fiyat Değiştir — Coca Cola 330ml   │
│ Liste fiyatı (KDV dahil): ₺25,00   │
│ Yeni fiyat (KDV dahil):  [ 20,00 ] │
│ ⚠ Bu değişiklik yalnızca bu satışa │
│   uygulanır. Ürünün fiyatı değişmez.│
│           [Vazgeç]  [Uygula]       │
└────────────────────────────────────┘
```

| Kural | ID |
|---|---|
| `Product.salePrice` değişmez | BR-SALE-003 |
| `SaleItem.originalUnitPriceMinor` liste fiyatını saklar | BR-SALE-004 |
| Audit log'a yazılır (`salePriceOverridden`) | BR-SALE-004 · OD-023 |
| Satır "fiyat değiştirildi" rozetiyle gösterilir | — |
| Negatif fiyat girilemez | BR-PROD-006 |

Bu yapı, ileride indirim sisteminin (yüzde indirim, kampanya) `originalUnitPrice` ↔ `unitPrice`
farkı üzerinden raporlanabilmesini sağlar. Bkz. [OD-007](28-open-decisions.md).

---

## 5. Nakit hesaplama

Opsiyoneldir; satışı bloklamaz (BR-SALE-007).

```text
F4
      ▼
┌──────────────────────────────┐
│ Toplam:        ₺135,00       │
│ Alınan:        [ 200,00 ]    │
│ ─────────────────────────    │
│ PARA ÜSTÜ:     ₺65,00        │  ← canlı hesaplanır
│                              │
│ Hızlı: [₺140][₺150][₺200]    │  ← akıllı öneriler
│        [Tam tutar]           │
│      [Vazgeç]  [Tamamla F12] │
└──────────────────────────────┘
```

- Alınan < toplam ise "Tamamla" pasiftir (BR-SALE-008).
- Alınan girilmezse `cashReceivedMinor` ve `changeMinor` `NULL` kaydedilir.
- Bu bir ödeme entegrasyonu değildir; yalnızca aritmetiktir.

---

## 6. Satışı tamamlama

### 6.1 Ön kontroller

| Kontrol | Başarısızsa |
|---|---|
| Sepet boş mu? | "Sepet boş" uyarısı, işlem yapılmaz (BR-CART-005) |
| Alınan nakit yeterli mi (girildiyse)? | Tamamlama engellenir |
| Stoğu tükenmiş ürün var mı? | Uyarı gösterilir, kullanıcı devam edebilir (BR-STOCK-006) |
| İşlem zaten devam ediyor mu? | Buton kilitlenir — çift gönderim engellenir ([EC-SALE-008](26-edge-cases.md)) |

### 6.2 Atomik transaction

> **BR-SALE-005 — Aşağıdaki adımların tümü tek transaction içindedir.**

```text
BEGIN TRANSACTION
  1. Satış numarası üret (app_settings sayacı, aynı transaction içinde artır)
  2. sales satırı oluştur (toplamlar, completedAt = now)
  3. Her sepet satırı için:
       a. Ürünün güncel purchasePrice, vatRate, ad ve kategori değerlerini oku
       b. sale_items satırı yaz — BEŞ SNAPSHOT ALANI (BR-SALE-001):
            productNameSnapshot, unitPriceMinor (KDV dahil),
            purchasePriceSnapshotMinor, vatRateSnapshot, categoryIdSnapshot
          + KDV çıkarımı: lineVat = roundHalfUp(lineTotal × bp / (10000+bp))
       c. stock_movements satırı yaz (type=sale, delta=-qty, resultingStock)
       d. products.stock_quantity güncelle
  4. carts.status = 'closed'
  5. Yeni boş active cart oluştur
  6. audit_logs kaydı yaz (saleCompleted)
COMMIT
```

Herhangi bir adımda hata → tam rollback. **Yarım satış oluşamaz.**

Transaction'ın kısa tutulması kritiktir: hiçbir dosya I/O, hiçbir UI beklemesi transaction
içinde yapılmaz. Hedef süre: **< 50 ms**.

### 6.3 Tamamlama sonrası

```text
✅ Satış tamamlandı — Fiş No: 2026-000148
   Toplam ₺135,00 · Para üstü ₺65,00
```

- 3 saniye görünen bildirim (ya da yeni barkod okutulduğunda hemen kaybolur).
- Sepet boşalır, odak barkod girişine döner.
- **Kullanıcı hiçbir şeye tıklamak zorunda kalmaz** — bir sonraki satışa hazırdır.

### 6.4 Satış numarası

Format: `YYYY-NNNNNN` → `2026-000148`

- Sayaç `app_settings['sale_counter_<yıl>']` içinde tutulur, satış transaction'ı içinde artırılır.
- Yıl değişince sıfırlanır.
- Restore sonrası sayaç, geri yüklenen veritabanındaki en yüksek numaraya göre düzeltilir
  ([19 §5](19-backup-restore.md)).

---

## 7. Satış geçmişi

Satışlar listelenebilir ve incelenebilir:

| Özellik | Detay |
|---|---|
| Filtreler | Tarih aralığı, durum, kullanıcı, tutar aralığı, ürün içeren |
| Arama | Satış numarası |
| Detay | Satırlar, snapshot fiyatlar, KDV, maliyet, kâr, nakit bilgisi, ilgili stok hareketleri |
| İşlemler | Satışı iptal et, iade oluştur (bkz. [14](14-returns-and-cancellation.md)) |
| Sayfalama | 50'şerli, sonsuz kaydırma |

---

## 8. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-CART-001 | Aynı anda yalnızca bir aktif sepet bulunabilir. |
| REQ-CART-002 | Sepetteki her değişiklik anında kalıcı olarak saklanır. |
| REQ-CART-003 | Uygulama beklenmedik şekilde kapanırsa, yeniden açıldığında aktif sepet aynen geri yüklenir. |
| REQ-CART-004 | Aktif sepet stok, ciro veya raporlara hiçbir etki yapmaz. |
| REQ-CART-005 | Sepet satırının fiyatı değiştirilebilir; ürünün fiyatı değişmez. |
| REQ-CART-006 | Aynı ürün aynı fiyatla tekrar eklenirse mevcut satırın miktarı artar. |
| REQ-CART-007 | Sepet geri yüklenirken ürün fiyatı değişmişse sepetteki fiyat korunur ve kullanıcı bilgilendirilir. |
| REQ-CART-008 | Boş sepetle satış tamamlanamaz. |
| REQ-SALE-001 | Satış; satırlar, stok hareketleri ve stok güncellemesi ile birlikte tek atomik transaction'da kaydedilir. |
| REQ-SALE-002 | Her satış satırı ürün adı, birim fiyat, birim maliyet, KDV oranı ve kategori snapshot'ı taşır. |
| REQ-SALE-003 | Ürün fiyatı sonradan değiştiğinde geçmiş satış kayıtları değişmez. |
| REQ-SALE-004 | Satış sırasındaki fiyat değişiklikleri audit log'a yazılır. |
| REQ-SALE-005 | Her satışın benzersiz, kullanıcıya gösterilen bir satış numarası vardır. |
| REQ-SALE-006 | Satış tamamlandıktan sonra yeni boş sepet otomatik oluşur ve odak barkod girişine döner. |
| REQ-SALE-007 | Nakit hesaplama opsiyoneldir ve satışı bloklamaz. |
| REQ-SALE-008 | Satış tamamlama butonuna arka arkaya basılması ikinci bir satış oluşturmaz. |
| REQ-SALE-009 | Satış tamamlama işlemi 50 ms içinde tamamlanır. |
| REQ-SALE-010 | Satış geçmişi tarih, durum ve tutar filtreleriyle listelenebilir. |
| REQ-SALE-011 | Satış ve sepet miktarları pozitif tam sayıdır; ondalık miktar girilemez. |
| REQ-SALE-012 | Sepet toplamı, ürün fiyatlarının (KDV dahil) toplamına eşittir; üzerine ek KDV hesaplanmaz. |
| REQ-CART-009 | Barkodsuz ürünler satış ekranında arama, kategori filtresi veya favoriler üzerinden tıklanarak sepete eklenebilir. |

---

## 9. Acceptance criteria

**REQ-CART-003**
```text
Given: Sepette 3 ürün var, toplam ₺95,00
When:  Uygulama görev yöneticisinden sonlandırılıyor
And:   Tekrar açılıyor
Then:  Aynı 3 ürün, aynı miktarlar ve aynı fiyatlarla sepette görünür
And:   "Yarım kalan satışınız geri yüklendi" bilgisi gösterilir
And:   Hiçbir stok hareketi oluşmamıştır
And:   Hiçbir satış kaydı oluşmamıştır
```

**REQ-SALE-001**
```text
Given: Sepette 3 satır var
When:  Satış tamamlanırken 3. satırın stok hareketi yazılırken hata oluşuyor
Then:  Hiçbir sales kaydı oluşmaz
And:   Hiçbir sale_items kaydı oluşmaz
And:   Hiçbir stok hareketi oluşmaz
And:   Hiçbir ürünün stoğu değişmez
And:   Sepet olduğu gibi korunur
And:   Kullanıcıya hata gösterilir
```

**REQ-SALE-003**
```text
Given: Coca Cola ₺25,00'den satılmış
When:  Ürünün fiyatı ₺30,00 yapılıyor
And:   O satışın detayı açılıyor
Then:  Satır fiyatı ₺25,00 görünür
And:   Satış toplamı değişmemiştir
```

**REQ-CART-005**
```text
Given: Sepette Coca Cola ₺25,00 (liste fiyatı ₺25,00, KDV dahil)
When:  Kullanıcı F2 ile fiyatı ₺20,00 yapıyor ve satışı tamamlıyor
Then:  sale_items.unit_price_minor = 2000
And:   sale_items.original_unit_price_minor = 2500
And:   products.sale_price_minor = 2500 (değişmemiş)
And:   Audit log'a fiyat değişikliği kaydı yazılmıştır
```

**REQ-SALE-002 — beş snapshot alanı**
```text
Given: Ürün: adı "Cips", satış fiyatı ₺20,00, alış fiyatı ₺12,00,
       KDV oranı %20, kategorisi "Atıştırmalık"
When:  1 adet satılıyor
Then:  sale_items.product_name_snapshot  = "Cips"
And:   sale_items.unit_price_minor       = 2000
And:   sale_items.purchase_price_snapshot_minor = 1200
And:   sale_items.vat_rate_snapshot_bp   = 2000
And:   sale_items.category_id_snapshot   = <Atıştırmalık id>
When:  Ürünün adı, fiyatı, alış fiyatı, KDV oranı ve kategorisi sonradan değiştiriliyor
Then:  Bu satırın beş snapshot alanının hiçbiri değişmez
And:   Geçmiş ciro, kâr, KDV ve kategori raporları aynı sonucu verir
```

**REQ-SALE-011**
```text
Given: Sepette bir ürün var
When:  Kullanıcı miktar alanına ondalıklı bir değer girmeye çalışıyor
Then:  Giriş kabul edilmez
And:   Miktar yalnızca 1, 2, 3... şeklinde artırılabilir
```

**REQ-SALE-008**
```text
Given: Kullanıcı F12'ye üst üste 3 kez basıyor
When:  İlk işlem devam ediyor
Then:  Yalnızca bir satış kaydı oluşur
And:   Stok yalnızca bir kez düşer
```
