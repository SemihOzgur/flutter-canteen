# 04 — Domain Model

> **Doküman sürümü:** v3 — snapshot alan adları hizalandı, recovery code anahtarları eklendi.
> **Tablo sayısı: 15 — şema FİNAL.**

Bu doküman sistemin **kavramsal** veri modelidir. Fiziksel tablo şemaları için [05](05-database-architecture.md).

---

## 1. Entity envanteri

> **Toplam: 15 tablo.**

| # | Entity | Amaç |
|---|---|---|
| 1 | **User** | Login + audit log'da "kim" bilgisi |
| 2 | **Category** | Zorunlu ürün alanı + kategori bazlı raporlama |
| 3 | **Supplier** | Tedarikçi bazlı raporlama |
| 4 | **VatRate** | KDV oranları yönetilebilir olmalı (BR-VAT-001) |
| 5 | **Product** | Çekirdek |
| 6 | **ProductBarcode** | Bir ürünün N barkodu olabilir (BR-PROD-004) |
| 7 | **Cart** | Aktif sepetin kalıcılığı (BR-CART-002) |
| 8 | **CartItem** | Sepet satırları |
| 9 | **Sale** | Tamamlanmış satış |
| 10 | **SaleItem** | Satış satırı + snapshot'lar (BR-SALE-001) |
| 11 | **Return** | Kısmi iade tek satış durumuyla ifade edilemez (BR-RET-002) |
| 12 | **ReturnItem** | İade satırları |
| 13 | **StockMovement** | Stok defteri (BR-STOCK-001) |
| 14 | **AuditLog** | İzlenebilirlik |
| 15 | **AppSetting** | Anahtar-değer ayar deposu |

### Ayrı entity YAPILMAYAN kavramlar

Aşağıdakiler V1'de ayrı tablo değildir. **Hiçbiri kalıcı olarak kapatılmamıştır** — her biri için
düşük maliyetli bir genişleme yolu tanımlanmıştır.

| Kavram | V1'deki karşılığı | Neden entity değil | Nasıl entity'ye dönüşür |
|---|---|---|---|
| **Brand** (marka) | `products.brand` — serbest metin + otomatik tamamlama (BR-SUP-003) | Marka bazlı raporlama, marka için ek alan (logo/iletişim) veya marka pasifleştirme gereksinimi yok. Yazım tutarlılığı otomatik tamamlama ile sağlanır. | `brands` tablosu oluşturulur, `SELECT DISTINCT brand` ile doldurulur, `products.brand_id` eklenir. Tek migration. |
| **Unit** (birim) | `products.sales_unit` — serbest metin + öneri listesi (BR-SUP-004) | Birim yalnızca açıklayıcıdır (BR-PROD-011); hiçbir hesaba girmez, birim dönüşümü yapılmaz. V1'de satış miktarı daima tam sayıdır (BR-SALE-011). | `units` tablosu + `products.unit_id`. Tartılı satış eklenirse ([30 §3.2](30-future-scope.md)) birlikte değerlendirilir. |
| **Favorite** (favori) | `products.is_favorite` boolean (BR-PROD-008) | Rol sistemi yok → kullanıcıya özel favori kümesi gerekmiyor. Tek küme yeterli. | `user_favorites(user_id, product_id)` tablosu. Yalnızca kullanıcıya özel favori istenirse gerekir. |
| **Payment** (ödeme) | `sales.cash_received_minor` + `change_minor` | Yalnızca nakit var; ödeme yöntemi çeşitlenmiyor, kısmi ödeme yok. | `payments(sale_id, method, amount)` tablosu. Kart/karma ödeme eklenirse gerekir. |

> **İlke:** Entity, ancak kendine ait **alanları**, **yaşam döngüsü** (aktif/pasif) veya
> **bağımsız raporlaması** olduğunda oluşturulur. Bu dördünün hiçbirinde V1'de böyle bir ihtiyaç yoktur.

---

## 2. ERD

```text
                          ┌──────────┐
                          │   User   │
                          └────┬─────┘
                 ┌─────────────┼──────────────┬───────────────┐
                 │             │              │               │
            ┌────▼────┐   ┌────▼─────┐  ┌─────▼───────┐ ┌─────▼─────┐
            │  Sale   │   │   Cart   │  │StockMovement│ │ AuditLog  │
            └────┬────┘   └────┬─────┘  └─────▲───────┘ └───────────┘
                 │             │              │
          ┌──────▼──────┐ ┌────▼─────┐        │
          │  SaleItem   │ │ CartItem │        │
          └──┬───────┬──┘ └────┬─────┘        │
             │       │         │              │
             │  ┌────▼─────────▼──────────────┴──┐
             │  │           Product              │
             │  └──┬────────┬─────────┬───────┬──┘
             │     │        │         │       │
             │ ┌───▼────┐ ┌─▼──────┐ ┌▼──────┐ ┌▼─────────────┐
             │ │Category│ │Supplier│ │VatRate│ │ProductBarcode│
             │ └────────┘ └────────┘ └───────┘ └──────────────┘
             │
      ┌──────▼───────┐        ┌──────────┐
      │  ReturnItem  ├────────►  Return  ├────► Sale
      └──────────────┘        └──────────┘

      ┌────────────┐
      │ AppSetting │  (bağımsız: oturum, dashboard parolası + recovery code, sayaçlar, tercihler)
      └────────────┘
```

