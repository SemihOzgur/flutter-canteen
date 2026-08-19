# 08 — KDV Kuralları

> **Doküman sürümü:** v2 — KDV dahil/hariç kararı **kapanmıştır.**
> Bu doküman artık açık karar içermez.

---

## 1. Kesinleşmiş kurallar

| ID | Kural |
|---|---|
| **BR-VAT-001** | KDV oranları veritabanında yönetilir; koda gömülmez. |
| **BR-VAT-002** | Her `SaleItem` kendi KDV oranının snapshot'ını taşır. |
| **BR-VAT-003** | **Ürünün satış fiyatı KDV DAHİLDİR.** Kullanıcı ₺120 girdiğinde müşteriden alınan tutar ₺120'dir; sistem bu tutarın içindeki KDV'yi hesaplar. |
| **BR-VAT-004** | KDV oranı değişikliği geçmiş satışların KDV tutarını değiştirmez. |
| **BR-VAT-005** | Sistemde tanımlı KDV oranı yoksa uygulama KDV'siz çalışır; KDV alanları ve sütunları gizlenir. |

### BR-VAT-003 — gerekçe

Kantin bir **perakende satış noktasıdır.** Rafta yazan fiyat, müşteriden alınan fiyattır.
Kullanıcıdan KDV'siz fiyat hesaplaması istemek:
- kasa mutabakatını bozar (hesaplanan toplam ile alınan tutar kuruş farkı yapabilir),
- ürün girişini yavaşlatır ve hata kaynağı olur,
- Türkiye perakende pratiğine aykırıdır.

### BR-VAT-002 — gerekçe

KDV oranları mevzuatla değişir. Oran değiştiğinde geçmiş satışların KDV tutarı **değişmemelidir**;
aksi halde geçmiş dönem KDV raporu her oran değişikliğinde farklı sonuç verir.

> Bu kural, ilk gereksinim listesinde eksikti; v1 dokümantasyonunda tespit edilip kurala dönüştürüldü
> ([02 §12](02-product-and-business-requirements.md)).

---

## 2. Hesaplama

KDV dahil fiyat modelinde **tek geçerli formül:**

```text
lineTotalMinor = unitPriceMinor × quantity          (KDV dahil brüt tutar)
lineVatMinor   = roundHalfUp( lineTotalMinor × vatBp / (10000 + vatBp) )
lineNetMinor   = lineTotalMinor − lineVatMinor
```

### Örnek

```text
Ürün satış fiyatı (KDV dahil):  ₺120,00  → 12000 kuruş
KDV oranı:                      %20      → 2000 bp
Miktar:                         2

lineTotalMinor = 12000 × 2                        = 24000   (₺240,00)
lineVatMinor   = roundHalfUp(24000 × 2000 / 12000) =  4000   (₺ 40,00)
lineNetMinor   = 24000 − 4000                      = 20000   (₺200,00)
```

Müşteri **₺240,00** öder. Fişte KDV matrahı ₺200,00, KDV ₺40,00 olarak gösterilebilir.

### Satış toplamı

```text
grandTotalMinor = Σ lineTotalMinor     ← müşteriden alınan tutar
vatTotalMinor   = Σ lineVatMinor
subtotalMinor   = Σ lineNetMinor       ← KDV matrahı

subtotalMinor + vatTotalMinor = grandTotalMinor   (invariant)
```

Yuvarlama **yalnızca satır seviyesinde** yapılır ve toplamlar yuvarlanmış satır değerlerinin
toplamıdır — böylece fişteki satırlar elle toplandığında genel toplam tutar ([07 §3](07-financial-rules.md)).

---

## 3. Veri modeli

```text
vat_rates
  id, name, rate_basis_points, is_default, is_active, created_at, updated_at

products.vat_rate_id             → ürünün geçerli oranı (NULL ise varsayılan oran)
sale_items.vat_rate_snapshot_bp  → satış anındaki oranın kopyası (BR-VAT-002)
sale_items.line_net_minor        → KDV hariç
sale_items.line_vat_minor        → KDV tutarı
sale_items.line_total_minor      → KDV dahil (= unit_price × quantity)
```

Oranlar **basis point** tam sayı olarak saklanır (BR-FIN-002): %20 → `2000`, %1 → `100`, %0,5 → `50`.

### Seed politikası — OD-017

> **Mevzuata bağlı hiçbir oran seed edilmez. Kurulumda yalnızca nötr `%0 — KDV Yok`
> oranı oluşturulur ve varsayılan olur.**

