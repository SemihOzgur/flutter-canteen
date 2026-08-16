# Kantin Otomasyonu — Geliştirme Anayasası

> Bu dosya projenin **değişmez çalışma kurallarının TEK giriş noktasıdır.**
> Kısa ve yönlendiricidir; ayrıntılı kurallar `.claude/rules/` altındadır.
>
> **Başka bir anayasa dosyası yoktur.** Otonom çalışma modu için → §10.

---

## 1. Proje kimliği

| | |
|---|---|
| Proje | Kantin Otomasyonu (POS + stok + raporlama) |
| Framework | Flutter Desktop |
| Production | **Windows** |
| Development | macOS |
| Backend / Server / Cloud | **YOK** |
| Mimari | **Offline-first / Local-first** |
| Veritabanı | **Drift + SQLite** |
| State management | **Riverpod** |
| Grafik | **fl_chart** |
| Installer | **Inno Setup** |
| Dil | **Türkçe** (V1 tek dil) |

Bu satırların hiçbiri geliştirme sırasında tartışmaya açık değildir.
Karar gerekçeleri: `docs/28-open-decisions.md`.

---

## 2. SOURCE OF TRUTH — karar hiyerarşisi

```text
1. docs/02-product-and-business-requirements.md   ← Business Rules (BR-*)
        ↓
2. docs/04-domain-model.md                        ← Entity'ler, invariant'lar
        ↓
3. docs/05-database-architecture.md               ← Fiziksel şema
        ↓
4. docs/25-functional-requirements.md             ← REQ-* + acceptance criteria
        ↓
5. docs/03-architecture.md                        ← Katmanlar, soyutlama sınırları
        ↓
6. docs/23-ux-requirements.md                     ← Ekran/etkileşim gereksinimleri
        ↓
7. docs/26-edge-cases.md                          ← EC-* uç durumlar
        ↓
8. .claude/rules/*                                ← ÇALIŞMA kuralları (docs'u enforce eder)
        ↓
9. IMPLEMENTATION (lib/, test/)
```

> **Kod bu dokümanlara uyar. Doküman koda uydurulmaz.**

| Kural | |
|---|---|
| `.claude/rules/*` hiçbir koşulda `docs/` üzerine **çıkamaz** | Rules, `docs/`'u açıklayan ve uygulatan çalışma kurallarıdır |
| Kural dosyası ≠ `docs/` | **`docs/` kazanır**, kural dosyası düzeltilir |
| Doküman ≠ doküman | **DUR** — karar bekle |

Bu hiyerarşinin ayrıntılı hâli: [`.claude/rules/00-source-of-truth.md §1`](.claude/rules/00-source-of-truth.md).
**İki dosya çelişemez; çelişirse bu dosya ile `rules/00` aynı anda düzeltilir.**

### Kod ile doküman çeliştiğinde

**KOD DEĞİŞTİRİLİR.** Dokümantasyon sessizce override edilmez.

### Bir business kuralı gerçekten değişecekse — sıra budur

```text
1. İlgili docs/ dosyası güncellenir
2. Business Rule (BR-*) / Requirement (REQ-*) güncellenir
3. Gerekiyorsa OD-017+ formatında yeni karar kaydı oluşturulur
4. Etkilenen tüm dokümanlar güncellenir (traceability korunur)
5. ANCAK BUNDAN SONRA kod değiştirilir
```

**Claude kendi başına business kararı verip kod yazamaz.**

---

## 3. SESSİZCE DEĞİŞTİRİLEMEZ — business invariants

Aşağıdakiler proje sahibinin kesinleştirdiği kararlardır. Bunları değiştiren, "iyileştiren",
"daha doğrusunu yapan" veya yorumlayan kod **yazılamaz**:

| # | Invariant |
|---|---|
| 1 | **Satış fiyatı KDV DAHİLDİR** — KDV fiyatın içinden çıkarılır, üzerine eklenmez |
| 2 | **Para tam sayı kuruştur** — floating point ile para hesabı yasak |
| 3 | **Satış miktarı pozitif tam sayıdır** — ondalık/tartılı satış yok |
| 4 | **SaleItem 5 snapshot alanı taşır** — ad, satış fiyatı, alış fiyatı, KDV oranı, kategori |
| 5 | **Stok bir defterdir** — `stock_movements` source of truth; `stock_quantity` türetilmiş özet |
| 6 | **Negatif stok satışı engellemez** — kullanıcı uyarılır, "Devam Et" ile satar |
| 7 | **Satış ve iade atomiktir** — yarım satış/iade oluşamaz |
| 8 | **Satış kayıtları silinmez** — yalnızca durum değişir |
| 9 | **Finansal erişim kilidi** — Dashboard + Raporlar ayrı parola ister |
| 10 | **Recovery code tek kullanımlıktır** ve hash olarak saklanır |
| 11 | **Düz metin parola/kurtarma kodu hiçbir yerde bulunamaz** |
| 12 | **Yedek tek dosyadır** (`.canteenbackup`) ve restore öncesi doğrulanır |
| 13 | **Local-first** — hiçbir temel işlev internete bağımlı olamaz |
| 14 | **Rol/yetki sistemi yoktur** |