---

## 3. Entity tanımları

### 3.1 User

| Alan | Tip | Not |
|---|---|---|
| id | int | PK |
| username | string | benzersiz, küçük harfe normalize |
| passwordHash | string | SHA-256 (BR-AUTH-011) |
| passwordSalt | string | kayıt başına rastgele |
| displayName | string | |
| isActive | bool | |
| lastLoginAt | datetime? | |
| createdAt / updatedAt | datetime | |

**Invariant:** En az bir `isActive = true` kullanıcı bulunmalıdır (BR-AUTH-006).
**Kural:** Düz metin parola alanı **yoktur** (BR-SEC-001).

### 3.2 Category

| Alan | Tip | Not |
|---|---|---|
| id | int | PK |
| name | string | benzersiz |
| sortOrder | int | satış ekranı sıralaması |
| isSystem | bool | `Genel` için `true` |
| isActive | bool | soft delete |
| createdAt / updatedAt | datetime | |

**Silme:** Yalnızca hiç kullanılmamışsa (BR-CAT-005); aksi halde pasifleştirme (BR-CAT-002).

### 3.3 Supplier

| Alan | Tip | Not |
|---|---|---|
| id | int | PK |
| name | string | zorunlu |
| contactName, phone, email, address, note | string? | opsiyonel |
| isActive | bool | soft delete |
| createdAt / updatedAt | datetime | |

### 3.4 VatRate

| Alan | Tip | Not |
|---|---|---|
| id | int | PK |
| name | string | örn. "Standart", "İndirimli" |
| rateBasisPoints | int | %20 → `2000` |
| isDefault | bool | yalnızca bir kayıt `true` |
| isActive | bool | |
| createdAt / updatedAt | datetime | |

Kurulumda yalnızca nötr `%0 — KDV Yok` oranı seed edilir ve varsayılan olur; mevzuata bağlı
oranlar (%20, %10 …) seed **edilmez** ([08 §3](08-vat-rules.md) · OD-017).

### 3.5 Product

| Alan | Tip | Zorunlu | Not |
|---|---|---|---|
| id | int | ✅ | PK |
| name | string | ✅ | BR-PROD-001 |
| description | string? | ❌ | |
| categoryId | FK Category | ✅ | BR-PROD-003 |
| brand | string? | ❌ | serbest metin (BR-SUP-003) |
| **salesUnit** | string? | ❌ | **satış birimi** — `adet`, `paket`, `kutu`. Açıklayıcı (BR-PROD-011) |
| **netWeightValue** | int? | ❌ | **gramaj / net ağırlık**, milli hassasiyet (150 g → `150000`) |
| **netWeightUnit** | string? | ❌ | `g`, `kg`, `ml`, `lt` |
| purchasePriceMinor | int | ✅ | varsayılan `0` (BR-PROD-002) |
| salePriceMinor | int | ✅ | `>= 0`, **KDV dahil** (BR-VAT-003) |
| vatRateId | FK VatRate? | ❌ | boşsa varsayılan oran |
| stockQuantity | int | ✅ | türetilmiş özet (BR-STOCK-002) |
| minimumStock | int | ✅ | varsayılan `0` |
| supplierId | FK Supplier? | ❌ | |
| shelfLocation | string? | ❌ | |
| imagePath | string? | ❌ | veri dizinine göreli yol (BR-IMG-001) |
| isFavorite | bool | ✅ | varsayılan `false` |
| isActive | bool | ✅ | varsayılan `true` |
| createdAt / updatedAt | datetime | ✅ | |

**Invariant'lar:**
- `salePriceMinor >= 0`, `purchasePriceMinor >= 0`
- `netWeightValue` ve `netWeightUnit` ya ikisi de dolu ya ikisi de boş (BR-PROD-011)
- `stockQuantity` = ilgili tüm `StockMovement.quantityDelta` toplamı (BR-STOCK-003)

> **Örnek:** `Cips` · `netWeight = 150 g` · `salesUnit = adet` → 150 gramlık paket, adetle satılır.
> Miktar daima tam sayıdır; gramaj hesaba girmez.

**Silme:** Hiç satılmamış ve hiç stok hareketi yoksa kalıcı silinebilir (BR-PROD-014);
aksi halde pasifleştirme (BR-PROD-009).

