# 03 — Veri, Kalıcılık, Migration, Yedekleme

> Kaynak: `docs/05-database-architecture.md` · `06-database-migrations.md` · `18-audit-log.md`
> `19-backup-restore.md` · `20-import-export.md` · `21-image-storage.md` · `24 §3`

---

## 1. Veritabanı

**Drift + SQLite.** Şema **FİNAL** — 15 tablo:

```text
users · categories · suppliers · vat_rates · products · product_barcodes
carts · cart_items · sales · sale_items · returns · return_items
stock_movements · audit_logs · app_settings
```

### Zorunlu yapılandırma

| Ayar | Değer | Gerekçe |
|---|---|---|
| `journal_mode` | **WAL** | Elektrik kesintisi dayanıklılığı |
| `synchronous` | **FULL** | Satış kaybı kabul edilemez |
| `foreign_keys` | **ON** | Referans bütünlüğü |
| `busy_timeout` | 5000 ms | |
| `temp_store` | **MEMORY** | Rapor aggregation hızı |

### Kurallar

- Tüm parasal alanlar **tam sayı kuruş**; hiçbir tabloda ondalık para alanı yok.
- Tüm zaman alanları **UTC unix-millisecond**; kullanıcıya yerel saat gösterilir.
- Tüm sorgular **parametrelidir** (Drift bunu zaten zorlar).
- Yeni tablo/kolon eklemek bir **şema kararıdır** → `00-source-of-truth.md §3` protokolü.

### Veri konumu — kritik

```text
Windows : %APPDATA%\CanteenApp\
macOS   : ~/Library/Application Support/CanteenApp/
```

> **Kullanıcı verisi ASLA kurulum dizinine yazılmaz** (BR-DATA-001).
> Bu kural [RSK-002](../../docs/29-risks.md)'nin (güncellemede veri kaybı) tek savunmasıdır.

Yol işlemlerinde `path` paketi kullanılır; elle string birleştirme yapılmaz.

---

## 2. Denormalize alanlar

Bilinçli olarak türetilmiş tutulan alanlar — **kaynağıyla aynı transaction içinde** güncellenir:

| Alan | Kaynağı |
|---|---|
| `products.stock_quantity` | `stock_movements` toplamı |
| `sale_items.returned_quantity` | `return_items` toplamı |
| `sales.item_count` / `unit_count` | `sale_items` |
| `sales.cost_total_minor` | satır maliyet snapshot'ları |

Tutarlılık kontrolü işlevi (`docs/24 §3.3`) bu alanları kaynaklarıyla karşılaştırır.
Sapma bulunursa **otomatik düzeltme yapılmaz** — kullanıcı onayıyla `adjustment` hareketi oluşturulur.

---

## 3. Migration

> **Şema doğrudan değiştirilemez.** Her değişiklik versiyonlu bir migration adımıdır.

### Kurallar

| # | Kural |
|---|---|
| 1 | Migration'lar **deterministik** ve **test edilebilir**dir |
| 2 | Yayınlanmış bir migration adımı **sonradan düzenlenmez**; yeni adım eklenir |
| 3 | **Veri kaybettiren işlem yasak** (kolon/tablo silme) — kullanımdan kaldırılır (deprecated) |
| 4 | Yeni `NOT NULL` kolon daima **varsayılan değerle** eklenir |
| 5 | Migration **tek transaction** içinde çalışır |
| 6 | Migration öncesi **otomatik snapshot** alınır ve doğrulanır |
| 7 | Başarısızlıkta veri **migration öncesi haline döner** |
| 8 | Yarım kalmış migration açılışta **tespit edilir ve kurtarılır** |
| 9 | Uygulama, desteklediğinden **yeni** bir şema versiyonunu açmayı reddeder |

> **Migration sırasında veri kaybı kabul edilemez.** Bu bir hedef değil, mutlak kısıttır.

### Migration testleri zorunludur

- Her `vN → vN+1` adımı ayrı ayrı
- `v1 → vSON` tam zincir
- **Veri koruma:** her adım öncesi örnek veri yazılır, sonrasında satır sayısı ve kritik alanlar doğrulanır
- Adım ortasında hata enjeksiyonu → rollback doğrulaması
- Migration sonrası `PRAGMA foreign_key_check` boş dönmelidir