Bu listeden birine dokunman gerektiğini düşünüyorsan → **§5 DUR koşulları.**

---

## 4. Kural dosyaları — hangi işten önce ne okunur

> **Zorunlu:** Bir alana kod yazmadan önce ilgili kural dosyasını **oku**.
> Bu bir öneri değil, ön koşuldur.

| Yapacağın iş | Önce oku |
|---|---|
| Herhangi bir business-critical değişiklik | [`.claude/rules/00-source-of-truth.md`](.claude/rules/00-source-of-truth.md) |
| Katman, klasör, soyutlama, paket ekleme | [`.claude/rules/01-architecture.md`](.claude/rules/01-architecture.md) |
| Para, KDV, kâr, stok, satış, iade, ürün, barkod | [`.claude/rules/02-business-invariants.md`](.claude/rules/02-business-invariants.md) |
| Veritabanı, migration, yedek, import/export, görsel, audit | [`.claude/rules/03-data-and-persistence.md`](.claude/rules/03-data-and-persistence.md) |
| Login, oturum, dashboard parolası, recovery code | [`.claude/rules/04-security-and-access.md`](.claude/rules/04-security-and-access.md) |
| Ekran, kısayol, dashboard, rapor, Windows/macOS farkı | [`.claude/rules/05-ux-and-platform.md`](.claude/rules/05-ux-and-platform.md) |
| Test yazma, **branch açma/kapsamı/merge**, feature tamamlama | [`.claude/rules/06-workflow-and-quality.md`](.claude/rules/06-workflow-and-quality.md) |

---

## 5. DUR koşulları — implementation'a devam etme

### 5.1 Rutin teknik işler DUR gerektirmez

Aşağıdaki işler **tek başına business kararına dokunmuyorsa** durmadan yapılır:

- private helper oluşturma/değiştirme
- saf iç refactor
- değişken / metot / sınıf yeniden adlandırma
- widget bölme / birleştirme
- log mesajı düzeltme
- test ekleme veya test refactor'ü
- performans optimizasyonu — **mevcut davranış değişmiyorsa**
- dead code temizleme
- import düzenleme
- format / lint düzeltmeleri
- mevcut abstraction'ın teknik iyileştirilmesi

### 5.2 DUR koşulları

Yapılan değişiklik şunlardan **birini** etkiliyorsa kod yazmayı bırak, raporla, karar bekle:

- **Business rule**
- **Database schema**
- **Para / stok hesaplama davranışı**
- **Authentication / security davranışı**
- **Persistence / migration / backup davranışı**
- **Kullanıcıya görünen iş davranışı**
- **Mevcut bir REQ / BR / OD kararının anlamı**

Ek olarak: iki doküman çelişiyorsa, ilgili business rule dokümanda hiç yoksa veya
§3'teki bir invariant'a dokunuluyorsa → **DUR.**

### 5.3 Ayrım — aynı dosya, farklı sonuç

| İş | Sonuç |
|---|---|
| `calculateTotal()` metodunu refactor etmek | ✅ DUR yok |
| `calculateTotal()` metodunun **KDV davranışını** değiştirmek | 🛑 DUR |
| Widget'ı iki dosyaya bölmek | ✅ DUR yok |
| Widget'a **indirim alanı** eklemek | 🛑 DUR |
| Repository kodunu optimize etmek | ✅ DUR yok |
| **Yeni repository/interface** eklemek | 🛑 DUR — [`01-architecture.md §4`](.claude/rules/01-architecture.md) |

> **Şüpheli durumda**, değişikliğin mevcut business davranışını değiştirme ihtimali varsa → **DUR.**
>
> Bu muafiyet bir **business kararı değiştirme serbestisi değildir.**

**Raporlama biçimi:**

```text
DURDURULDU — <konu>

Çelişki/belirsizlik: <ne>
İlgili doküman(lar): <docs/... dosyaları, BR-*/REQ-* ID'leri>
Etkilenen alan: <domain / şema / UI / migration>
Seçenekler: <A / B / C ve sonuçları>
Önerim: <biri> — <gerekçe>
Gereken karar: <proje sahibinden ne isteniyor>
```

Gerekiyorsa `OD-017+` formatında yeni karar kaydı oluşturulmasını öner
(`Decision / Options / Recommendation / Impact`).

---

## 6. Kod yazmadan önce (pre-flight)

