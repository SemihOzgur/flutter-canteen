# 24 — Fonksiyonel Olmayan Gereksinimler

> **Doküman sürümü:** v3 — ölçek 10.000+ ürüne çıkarıldı; finansal erişim kilidi kapsamı güncellendi.

Performans, veri bütünlüğü, güvenlik ve platform uyumluluğu bu dokümanda toplanmıştır.

---

## 1. Ölçek varsayımları

Tasarım kararları bu rakamlara göre alınmıştır:

| Veri | 1. yıl | 5. yıl |
|---|---|---|
| Ürün | ~1.000 | **10.000+** |
| Barkod | ~1.400 | ~15.000 |
| Kategori | ~20 | ~40 |
| Tedarikçi | ~10 | ~25 |
| Satış (fiş) | ~40.000 (günde ~120) | ~200.000 |
| Satış satırı | ~120.000 | ~600.000 |
| Stok hareketi | ~140.000 | ~700.000 |
| Audit kaydı | ~20.000 | ~100.000 |
| Veritabanı boyutu | ~50 MB | ~250 MB |
| Görsel | ~200 dosya / 20 MB | ~800 dosya / 80 MB |

**Ürün sayısına yapay bir üst sınır konulmaz.** Mimari, uygun index + sayfalama + sunucu tarafı
(SQL) arama ile **en az birkaç bin, tercihen 10.000+ ürün** senaryosunu kaldırmalıdır.

Bu ölçekte SQLite rahatlıkla çalışır; sunucu tarafı bir çözüme ihtiyaç yoktur.
Ancak **premature optimization yapılmaz**: FTS5, rollup tabloları ve önbellek katmanları
yalnızca §2'deki ölçüm eşikleri aşıldığında devreye alınır.

---

## 2. Performans

### Hedefler

| İşlem | Hedef | Kabul edilemez |
|---|---|---|
| **Barkod → sepette görünme** | < 100 ms | > 250 ms |
| Ürün arama sonucu (10.000 ürün) | < 150 ms | > 400 ms |
| Sepet işlemi (ekle/sil/miktar) | < 50 ms | > 150 ms |
| **Satış tamamlama (transaction)** | < 50 ms | > 300 ms |
| Uygulama soğuk açılış | < 3 sn | > 6 sn |
| Ürün listesi (10.000 ürün, sayfalı) | < 300 ms | > 1 sn |
| Dashboard (100k satış satırı) | < 1 sn | > 3 sn |
| Rapor (10k satır sonuç) | < 2 sn | > 5 sn |
| Yedek alma (50 MB + 200 görsel) | < 15 sn | > 60 sn |
| 1.000 satırlık import | < 10 sn | > 30 sn |

> En kritik iki satır kalın olanlardır. Bunlar kasadaki kullanıcının doğrudan hissettiği sürelerdir.

### Teknikler

| Alan | Yaklaşım |
|---|---|
| Barkod lookup | `product_barcodes(barcode)` UNIQUE index — O(log n), ürün sayısından bağımsız |
| Ürün listesi | `ListView.builder` + sayfalama; hiçbir zaman tüm ürünler belleğe alınmaz |
| Görseller | Boyutlandırılmış + `ImageCache` sınırlı |
| Arama | 150 ms debounce, maks. 50 sonuç, `is_active` ön filtresi |
| Dashboard/rapor | SQL aggregation; Dart tarafında döngüyle toplama **yasak** |
| Uzun işlem | Isolate; UI bloklanmaz |
| Sepet yazımı | Tek satır INSERT/UPDATE; WAL sayesinde < 1 ms |
| Uygulama açılışı | Kritik olmayan işler (görsel taraması, istatistik) arka plana ertelenir |

### Performans testi

Yapay veri üreteci ile 5. yıl hacminde bir veritabanı oluşturulur ve yukarıdaki hedefler
otomatik testlerle ölçülür. Bkz. [27 §7](27-testing-strategy.md).

---

## 3. Veri bütünlüğü

### 3.1 Tehdit senaryoları ve korumalar

