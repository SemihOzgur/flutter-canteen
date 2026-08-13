# 03 — Uygulama Mimarisi

## 1. Mimari prensip

Hedef: **projenin gerçek ihtiyacı kadar karmaşık** bir mimari.

Bu proje için geçerli gerçekler:
- Backend yok, network yok, distributed sistem yok.
- Tek kullanıcı, tek makine, tek process.
- Veri kaynağı tek: local SQLite.
- Ancak **iş kuralları önemsiz değil** — stok defteri, fiyat snapshot'ı, atomik satış, kâr hesabı.

Bu nedenle:

> **Katmanlar iş kurallarını UI'dan ve veritabanından ayırmak için vardır — gelecekteki backend için değil.**
> Backend'e geçiş bu ayrımın bir yan faydasıdır, gerekçesi değildir.

### Kaçınılan over-engineering

| Yapmıyoruz | Neden |
|---|---|
| Her entity için ayrı `Entity` + `Model` + `DTO` + `Mapper` | Tek veri kaynağı var; dönüşüm katmanı boş iş |
| Her operasyon için ayrı UseCase sınıfı | Servis sınıfı içinde metot yeterli; 200 dosyalık UseCase klasörü bakım yükü |
| Her repository için interface | Yalnızca **gelecekte uzaktan gelmesi mantıklı olan** repository'ler interface alır (bkz. §4) |
| Event bus / CQRS / event sourcing | Stok defteri zaten olay tabanlı; genel CQRS gereksiz |
| Dependency injection framework şişkinliği | Basit provider ağacı yeterli |

---

## 2. Katmanlar

```text
┌─────────────────────────────────────────────────────────┐
│ PRESENTATION                                            │
│ Flutter widget'ları, ekranlar, controller/notifier'lar   │
│ Kural: iş kuralı içermez, DB'ye doğrudan erişmez         │
├─────────────────────────────────────────────────────────┤
│ APPLICATION (Services)                                  │
│ SaleService, StockService, ProductService,               │
│ BackupService, ImportService, ReportService...           │
│ Kural: transaction sınırları burada çizilir              │
├─────────────────────────────────────────────────────────┤
│ DOMAIN                                                  │
│ Saf Dart modelleri, enum'lar, hesaplama fonksiyonları    │
│ (Money, VatCalculator, CartCalculator, StockLedger)      │
│ Kural: Flutter'a ve veritabanına hiçbir bağımlılık yok   │
├─────────────────────────────────────────────────────────┤
│ DATA                                                    │
│ Repository'ler + Drift veritabanı + dosya sistemi        │
│ Kural: iş kuralı içermez, yalnızca kalıcılık             │
└─────────────────────────────────────────────────────────┘
```

**Bağımlılık yönü daima aşağı doğrudur.** Domain katmanı hiçbir şeye bağımlı değildir ve
bu yüzden **tamamen unit test edilebilir** — projedeki en kritik mantık (para, KDV, stok, kâr) burada yaşar.

### Katman sorumlulukları

| Katman | Yapar | Yapmaz |
|---|---|---|
| Presentation | Görüntüleme, kullanıcı girdisi, format, navigasyon | Hesaplama, validasyon kuralı, SQL |
| Application | Orkestrasyon, transaction, audit log yazımı, validasyon | Widget bilgisi, SQL detayı |
| Domain | Hesaplama, invariant, kural | I/O, async, framework |
| Data | CRUD, sorgu, migration, dosya I/O | İş kararı |

---

## 3. Klasör yapısı