1. İlgili `docs/` dosyalarını bul ve oku
2. Business Rules (BR-*) — hangi kurallar bağlayıcı?
3. Functional Requirements (REQ-*) + acceptance criteria
4. Domain etkisi — hangi hesaplama/invariant etkileniyor?
5. Database etkisi — şema, migration, index gerekiyor mu?
6. Edge cases (`docs/26-edge-cases.md`) — ilgili EC-* maddeleri
7. Test planı — neyi nasıl doğrulayacaksın?

Ancak bundan sonra implementation.

---

## 7. Feature "tamamlandı" sayılma koşulları

- [ ] `flutter analyze` temiz
- [ ] `dart format` uygulanmış
- [ ] İlgili unit testler yazılmış ve geçiyor
- [ ] Gerekiyorsa integration testler çalıştırılmış
- [ ] §3'teki business invariant'lar doğrulanmış
- [ ] İlgili acceptance criteria karşılanmış
- [ ] Dokümantasyonla tutarlılık kontrol edilmiş

Business-critical mantık **testsiz tamamlanmış sayılmaz.**

---

## 8. Branch disiplini

> Detay: [`.claude/rules/06-workflow-and-quality.md §4`](.claude/rules/06-workflow-and-quality.md)

| Kural | |
|---|---|
| **Bağımsız kapsam** (feature / bugfix / faz / alt faz / migration / docs-rules) | **Ayrı branch** |
| Tek bir kapsamın **doğal alt işleri** | **Aynı branch** |
| Kapsam **dışı** iş ortaya çıktı | 🛑 **DUR** — mevcut branch'e ekleme, yeni branch öner, onay bekle |
| `main` üzerinde doğrudan geliştirme | ❌ **Yapılmaz** |
| `main`'e commit / push | ❌ Kullanıcı açıkça istemedikçe yapılmaz |
| **Merge · branch silme · cherry-pick** | ❌ **Kullanıcı onayı olmadan asla** |

### Akış

```text
BRANCH → IMPLEMENT → TEST → ANALYZE → REPORT → USER TEST → USER APPROVAL → MERGE
                                          ▲
                                    CLAUDE BURADA DURUR
```

Kullanıcı test sonucu vermeden **sonraki branch/faz kapsamına geçilmez.**

Branch tamamlanmadan önce `git status` + `git diff` ile **kapsam dışı değişiklik kontrolü** yapılır;
beklenmeyen değişiklik varsa DUR. Branch kapsamı, iş başlamadan önce tanımlanır.

> **Branch açılmış olması business kararını değiştirme yetkisi vermez** — §2'deki protokol
> her koşulda geçerlidir. Branch stratejisi yalnızca workflow'dur; source-of-truth değildir.

---

## 9. Bu dosyanın ve kuralların statüsü

- `CLAUDE.md` ve `.claude/rules/*` projenin **geliştirme anayasasıdır.**
- `docs/` **ürün ve iş kurallarının source of truth'udur.**
- Çelişirlerse: `docs/` kazanır; kural dosyası düzeltilir.
- Kural dosyaları proje sahibinin onayı olmadan gevşetilemez.
- **Anayasa yalnızca bu dosyadır.** `.claude/` altında ikinci bir `CLAUDE.md` tutulmaz.

---

## 10. Otonom çalışma modu

> Ayrıntı: [`.claude/rules/06-workflow-and-quality.md`](.claude/rules/06-workflow-and-quality.md)
> → *AUTONOMOUS EXECUTION MODE*. Buradaki özet o bölümle çelişemez.

### Rutin teknik işlemler için izin istenmez

`git status` · `git diff` · `git log` · `git branch` · `git switch` · `git checkout` · `git fetch` ·
`flutter analyze` · `flutter test` · `dart format` · `dart fix` · `sqlite3` ·
`grep` · `find` · `sed` · `awk` · `python3` · shell scriptleri ·
dosya oluşturma/değiştirme · test çalıştırma

> "Bu komutu çalıştırabilir miyim?" / "Testleri başlatayım mı?" / "Branch oluşturayım mı?"
> gibi sorular rutin işlerde **sorulmaz** — iş doğrudan yapılır.

### Otomatik kurtarma

```text
FAIL → ROOT CAUSE → FIX → RETEST
```

Teknik bir hata ise düzeltilir ve tekrar test edilir.
**Business kararı gerekiyorsa döngü durur** (§5).

### Kullanıcıya yalnızca şunlarda dönülür

1. Business kararı
2. Doküman çelişkisi
3. Database business model değişikliği
4. Security / business davranışı değişikliği
5. Merge
6. `main`'e push
7. Release

### Otomasyon dosyaları

| Ne | Nerede |
|---|---|
| Kural dosyaları | `.claude/rules/*.md` — §4 |
| Subagent tanımları | `.claude/agents/*.md` |
| Slash komutları | `.claude/commands/*.md` |
| Workflow şablonları | `.claude/workflows/*.md` |
| Doğrulama scriptleri | `.claude/scripts/{verify,test,audit}.sh` |