| Senaryo | Koruma |
|---|---|
| **Elektrik kesintisi** | WAL + `synchronous=FULL`; tamamlanmamış transaction'lar geri alınır |
| **Uygulama çökmesi** | Aynı; ek olarak açılışta kurtarma kontrolü |
| **Satış ortasında kesinti** | Tek transaction — ya tam satış ya hiç ([12 §6.2](12-sales-system.md)) |
| **Stok güncellenirken hata** | Aynı transaction içinde — defter ve özet birlikte değişir |
| **Yedek alırken kesinti** | `.tmp` → atomik yeniden adlandırma ([19 §3](19-backup-restore.md)) |
| **Restore sırasında kesinti** | `restore_in_progress` bayrağı + `.old_<ts>` dosyaları ([19 §4](19-backup-restore.md)) |
| **Migration sırasında kesinti** | Pre-migration snapshot + `migration_in_progress` bayrağı ([06 §3](06-database-migrations.md)) |
| **Import sırasında hata** | Tek transaction, tam rollback ([20 §6](20-import-export.md)) |
| **İki uygulama örneği** | Single-instance lock (BR-GEN-005) |
| **Disk dolu** | Yazma öncesi boş alan kontrolü (yedek/import için); hata mesajı |
| **Diskin bozulması** | Yedekleme — tek koruma budur; hatırlatma sistemi ([19 §3](19-backup-restore.md)) |

### 3.2 Atomiklik gerektiren işlemler

Aşağıdakiler **tek transaction** olmak zorundadır:

| İşlem | İçerik |
|---|---|
| Satış tamamlama | sale + saleItems + stockMovements + stock + cart kapatma + audit |
| Satış iptali | status + N stockMovement + N stock + audit |
| İade | return + returnItems + returnedQuantity + N stockMovement + N stock + status + audit |
| Stok girişi | N stockMovement + N stock + (fiyat güncelleme) + audit |
| Ürün import | kategoriler + tedarikçiler + ürünler + barkodlar + stok hareketleri + audit |
| Ürün + barkod oluşturma | product + productBarcodes + (initial hareket) + audit |
| Sayım düzeltmesi | N adjustment + N stock + audit |
| Kategori birleştirme | N ürün güncelleme + audit |

### 3.3 Tutarlılık doğrulaması

**Ayarlar → Bakım → Veri Tutarlılığı Kontrolü** aşağıdakileri denetler:

| Kontrol | Beklenen |
|---|---|
| `products.stock_quantity` = Σ `stock_movements.quantity_delta` | Her ürün için eşit |
| `sale_items.returned_quantity` = Σ `return_items.quantity` | Her satır için eşit |
| `sales.grand_total_minor` = Σ `sale_items.line_total_minor` | Her satış için eşit |
| `sales.item_count` / `unit_count` | Satırlarla tutarlı |
| `sales.status` | İade miktarlarıyla tutarlı ([14 §2](14-returns-and-cancellation.md)) |
| `products.image_path` | Dosya mevcut |
| Foreign key bütünlüğü | `PRAGMA foreign_key_check` boş |
| SQLite bütünlüğü | `PRAGMA integrity_check` = ok |

Sapma bulunursa: rapor gösterilir, **otomatik düzeltme yapılmaz** (kullanıcı onayıyla,
her sapma için ayrı `adjustment` hareketi oluşturularak düzeltilir — defter mantığı korunur).

Bu kontrol her yedek alma öncesi otomatik çalışır (hızlı sürüm) ve sonucu metadata'ya yazılır.

---

## 4. Güvenlik

Bu **yerel, tek kullanıcılı, ağ bağlantısı olmayan** bir masaüstü uygulamasıdır.
Tehdit modeli buna göre dardır. Güvenlik gereksinimleri gereksiz büyütülmez.

### 4.1 Tehdit modeli