Yayınlanan her şema versiyonu repoda saklanır (`test/db/schema/vN.json`).

---

## 4. Uygulama güncellemesi

Yeni sürüm kurulumu şunları **silmemelidir:**

`veritabanı` · `ürünler` · `satışlar` · `stoklar` · `görseller` · `oturum` · `aktif sepet`

- Installer `%APPDATA%\CanteenApp\` dizinine **dokunmaz.**
- Migration açılışta çalışır ve güncelleme ile birlikte güvenli ilerler.
- Bu davranış her sürümde **manuel olarak test edilir** (`docs/27 §8` — W5, W6).

---

## 5. Single instance

> Aynı veritabanını kullanan **iki uygulama örneği aynı anda çalışamaz** (BR-GEN-005).

- Veri dizininde kilit dosyası tutulur.
- İkinci örnek: mevcut pencereyi öne getirir ve kapanır.
- Çökme sonrası kalan kilit (stale lock) PID kontrolüyle temizlenir.
- Özellikle **Windows production** için kritiktir ([RSK-003](../../docs/29-risks.md)).

---

## 6. Yedekleme

**Kritik business feature'dır** — [RSK-005](../../docs/29-risks.md)'in tek savunması.

### Format

Tek dosya: `canteen_backup_<timestamp>.canteenbackup` (ZIP/archive tabanlı)

İçerik:

```text
metadata.json     → schemaVersion, appVersion, createdAt, createdBy, counts
database.sqlite   → tutarlı snapshot (VACUUM INTO)
checksums.json    → SHA-256
images/           → yalnızca DB'de referansı olan görseller
```

### Kurallar

| # | Kural |
|---|---|
| 1 | Yedek **düz metin parola veya recovery code içermez** (BR-SEC-001) |
| 2 | Dosya **ancak tamamen yazılıp doğrulandıktan sonra** nihai adını alır (`.tmp` → atomik rename) |
| 3 | Oluşturulduktan sonra **tekrar okunarak doğrulanır** |
| 4 | Uygulama durdurulmadan tutarlı snapshot alınır |

### Restore — mevcut veri kaybı engellenmelidir

```text
1. DOĞRULAMA (hiçbir şey değiştirilmez)
   format · backupFormatVersion · schemaVersion · checksum · integrity_check
