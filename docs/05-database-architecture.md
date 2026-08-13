# 05 — Database Mimarisi

> **Doküman sürümü:** v3 — snapshot alan adları hizalandı; recovery code anahtarları eklendi.
> **Şema durumu: FİNAL.** Faz 2 hiçbir açık karar tarafından bloke edilmemektedir.

## 1. Teknoloji kararı

### Değerlendirilen seçenekler

| Seçenek | Artı | Eksi |
|---|---|---|
| **Drift** (SQLite üzerinde) | Tip güvenli sorgu, derleme zamanı kontrol, **yerleşik migration + schema versiyon test araçları**, transaction desteği, `Stream` tabanlı reaktif sorgular, isolate desteği, Windows/macOS masaüstünde `sqlite3_flutter_libs` ile sorunsuz | Kod üretimi (build_runner) gerekir, öğrenme eğrisi |
| `sqflite_common_ffi` (ham SQL) | Basit, bağımlılık az | Tip güvenliği yok, migration'ı elle yazılır, karmaşık raporlarda hata riski yüksek |
| `sqlite3` (doğrudan) | En düşük seviye, en hızlı | Her şey elle; bu projenin ölçeğinde bakım maliyeti yüksek |
| Isar / Hive (NoSQL) | Hızlı basit okuma | **Relational raporlama ve aggregation zayıf** — bu projenin en ağır işi tam olarak bu. JOIN/GROUP BY gerektiren onlarca rapor var. Elenmiştir. |
| ObjectBox | Hızlı | Lisans/ticari koşullar + ilişkisel raporlama zayıf. Elenmiştir. |

### Karar

> ✅ **Drift + SQLite kullanılacaktır.** Bu karar proje sahibi tarafından onaylanmıştır
> ([OD-001 — KAPANDI](28-open-decisions.md)).

**Belirleyici gerekçeler:**
1. Projenin en riskli iki alanı **migration** ve **raporlama aggregation'ı**. Drift ikisinde de en güçlü seçenek.
2. Stok defteri ve satış işlemleri **atomik transaction** gerektiriyor (BR-SALE-005); SQLite bunu garanti ediyor.
3. Backup formatının merkezinde tek bir SQLite dosyası olması, `VACUUM INTO` ile tutarlı snapshot alınmasını sağlıyor ([19](19-backup-restore.md)).
4. Drift'in schema dump/verify araçları, "yeni sürüm veri kaybetmesin" gereksinimini test edilebilir kılıyor ([06](06-database-migrations.md)).

### SQLite yapılandırması

| Ayar | Değer | Gerekçe |
|---|---|---|
| `journal_mode` | **WAL** | Elektrik kesintisinde dayanıklılık + okuma/yazma çakışmasını azaltır |
| `synchronous` | **FULL** | Kesintisiz güç kaynağı varsayılmıyor; performans kaybı bu ölçekte önemsiz ([01 §6](01-project-overview.md)) |
| `foreign_keys` | **ON** | Referans bütünlüğü |
| `busy_timeout` | 5000 ms | |
| `temp_store` | MEMORY | Rapor aggregation hızı |

> `synchronous = NORMAL` daha hızlıdır ancak ani güç kesintisinde son işlemleri kaybedebilir.
> Bir satışın kaybolması bu projede kabul edilemez → **FULL** seçildi.

### Dosya konumu

| Platform | Yol |
|---|---|
| Windows | `%APPDATA%\CanteenApp\data\canteen.sqlite` |
| macOS | `~/Library/Application Support/CanteenApp/data/canteen.sqlite` |

**Kurulum dizininde veri tutulmaz** (BR-DATA-001) — güncelleme veriyi silmesin diye.

---

## 2. Tablo şemaları

> **Toplam 15 tablo:** `users`, `categories`, `suppliers`, `vat_rates`, `products`,
> `product_barcodes`, `carts`, `cart_items`, `sales`, `sale_items`, `returns`, `return_items`,
> `stock_movements`, `audit_logs`, `app_settings`.

Aşağıdaki tanımlar **veri modeli dokümantasyonudur**, üretim kodu değildir.
Alan anlamları için [04 — Domain Model](04-domain-model.md).