| Tehdit | Geçerli mi | Not |
|---|---|---|
| Uzaktan saldırı | ❌ | Ağ dinleyicisi yok, API yok |
| SQL injection | 🟡 | Parametreli sorgular kullanılır (Drift zaten zorlar) |
| Yerel dosya erişimi | ✅ | Bilgisayara fiziksel erişimi olan herkes DB'yi okuyabilir |
| Yedek dosyasının sızması | 🟡 | Taşınabilir dosya; **artık parola içermiyor** (BR-SEC-001) — kalan risk yalnızca ticari veridir |
| Kötü niyetli import dosyası | 🟡 | Zip-slip, aşırı büyük dosya, formül enjeksiyonu |
| Yetkisiz işlem (rol yok) | ✅ | [RSK-004](29-risks.md) — audit log tespit eder, engellemez |
| Finansal veriye yetkisiz bakış | 🟡 | **Finansal erişim kilidi** Dashboard ve Raporlar'ı kapsar (BR-AUTH-013) |
| Veri kaybı | ✅ | En büyük gerçek risk — §3'te ele alındı |

**Kapsam dışı bırakılan güvenlik konuları** (proje sahibi kararı): OAuth, JWT, MFA,
**kullanıcı parolası** kurtarma akışı, sunucu tarafı kimlik doğrulama, veritabanı şifreleme.
*(Dashboard parolası için recovery code **vardır** — [17 §8](17-authentication.md).)*
Güvenlik karmaşıklığı bu tehdit modelinin ötesine büyütülmez.

### 4.2 Alınan önlemler