Güncel oranları (%20, %10, %1 …) varsayarak seed etmek, mevzuata bağlı bir değeri koda yazmak
olur — BR-VAT-001'in yasakladığı budur. `%0` ise mevzuata bağlı bir oran değil, KDV
aritmetiğinin **nötr elemanıdır**: `vat = total × 0 / (10000 + 0) = 0`. Seed edilmesi hiçbir
vergi varsayımı yapmaz.

Kurulumda (`Genel` kategorisiyle aynı idempotent seed yolunda) tek bir oran oluşturulur:

```text
name              : "%0 — KDV Yok"
rate_basis_points : 0
is_default        : true
is_active         : true
```

Kullanıcı KDV takibi istiyorsa Ayarlar → KDV Oranları'ndan kendi oranlarını ekler ve
ürünlerine atar. Kurulum sihirbazında oran tanımlama adımı **yoktur** — KDV takip etmek
istemeyen kullanıcıya anlamsız bir adım dayatılmaz.

Kullanıcı kendi oranlarını tanımlamadığı sürece (BR-VAT-005):
- `%0 — KDV Yok` varsayılan oran olarak kalır,
- ürün formunda ve satış ekranında KDV alanları **gizlenir**,
- raporlarda KDV sütunları görünmez,
- `sale_items.vat_rate_snapshot_bp = 0`, `line_vat_minor = 0`, `line_net_minor = line_total_minor` kaydedilir.

Bu, "KDV takibi istemeyen küçük kantin" senaryosunu doğal olarak destekler. Kullanıcı sonradan
Ayarlar → KDV Oranları'ndan oran ekleyerek KDV takibini aktif edebilir.

---

## 4. Oran yönetimi

Kullanıcı KDV oranlarını ekleyebilir, düzenleyebilir, pasifleştirebilir ve
**yeniden aktifleştirebilir** (OD-020 · `vatRateActivated`).
Oran kaydı **silinemez** (geçmiş ürün ilişkileri korunur).

### Varsayılan oran — BR-VAT-006 · OD-019

Varsayılan oran araması aktiflik filtreler (`is_default AND is_active`). Bu nedenle:

| Durum | Davranış |
|---|---|
| Aktif bir oran varsayılan yapılıyor | ✅ Eski varsayılan aynı transaction içinde devredilir |
| **Pasif** bir oran varsayılan yapılıyor | ❌ **Reddedilir** — görünür hata |
| Varsayılan olan oran pasifleştiriliyor | `is_default` bayrağına dokunulmaz; arama zaten aktiflik filtrelediği için sonuç "varsayılan yok" olur |

> Pasif bir oranın varsayılan yapılmasına izin verilseydi sistem "varsayılan oran yok"
> durumuna düşer ve aşağıdaki tabloya göre **KDV sessizce %0 kabul edilirdi.** Kullanıcı bir
> oran seçtiğini sanırken ürünlerinin KDV'si sıfırlanırdı — para davranışındaki sessiz
> değişiklik kabul edilemez.

Aynı anda yalnızca **bir** kayıt `is_default = true` olabilir ([04 §3.4](04-domain-model.md)).

### Bir oranın değeri değiştirildiğinde

```text
"Bu oran <N> üründe kullanılıyor.
 Değişiklik yalnızca bundan sonraki satışları etkiler.
 Geçmiş satışların KDV tutarları değişmez."

              [Vazgeç]   [Değiştir]
```

Değişiklik audit log'a eski ve yeni oranla birlikte yazılır (`vatRateChanged`).

**Alternatif kullanım:** Kullanıcı isterse eski oranı pasifleştirip yeni bir oran oluşturabilir ve
ürünleri yeni orana taşıyabilir. Bu, "hangi ürün ne zaman hangi orandaydı" sorusunu da yanıtlanabilir kılar.
Her iki yol da desteklenir; sistem birini dayatmaz.

### Ürünlerin oranı

| Durum | Davranış |
|---|---|
| Ürüne oran atanmış | O oran kullanılır |
| Ürüne oran atanmamış (`NULL`) | `is_default = true` olan oran kullanılır |
| Varsayılan oran yok | `%0` kabul edilir; KDV hesaplanmaz |
| Ürünün oranı pasifleştirilmiş | Ürün geçerliliğini korur; satışta o oran kullanılmaya devam eder — snapshot mantığı gereği doğru davranıştır |

---

## 5. Raporlama

KDV aktifse üretilebilecek raporlar:

- Tarih aralığında **oran bazında** toplanan KDV (matrah / KDV / KDV dahil toplam)
- Satış raporunda KDV hariç, KDV ve KDV dahil sütunları
- KDV oranı bazında ürün dağılımı

Bu raporlar `sale_items.vat_rate_snapshot_bp` üzerinden gruplanır — `vat_rates` tablosuna **JOIN yapılmaz**,
çünkü oran sonradan değişmiş olabilir.

### Kâr hesabına etkisi

KDV dahil fiyat modelinde KDV işletmenin geliri değildir. Bu nedenle:

```text
Brüt kâr = subtotalMinor (KDV hariç ciro) − costTotalMinor
```

Raporlarda hem "KDV dahil ciro" hem "KDV hariç ciro (matrah)" gösterilir; **kâr daima KDV hariç
matrah üzerinden hesaplanır.** Bkz. [07 §4.5](07-financial-rules.md).

---

## 6. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-VAT-001 | KDV oranları kullanıcı tarafından eklenebilir, düzenlenebilir, pasifleştirilebilir ve yeniden aktifleştirilebilir; **silinemez**. |
| REQ-VAT-002 | **Mevzuata bağlı** hiçbir KDV oranı koda gömülmez veya seed edilmez; kurulumda yalnızca nötr `%0 — KDV Yok` oranı oluşturulur ve varsayılan olur (OD-017). |
| REQ-VAT-003 | Her satış satırı KDV oranını snapshot olarak saklar. |
| REQ-VAT-004 | KDV oranı değişikliği geçmiş satışların KDV tutarlarını değiştirmez. |
| REQ-VAT-005 | Kullanıcı kendi oranlarını tanımlamadığı sürece uygulama KDV'siz çalışır (`%0` varsayılan) ve KDV alanları gizlenir. |
| **REQ-VAT-010** | **Pasif bir KDV oranı varsayılan olarak atanamaz; işlem görünür bir hata ile reddedilir** (BR-VAT-006 · OD-019). |
| **REQ-VAT-011** | **Pasifleştirilmiş KDV oranı yeniden aktifleştirilebilir** (OD-020). |
| REQ-VAT-006 | KDV raporları oran snapshot'ı üzerinden gruplanır. |
| REQ-VAT-007 | Ürün satış fiyatı KDV dahil olarak girilir; sepet ve satış toplamı girilen fiyatların toplamına eşittir. |
| REQ-VAT-008 | KDV tutarı satır bazında, KDV dahil tutardan çıkarılarak hesaplanır. |
| REQ-VAT-009 | Kâr hesabı KDV hariç matrah üzerinden yapılır. |

---

## 7. Acceptance criteria

**REQ-VAT-007 / REQ-VAT-008**
```text
Given: Ürünün satış fiyatı ₺120,00 ve KDV oranı %20
When:  Ürün 2 adet satılıyor
Then:  Sepet toplamı ₺240,00 gösterilir
And:   Müşteriden alınan tutar ₺240,00'dır
And:   sale_items.line_total_minor = 24000
And:   sale_items.line_vat_minor   =  4000
And:   sale_items.line_net_minor   = 20000
And:   Fiyatın üzerine ek KDV EKLENMEZ
```

**REQ-VAT-004**
```text
Given: %10 KDV oranıyla ₺110,00'lik bir satış yapılmış (KDV ₺10,00)
When:  Oran %20 olarak güncelleniyor
And:   Geçmiş dönem KDV raporu çalıştırılıyor
Then:  O satışın KDV tutarı ₺10,00 olarak raporlanır
And:   Satış toplamı ₺110,00 olarak kalır
```

**REQ-VAT-005**
```text
Given: Sistemde hiç KDV oranı tanımlı değil
When:  Kullanıcı ürün ekliyor ve satış yapıyor
Then:  Ürün formunda KDV alanı görünmez
And:   Satış ekranında KDV satırı görünmez
And:   sale_items: vat_rate_snapshot_bp = 0, line_vat_minor = 0,
       line_net_minor = line_total_minor olarak kaydedilir
```

**REQ-VAT-009**
```text
Given: Ürün ₺120,00 (KDV dahil, %20) satılmış, alış fiyatı ₺60,00
When:  Kâr raporu çalıştırılıyor
Then:  KDV hariç ciro ₺100,00 olarak hesaplanır
And:   Brüt kâr ₺40,00 olarak raporlanır (₺100,00 − ₺60,00)
And:   KDV dahil ciro ₺120,00 ayrı bir sütunda gösterilir
```
