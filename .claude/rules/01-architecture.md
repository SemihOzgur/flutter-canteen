# 01 — Mimari, Soyutlama ve Bağımlılık Kuralları

> Kaynak: `docs/03-architecture.md` · `docs/24-non-functional-requirements.md` · `docs/30-future-scope.md`

---

## 1. Katmanlar

```text
PRESENTATION      Widget'lar, ekranlar, controller/notifier'lar
      ↓
APPLICATION       Servisler — orkestrasyon, TRANSACTION SINIRLARI, audit yazımı
      ↓
DOMAIN            Saf Dart: Money, VAT, kâr, stok, satış, iade kuralları
      ↓
DATA              Repository'ler, Drift, dosya sistemi
```

**Bağımlılık yönü daima aşağı doğrudur.**

### Katman yasakları — ihlali kabul edilmez

| Katman | ❌ İçeremez |
|---|---|
| Presentation | Veritabanı sorgusu · dosya sistemi erişimi · finansal hesaplama · iş kuralı · `import 'package:drift/...'` |
| Application | Widget bilgisi · ham SQL detayı |
| Domain | Flutter import'u · async I/O · veritabanı · dosya sistemi |
| Data | İş kararı · hesaplama |

> `presentation/` altında `drift` import'u görülürse bu bir **bug'dır**, tercih değil.

---

## 2. Domain = iş otoritesi

Aşağıdakiler **yalnızca `domain/` içinde**, tek merkezî implementasyon olarak yaşar:

- `Money` (kuruş aritmetiği, parse, format kuralları)
- KDV hesaplama (KDV dahil fiyattan çıkarma)
- Kâr hesaplama
- Sepet/satır toplamları
- Stok defteri kuralları
- Satış ve iade durum kuralları

### Tek implementasyon kuralı

> Aynı hesaplama **birden fazla yerde yazılamaz.**

```text
❌ YASAK
UI'da KDV hesabı        →  bir formül
Dashboard'da KDV hesabı →  başka formül
Rapor'da KDV hesabı     →  üçüncü formül

✅ DOĞRU
domain/services/vat_calculator  →  tek kaynak
   ↑            ↑            ↑
  UI       Dashboard      Rapor
```

Dashboard ve raporlar hesaplamayı **domain/servis katmanından alır**; kendi içinde hesap yapmaz.
UI yalnızca **formatlar** (`₺25,50` gösterimi bir presentation concern'dür).

Domain katmanı Flutter'a bağımlı olmadığı için **saf unit test edilebilir** — bu tesadüf değil,
kasıtlı bir tasarım kararıdır ve korunmalıdır.

---

## 3. Over-engineering yasağı

> Bir soyutlama ancak **gerçek bir ihtiyacı çözüyorsa** veya **test edilebilirliği ciddi
> şekilde artırıyorsa** eklenir.

### Varsayılan olarak YAPILMAZ

| ❌ | Neden |
|---|---|
| CQRS | Tek veri kaynağı, tek process |
| Event Bus / Mediator | Stok defteri zaten olay tabanlı; genel event bus gereksiz |
| Service Locator | Riverpod zaten DI sağlıyor |
| Her operasyon için UseCase sınıfı | Servis metodu yeterli; 200 dosyalık klasör bakım yükü |
| Gereksiz DTO / Mapper katmanı | Tek veri kaynağı var; dönüşüm katmanı boş iş |
| Her repository için interface | §4'teki ölçüt geçerli değilse yazılmaz |
| Gereksiz generic soyutlama | Tek kullanımı olan generic, generic değildir |
| Erken plugin abstraction | İkinci implementasyon ortaya çıkana kadar beklenir |
| Backend için remote repository | Backend YOK — §6 |

### Karar testi

Yeni bir soyutlama eklemeden önce:

1. Bugün **en az iki** somut kullanımı var mı?
2. Yoksa, bir servis testini **anlamlı şekilde** mümkün kılıyor mu?
3. İkisi de hayırsa → **ekleme.**

---

## 4. Repository stratejisi

Interface yalnızca şu ölçüt sağlanırsa yazılır:

> Bu veri kaynağı ileride **uzaktan gelebilir mi** *veya* test'te **mock edilmesi gerekiyor mu?**

| Repository | Interface? |
|---|---|
| ProductRepository | ✅ |
| SaleRepository | ✅ |
| StockRepository | ✅ |
| Category / Supplier / Audit / Report | ❌ doğrudan DAO |
| Backup / Image / Csv | ❌ doğrudan sınıf |

### Yeni interface ekleme

> Repository interface yalnızca **`docs/03-architecture.md §4` içinde tanımlanan ölçüt
> karşılandığında** eklenir. Belirleyici olan `docs/` ölçütüdür, bu dosyadaki sayı değildir.

**Mevcut V1 repository interface'leri:** Product · Sale · Stock

Yeni bir interface için sırasıyla:

```text
1. docs/03 §4 kriterinin karşılandığı GÖSTERİLİR
   ("uzaktan gelmesi mantıklı mı" veya "test'te mock edilmesi gerekli mi")
2. Gerekçe DOKÜMANTE EDİLİR
3. İlgili business/architecture kararı GÜNCELLENİR
4. Ardından implementasyon yapılır
```

**Yeterli olmayan gerekçeler:**

| ❌ | |
|---|---|
| "Daha temiz olur" | Estetik tercih, ölçüt değil |
| "SOLID gereği" | Prensip adı bir ihtiyaç kanıtı değildir |
| "İleride lazım olabilir" | Somut ikinci kullanım yoksa erken soyutlamadır |
| "Diğerlerinde var, tutarlı olsun" | Simetri bir ihtiyaç değildir |

---

## 5. Transaction sınırları

> Transaction **yalnızca application (servis) katmanında** açılır.

- Repository kendi başına transaction açmaz.
- UI transaction bilmez.
- Transaction içinde **dosya I/O, ağ çağrısı, UI beklemesi yapılmaz.**
- Transaction kısa tutulur (satış hedefi: < 50 ms).

Atomik olması zorunlu işlemler: `docs/24 §3.2`.

---

## 6. Backend sınırı

Backend **yoktur** ve V1'de **yazılmayacaktır.**

### Şimdi oluşturulmayacaklar

- API client
- DTO hiyerarşisi
- Remote repository implementasyonu
- Sync engine
- Conflict resolution

> "Gelecekte backend gelebilir" gerekçesiyle bugün **hiçbir kod yazılmaz.**
> Mevcut temiz katman sınırı yeterlidir.

Genişleme analizi (yalnızca bilgi amaçlı): `docs/30 §2`.

---

## 7. Bağımlılık (paket) ekleme kuralı

Yeni bir `pubspec.yaml` bağımlılığı eklemeden önce **dördü de** yanıtlanır:

1. Gerçekten gerekli mi?
2. Dart/Flutter standart kütüphanesiyle çözülebilir mi?
3. Mevcut bir bağımlılık bunu zaten sağlıyor mu?
4. Bakım maliyetini (lisans, terk edilme riski, platform desteği) artırıyor mu?

### Karar kapsamındaki bağımlılıklar — yeniden onay gerekmez

Aşağıdaki işlevler `docs/` tarafından **zaten karara bağlanmıştır.** Bu işlevleri karşılayan
bağımlılığın eklenmesi için tekrar gerekçe/onay gerekmez:

| İşlev | Paket | Kaynak karar |
|---|---|---|
| Veritabanı | `drift` (native SQLite'ı `sqlite3` 3.x kendi build hook'uyla sağlar) | OD-001 |
| State management / DI | `riverpod` | OD-002 |
| Grafik | `fl_chart` | OD-014 |
| Yedek arşivleme | `archive` | OD-012 |
| CSV okuma/yazma (**birincil**) | `csv` | OD-009 |
| **Excel `.xlsx` (ikincil)** | `excel` | **OD-009** — CSV birincil, Excel **ayrı abstraction arkasından** |
| Parola/kod hash'leme | `crypto` | OD-003 (salt'lı SHA-256) |
| Dosya yolu çözümleme | `path` / `path_provider` | BR-DATA-001 |
| **Görsel işleme** (yeniden boyutlandırma + yeniden kodlama) | **image processing dependency — REQ-IMG-003 kapsamında** | **BR-IMG-002 / REQ-IMG-003 / OD-016** |