### 2.1 users

```text
users
  id                INTEGER PK AUTOINCREMENT
  username          TEXT    NOT NULL UNIQUE          -- lowercase normalize
  password_hash     TEXT    NOT NULL                 -- SHA-256, BR-AUTH-011
  password_salt     TEXT    NOT NULL                 -- kayıt başına rastgele
  -- Düz metin parola alanı YOKTUR (BR-SEC-001)
  display_name      TEXT    NOT NULL
  is_active         INTEGER NOT NULL DEFAULT 1
  last_login_at     INTEGER NULL                     -- unix ms, UTC
  created_at        INTEGER NOT NULL
  updated_at        INTEGER NOT NULL
```

### 2.2 categories

```text
categories
  id          INTEGER PK
  name        TEXT    NOT NULL
  sort_order  INTEGER NOT NULL DEFAULT 0
  is_system   INTEGER NOT NULL DEFAULT 0
  is_active   INTEGER NOT NULL DEFAULT 1
  created_at  INTEGER NOT NULL
  updated_at  INTEGER NOT NULL
  UNIQUE(name)                                        -- pasifler dahil; isim geri kullanılmaz
```

### 2.3 suppliers

```text
suppliers
  id            INTEGER PK
  name          TEXT    NOT NULL
  contact_name  TEXT    NULL
  phone         TEXT    NULL
  email         TEXT    NULL
  address       TEXT    NULL
  note          TEXT    NULL
  is_active     INTEGER NOT NULL DEFAULT 1
  created_at    INTEGER NOT NULL
  updated_at    INTEGER NOT NULL
```

### 2.4 vat_rates

```text
vat_rates
  id                 INTEGER PK
  name               TEXT    NOT NULL
  rate_basis_points  INTEGER NOT NULL CHECK(rate_basis_points >= 0)
  is_default         INTEGER NOT NULL DEFAULT 0
  is_active          INTEGER NOT NULL DEFAULT 1
  created_at         INTEGER NOT NULL
  updated_at         INTEGER NOT NULL
```

### 2.5 products

```text
products
  id                    INTEGER PK
  name                  TEXT    NOT NULL
  description           TEXT    NULL
  category_id           INTEGER NOT NULL REFERENCES categories(id)
  brand                 TEXT    NULL                  -- serbest metin, BR-SUP-003
  sales_unit            TEXT    NULL                  -- satış birimi: adet/paket/kutu
  net_weight_value      INTEGER NULL                  -- gramaj, milli hassasiyet (150 g → 150000)
  net_weight_unit       TEXT    NULL                  -- g / kg / ml / lt
  purchase_price_minor  INTEGER NOT NULL DEFAULT 0 CHECK(purchase_price_minor >= 0)
  sale_price_minor      INTEGER NOT NULL          CHECK(sale_price_minor >= 0)
                                                      -- KDV DAHİL fiyat (BR-VAT-003)
  vat_rate_id           INTEGER NULL REFERENCES vat_rates(id)
  stock_quantity        INTEGER NOT NULL DEFAULT 0    -- negatif olabilir
  minimum_stock         INTEGER NOT NULL DEFAULT 0 CHECK(minimum_stock >= 0)
  supplier_id           INTEGER NULL REFERENCES suppliers(id)
  shelf_location        TEXT    NULL
  image_path            TEXT    NULL
  is_favorite           INTEGER NOT NULL DEFAULT 0
  is_active             INTEGER NOT NULL DEFAULT 1
  created_at            INTEGER NOT NULL
  updated_at            INTEGER NOT NULL
  CHECK((net_weight_value IS NULL) = (net_weight_unit IS NULL))   -- BR-PROD-011
```

### 2.6 product_barcodes

```text
product_barcodes
  id          INTEGER PK
  product_id  INTEGER NOT NULL REFERENCES products(id)
  barcode     TEXT    NOT NULL
  is_primary  INTEGER NOT NULL DEFAULT 0
  created_at  INTEGER NOT NULL
  UNIQUE(barcode)                                     -- BR-PROD-005: global benzersiz
```

### 2.7 carts / cart_items

