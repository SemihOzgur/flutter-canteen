# 06 — Çalışma Akışı, Test ve Kalite Kapıları

> Kaynak: `docs/27-testing-strategy.md` · `docs/31-roadmap.md` · `docs/26-edge-cases.md`

---

# AUTONOMOUS EXECUTION MODE

Bu proje Claude tarafından otonom geliştirme prensibiyle yürütülür.

## Kullanıcıdan rutin izin isteme

Aşağıdaki operasyonlar için kullanıcıdan tekrar izin istenmez:

- git status
- git diff
- git log
- git branch
- git switch
- git checkout
- git fetch
- flutter analyze
- flutter test
- dart format
- dart fix
- sqlite3
- grep
- find
- sed
- awk
- python3
- shell scriptleri
- dosya oluşturma
- dosya değiştirme
- test çalıştırma

## Automatic recovery

Bir test veya kalite kontrolü başarısız olursa:

FAIL
→ ROOT CAUSE
→ FIX
→ TEST AGAIN

döngüsü otomatik uygulanır.

## User interruption yalnızca şu durumlarda

1. Business kararı
2. Doküman çelişkisi
3. Database business model değişikliği
4. Security/business davranışı değişikliği
5. Merge
6. Main'e push
7. Release

Bunların dışındaki rutin teknik operasyonlar otomatik yapılır.

## 1. Kod yazmadan önce (pre-flight)

**Her feature/bugfix için atlanamaz:**

```text
1. İlgili docs/ dosyalarını bul ve OKU
2. Business Rules (BR-*)        → hangi kurallar bağlayıcı?
3. Functional Requirements (REQ-*) + acceptance criteria
4. Domain etkisi                → hangi hesaplama/invariant etkileniyor?
5. Database etkisi              → şema / migration / index gerekiyor mu?
6. Edge cases (docs/26)         → ilgili EC-* maddeleri
7. Test planı                   → neyi, nasıl doğrulayacaksın?
        ▼
   ANCAK BUNDAN SONRA implementation
```

### Doküman haritası — hangi iş için nereye bakılır

| İş | Dokümanlar |
|---|---|
| Satış ekranı / sepet | `12` · `11` · `23` · `26 §4-5` |
| Stok | `13` · `04 §3.11` · `26 §6` |
| İade / iptal | `14` · `26 §7` |
| Ürün / kategori / tedarikçi | `09` · `10` · `26 §1-2` |
| Para / KDV / kâr | `07` · `08` |
| Dashboard / rapor | `15` · `16` |
| Auth / finansal erişim | `17` · `26 §10-10c` |
| Yedek / restore | `19` · `26 §8` |
| Import / export | `20` · `26 §9` |
| Migration | `06` |
| Şema | `04` · `05` |

---

## 2. Test önceliği

> Test yatırımı kapsama yüzdesine göre değil, **hatanın maliyetine** göre yapılır.