| Konu | Önlem |
|---|---|
| **Parola saklama** | ✅ **SHA-256 + rastgele salt — karar kapandı** (BR-AUTH-011, [17 §5](17-authentication.md)). Düz metin parola hiçbir yerde bulunmaz (BR-SEC-001) |
| **Finansal erişim** | Dashboard **ve Raporlar**, ayrı bir dashboard parolası ile korunur (BR-AUTH-013). Rol sistemi değildir |
| **Dashboard parolası kurtarma** | Tek kullanımlık recovery code; hash saklanır, kullanıldığında yenisi üretilir (BR-AUTH-015/017) |
| Parola/kod log/audit | Parola, recovery code, hash veya salt hiçbir yere yazılmaz (REQ-AUDIT-004) |
| Veritabanı şifreleme | ❌ Yapılmaz — anahtar aynı makinede duracağı için gerçek koruma sağlamaz, ama backup/kurtarmayı zorlaştırır |
| Yedek dosyası şifreleme | ❌ v1'de yok; kullanıcıya "yedeği güvenli yerde saklayın" uyarısı verilir. İhtiyaç doğarsa parolalı ZIP eklenebilir ([30](30-future-scope.md)) |
| Zip-slip (yedek/import) | Arşivden çıkarılan her yolun hedef klasör içinde kaldığı doğrulanır |
| Aşırı büyük arşiv | Açılmadan önce sıkıştırılmamış boyut kontrol edilir (zip bomb koruması) |
| CSV formül enjeksiyonu | Export'ta `=`, `+`, `-`, `@` ile başlayan hücreler `'` ile öneklenir |
| Dosya yolu doğrulama | Kullanıcıdan gelen yollar normalize edilir; `..` bileşenleri reddedilir |
| Görsel dosyası | İçerik doğrulaması (magic bytes), boyut sınırı ([21 §5](21-image-storage.md)) |
| Hata mesajları | Dosya yolu ve teknik detay kullanıcıya sızdırılmaz; log dosyasına yazılır |

---

## 5. Platform uyumluluğu

### Windows (production)

| Konu | Gereksinim |
|---|---|
| Sürüm | Windows 10 (1809+) ve Windows 11, x64 |
| Veri dizini | `%APPDATA%\CanteenApp\` |
| Kurulum dizini | `C:\Program Files\CanteenApp\` — **veri buraya yazılmaz** (BR-DATA-001) |
| Yönetici hakkı | Çalışma sırasında gerekmez; yalnızca kurulumda |
| Uzun dosya yolu | Yol uzunluğu 260 karakteri aşmayacak şekilde tasarlanır |
| Dosya kilitleme | Windows dosya kilitleri Unix'ten katıdır; DB kapatılmadan dosya taşıma yapılamaz ([19 §4 adım 12](19-backup-restore.md)) |
| Klavye düzeni | Barkod girişi Türkçe Q/F düzeninde doğrulanır ([11 §5](11-barcode-system.md)) |
| Yüksek DPI | %100, %125, %150 ölçeklemede test edilir |
| Installer | Bkz. [OD-013](28-open-decisions.md) |

### macOS (geliştirme)

| Konu | |
|---|---|
| Veri dizini | `~/Library/Application Support/CanteenApp/` |
| Test edilebilir | UI, DB, satış, stok, backup, restore, import/export, raporlar |
| Test edilemez / Windows'ta doğrulanmalı | Installer, güncelleme, dosya kilitleme davranışı, klavye düzeni, yol uzunluğu, yüksek DPI, gerçek barkod okuyucu HID davranışı |
| Kod imzalama / notarization | ❌ Gerekmez — dağıtım yapılmayacak |

> **Kural:** macOS'ta çalışan bir şeyin Windows'ta çalıştığı **varsayılamaz.**
> Her faz sonunda Windows doğrulaması yapılır ([31](31-roadmap.md) faz çıkış kriterleri).

---

## 6. Uygulama güncellemesi

> **En kritik kural: güncelleme veri silmez.** (BR-DATA-001)

| Konu | Karar |
|---|---|
| Veri konumu | `%APPDATA%` — kurulum dizininden tamamen ayrı |
| Kurulum | Installer eski sürümün üzerine yazar; `%APPDATA%`'ya dokunmaz |
| Şema | Yeni sürüm açılışta migration çalıştırır ([06](06-database-migrations.md)) |
| Oturum | Korunur |
| Aktif sepet | Korunur |
| Görseller | Korunur |
| Geri dönüş | Eski sürüm yeni şemayı açamaz → kullanıcı uyarılır (REQ-MIG-005) |
| Otomatik güncelleme | v1'de yok; kullanıcı yeni installer'ı elle çalıştırır |
| Sürüm numarası | Semantic versioning (`MAJOR.MINOR.PATCH`) |

Installer/paketleme kararı: [OD-013](28-open-decisions.md).

---

## 7. Gözlemlenebilirlik

| Konu | |
|---|---|
| Log dosyası | `<veri dizini>/logs/app-YYYY-MM-DD.log` |
| Rotasyon | 14 gün, maksimum toplam 50 MB |
| Seviyeler | ERROR, WARN, INFO (DEBUG yalnızca geliştirme derlemesinde) |
| İçerik | Hata + stack trace, uzun süren işlemler, kurtarma olayları, migration adımları |
| Loglanmaz | Parola, tam veritabanı satırları, kişisel veri |
| Kullanıcı erişimi | Ayarlar → "Log klasörünü aç" + "Tanılama paketi oluştur" (log + sistem bilgisi + şema versiyonu, **veri içermez**) |
| Telemetri / analytics | ❌ Yok — offline uygulama, veri dışarı çıkmaz |

---

## 8. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-PERF-001 | Barkod okutmadan ürünün sepette görünmesine kadar geçen süre 100 ms'yi aşmaz. |
| REQ-PERF-002 | Satış tamamlama transaction'ı 50 ms'yi aşmaz. |
| REQ-PERF-003 | Uygulama soğuk açılışı 3 saniyeyi aşmaz. |
| REQ-PERF-004 | Dashboard, 5 yıllık veri hacminde 1 saniye içinde yüklenir. |
| REQ-PERF-005 | Hiçbir işlem UI thread'ini 100 ms'den uzun bloklamaz. |
| REQ-PERF-006 | Ürün listeleri sayfalanır; tüm kayıtlar aynı anda belleğe alınmaz. |
| REQ-PERF-007 | Dashboard ve rapor hesaplamaları veritabanı aggregation'ı ile yapılır. |
| REQ-PERF-008 | Uygulama, 10.000 ürünlük bir katalogda arama ve listeleme hedeflerini karşılar; ürün sayısına yapay bir üst sınır konulmaz. |
| REQ-DATA-001 | [24 §3.2](24-non-functional-requirements.md)'de listelenen işlemler atomik transaction içinde yürütülür. |
| REQ-DATA-002 | Veritabanı WAL ve `synchronous=FULL` ile çalışır. |
| REQ-DATA-003 | Elektrik kesintisi sonrası veritabanı tutarlı durumda açılır; yarım işlem kalmaz. |
| REQ-DATA-004 | Yarım kalmış migration, restore veya import açılışta tespit edilir ve kurtarılır. |
| REQ-DATA-005 | Uygulama aynı veri dizini üzerinde ikinci örneğin çalışmasını engeller. |
| REQ-DATA-006 | Veri tutarlılığını denetleyen bir kontrol işlevi bulunur ve sapmaları raporlar. |
| REQ-DATA-007 | Tutarsızlıklar otomatik değil, kullanıcı onayıyla ve stok hareketi oluşturularak düzeltilir. |
| REQ-DATA-008 | Kullanıcı verisi kurulum dizininde tutulmaz; güncelleme veriyi etkilemez. |
| REQ-SEC-001 | Kullanıcı parolaları ve dashboard parolası salt'lı SHA-256 hash olarak saklanır. |
| REQ-SEC-002 | Parola, hash ve salt değerleri log, audit, yedek veya export dosyalarına yazılmaz. |
| REQ-SEC-003 | Arşivden dosya çıkarırken hedef dizin dışına yazma engellenir. |
| REQ-SEC-004 | Aşırı büyük sıkıştırılmış arşivler açılmadan reddedilir. |
| REQ-SEC-005 | CSV export'ta formül enjeksiyonu riski taşıyan hücreler kaçışlanır. |
| REQ-SEC-006 | Tüm veritabanı sorguları parametrelidir. |
| REQ-SEC-007 | Teknik hata detayları kullanıcıya gösterilmez, log dosyasına yazılır. |
| REQ-SEC-008 | Uygulama hiçbir veriyi ağ üzerinden dışarı göndermez. |
| REQ-COMP-001 | Uygulama Windows 10 (1809+) ve Windows 11 x64 üzerinde çalışır. |
| REQ-COMP-002 | Uygulama %100, %125 ve %150 DPI ölçeklemesinde doğru görüntülenir. |
| REQ-COMP-003 | Uygulama macOS üzerinde geliştirme ve test amacıyla tam işlevsel çalışır. |
| REQ-COMP-004 | Yeni sürüm kurulumu mevcut veritabanı, görsel, oturum ve sepet verilerini korur. |

---

## 9. Acceptance criteria

**REQ-DATA-003**
```text
Given: Satış tamamlanırken bilgisayarın fişi çekiliyor
When:  Bilgisayar açılıp uygulama başlatılıyor
Then:  Veritabanı hatasız açılır
And:   Satış ya tamamen kaydedilmiştir ya da hiç kaydedilmemiştir
And:   Yarım satış (satırsız satış veya stok hareketi olmayan satış) bulunmaz
And:   Tutarlılık kontrolü sapma bildirmez
```

**REQ-DATA-005**
```text
Given: Uygulama çalışıyor
When:  Kullanıcı kısayola tekrar tıklıyor
Then:  İkinci bir pencere açılmaz
And:   Mevcut pencere öne getirilir
```

**REQ-COMP-004**
```text
Given: v1.0.0 kurulu, 500 ürün ve 8.000 satış var, kullanıcı giriş yapmış, sepette 3 ürün var
When:  v1.1.0 installer'ı çalıştırılıyor ve uygulama açılıyor
Then:  500 ürün ve 8.000 satış eksiksizdir
And:   Kullanıcı parola sormadan içeri girer
And:   Sepetteki 3 ürün korunmuştur
And:   Görseller görünür durumdadır
```

**REQ-PERF-001**
```text
Given: 2.000 ürün ve 3.000 barkod kayıtlı
When:  Barkod okutuluyor
Then:  Ürün 100 ms içinde sepette görünür
```
