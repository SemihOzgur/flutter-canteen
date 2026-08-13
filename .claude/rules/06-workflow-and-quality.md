# 06 — Çalışma Akışı, Test ve Kalite Kapıları

> Kaynak: `docs/27-testing-strategy.md` · `docs/31-roadmap.md` · `docs/26-edge-cases.md`

---

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

## 4. Git ve değişiklik yönetimi

> **Kaynak notu:** Bu bölümdeki Git/branch kuralları **proje sahibi çalışma talimatından** gelir;
> `docs/` business source of truth kapsamında **değildir.** Bu nedenle `docs/` ile çelişme
> durumu söz konusu olamaz — ancak business kuralı gibi de yorumlanmaz.


| Kural | |
|---|---|
| Doğrudan `main` | ❌ **Değiştirilmez** |
| Her feature/bugfix | Ayrı branch |
| Business-critical değişiklik | Testler **aynı branch içinde** |

### Branch adlandırma

```text
feature/<kısa-açıklama>      örn. feature/sale-transaction
bugfix/<kısa-açıklama>       örn. bugfix/vat-rounding
refactor/<kısa-açıklama>
docs/<kısa-açıklama>
```

### Commit kuralları

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