| # | Alan | Öncelik |
|---|---|---|
| 1 | **Money** (kuruş aritmetiği, parse, format, yuvarlama) | 🔴 |
| 2 | **VAT** (KDV dahil fiyattan çıkarma) | 🔴 |
| 3 | **Profit** (maliyet snapshot'ı + KDV hariç matrah) | 🔴 |
| 4 | **Stock** (defter tutarlılığı, negatif stok) | 🔴 |
| 5 | **Sale** (transaction atomikliği, 5 snapshot alanı) | 🔴 |
| 6 | **Return** (kısmi iade, durum makinesi, snapshot fiyat) | 🔴 |
| 7 | **Backup / Restore** (doğrulama, kurtarma, parola sızıntısı yok) | 🔴 |
| 8 | **Migration** (veri koruma, rollback) | 🔴 |
| 9 | **Authentication** (hash, finansal kilit, recovery code) | 🔴 |

Düşük öncelik: UI düzeni. Test edilmez: tema/renk.

### Zorunlu test edilecek davranışlar

| Konu | Doğrulanacak |
|---|---|
| **Transaction atomicity** | Hata enjekte → hiçbir kayıt oluşmaz, sepet korunur |
| **Snapshot integrity** | Ürün değişince geçmiş satış **değişmez** (5 alan ayrı ayrı) |
| **Stock consistency** | `stock_quantity == Σ quantity_delta` (property test, 1.000 rastgele hareket) |
| **VAT calculation** | `net + kdv == brüt` invariant'ı (property test, 10.000 değer) |
| **VAT regresyonu** | KDV'nin fiyatın **üzerine eklenmediğini** doğrulayan **açık test** |
| **Migration safety** | Her adım öncesi/sonrası satır sayısı ve kritik alan değerleri |
| **Parola sızıntısı** | DB + yedek + log'da düz metin parola/kod **bulunmadığı** |
| **Finansal kilit** | Parola girilmeden **hiçbir sorgunun çalışmadığı** (sorgu sayacı ile) |

### Test piramidi

```text
Manuel / Windows doğrulama    (donanım, installer, DPI, klavye — W1–W15)
Integration (~40)             satış, iade, backup/restore, import, migration, kilit
Repository / DB (~80)         gerçek in-memory SQLite
Unit (~250)                   domain katmanı — hedef %100
```

Widget testleri **seçicidir**: barkod input handler, sepet paneli, odak yönetimi, para/miktar alanları.
Golden (piksel) testleri **yazılmaz.**

---

## 3. Feature tamamlanma kapısı

Bir feature "tamamlandı" **sayılmaz** eğer:

- [ ] `flutter analyze` uyarısız geçmiyorsa
- [ ] `dart format` uygulanmamışsa
- [ ] İlgili unit testler yazılmamış veya geçmiyorsa
- [ ] Gerekli integration testler çalıştırılmamışsa
- [ ] İlgili **acceptance criteria** karşılanmamışsa
- [ ] **Business invariant'lar doğrulanmamışsa** ([`00-source-of-truth.md §4`](00-source-of-truth.md))
- [ ] Dokümantasyonla tutarlılık kontrol edilmemişse
- [ ] Faz kapsamındaki Windows manuel testleri yapılmamışsa (faz sonunda)

> **Business-critical mantık testsiz tamamlanmış sayılmaz.**
> "Sonra test yazarım" kabul edilmez.

---

## 4. Git, branch izolasyonu ve merge

> **Kaynak notu:** Bu bölümdeki Git/branch kuralları **proje sahibi çalışma talimatından** gelir;
> `docs/` business source of truth kapsamında **değildir.** Bu nedenle `docs/` ile çelişme
> durumu söz konusu olamaz — ancak business kuralı gibi de yorumlanmaz.
>
> **Branch stratejisi yalnızca geliştirme workflow'udur**; source-of-truth hiyerarşisinin
> ([`00-source-of-truth.md §1`](00-source-of-truth.md)) üzerinde yeni bir otorite **değildir.**

### 4.1 Temel kural — branch izolasyonu

> **Her bağımsız geliştirme kapsamı ayrı bir branch'te geliştirilir.**

Bağımsız kapsam sayılanlar: feature · bugfix · kapsamlı/izole refactor · migration ·
performance fix · test-only çalışma · dokümantasyon/rule değişikliği · ayrı bir faz veya faz alt fazı.

```text
main
├── feature/faz-1-foundation
├── feature/faz-2-database
├── feature/faz-3a-auth
├── feature/faz-3b-financial-lock
├── bugfix/vat-calculation
├── bugfix/stock-movement
└── bugfix/recovery-code
```

### 4.2 Aynı branch'te ne olabilir?

> **Bağımsız kapsam = ayrı branch**
> **Tek bir kapsamın doğal alt işleri = aynı branch**

Aynı feature/faz kapsamının **birbirine bağlı** alt işleri aynı branch'te yapılır:

```text
feature/faz-1-foundation
   ├── Riverpod kurulumu
   ├── l10n kurulumu
   ├── Money domain
   ├── VAT hesaplama
   └── ilgili unit testler        ← hepsi aynı kapsamın parçası
```

Aynı alt fazın doğal olarak birbirine bağlı işleri **gereksiz şekilde farklı branch'lere bölünmez.**

### 4.3 Kapsam dışı iş ortaya çıkarsa — 🛑 KAPSAM DURDURMASI

Mevcut branch'in kapsamı dışında bir iş ortaya çıkarsa:

```text
🛑 DUR
   → Mevcut branch'e ekleme
   → Yeni kapsam için ayrı branch OLUŞTURULMASINI ÖNER
   → Onay bekle
```

**Örnek:** Faz 1 sırasında *"Ürün CRUD'u da yapalım"* denirse → bu Faz 2 kapsamıdır →
`feature/faz-1-foundation` branch'ine **eklenmez.**

> ⚠️ **Bu, business DUR'undan farklı bir mekanizmadır.**
>
> | | Tetikleyen | Çözüm |
> |---|---|---|
> | **Business DUR** ([`00 §5.2`](00-source-of-truth.md)) | Business/şema/para/güvenlik davranışı değişiyor | `docs/` protokolü + `OD-017+` |
> | **Kapsam durdurması** (bu bölüm) | İş doğru ama **yanlış branch'te** | Yeni branch öner, onay bekle |
>
> [`00 §5.1`](00-source-of-truth.md) rutin teknik iş muafiyeti **bir branch kapsamı muafiyeti değildir.**
> Bir refactor DUR gerektirmeyebilir; ancak mevcut branch'in kapsamı dışındaysa yine de ayrı branch ister.

### 4.4 Branch oluşturma prosedürü

Yeni geliştirmeye başlamadan önce sırasıyla:

```text
1. Repository durumunu kontrol et        (git status)
2. Aktif branch'i kontrol et             (git branch --show-current)
3. Working tree temiz mi?                (kirliyse DUR, raporla)
4. Güncel main'i temel al
5. Branch'i main üzerinden oluştur
6. Branch KAPSAMINI AÇIKÇA TANIMLA       ← çalışma başlamadan önce
7. Yalnızca o kapsam içinde çalış
```

### 4.5 Branch adlandırma

```text
feature/<kapsam>     feature/faz-1-foundation · feature/faz-3a-auth
bugfix/<kapsam>      bugfix/vat-calculation · bugfix/recovery-code
refactor/<kapsam>    refactor/domain-money
docs/<kapsam>        docs/rules-workflow-update
```

**Kaçınılacak belirsiz adlar:** `work` · `test` · `temp` · `fix` · `new` · `changes`

### 4.6 Branch scope lock

Branch oluşturulduğunda kapsamı **çalışma başlamadan önce** belirlenir. Branch içinde yalnızca:

- branch'in tanımlanmış feature/faz/bugfix kapsamı,
- bu kapsamın **doğrudan gerekli** testleri,
- bu kapsamın **doğrudan gerekli** teknik yardımcı değişiklikleri

yapılabilir. Başka kapsamdan değişiklik tespit edilirse → §4.3.

### 4.7 Bugfix kuralı

Sonradan tespit edilen bug mevcut feature branch'ine **otomatik eklenmez.**

| Durum | Branch |
|---|---|
| Bug, o feature'ın **henüz tamamlanmamış doğal parçası** | ✅ Aynı branch'te kalabilir |
| Bug **bağımsız bir düzeltme** | 🛑 Ayrı `bugfix/*` branch'i |

**Örnek:** `feature/faz-5-sales` geliştirilirken bağımsız bir VAT hesaplama bug'ı çıkarsa →
`bugfix/vat-calculation` ayrı branch'i açılır.

> Bu ayrım **Claude tarafından business kararına dönüştürülmez.**
> Şüphe varsa → **DUR ve raporla.**

### 4.8 Business kuralına dokunan değişiklik

> **Branch açılmış olması business kararını değiştirme yetkisi vermez.**

Branch sırasında business rule / schema / BR-* / REQ-* / OD-* değişmesi gerektiği ortaya çıkarsa,
normal kodlamaya devam edilmez — [`00-source-of-truth.md §3`](00-source-of-truth.md) protokolü işletilir:

```text
DUR → raporla → (gerekirse OD-017+) → docs/ güncelle
    → ilgili rules güncelle → doğrula → ancak sonra kodlamaya devam
```

### 4.9 main koruması

`main` her zaman: **build edilebilir · test edilebilir · dokümantasyonla uyumlu ·
yalnızca merge edilmiş ve onaylanmış işleri içerir.**

| ❌ Kullanıcı açıkça istemedikçe yapılmaz |
|---|
| `main` üzerinde doğrudan feature geliştirme |
| `main`'e doğrudan commit / push |
| Kullanıcı onayı olmadan **merge** |
| Branch **silme** |
| Başka branch'e **cherry-pick** |
| Kapsam dışı değişiklikleri **taşıma** |

### 4.10 Merge akışı ve kullanıcı onayı

```text
BRANCH → IMPLEMENT → TEST → ANALYZE → REPORT → USER TEST → USER APPROVAL → MERGE
                                          ▲
                                    CLAUDE BURADA DURUR
```

- Kullanıcı testi gereken iş tamamlandığında Claude **durur.**
- Kullanıcı test sonucu vermeden **sonraki branch/faz kapsamına geçilmez.**
- Merge **yalnızca** açık kullanıcı onayıyla yapılır.

### 4.11 Kapsam dışı değişiklik tespiti

Branch tamamlanmadan önce **`git status` ve `git diff` kontrol edilir.**
Beklenmeyen değişiklik varsa → 🛑 **DUR ve raporla.** Özellikle:

| Tespit | |
|---|---|
| Başka feature'a ait dosya değişmiş | 🛑 |
| Başka faza ait kod değişmiş | 🛑 |
| `docs/` ile ilgisiz değişiklik oluşmuş | 🛑 |
| Otomatik/generated dosya beklenmedik şekilde değişmiş | 🛑 |
| Dependency değişmiş | 🛑 |
| `pubspec.lock` kapsam dışı değişmiş | 🛑 |
| Migration / schema değişmiş | 🛑 |
| Test dışında business davranışı değişmiş | 🛑 |

### 4.12 Branch tamamlanma kapısı

**Önce §3 kalite kapısının tamamı sağlanır** (analyzer, format, testler, invariant'lar,
acceptance criteria, doküman tutarlılığı). Buna **ek olarak** branch seviyesinde:

- [ ] Kapsam analizi yapılmış
- [ ] İlgili `docs/` okunmuş
- [ ] İlgili `rules/` dosyaları okunmuş
- [ ] **Branch scope dışında değişiklik yok** (§4.11)
- [ ] `docs` ↔ kod izlenebilirliği kontrol edilmiş
- [ ] `git diff` incelenmiş
- [ ] Değişen dosyalar raporlanmış

### 4.13 Branch tamamlanma raporu

Tamamlandığında kullanıcıya şunlar raporlanır, **ardından DURULUR:**

```text
1. Branch adı
2. Yapılan değişiklikler
3. Değişen dosyalar
4. Test sonuçları
5. Analyzer sonucu
6. Kapsam dışı değişiklik kontrolü
7. Bilinen riskler
8. Kullanıcının test etmesi gereken senaryolar
```

### 4.14 Fazlar ve branch ilişkisi

> **Proje sahibi talimatı: her faz TEK branch'tir.**

```text
feature/phase-1   feature/phase-2   feature/phase-3   …   feature/phase-12
```

O faza ait **her şey** o branch'te geliştirilir ve faz tamamlandığında tek seferde
push/merge edilir. Alt fazlar (örn. Faz 3 → 3a–3d) **planlama birimidir, branch birimi
değildir**; ayrı branch'e bölünmezler.

| Faz | Branch | İçindeki alt fazlar (`docs/31`) |
|---|---|---|
| Faz 3 | `feature/phase-3` | **3a** Auth + parola hash + finansal erişim kilidi + recovery code<br>**3b** Kategori · Tedarikçi · KDV<br>**3c** Ürün CRUD + barkod<br>**3d** Görsel + favori |

> **Kaynak: [`docs/31-roadmap.md`](../../docs/31-roadmap.md) Faz 3 → "Not" satırı.**
> Alt fazların **içeriği** oradan gelir; çelişki hâlinde `docs/31` geçerlidir.
> Buradaki tablo yalnızca hangi işin hangi **branch**'te yapılacağını söyler.

> Finansal erişim kilidi ve recovery code **3a'ya aittir**, ayrı bir alt faz değildir:
> kurulum sihirbazının Adım 2–3'ü bunları zorunlu kılar (REQ-AUTH-016/022/024), yani
> 3a onlarsız çalışan bir bütün bırakmaz. `docs/31` Faz 8 de *"servis Faz 3'te hazır"* der.

**§4.1'deki "ayrı bir faz alt fazı" ibaresi bu talimatla sınırlanmıştır:** alt faz tek
başına ayrı branch gerekçesi değildir. Bugfix ve kapsam dışı iş kuralları (§4.3, §4.7)
değişmeden geçerlidir.

### 4.15 Docs / rules değişiklikleri

Yalnızca workflow/rules/documentation değiştiren çalışmalar da **izole branch'te** yapılır
(örn. `docs/rules-workflow-update`).

`docs/` source-of-truth olduğu için, `docs/` değişikliği gerekiyorsa
[`00-source-of-truth.md §3`](00-source-of-truth.md) protokolüne uyulur.
**Rules dosyaları `docs/` ile çelişemez.**

### 4.16 Commit kuralları

- Anlamlı, kapsamı belirli commit'ler.
- Şema değişikliği içeren commit **migration'ı da içerir.**
- Doküman güncellemesi gerektiren değişiklik, **dokümanı de aynı branch'te günceller.**
- Commit ve push yalnızca **kullanıcı istediğinde** yapılır.

---

## 5. Faz disiplini

Geliştirme `docs/31-roadmap.md`'deki faz sırasına uyar.

```text
Faz 1  Temel altyapı (Riverpod, l10n, domain: Money/VAT)
Faz 2  Veritabanı (15 tablo, migration altyapısı)
Faz 3  Ürün + Auth + Finansal erişim + Recovery  ← 69 req, 3a–3d'ye bölünmeli
Faz 4  Barkod
Faz 5  SATIŞ  ← ilk kullanılabilir sürüm
Faz 6  Stok + Audit
Faz 7  İade/İptal
Faz 8  Dashboard + Rapor
Faz 9  Yedekleme  ← ERTELENMEZ
Faz 10 Import/Export
Faz 11 Test + Optimizasyon
Faz 12 Windows sürüm
```

### Kurallar

- Bir faz, **çıkış kriterleri** karşılanmadan tamamlanmış sayılmaz.
- **Faz 9 (Yedekleme) ertelenmez** — Faz 5'ten sonra gerçek kullanım başlayabilir ve
  yedeksiz geçen her gün [RSK-005](../../docs/29-risks.md) riskidir.
- Sonraki fazın işi "hazırlık olsun diye" öne alınmaz.

---

## 6. Kapsam kontrolü

Geliştirme sırasında yeni bir fikir ortaya çıkarsa:

```text
Bu fikir v1'in bir 🔴 Must requirement'ını mı karşılıyor?
   ├── Evet → zaten kapsamda, docs/25'e bak
   └── Hayır
         ▼
   Onsuz v1 kullanılabilir mi?
         ├── Evet → docs/30-future-scope.md'ye YAZ, faza SOKMA
         └── Hayır → gerçekten Must olduğunu kanıtla,
                     docs/25'e ekle, faz ve takvimi güncelle
```

> **Kapsam genişletme kararı proje sahibinindir**, Claude'un değil ([RSK-012](../../docs/29-risks.md)).

---

## 7. Kod kalite ilkeleri

Kod şu niteliklere sahip olmalıdır:

`readable` · `maintainable` · `testable` · `pragmatic` · `strongly typed` · `null-safe` · `deterministic`

### Somut kurallar

| Kural | |
|---|---|
| Null safety | Tam kullanılır; gereksiz `!` operatörü kaçınılır |
| Tip | `dynamic` kullanılmaz; açık tipler tercih edilir |
| Determinizm | Aynı girdi → aynı çıktı. Domain'de rastgelelik/zaman yan etkisi yok |
| Zaman | `DateTime.now()` domain fonksiyonlarına **parametre olarak** geçirilir (test edilebilirlik) ¹ |
| Hata yönetimi | Beklenen iş hataları `Result`/`Failure` ile döner; exception fırlatılmaz |
| Beklenmeyen hata | Yakalanır, loglanır, kullanıcıya sade Türkçe mesaj gösterilir |
| Yorumlar | Neden'i açıklar, ne'yi değil. Business rule referansı verilir (`// BR-VAT-003`) |
| Ölü kod | Bırakılmaz |
| TODO | Kalıcı TODO yerine `docs/30-future-scope.md`'ye kayıt |

> ¹ **Kaynak notu:** `DateTime.now()` enjeksiyonu bir **teknik test edilebilirlik kuralıdır**;
> `docs/` business source of truth kapsamında **değildir.** Business kararı olarak yorumlanmaz.

### Kod ↔ doküman izlenebilirliği

Business-critical mantık içeren sınıf ve fonksiyonlarda ilgili kural referansı verilir:

```text
/// BR-VAT-003: satış fiyatı KDV dahildir.
/// Bkz. docs/08-vat-rules.md §2
```

Bu, ileride "bu neden böyle?" sorusunun **dokümana kadar izlenebilmesini** sağlar.

---

## 8. Raporlama alışkanlığı

Bir iş tamamlandığında **kısa ve doğrulanabilir** rapor verilir:

- Ne yapıldı, hangi dosyalar değişti
- Hangi BR-*/REQ-* karşılandı
- Hangi testler yazıldı ve **gerçekten çalıştırıldı mı**
- Neyin yapılmadığı ve nedeni
- Tespit edilen ama kapsamda olmayan sorunlar

> Test çalıştırılmadıysa "çalıştırıldı" denmez. Başarısız test varsa **çıktısıyla birlikte** bildirilir.
