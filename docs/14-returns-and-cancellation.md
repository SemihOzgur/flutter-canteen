# 14 — Satış İptali ve İade

## 1. İki farklı işlem

Kullanıcının orijinal gereksiniminde satış durumları `Completed / Cancelled / Returned` olarak
verilmiş, ancak ayrıca **kısmi iade** istenmiştir. Kısmi iade tek bir satış durumuyla ifade edilemez
(bkz. [02 §12, madde 1](02-product-and-business-requirements.md)). Bu nedenle:

| | Satış İptali (Cancellation) | İade (Return) |
|---|---|---|
| Kapsam | Satışın **tamamı** | Satırların **bir kısmı veya tamamı** |
| Ne zaman | Yanlış satış, hemen fark edilen hata | Müşteri ürünü geri getirdi |
| Kayıt | `sales.status = cancelled` | Ayrı `returns` + `return_items` kaydı |
| Stok | Tüm satırlar iade edilir | Yalnızca iade edilen miktar |
| Tekrarlanabilir mi | ❌ Bir kez | ✅ Kalan miktar kadar birden fazla kez |
| Ön koşul | Satışta hiç iade yapılmamış olmalı | Satış `cancelled` olmamalı |

---

## 2. Satış durumu geçişleri

```text
                    ┌───────────┐
                    │ completed │
                    └─────┬─────┘
          ┌───────────────┼─────────────────┐
          │ iptal         │ kısmi iade      │ tam iade (tek seferde)
          ▼               ▼                 ▼
    ┌───────────┐  ┌──────────────────┐  ┌──────────┐
    │ cancelled │  │partiallyReturned │  │ returned │
    └───────────┘  └────────┬─────────┘  └──────────┘
      (terminal)            │  ek iadeler   (terminal)
                            │  ↺
                            ▼ tüm miktarlar iade edilince
                       ┌──────────┐
                       │ returned │
                       └──────────┘
```

**Durum hesaplama kuralı** (her iade sonrası yeniden değerlendirilir):

```text
toplamSatilan  = Σ sale_items.quantity
toplamIade     = Σ sale_items.returned_quantity

toplamIade == 0                → completed
0 < toplamIade < toplamSatilan → partiallyReturned
toplamIade == toplamSatilan    → returned
```

---

## 3. Satış iptali akışı

```text
Satış geçmişi → satış detayı → [Satışı İptal Et]
      ▼
Ön kontrol:  status == 'completed'  ve  hiç iade yok
      ├── Değilse → "Bu satış iptal edilemez" (sebep gösterilir)
      ▼
┌──────────────────────────────────────────────┐
│ Satışı İptal Et — 2026-000148                │
│ Tutar: ₺135,00 · 4 ürün                      │
│                                              │
│ ⚠ Bu işlem geri alınamaz.                    │
│   Tüm ürünlerin stoğu geri eklenecek.        │
│   Satış kaydı silinmez, iptal olarak         │
│   işaretlenir ve raporlarda görünmeye devam  │
│   eder.                                      │
│                                              │
│ İptal sebebi: [____________________]         │
│           [Vazgeç]     [İptal Et]            │
└──────────────────────────────────────────────┘
      ▼
BEGIN TRANSACTION
  sales.status = 'cancelled', cancelled_at = now, note += sebep
  Her sale_item için:
    stock_movements: type=saleCancellation, delta=+quantity,
                     reference=(sale, saleId)
    products.stock_quantity += quantity
  audit_logs: action=saleCancelled
COMMIT
```

---

## 4. İade akışı

```text
Satış detayı → [İade Oluştur]
      ▼
┌─────────────────────────────────────────────────────────┐
│ İADE — Satış 2026-000148                                │
│                                                         │
│ Ürün              Satılan  Önceki iade  İade edilecek   │
│ Coca Cola 330ml       2          0         [ 1 ]        │
│ Tost                  1          0         [ 0 ]        │
│ Su 500ml              3          1         [ 2 ] (maks 2)│
│                                                         │
│ İade tutarı:                        ₺45,00              │
│ (satış anındaki fiyatlar üzerinden)                     │
│                                                         │
│ Sebep: [______________________]                         │
│                     [Vazgeç]   [İadeyi Kaydet]          │
└─────────────────────────────────────────────────────────┘
      ▼
Validasyon:  her satır için  iadeEdilecek <= quantity − returned_quantity
             ve toplam iade miktarı > 0
      ▼
BEGIN TRANSACTION
  returns satırı oluştur (type = tam mı kısmi mi)
  Her iade satırı için:
    return_items satırı (unit_price = sale_item.unit_price SNAPSHOT)
    sale_items.returned_quantity += miktar
    stock_movements: type=return, delta=+miktar, reference=(return, returnId)
    products.stock_quantity += miktar
  sales.status yeniden hesaplanır (§2)
  audit_logs: action=saleReturned
COMMIT
```

### İade tutarı

> **BR-RET-005 — Orijinal `sale_items.unit_price_minor` snapshot'ı kullanılır.**

Ürünün güncel fiyatı **kullanılmaz.** Müşteri ₺25'e aldığı ürünü ₺30 olduğunda iade ettiğinde
₺25 geri alır. Bu, fiyat snapshot mimarisinin ([12 §6.2](12-sales-system.md)) doğrudan sonucudur.

---

## 5. Raporlara etkisi

> **BR-RET-007 — Raporlar net değerleri gösterir.**

