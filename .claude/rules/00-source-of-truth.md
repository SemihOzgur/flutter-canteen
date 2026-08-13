# 00 — Source of Truth ve Değişiklik Protokolü

> **Bu dosya diğer tüm kuralların üstündedir.** Bir kural dosyası ile bu dosya çelişirse bu dosya kazanır.
> Bu dosya ile `docs/` çelişirse **`docs/` kazanır** ve bu dosya düzeltilir.

---

## 1. Karar hiyerarşisi

```text
┌────────────────────────────────────────────────────────────┐
│ 1. docs/02-product-and-business-requirements.md            │
│    Business Rules (BR-*) — 76 kural                        │  EN YÜKSEK
├────────────────────────────────────────────────────────────┤
│ 2. docs/04-domain-model.md                                 │
│    Entity'ler, alanlar, invariant'lar, durum makineleri    │
├────────────────────────────────────────────────────────────┤
│ 3. docs/05-database-architecture.md                        │
│    15 tablo, kısıtlar, index'ler                           │
├────────────────────────────────────────────────────────────┤
│ 4. docs/25-functional-requirements.md                      │
│    REQ-* (285 adet) + acceptance criteria                  │
├────────────────────────────────────────────────────────────┤
│ 5. docs/03-architecture.md · 23-ux · 26-edge-cases         │
├────────────────────────────────────────────────────────────┤
│ 6. IMPLEMENTATION (lib/, test/)                            │  EN DÜŞÜK
└────────────────────────────────────────────────────────────┘
```

**Üsttekiler alttakileri belirler. Alttakiler üsttekileri değiştiremez.**

---

## 2. Çelişki çözümü

| Durum | Yapılacak |
|---|---|
| Kod ≠ doküman | **Kod değiştirilir.** Doküman haklıdır. |
| Doküman ≠ doküman | **DUR.** Rapor et, karar bekle. Kendin seçme. |
| Kural dosyası ≠ `docs/` | `docs/` kazanır; kural dosyası düzeltilir |
| Doküman bir konuyu hiç kapsamıyor **ve konu business/şema/güvenlik alanına giriyor** | **DUR.** Yeni karar (`OD-017+`) önerisi yap |
| Doküman bir konuyu hiç kapsamıyor **ama iş saf teknik** (§5.1) | **Devam et.** DUR gerekmez |
| Doküman kapsıyor ama sen daha iyisini biliyorsun | **Yine de dokümana uy.** Öneriyi ayrıca dile getir. |

> "Daha iyi bir yol biliyorum" bir uygulama gerekçesi değildir; bir **öneri** gerekçesidir.
> Öneriyi sun, kararı proje sahibi verir.

---

## 3. Business kuralı değiştirme protokolü

Bir BR-* veya REQ-* gerçekten değişecekse **sıra budur ve atlanamaz:**

```text
1. docs/ içindeki ilgili dosya güncellenir
2. BR-* / REQ-* metni güncellenir
3. Gerekiyorsa OD-017+ karar kaydı oluşturulur
   (Decision / Options / Recommendation / Impact)
4. Etkilenen TÜM dokümanlar güncellenir:
   - docs/02 (business rule)
   - docs/04 (domain model) — alan/invariant etkilendiyse
   - docs/05 (şema) — tablo/kolon etkilendiyse
   - docs/25 (requirement indeksi + öncelik + faz)
   - docs/26 (edge case)
   - docs/27 (test planı)
   - docs/29 (risk) — yeni risk doğuyorsa
   - docs/31 (roadmap) — faz yükü değişiyorsa
5. ANCAK BUNDAN SONRA kod yazılır
```

**Adım 1–4 yapılmadan adım 5'e geçilmez.** Kod, dokümandan önce yazılmaz.

---

## 4. Sessizce değiştirilemeyecek kararlar

Aşağıdaki 14 madde proje sahibinin kesinleştirdiği **business invariant'lardır.**
Bunları değiştiren kod, "iyileştirme" veya "düzeltme" gerekçesiyle bile yazılamaz.

| # | Invariant | Kaynak |
|---|---|---|
| 1 | Satış fiyatı KDV **dahildir** | BR-VAT-003 · `docs/08` |
| 2 | Para tam sayı kuruş; floating point yasak | BR-FIN-001 · `docs/07` |
| 3 | Satış miktarı pozitif tam sayı | BR-SALE-011 |
| 4 | SaleItem 5 snapshot alanı taşır | BR-SALE-001 · `docs/04 §3.9` |
| 5 | Stok defter tabanlı; `stock_quantity` türetilmiş | BR-STOCK-001/002 · `docs/13` |
| 6 | Negatif stok satışı engellemez, uyarır | BR-STOCK-006 |
| 7 | Satış ve iade atomik | BR-SALE-005, REQ-RET-010 |
| 8 | Satış kayıtları silinmez | BR-GEN-002, BR-SALE-006 |
| 9 | Finansal erişim kilidi: Dashboard + Raporlar | BR-AUTH-013 · `docs/17 §7` |
| 10 | Recovery code tek kullanımlık, hash saklanır | BR-AUTH-015/017 · `docs/17 §8` |
| 11 | Düz metin parola/kod hiçbir yerde bulunamaz | BR-SEC-001 |
| 12 | Yedek tek dosya, restore öncesi doğrulanır | BR-DATA-002/003 · `docs/19` |
| 13 | Local-first; ağ bağımlılığı yasak | BR-GEN-001, BR-SEC-003 |
| 14 | Rol/yetki sistemi yok | BR-AUTH-002 |

---

## 5. DUR koşulları

> **DUR mekanizması business kararlarını korumak içindir — rutin geliştirmeyi yavaşlatmak için değil.**
> Bu bölüm ikisini kesin olarak ayırır.