### 3.6 ProductBarcode

| Alan | Tip | Not |
|---|---|---|
| id | int | PK |
| productId | FK Product | |
| barcode | string | **global benzersiz** (BR-PROD-005), metin olarak saklanır (BR-BARC-009) |
| isPrimary | bool | ürün başına en fazla bir `true` |
| createdAt | datetime | |

### 3.7 Cart / CartItem

| Cart alanı | Tip | Not |
|---|---|---|
| id | int | PK |
| status | enum | `active` \| `closed` \| `abandoned` |
| userId | FK User | |
| note | string? | |
| createdAt / updatedAt | datetime | |

| CartItem alanı | Tip | Not |
|---|---|---|
| id | int | PK |
| cartId | FK Cart | |
| productId | FK Product | |
| quantity | **int** | `> 0` (BR-SALE-011) |
| unitPriceMinor | int | sepete eklenirken kopyalanan fiyat (KDV dahil) |
| isPriceOverridden | bool | |
| addedAt / updatedAt | datetime | |

**Invariant:** `status = active` olan en fazla **bir** Cart bulunabilir (BR-CART-001).

### 3.8 Sale

| Alan | Tip | Not |
|---|---|---|
| id | int | PK |
| saleNumber | string | benzersiz (BR-SALE-009) |
| status | enum | `completed` \| `cancelled` \| `partiallyReturned` \| `returned` |
| subtotalMinor | int | **KDV hariç** toplam (matrah) |
| vatTotalMinor | int | KDV toplamı |
| discountTotalMinor | int | V1'de daima `0` ([OD-007](28-open-decisions.md)) |
| grandTotalMinor | int | **KDV dahil** — müşteriden alınan tutar |
| costTotalMinor | int | satış anındaki toplam maliyet snapshot'ı |
| cashReceivedMinor | int? | opsiyonel |
| changeMinor | int? | opsiyonel |
| userId | FK User | |
| itemCount / unitCount | int | rapor hızlandırma |
| note | string? | |
| completedAt | datetime | **raporların zaman ekseni** |
| cancelledAt | datetime? | |
| createdAt / updatedAt | datetime | |

**Invariant:** `subtotalMinor + vatTotalMinor = grandTotalMinor`

### 3.9 SaleItem — snapshot alanları

> **BR-SALE-001 kesinleşmiştir.** Aşağıdaki beş alan snapshot'tır ve kaynak kayıt değişse bile değişmez.

| Alan | Tip | Snapshot? | Not |
|---|---|---|---|
| id | int | | PK |
| saleId | FK Sale | | |
| productId | FK Product | | referans (raporlama) |
| **productNameSnapshot** | string | ✅ | Satış anındaki ürün adı |
| barcodeSnapshot | string? | ✅ | Ürünün satış anındaki **birincil** barkodu; barkodsuz üründe `NULL` (OD-022) |
| **categoryIdSnapshot** | int? | ✅ | Kategori raporu geçmişi bozulmasın diye |
| quantity | **int** | | `> 0` (BR-SALE-011) |
| **unitPriceMinor** | int | ✅ | **Satış anındaki birim satış fiyatı (KDV dahil)** |
| originalUnitPriceMinor | int | ✅ | Ürünün o andaki liste fiyatı (override edildiyse farklı) |
| **purchasePriceSnapshotMinor** | int | ✅ | **Satış anındaki birim alış fiyatı** — kâr hesabı için |
| **vatRateSnapshot** | int | ✅ | **Satış anındaki KDV oranı** |
| lineNetMinor | int | | KDV hariç satır tutarı |
| lineVatMinor | int | | Satır KDV tutarı |
| lineTotalMinor | int | | KDV dahil satır tutarı = `unitPrice × quantity` |
| returnedQuantity | int | | İade edilen kümülatif miktar, varsayılan `0` |

**Invariant'lar:**
- `0 <= returnedQuantity <= quantity` (BR-RET-003)
- `lineNetMinor + lineVatMinor = lineTotalMinor`
- `lineTotalMinor = unitPriceMinor × quantity`

### 3.10 Return / ReturnItem

| Return alanı | Tip | Not |
|---|---|---|
| id | int | PK |
| saleId | FK Sale | |
| type | enum | `full` \| `partial` |
| totalMinor | int | iade edilen tutar (KDV dahil) |
| reason | string? | |
| userId | FK User | |
| createdAt | datetime | **iadenin raporlama tarihi** (BR-RET-008) |

| ReturnItem alanı | Tip | Not |
|---|---|---|
| id | int | PK |
| returnId | FK Return | |
| saleItemId | FK SaleItem | |
| quantity | int | `> 0` |
| unitPriceMinor | int | orijinal snapshot'tan kopya (BR-RET-005) |
| lineTotalMinor | int | |

### 3.11 StockMovement