> **Görsel işleme paketi hakkında:** `docs/` somut bir paket adı sabitlememiştir.
> BR-IMG-002 ve REQ-IMG-003 optimizasyonu **zorunlu** kıldığı için, bu işi yapan bir
> bağımlılık **karar kapsamındadır** ve ayrıca onay gerektirmez. Somut paket seçimi bir
> **teknik tercihtir**; seçim yapılırken §7'deki dört soru yanıtlanır ve seçilen paket
> bu tabloya yazılır. Var olmayan bir paket adı bu tabloya yazılmaz.
>
> Aynı durum `excel` için de geçerlidir: OD-009 Excel desteğini karara bağlamıştır;
> paket adı `docs/` tarafından sabitlenmemiştir.

Bu tablonun **dışındaki** her paket için §7'deki dört soru yanıtlanır ve onay beklenir.

---

## 8. Performans

Hedef: **10.000+ ürün** — ancak **premature optimization yapılmaz.**

### Öncelikli alanlar

| Alan | Hedef |
|---|---|
| Barkod lookup | < 100 ms |
| Ürün arama (10.000 ürün) | < 150 ms |
| Satış transaction | < 50 ms |
| Dashboard (100k satır) | < 1 sn |
| Backup / restore | `docs/24 §2` |

### Kurallar

- Sorgular **uygun index** kullanır (`docs/05 §3` — 🔴 kritik index'ler zorunlu).
- Aggregation **SQL tarafında** yapılır; Dart'ta döngüyle toplama **yasak**.
- Listeler **sayfalanır**; tüm kayıtlar belleğe alınmaz.
- Ağır işler (import, backup, büyük rapor) **isolate**'te çalışır.
- **UI thread hiçbir zaman ağır DB/dosya işiyle bloklanmaz.**

### Ölçüme dayalı optimizasyon

FTS5, rollup tabloları, önbellek katmanları **önceden eklenmez.**
Yalnızca `docs/24 §2` eşiği ölçülerek aşıldığında devreye alınır.

---

## 9. Local-first

- Uygulamanın **hiçbir temel işlevi** internete bağımlı olamaz (BR-GEN-001).
- Ağ çağrısı yapan kod **yazılmaz**.
- Analytics, telemetry, crash reporting, cloud sync, otomatik güncelleme kontrolü **V1'de yoktur**.
- Uygulama hiçbir veriyi dışarı göndermez (REQ-SEC-008).

---

## 10. Klasör yapısı

`docs/03 §3`'teki yapı bağlayıcıdır. Yeni üst düzey klasör eklemek bir mimari karardır;
gerekçesiz yapılmaz.

```text
lib/
├── app/          (router, tema, l10n)
├── core/         (money, result, errors, logging, paths)
├── domain/       (models, enums, services) ← framework bağımsız
├── data/         (db, repositories, files)
├── application/  (servisler, transaction sınırları)
└── presentation/ (ekranlar, widget'lar)
```