```text
Brüt ciro   = Σ completed + partiallyReturned + returned satışların grandTotal
İptal       = Σ cancelled satışların grandTotal
İade        = Σ return_items.line_total
────────────────────────────────────────────
NET CİRO    = Brüt ciro − İptal − İade
```

Aynı mantık **satılan adet** ve **kâr** için de geçerlidir:

```text
Net adet = Σ sale_items.quantity (iptal edilmemiş satışlarda)
         − Σ sale_items.returned_quantity

Net kâr  = Net ciro − (net adetlerin unit_cost toplamı)
```

**Dashboard ve raporlarda varsayılan görünüm nettir.** Brüt/iptal/iade ayrıntısı ayrı bir
"İptal ve İadeler" bölümünde gösterilir.

### Tarih ilişkilendirme sorunu

> Bir satış 1 Ağustos'ta yapılıp 5 Ağustos'ta iade edilirse, iade hangi güne yazılır?

**Karar:** İade, **iade tarihine** yazılır (`returns.created_at`). Ciro raporunda:
- 1 Ağustos: satış görünür (brüt),
- 5 Ağustos: iade eksi olarak görünür.

Gerekçe: Kasa mutabakatı günlük yapılır; para 5 Ağustos'ta kasadan çıkmıştır.
Alternatif (orijinal satış gününü düzeltmek) geçmiş kapanmış günleri değiştirir ve kabul edilemez.

Bu davranış rapor ekranında bir dipnotla açıklanır.

---

## 6. Kısıtlar

| Kural | ID |
|---|---|
| İptal edilmiş satış tekrar iptal edilemez | BR-RET-006 |
| İptal edilmiş satıştan iade yapılamaz | BR-RET-006 |
| Bir satırın toplam iadesi satılan miktarı aşamaz | BR-RET-003 |
| İade edilmiş miktar tekrar iade edilemez | BR-RET-006 |
| Hiç iade yapılmamış satış iptal edilebilir; iade yapılmış satış iptal edilemez | BR-RET-001 |
| İptal ve iade kayıtları silinemez | BR-GEN-002 |
| Ürün pasifleştirilmiş olsa da iadesi yapılabilir | — |

### İade süresi sınırı

**v1'de zaman sınırı yoktur** — kullanıcı istediği tarihteki satışı iade edebilir.
İhtiyaç doğarsa ayarlarla sınırlandırılabilir ([30](30-future-scope.md)).

---

## 7. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-RET-001 | Satış kayıtları hiçbir koşulda silinemez; yalnızca durumu değişir. |
| REQ-RET-002 | Satış iptali tüm satırların stoğunu geri ekler. |
| REQ-RET-003 | Kısmi iade desteklenir; satır bazında iade miktarı seçilebilir. |
| REQ-RET-004 | Bir satır için toplam iade miktarı satılan miktarı aşamaz. |
| REQ-RET-005 | İade tutarı satış anındaki fiyat snapshot'ı üzerinden hesaplanır. |
| REQ-RET-006 | İptal ve iade işlemleri stok defterine ayrı hareket olarak yazılır; orijinal satış hareketi silinmez. |
| REQ-RET-007 | Satış durumu, iade miktarlarına göre otomatik olarak `completed` / `partiallyReturned` / `returned` şeklinde güncellenir. |
| REQ-RET-008 | İptal edilmiş bir satış tekrar iptal edilemez ve iade edilemez. |
| REQ-RET-009 | Raporlar net (iptal ve iade düşülmüş) değerleri varsayılan olarak gösterir. |
| REQ-RET-010 | İptal ve iade işlemleri tek atomik transaction'da uygulanır. |
| REQ-RET-011 | İade, iade tarihine göre raporlanır; orijinal satış tarihi değiştirilmez. |
| REQ-RET-012 | İptal ve iade işlemleri audit log'a sebep bilgisiyle yazılır. |

---

## 8. Acceptance criteria

**REQ-RET-002**
```text
Given: 3 satırlık (toplam 6 adet) tamamlanmış bir satış var
And:   Ürünlerin güncel stokları sırasıyla 10, 20, 30
When:  Satış iptal ediliyor
Then:  sales.status = 'cancelled'
And:   Satış kaydı ve satırları silinmemiştir
And:   Her ürün için type='saleCancellation' hareketi oluşur
And:   Stoklar 12, 21, 33 olur (satılan miktarlar geri eklenmiş)
And:   Audit log'a iptal kaydı yazılmıştır
```

**REQ-RET-003 / REQ-RET-007**
```text
Given: Satışta "Su 500ml" 3 adet satılmış
When:  1 adet iade ediliyor
Then:  sale_items.returned_quantity = 1
And:   sales.status = 'partiallyReturned'
And:   Stok +1 artar
When:  Kalan 2 adet de iade ediliyor (satışta başka satır yoksa)
Then:  sale_items.returned_quantity = 3
And:   sales.status = 'returned'
When:  Tekrar iade denenirse
Then:  İade miktarı alanı 0 ile sınırlıdır ve işlem yapılamaz
```

**REQ-RET-005**
```text
Given: Ürün ₺25,00'den satılmış, güncel fiyatı ₺30,00
When:  1 adet iade ediliyor
Then:  İade tutarı ₺25,00 olarak hesaplanır ve kaydedilir
```

**REQ-RET-009**
```text
Given: Bugün ₺1.000 satış yapılmış, ₺150'lik iade alınmış
When:  Dashboard bugünkü ciro kartı görüntüleniyor
Then:  Net ciro ₺850 gösterilir
And:   Detayda brüt ₺1.000 ve iade ₺150 ayrı görünür
```