```text
carts
  id          INTEGER PK
  status      TEXT    NOT NULL        -- 'active' | 'closed' | 'abandoned'
  user_id     INTEGER NOT NULL REFERENCES users(id)
  note        TEXT    NULL
  created_at  INTEGER NOT NULL
  updated_at  INTEGER NOT NULL

cart_items
  id                    INTEGER PK
  cart_id               INTEGER NOT NULL REFERENCES carts(id) ON DELETE CASCADE
  product_id            INTEGER NOT NULL REFERENCES products(id)
  quantity              INTEGER NOT NULL CHECK(quantity > 0)   -- BR-SALE-011: tam sayı
  unit_price_minor      INTEGER NOT NULL                       -- KDV dahil
  is_price_overridden   INTEGER NOT NULL DEFAULT 0
  added_at              INTEGER NOT NULL
  updated_at            INTEGER NOT NULL
  UNIQUE(cart_id, product_id, unit_price_minor)   -- aynı fiyattaki aynı ürün tek satırda birleşir
```

> `carts.status = 'active'` tekliği (BR-CART-001) kısmi benzersiz index ile zorlanır:
> `CREATE UNIQUE INDEX ux_carts_active ON carts(status) WHERE status = 'active'`

### 2.8 sales / sale_items

```text
sales
  id                    INTEGER PK
  sale_number           TEXT    NOT NULL UNIQUE
  status                TEXT    NOT NULL   -- completed|cancelled|partiallyReturned|returned
  subtotal_minor        INTEGER NOT NULL     -- KDV HARİÇ toplam (matrah)
  vat_total_minor       INTEGER NOT NULL
  discount_total_minor  INTEGER NOT NULL DEFAULT 0   -- V1'de daima 0 (OD-007)
  grand_total_minor     INTEGER NOT NULL     -- KDV DAHİL, müşteriden alınan tutar
                                             -- invariant: subtotal + vat = grand_total
  cost_total_minor      INTEGER NOT NULL
  cash_received_minor   INTEGER NULL
  change_minor          INTEGER NULL
  item_count            INTEGER NOT NULL
  unit_count            INTEGER NOT NULL
  user_id               INTEGER NOT NULL REFERENCES users(id)
  note                  TEXT    NULL
  completed_at          INTEGER NOT NULL     -- raporların zaman ekseni
  cancelled_at          INTEGER NULL
  created_at            INTEGER NOT NULL
  updated_at            INTEGER NOT NULL

sale_items
  id                        INTEGER PK
  sale_id                   INTEGER NOT NULL REFERENCES sales(id)
  product_id                INTEGER NOT NULL REFERENCES products(id)
  product_name_snapshot     TEXT    NOT NULL
  barcode_snapshot          TEXT    NULL
  category_id_snapshot      INTEGER NULL
  quantity                  INTEGER NOT NULL CHECK(quantity > 0)  -- BR-SALE-011
  unit_price_minor          INTEGER NOT NULL   -- SNAPSHOT: satış anındaki fiyat (KDV dahil)
  original_unit_price_minor INTEGER NOT NULL   -- SNAPSHOT: o andaki liste fiyatı
  purchase_price_snapshot_minor INTEGER NOT NULL -- SNAPSHOT: satış anındaki alış fiyatı
  vat_rate_snapshot_bp      INTEGER NOT NULL   -- SNAPSHOT: satış anındaki KDV oranı
  line_net_minor            INTEGER NOT NULL   -- KDV hariç
  line_vat_minor            INTEGER NOT NULL
  line_total_minor          INTEGER NOT NULL   -- = unit_price_minor × quantity (KDV dahil)
  returned_quantity         INTEGER NOT NULL DEFAULT 0
  CHECK(returned_quantity >= 0 AND returned_quantity <= quantity)
```

### 2.9 returns / return_items

```text
returns
  id           INTEGER PK
  sale_id      INTEGER NOT NULL REFERENCES sales(id)
  type         TEXT    NOT NULL          -- 'full' | 'partial'
  total_minor  INTEGER NOT NULL
  reason       TEXT    NULL
  user_id      INTEGER NOT NULL REFERENCES users(id)
  created_at   INTEGER NOT NULL

return_items
  id                INTEGER PK
  return_id         INTEGER NOT NULL REFERENCES returns(id)
  sale_item_id      INTEGER NOT NULL REFERENCES sale_items(id)
  quantity          INTEGER NOT NULL CHECK(quantity > 0)
  unit_price_minor  INTEGER NOT NULL
  line_total_minor  INTEGER NOT NULL
```