| Alan | Tip | Not |
|---|---|---|
| id | int | PK |
| productId | FK Product | |
| type | enum | BR-STOCK-004 |
| quantityDelta | int | pozitif veya negatif, **asla 0** |
| resultingStock | int | hareket sonrası stok (BR-STOCK-008) |
| unitCostMinor | int? | yalnızca `stockEntry` / `initial` için |
| referenceType | enum? | `sale` \| `return` \| `import` \| `manual` \| `backupRestore` |
| referenceId | int? | ilgili kaydın id'si |
| supplierId | FK Supplier? | stok girişinde |
| note | string? | fire ve düzeltmede **zorunlu** (BR-STOCK-010) |
| userId | FK User | |
| createdAt | datetime | |

**Invariant:** Kayıt yazıldıktan sonra **değiştirilemez ve silinemez** (BR-STOCK-005).

### 3.12 AuditLog

Bkz. [18 — Audit Log](18-audit-log.md).

### 3.13 AppSetting

| Alan | Tip | Not |
|---|---|---|
| key | string | PK |
| value | string | JSON veya düz metin |
| updatedAt | datetime | |

Kullanılan anahtarlar:

| Anahtar | İçerik |
|---|---|
| `session` | `{ userId, loginAt }` — oturum ([17 §6](17-authentication.md)) |
| `dashboard_password_hash` | Dashboard parolası hash'i (BR-AUTH-009) |
| `dashboard_password_salt` | Dashboard parolası salt'ı |
| `dashboard_recovery_hash` | **Recovery code hash'i** (BR-AUTH-015) |
| `dashboard_recovery_salt` | Recovery code salt'ı |
| `dashboard_recovery_used_at` | Recovery code kullanıldıysa zaman damgası, yoksa `NULL` |
| `sale_counter_<yıl>` | Satış numarası sayacı |
| `last_backup_at` | Yedek hatırlatması |
| `migration_in_progress` | Kurtarma bayrağı ([06](06-database-migrations.md)) |
| `restore_in_progress` | Kurtarma bayrağı ([19](19-backup-restore.md)) |
| `image_optimization` | Görsel optimizasyon profili ([OD-016](28-open-decisions.md)) |
| `window_state`, `dashboard_range`, `sound_enabled`, `stock_warning_enabled` | UI tercihleri |
| `last_image_scan_at` | Görsel bakım taraması ([21 §4](21-image-storage.md)) |

> Dashboard parolası ve recovery code `users` tablosunda değil `app_settings`'tedir — çünkü
> kullanıcıya değil, **sisteme** aittir (BR-AUTH-008). Hiçbiri düz metin saklanmaz (BR-SEC-001).

---

## 4. Durum makineleri

### 4.1 Sale

```text
        ┌───────────┐
        │ completed │
        └─────┬─────┘
      ┌───────┼──────────────┐
      │       │              │
      ▼       ▼              ▼
 ┌─────────┐ ┌──────────────────┐   (ek kısmi
 │cancelled│ │partiallyReturned │◄──┐ iadeler)
 └─────────┘ └────────┬─────────┘   │
   (terminal)         │─────────────┘
                      ▼ (tüm miktarlar iade edilince)
                 ┌──────────┐
                 │ returned │  (terminal)
                 └──────────┘
```

- `cancelled` ve `returned` **terminal**dir.
- `cancelled` yalnızca **hiç iade yapılmamış** satışlara uygulanabilir (BR-RET-006).

### 4.2 Cart

```text
active ──(satış tamamlandı)──► closed        (terminal)
active ──(kullanıcı temizledi / devir)──► abandoned  (terminal)
```

---

## 5. Silme politikası özeti

| Entity | Kalıcı silme | Soft delete | Koşul |
|---|---|---|---|
| Sale / SaleItem | ❌ | ❌ | Yalnızca durum değişir |
| Return / ReturnItem | ❌ | ❌ | |
| StockMovement | ❌ | ❌ | Değişmez defter |
| AuditLog | ❌ | ❌ | Yalnızca yaş bazlı arşivleme |
| **Product** | 🟡 | ✅ | Hiç satılmamış **ve** hiç stok hareketi yoksa silinebilir (BR-PROD-014) |
| **Category** | 🟡 | ✅ | Hiç ürüne atanmamış **ve** hiç satış snapshot'ında geçmemişse silinebilir (BR-CAT-005); sistem kategorisi hariç |
| Supplier | ❌ | ✅ | |
| VatRate | ❌ | ✅ | |
| User | ❌ | ✅ | Son aktif kullanıcı hariç |
| ProductBarcode | ✅ | — | Kullanıcı yanlış barkodu kaldırabilmeli; audit log'a yazılır |
| Cart / CartItem | ✅ | — | Finansal kayıt değil; `closed` sepetler 30 gün sonra temizlenebilir |