```text
lib/
├── main.dart                     # bootstrap: DB aç, DI kur, single-instance lock, uygulama başlat
├── app/
│   ├── app.dart                  # MaterialApp, tema, router
│   ├── router.dart
│   ├── theme/
│   └── l10n/                     # Türkçe metinler (bkz. OD-011)
├── core/
│   ├── money/                    # Money value type, formatlama, yuvarlama
│   ├── result/                   # Result / Failure tipleri
│   ├── errors/                   # AppException hiyerarşisi
│   ├── logging/
│   ├── paths/                    # platform bazlı veri dizini çözümleme
│   └── utils/
├── domain/
│   ├── models/                   # Product, Sale, SaleItem, StockMovement, Cart...
│   ├── enums/                    # SaleStatus, StockMovementType, AuditAction...
│   └── services/                 # saf hesaplama: CartCalculator, VatCalculator, ProfitCalculator
├── data/
│   ├── db/
│   │   ├── database.dart         # Drift database tanımı
│   │   ├── tables/               # tablo tanımları
│   │   ├── daos/                 # sorgular
│   │   └── migrations/           # versiyonlu migration adımları
│   ├── repositories/             # ProductRepository, SaleRepository, ...
│   └── files/                    # ImageStore, BackupArchive, CsvIo
├── application/
│   ├── product/                  # ProductService
│   ├── sales/                    # SaleService, CartService
│   ├── stock/                    # StockService
│   ├── reports/                  # ReportService, DashboardService
│   ├── backup/                   # BackupService, RestoreService
│   ├── importexport/
│   ├── auth/                     # AuthService, SessionService,
│   │                             # FinancialAccessService, RecoveryCodeService
│   └── audit/                    # AuditService
└── presentation/
    ├── auth/
    ├── sales/                    # satış ekranı (uygulamanın kalbi)
    ├── products/
    ├── categories/
    ├── suppliers/
    ├── stock/
    ├── dashboard/
    ├── reports/
    ├── settings/
    └── shared/                   # ortak widget'lar, dialoglar, barkod input handler
```

**Kural:** `presentation/` altında `import 'package:drift/...'` görülmemelidir. Lint ile zorlanabilir.

---

## 4. Repository stratejisi

Interface (soyutlama) yalnızca şu ölçüt sağlanırsa yazılır:

> Bu veri kaynağının ileride **uzaktan gelmesi** veya **test'te taklit edilmesi** somut olarak gerekli mi?

| Repository | Interface? | Gerekçe |
|---|---|---|
| ProductRepository | ✅ | Gelecekte merkezi ürün kataloğu senaryosu mantıklı; servis testlerinde mock edilecek |
| SaleRepository | ✅ | Gelecekte satışların merkeze gönderilmesi en olası senaryo |
| StockRepository | ✅ | Satışla birlikte test edilir |
| CategoryRepository / SupplierRepository | ❌ | Doğrudan DAO kullanılır; soyutlamanın bugün faydası yok |
| AuditRepository | ❌ | Yalnızca yazma; doğrudan DAO |
| ReportRepository | ❌ | Ağır SQL aggregation; soyutlanması anlamsız |
| Backup / Image / Csv | ❌ | Dosya sistemi sarmalayıcıları; doğrudan sınıf |

Gelecekte backend eklenirse:

```text
ProductRepository (interface)
├── LocalProductRepository   ← bugün
└── SyncingProductRepository ← gelecekte (local + remote)
```

Bkz. [30 §2 — Future Backend Strategy](30-future-scope.md).

---

## 5. State management

**KARAR: Riverpod** ([OD-002 — kapandı](28-open-decisions.md)).

Gerekçe özeti:
- Compile-time güvenli DI + state yönetimi tek pakette; ayrı bir `get_it` gerekmez.
- Drift'in `Stream` tabanlı sorgularıyla doğal uyum (`StreamProvider`) — stok/sepet UI'ı otomatik tazelenir.
- Test edilebilirlik: `ProviderContainer` ile servis override etmek kolay.
- Masaüstünde tek pencere/tek process olduğu için scope karmaşası yok.

Alternatifler: `provider` (daha basit ama DI zayıf), `bloc` (bu ölçek için tören fazlası), `signals` (ekosistem daha küçük).