### 2.10 stock_movements

```text
stock_movements
  id               INTEGER PK
  product_id       INTEGER NOT NULL REFERENCES products(id)
  type             TEXT    NOT NULL
  quantity_delta   INTEGER NOT NULL CHECK(quantity_delta <> 0)
  resulting_stock  INTEGER NOT NULL
  unit_cost_minor  INTEGER NULL
  reference_type   TEXT    NULL
  reference_id     INTEGER NULL
  supplier_id      INTEGER NULL REFERENCES suppliers(id)
  note             TEXT    NULL
  user_id          INTEGER NOT NULL REFERENCES users(id)
  created_at       INTEGER NOT NULL
```

### 2.11 audit_logs

```text
audit_logs
  id           INTEGER PK
  created_at   INTEGER NOT NULL
  user_id      INTEGER NULL REFERENCES users(id)
  action       TEXT    NOT NULL
  entity_type  TEXT    NOT NULL
  entity_id    INTEGER NULL
  old_value    TEXT    NULL      -- JSON, yalnızca değişen alanlar
  new_value    TEXT    NULL      -- JSON, yalnızca değişen alanlar
  metadata     TEXT    NULL      -- JSON
```

### 2.12 app_settings

```text
app_settings
  key         TEXT PK
  value       TEXT NOT NULL
  updated_at  INTEGER NOT NULL
```

Kritik anahtarlar (tam liste: [04 §3.13](04-domain-model.md)):

| Anahtar | İçerik |
|---|---|
| `session` | `{ userId, loginAt }` |
| `dashboard_password_hash` / `dashboard_password_salt` | **Dashboard parolası** — salt'lı SHA-256 (BR-AUTH-009). Düz metin saklanmaz. |
| `dashboard_recovery_hash` / `dashboard_recovery_salt` | **Recovery code** — salt'lı SHA-256 (BR-AUTH-015). Düz metin saklanmaz. |
| `dashboard_recovery_used_at` | Recovery code tek kullanımlık kontrolü (BR-AUTH-015) |
| `sale_counter_<yıl>` | Satış numarası sayacı |
| `migration_in_progress` / `restore_in_progress` | Kurtarma bayrakları |
| `image_optimization` | Görsel optimizasyon profili ([OD-016](28-open-decisions.md)) |

---

## 3. Index stratejisi

Index'ler tahminle değil, **gerçek sorgu desenlerine** göre belirlenmiştir.

| Index | Tablo/Alan | Hangi sorgu için | Kritiklik |
|---|---|---|---|
| `ux_barcode` | `product_barcodes(barcode)` UNIQUE | **Barkod lookup — satış hızının tamamı buna bağlı** | 🔴 Kritik |
| `ix_barcode_product` | `product_barcodes(product_id)` | Ürün detayında barkod listesi | 🟡 |
| `ix_products_active_name` | `products(is_active, name)` | Ürün arama / listeleme | 🔴 |
| `ix_products_category` | `products(category_id, is_active)` | Kategori bazlı listeleme ve rapor | 🟡 |
| `ix_products_supplier` | `products(supplier_id)` | Tedarikçi raporu | 🟢 |
| `ix_products_favorite` | `products(is_favorite)` WHERE `is_favorite = 1` | Satış ekranı favoriler | 🟡 |
| `ix_products_lowstock` | `products(minimum_stock, stock_quantity)` | Kritik/negatif stok raporu | 🟡 |
| `ix_sales_completed_at` | `sales(completed_at)` | **Tüm tarih aralıklı raporlar ve dashboard** | 🔴 |
| `ix_sales_status_date` | `sales(status, completed_at)` | Net ciro (iptaller hariç) | 🟡 |
| `ix_sale_items_sale` | `sale_items(sale_id)` | Satış detayı | 🔴 |
| `ix_sale_items_product` | `sale_items(product_id)` | En çok/az satan ürün raporu | 🔴 |
| `ix_movements_product_date` | `stock_movements(product_id, created_at)` | Ürün stok geçmişi | 🔴 |
| `ix_movements_date` | `stock_movements(created_at)` | Stok hareket raporu | 🟡 |
| `ix_movements_reference` | `stock_movements(reference_type, reference_id)` | Satışa bağlı hareketleri bulma (iptal) | 🟡 |
| `ix_audit_date` | `audit_logs(created_at)` | Audit görüntüleme | 🟢 |
| `ix_audit_entity` | `audit_logs(entity_type, entity_id)` | Bir ürünün değişim geçmişi | 🟢 |
| `ux_carts_active` | `carts(status)` WHERE `status='active'` | Aktif sepet tekliği | 🔴 |