### 5.1 Rutin teknik işler — DUR GEREKTİRMEZ

Aşağıdaki işler, **tek başına business kararına dokunmuyorsa**, durmadan ve karar beklemeden yapılır:

| ✅ DUR gerektirmez |
|---|
| private helper oluşturma/değiştirme |
| saf iç refactor |
| değişken / metot / sınıf yeniden adlandırma |
| widget bölme / birleştirme |
| log mesajı düzeltme |
| test ekleme veya test refactor'ü |
| performans optimizasyonu — **mevcut davranış değişmiyorsa** |
| dead code temizleme |
| import düzenleme |
| format / lint düzeltmeleri |
| mevcut abstraction'ın teknik iyileştirilmesi |

### 5.2 DUR koşulları — implementation durur

DUR **yalnızca** yapılan değişiklik şunlardan birini etkiliyorsa uygulanır:

| # | Etkilenen alan |
|---|---|
| 1 | **Business rule** |
| 2 | **Database schema** |
| 3 | **Para / stok hesaplama davranışı** |
| 4 | **Authentication / security davranışı** |
| 5 | **Persistence / migration / backup davranışı** |
| 6 | **Kullanıcıya görünen iş davranışı** |
| 7 | **Mevcut bir REQ / BR / OD kararının anlamı** |

Ayrıca şu üç durumda da DUR edilir:

| # | Durum |
|---|---|
| 8 | İlgili business rule dokümanda **hiç yok** ve iş §5.1 listesinde **değil** |
| 9 | **İki doküman birbiriyle çelişiyor** |
| 10 | İş, **§4'teki bir invariant'a** dokunuyor |

### 5.3 Ayrım örnekleri — aynı kod, farklı sonuç

| İş | Sonuç | Neden |
|---|---|---|
| `calculateTotal()` metodunu refactor etmek | ✅ DUR yok | Davranış aynı, yalnızca yapı değişiyor |
| `calculateTotal()` metodunun **KDV davranışını** değiştirmek | 🛑 **DUR** | Para hesaplama davranışı (§5.2/3) |
| Widget'ı iki dosyaya bölmek | ✅ DUR yok | Kullanıcıya görünen davranış aynı |
| Widget'a **indirim alanı** eklemek | 🛑 **DUR** | Yeni iş davranışı + OD-007 ihlali |
| Repository kodunu optimize etmek | ✅ DUR yok | Davranış aynı |
| **Yeni repository/interface** eklemek | 🛑 **DUR** | Mimari karar — [`01-architecture.md §4`](01-architecture.md) |
| Değişken adını `qty` → `quantity` yapmak | ✅ DUR yok | Adlandırma |
| `quantity` tipini `int` → `double` yapmak | 🛑 **DUR** | BR-SALE-011 ihlali |
| Stok sorgusuna index eklemek | ✅ DUR yok | Performans, davranış aynı |
| Stok sorgusunun **döndürdüğü kümeyi** değiştirmek | 🛑 **DUR** | Stok davranışı |
| Hata mesajının Türkçesini düzeltmek | ✅ DUR yok | Metin |
| Hata mesajını **engelleyici dialog'a** çevirmek | 🛑 **DUR** | Kullanıcıya görünen iş davranışı |

### 5.4 Şüphe kuralı

> Değişikliğin **mevcut business davranışını değiştirme ihtimali varsa → DUR edilir.**

§5.1 muafiyeti bir **business kararı değiştirme serbestisi değildir.**
Rutin bir işin içine business değişikliği gizlenemez — örneğin "refactor" adı altında
KDV formülünü sadeleştirmek §5.2'ye girer.

### 5.5 Rapor formatı

```text
DURDURULDU — <konu>

Çelişki/belirsizlik : <ne olduğu>
İlgili dokümanlar   : <docs/... + BR-*/REQ-* ID'leri>
Etkilenen alan      : <domain / şema / migration / UI>
Seçenekler          : A) ... sonucu ...
                      B) ... sonucu ...
Önerim              : <A veya B> — <gerekçe>
Gereken karar       : <proje sahibinden ne isteniyor>
```

Karar gerekiyorsa `OD-017+` önerisi şu formatta sunulur:

```text
OD-0NN — <başlık>
Decision       : <hangi soru karara bağlanıyor>
Options        : <seçenekler, artı/eksileriyle>
Recommendation : <öneri + gerekçe>
Impact         : <hangi doküman/şema/faz etkilenir>
```

---

## 6. Yasak davranışlar

| ❌ Yasak | Neden |
|---|---|
| Dokümanda olmayan bir business kuralını "mantıklı olduğu için" uygulamak | Karar yetkisi proje sahibinindir |
| Dokümanı koda uydurmak için güncellemek | Hiyerarşi tersine çevrilemez |
| Bir invariant'ı "geçici olarak" esnetmek | Geçici çözüm kalıcı olur |
| Belirsizliği varsayımla kapatıp devam etmek | Yanlış varsayım kalıcı veri bozar |
| Karar kaydı oluşturmadan business-critical kod yazmak | İzlenebilirlik kaybolur |
| Test yazmadan finansal/stok mantığı tamamlamak | Sessiz veri hatası riski |

---

## 7. İzin verilen ve beklenen davranışlar

- Dokümanda **eksik** bir nokta tespit edip raporlamak ✅
- Daha iyi bir yaklaşım **önermek** (uygulamadan) ✅
- Doküman güncellemesini **teklif etmek** ✅
- Risk/edge case tespit edip `docs/26` veya `docs/29`'a eklenmesini önermek ✅
- Belirsizlik karşısında durmak ✅

> Durmak başarısızlık değildir. Yanlış varsayımla devam etmek başarısızlıktır.