2. Karşılaştırmalı özet (yedekteki vs mevcut kayıt sayıları)
3. Kullanıcının kasıtlı onayı (yazarak)
4. GÜVENLİK YEDEĞİ (mevcut verinin otomatik yedeği)
5. Mevcut dosyalar SİLİNMEZ → .old_<ts> olarak yeniden adlandırılır
6. Yeni dosyalar yerleştirilir → doğrulanır
7. Gerekiyorsa migration
8. Doğrulama başarısızsa → GERİ AL
9. Oturum sonlandırılır + finansal erişim kilidi kapatılır
10. Satış numarası sayacı düzeltilir
```

Yarım kalmış restore açılışta **tespit edilir ve kurtarılır** (`restore_in_progress` bayrağı).

**Daha yeni şema versiyonlu yedek reddedilir.** Daha eski yedek restore sonrası migration'dan geçer.

---

## 7. Import / Export

> **CSV birincil, Excel ikincil** (ayrı abstraction arkasından).

### Akış — atlanamaz

```text
Dosya seç → Parse → Validate → PREVIEW → Kullanıcı onayı → Transactional import
```

### Kurallar

| # | Kural |
|---|---|
| 1 | **Kısmi ve sessiz import YASAKTIR** — all-or-nothing, tek transaction |
| 2 | Hata durumunda **tam rollback**; hiçbir kayıt oluşmaz |
| 3 | Kullanıcı onayı olmadan import başlamaz |
| 4 | Hatalı satırlar satır numarası + sebebiyle gösterilir |
| 5 | **Duplicate barcode politikası** uygulanır (aşağıda) |
| 6 | Stok değişiklikleri **stok hareketi** oluşturur (doğrudan yazım yok) |
| 7 | **Satış, satış satırı ve stok hareketi import edilemez** — denetim izinin temeli |
| 8 | CSV: UTF-8 **BOM ile**, ayırıcı `;` (Türkçe Excel uyumu) |

### Duplicate barcode politikası (BR-IMEX-001/002)

| Çakışma | Davranış |
|---|---|
| Barkod **sistemde zaten var** | Kullanıcı politika seçer: *atla* (varsayılan) / *mevcut ürünleri güncelle* / *iptal* |
| Barkod **dosya içinde tekrarlanıyor** | O barkoda ait **tüm satırlar reddedilir** — sistem hangisinin doğru olduğuna karar veremez |

### Güvenlik

- Arşivden çıkarmada **zip-slip koruması** (hedef dizin dışına yazma engellenir)
- Aşırı büyüyen arşiv reddedilir (zip bomb)
- CSV export'ta `=`, `+`, `-`, `@` ile başlayan hücreler kaçışlanır (formül enjeksiyonu)

---

## 8. Görsel dosyaları

```text
Dosya seç → OPTİMİZE ET → local storage'a kopyala → DB'ye göreli yol yaz
```

| Kural | |
|---|---|
| Saklama | **Dosya sistemi**; DB'ye binary gömülmez |
| DB'de tutulan | **Göreli** yol (`images/<uuid>.jpg`) — mutlak yol asla |
| Adlandırma | UUID v4; orijinal dosya adı kullanılmaz |
| Optimizasyon | **Import sırasında yapılır** |
| Orijinal dosya | **Saklanmaz** — yalnızca optimize edilmiş kopya kalır |
| Silme | Anında değil; `.trash/`'a taşınır, gecikmeli temizlenir |
| Ürün başına | 1 görsel |

### Optimizasyon politikası — configurable technical policy

| Parametre | Başlangıç değeri |
|---|---|
| Maksimum boyut (uzun kenar) | **1000 px** |
| JPEG kalitesi | **85** |
| Maksimum yükleme dosya boyutu | 10 MB |

> Bu değerler **business rule değildir.** `app_settings['image_optimization']` üzerinden
> yapılandırılabilir; koda sabit yazılmaz.

Format doğrulaması **dosya içeriğinden** (magic bytes) yapılır, uzantıdan değil.

---

## 9. Audit log

Önemli **mutation** işlemleri kaydedilir:

`stok değişiklikleri` · `fiyat değişiklikleri` · `ürün değişiklikleri` · `satışlar` ·
`iptaller` · `iadeler` · `import` · `export` · `backup` · `restore` · `authentication olayları` ·
`finansal erişim kilidi olayları` · `recovery code kullanımı`

### Kurallar

| # | Kural |
|---|---|
| 1 | Audit kaydı **kaydettiği işlemle aynı transaction** içinde yazılır |
| 2 | Audit yazımındaki hata **ana işlemi başarısız kılmaz** (log'a yazılır, satış devam eder) |
| 3 | Audit kayıtları **düzenlenemez ve silinemez** |
| 4 | Yalnızca **değişen alanların** eski/yeni değeri saklanır (tüm kayıt kopyalanmaz) |
| 5 | **Parola, recovery code, hash, salt ASLA yazılmaz** |

### Audit log ≠ business history

> Audit log, business history'nin **yerine geçmez.**

```text
stock_movements  →  stok geçmişinin OTORİTESİ
sales/sale_items →  satış geçmişinin OTORİTESİ
audit_logs       →  "kim, ne zaman, neyi değiştirdi" DENETİM İZİ
```

Bunlar **ayrı tutulur.** Stok geçmişi audit log'dan türetilmez; audit log stok defterinin yerini almaz.

---

## 10. Veri bütünlüğü — atomik olmak zorunda olanlar

| İşlem | Kapsam |
|---|---|
| Satış tamamlama | sale + saleItems + stockMovements + stock + cart + audit |
| Satış iptali | status + N stockMovement + N stock + audit |
| İade | return + returnItems + returnedQuantity + N stockMovement + N stock + status + audit |
| Stok girişi | N stockMovement + N stock + (fiyat) + audit |
| Ürün import | kategoriler + tedarikçiler + ürünler + barkodlar + stok hareketleri + audit |
| Ürün + barkod oluşturma | product + productBarcodes + initial hareket + audit |
| Recovery ile parola sıfırlama | parola + kod geçersizleştirme + yeni kod + audit |

Elektrik kesintisi **normal bir senaryo** kabul edilir; tasarım buna göre yapılır.
