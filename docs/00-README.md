# Kantin Otomasyonu — Dokümantasyon İndeksi

> **Doküman sürümü: v3 — FİNAL** (revizyon: 2026-08-13)
> **Durum:** ✅ **Dokümantasyon tamamlandı. Açık karar yok. Geliştirmeye hazır.**
> **Kod durumu:** Repository yalnızca `flutter create` iskeletini içeriyor. Henüz uygulama kodu yok.

## Kesinleşen kararlar (16/16 kapandı)

| Konu | Karar |
|---|---|
| Veritabanı | **Drift + SQLite** |
| State management | **Riverpod** |
| KDV | **Satış fiyatı KDV DAHİLDİR** |
| Satış miktarı | **Tam sayı** (tartılı satış V1 dışı) |
| Maliyet | **Son alış fiyatı** + SaleItem snapshot'ı |
| Parola saklama | **Salt'lı SHA-256** — düz metin hiçbir yerde yok |
| **Finansal erişim** | **Dashboard + Raporlar**, ayrı dashboard parolası ile korunur |
| **Kurtarma** | **Tek kullanımlık recovery code** (`XXXX-XXXX-XXXX-XXXX`) |
| İndirim / nakit yuvarlama | **V1'de yok** |
| Kasa / vardiya | **V1 kapsamı dışı** |
| Import/export | **CSV birincil**, Excel ayrı abstraction |
| Yedek | **ZIP, tek dosya** `.canteenbackup` |
| Installer | **Inno Setup** |
| Grafik | **fl_chart** |
| Lokalizasyon | **Türkçe**, merkezî metin dosyası |
| Görsel optimizasyon | **1000 px / JPEG 85** — yapılandırılabilir teknik politika |

**Açık karar: 0** → [28 — Karar Kaydı](28-open-decisions.md)

---

## 1. Bu dokümantasyon nedir?

Bu klasör, Kantin Otomasyonu projesinin **geliştirmeye başlamadan önceki tek doğruluk kaynağıdır (single source of truth)**.
Buradaki dokümanlar; ürün gereksinimlerini, business rule'ları, veri modelini, mimariyi, akışları, edge-case'leri,
verilmiş kararları ve yol haritasını tanımlar.

**Kod yazılırken bu dokümanlar referans alınır.** Bir davranış burada tanımlıysa, kod ona uymalıdır.
Bir davranış burada tanımlı değilse, önce doküman güncellenir, sonra kod yazılır.

---

## 2. Okuma sırası

Projeye yeni başlayan biri için önerilen sıra:

| Sıra | Doküman | Neden |
|---|---|---|
| 1 | [01 — Proje Genel Bakış](01-project-overview.md) | Proje ne, ne değil |
| 2 | [28 — Karar Kaydı](28-open-decisions.md) | Hangi kararın neden verildiği |
| 3 | [04 — Domain Model](04-domain-model.md) | Sistemin kavramsal omurgası |
| 4 | [05 — Database Mimarisi](05-database-architecture.md) | Fiziksel veri modeli |
| 5 | [03 — Uygulama Mimarisi](03-architecture.md) | Katmanlar ve klasör yapısı |
| 6 | [31 — Roadmap](31-roadmap.md) | Hangi sırayla geliştirilecek |

---

## 3. Doküman haritası

### Temel / Ürün

| Dosya | İçerik |
|---|---|
| [01-project-overview.md](01-project-overview.md) | Proje tanımı, kapsam, platform, terimler sözlüğü |
| [02-product-and-business-requirements.md](02-product-and-business-requirements.md) | Ürün felsefesi, kullanıcı profili, business rule kataloğu (BR-*) |
| [25-functional-requirements.md](25-functional-requirements.md) | **Ana requirement indeksi (REQ-*) + acceptance criteria** |
| [24-non-functional-requirements.md](24-non-functional-requirements.md) | Performans, data integrity, güvenlik, uyumluluk |

### Mimari / Veri

| Dosya | İçerik |
|---|---|
| [03-architecture.md](03-architecture.md) | Katmanlı mimari, klasör yapısı, DI, state management |
| [04-domain-model.md](04-domain-model.md) | Entity'ler, ilişkiler, ERD, invariant'lar |
| [05-database-architecture.md](05-database-architecture.md) | Tablo şemaları, index'ler, DB teknolojisi kararı |
| [06-database-migrations.md](06-database-migrations.md) | Schema versiyonlama, migration ve rollback stratejisi |

### Finans

| Dosya | İçerik |
|---|---|
| [07-financial-rules.md](07-financial-rules.md) | Para gösterimi, integer kuruş, yuvarlama, kâr hesabı |
| [08-vat-rules.md](08-vat-rules.md) | KDV altyapısı — **satış fiyatı KDV dahil** |

### Modüller