### Ürün adına göre arama

`LIKE '%kelime%'` index kullanamaz. Ölçümler, 10.000 ürünlük bir tabloda tam taramanın
masaüstü donanımında ~15–30 ms sürdüğünü gösterir — 150 ms hedefinin fazlasıyla altında.

**V1'de FTS5 kullanılmaz.** Aşağıdakiler yeterlidir:
- `is_active` ön filtresi (pasif ürünler taranmaz)
- 150 ms debounce, maksimum 50 sonuç
- Sonuçların SQL tarafında sıralanması ve sayfalanması

> **Ölçüm eşiği:** Arama 150 ms'yi aşarsa FTS5 sanal tablosu devreye alınır
> ([24 §2](24-non-functional-requirements.md)). Bu, ölçüme dayalı bir tetikleyicidir —
> önceden yapılmaz (premature optimization).

---

## 4. Denormalizasyon kayıtları

Bilinçli olarak türetilmiş (denormalize) tutulan alanlar ve senkron garantileri:

| Alan | Kaynağı | Senkron garantisi |
|---|---|---|
| `products.stock_quantity` | `stock_movements` toplamı | Aynı transaction (BR-STOCK-002) |
| `sale_items.returned_quantity` | `return_items` toplamı | Aynı transaction |
| `sales.item_count` / `unit_count` | `sale_items` | Satış oluşturma transaction'ı |
| `sales.cost_total_minor` | `sale_items.unit_cost × quantity` | Satış oluşturma transaction'ı |

**Doğrulama aracı:** Ayarlar → "Veri Tutarlılığı Kontrolü" ekranı bu dört alanı kaynaklarıyla karşılaştırır
ve sapma varsa raporlar. Bkz. [24 §3](24-non-functional-requirements.md).

---

## 5. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-DB-001 | Veritabanı WAL modunda, `synchronous=FULL` ve `foreign_keys=ON` ile açılır. |
| REQ-DB-002 | Tüm parasal alanlar tam sayı kuruş tipindedir; hiçbir tabloda ondalık para alanı bulunmaz. |
| REQ-DB-003 | Tüm zaman alanları UTC unix-millisecond tam sayıdır. |
| REQ-DB-004 | `product_barcodes.barcode` üzerinde global UNIQUE kısıt bulunur. |
| REQ-DB-005 | Aynı anda birden fazla `active` sepet oluşmasını engelleyen kısmi unique index bulunur. |
| REQ-DB-006 | §3'teki 🔴 kritik index'lerin tamamı ilk sürümde mevcuttur. |
| REQ-DB-007 | Veritabanı dosyası kullanıcı veri dizininde tutulur, kurulum dizininde tutulmaz. |
| REQ-DB-008 | Denormalize alanların kaynak verilerle uyumunu kontrol eden bir doğrulama işlevi bulunur. |
| REQ-DB-009 | Miktar alanları (`cart_items.quantity`, `sale_items.quantity`, `return_items.quantity`) tam sayıdır ve pozitif olmak zorundadır. |
| REQ-DB-010 | Hiçbir tabloda düz metin parola veya kurtarma kodu alanı bulunmaz. |
| REQ-DB-011 | Ürün tablosu satış birimi ve net ağırlık alanlarını ayrı ayrı taşır; ağırlık değeri ve birimi birlikte doldurulmak zorundadır. |