---

## 6. Uygulama başlangıç sırası (bootstrap)

```text
1. Flutter binding init
2. Veri dizinini çöz (%APPDATA%/CanteenApp | ~/Library/Application Support/CanteenApp)
3. Single-instance lock al          ── başarısızsa: uyarı göster + çık   [BR-GEN-005]
4. Kurtarma kontrolü (yarım kalmış restore/import işareti var mı?)
5. Veritabanını aç (WAL, foreign_keys=ON)
6. Migration çalıştır               ── başarısızsa: rollback + hata ekranı   [06]
7. Seed kontrolü (Genel kategorisi, varsayılan KDV, ilk kullanıcı)
8. Orphan görsel taraması (arka planda)
9. Session yükle                    ── varsa satış ekranı, yoksa login
10. Finansal erişim kilidi KAPALI olarak başlatılır (bellekte)  [BR-AUTH-013]
11. Aktif sepet restore
```

Bu sıra [26 — Edge Cases](26-edge-cases.md) senaryolarının çoğunun karşılandığı yerdir.

---

## 7. Hata yönetimi

- Beklenen iş hataları (`stok yetersiz`, `barkod zaten var`) → `Result`/`Failure` ile döner, exception fırlatılmaz.
- Beklenmeyen hatalar → yakalanır, log dosyasına yazılır, kullanıcıya sade Türkçe mesaj gösterilir.
- Kullanıcıya asla stack trace gösterilmez; "Detayları kopyala" seçeneği sunulur.
- Log dosyası: `<veri dizini>/logs/app-YYYY-MM-DD.log`, 14 gün rotasyon.

---

## 8. Eşzamanlılık

- Tüm veritabanı yazımları uygulama içinde tek noktadan (Drift) geçer.
- Uzun süren işlemler (import, backup, restore, büyük rapor) **isolate**'te çalışır; UI bloklanmaz.
- Uzun işlem sürerken satış ekranı **kilitlenir** (modal ilerleme) — yarım veri üzerinde satış yapılmasını engellemek için.

---

## 9. Mimari requirement'lar

| ID | Requirement |
|---|---|
| REQ-ARCH-001 | Presentation katmanı veritabanına doğrudan erişmez. |
| REQ-ARCH-002 | Domain katmanı Flutter ve Drift'e bağımlı olmaz; saf Dart olarak test edilebilir. |
| REQ-ARCH-003 | Transaction sınırları yalnızca application (servis) katmanında tanımlanır. |
| REQ-ARCH-004 | Ürün, satış ve stok repository'leri interface arkasındadır. |
| REQ-ARCH-005 | Uygulama aynı veri dizini üzerinde ikinci bir örnek başlatmayı engeller. |
| REQ-ARCH-006 | Uzun süren işlemler UI thread'ini bloklamaz. |
| REQ-ARCH-007 | Kullanıcı verisi kurulum dizininden bağımsız bir veri dizininde tutulur. |

> **Finansal erişim kilidi mimarisi:** `FinancialAccessService` bellekte bir bayrak tutar ve
> **hem Dashboard hem Raporlar** rotasının önünde bir kapı (route guard) olarak çalışır
> (BR-AUTH-013). Kilit açılmadan bu ekranların **hiçbir sorgusu tetiklenmez** (BR-AUTH-012) —
> bu kural servis katmanında zorlanır, yalnızca UI'da değil.
>
> `RecoveryCodeService` kod üretimi, hash doğrulaması ve tek kullanımlık geçersizleştirmeyi yönetir;
> parola sıfırlama + kod geçersizleştirme + yeni kod üretimi **tek transaction**'dır (BR-AUTH-015/017).
> State management olarak **Riverpod** kullanılır ([OD-002](28-open-decisions.md)); kilit durumu
> bir `StateProvider` ile tutulur ve uygulama kapanışında doğal olarak sıfırlanır.