| Dosya | İçerik |
|---|---|
| [09-product-management.md](09-product-management.md) | Ürün CRUD, alan zorunlulukları, favoriler |
| [10-category-brand-supplier.md](10-category-brand-supplier.md) | Kategori, marka, tedarikçi, birim yönetimi |
| [11-barcode-system.md](11-barcode-system.md) | Scanner abstraction, input handler, barkod modeli |
| [12-sales-system.md](12-sales-system.md) | Satış ekranı, sepet, aktif sepet kalıcılığı, nakit |
| [13-stock-system.md](13-stock-system.md) | Stok hareket defteri, negatif stok |
| [14-returns-and-cancellation.md](14-returns-and-cancellation.md) | Satış iptali, tam/kısmi iade |
| [15-dashboard.md](15-dashboard.md) | Finansal erişim kilidi, KPI'lar, grafikler, tarih aralıkları |
| [16-reporting.md](16-reporting.md) | Rapor kataloğu, filtreler, çıktı formatları (kilit arkasında) |
| [17-authentication.md](17-authentication.md) | Login, oturum, kullanıcı yönetimi, **finansal erişim kilidi**, **recovery code** |
| [18-audit-log.md](18-audit-log.md) | Denetim kaydı kapsamı ve şeması |
| [19-backup-restore.md](19-backup-restore.md) | Backup container formatı, restore protokolü |
| [20-import-export.md](20-import-export.md) | CSV (birincil) / Excel import validasyonu, export kapsamı |
| [21-image-storage.md](21-image-storage.md) | Görsel dosya stratejisi, orphan yönetimi |

### Deneyim / Akış

| Dosya | İçerik |
|---|---|
| [22-user-flows.md](22-user-flows.md) | Uçtan uca kullanıcı akışları |
| [23-ux-requirements.md](23-ux-requirements.md) | Keyboard-first POS UX, kısayollar, layout |

### Kalite / Yönetim

| Dosya | İçerik |
|---|---|
| [26-edge-cases.md](26-edge-cases.md) | Edge-case kataloğu (EC-*) ve beklenen davranışlar |
| [27-testing-strategy.md](27-testing-strategy.md) | Test piramidi, kritik test alanları |
| [28-open-decisions.md](28-open-decisions.md) | **Karar kaydı (OD-*) — 16 karar, tümü kapalı** |
| [29-risks.md](29-risks.md) | Risk kaydı (RSK-*) ve mitigasyonlar |
| [30-future-scope.md](30-future-scope.md) | Kapsam dışı olanlar, gelecek backend stratejisi |
| [31-roadmap.md](31-roadmap.md) | Faz planı, bağımlılıklar, çıkış kriterleri |

---

## 4. Kimlik (ID) sistemleri

Bu dokümantasyonda dört ayrı numaralandırma kullanılır:

| Önek | Anlamı | Nerede tanımlı |
|---|---|---|
| `REQ-<MODÜL>-NNN` | Functional requirement (285 adet) | [25-functional-requirements.md](25-functional-requirements.md) |
| `BR-<MODÜL>-NNN` | Business rule (76 adet) | [02-product-and-business-requirements.md](02-product-and-business-requirements.md) |
| `EC-<MODÜL>-NNN` | Edge case | [26-edge-cases.md](26-edge-cases.md) |
| `OD-NNN` | Karar kaydı (tümü kapalı) | [28-open-decisions.md](28-open-decisions.md) |
| `RSK-NNN` | Risk (13 aktif) | [29-risks.md](29-risks.md) |

Modül kısaltmaları: `ARCH`, `DB`, `MIG`, `FIN`, `VAT`, `PROD`, `CAT`, `SUP`, `BARC`, `CART`, `SALE`, `STOCK`,
`RET`, `DASH`, `REP`, `AUTH`, `AUDIT`, `BKUP`, `IMEX`, `IMG`, `UX`, `PERF`, `DATA`, `SEC`.

---

## 5. Doküman bakım kuralları

1. **Tek tanım kuralı.** Bir business rule tek bir dokümanda tanımlanır; diğer dokümanlar ona **link verir**, yeniden yazmaz.
2. **Çelişki yasağı.** İki doküman aynı davranışı farklı tanımlıyorsa bu bir bug'dır; kod yazılmadan çözülür.
3. **Varsayım yasağı.** Geliştirme sırasında kararlaştırılmamış bir konu çıkarsa `OD-017`'den başlayarak [28](28-open-decisions.md)'e yazılır ve kapanmadan ilgili kod yazılmaz.
4. **Kod yok.** Bu dokümanlarda production kodu bulunmaz. Şema tanımları ve pseudocode veri modeli dokümantasyonudur.
5. Bir requirement değişirse; ilgili REQ, acceptance criteria, edge-case ve test planı **birlikte** güncellenir.
