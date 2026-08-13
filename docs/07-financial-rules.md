# 07 — Finansal Kurallar

## 1. Neden floating point kullanılmıyor

`double`/`float` ikili (binary) kayan noktalıdır ve `0.1`, `0.2`, `25.50` gibi ondalık değerleri **tam olarak temsil edemez.**

```text
0.1 + 0.2            → 0.30000000000000004
25.50 * 3            → 76.49999999999999
(19.99 * 3) yuvarla  → duruma göre 59.97 veya 59.96
```

Bir kantinde günde yüzlerce satır işlenir. Her satırda oluşan mikroskobik hata:
- gün sonu toplamının kasa ile tutmamasına,
- kâr raporunun stok maliyetiyle çelişmesine,
- iade tutarının orijinal satıştan farklı çıkmasına

yol açar. Bu hatalar **geri döndürülemez şekilde veritabanına yazılır.**

> **BR-FIN-001: Tüm parasal değerler tam sayı kuruş (minor unit) olarak saklanır.**

```text
₺25,50   →  2550
₺0,05    →  5
₺1.234,00 → 123400
```

**Tip:** 64-bit signed integer. Taşma sınırı pratikte sonsuzdur (≈ 92 katrilyon TL).

**Negatif değerler:** Para alanları normalde `>= 0`'dır. İade/iptal tutarları ayrı tablolarda pozitif
saklanır; işaret raporlama katmanında uygulanır. Böylece "eksi tutarlı satış satırı" gibi belirsiz kayıtlar oluşmaz.

---

## 2. Oranlar — basis point

Oranlar da tam sayıdır (BR-FIN-002):

```text
%20    → 2000 bp
%10    → 1000 bp
%1     →  100 bp
%0,5   →   50 bp
```

Bu, ileride %0,5 gibi ondalıklı bir oran gerekirse şema değişikliği gerektirmemesini sağlar.

---

## 3. Yuvarlama

> **BR-FIN-003: Half-up (0,5 yukarı), yalnızca son adımda.**

Half-up seçildi çünkü Türkiye'deki perakende ve fatura pratiğinde beklenen davranış budur;
banker's rounding kullanıcıya "yanlış" görünür ve kasa mutabakatında açıklanamaz.

**Kritik kural: ara sonuçlar yuvarlanmaz.**

```text
YANLIŞ:  her satırın KDV'sini yuvarla → topla
DOĞRU:   satır bazında hesapla, satır bazında yuvarla, sonra topla
         (çünkü satır tutarı fişte ayrı gösterilir ve tutmalıdır)
```

Bu proje için karar:

| Seviye | Yuvarlama |
|---|---|
| Birim fiyat | Zaten tam sayı kuruş — yuvarlama yok |
| Satır tutarı (`unitPrice × quantity`) | Tam sayı çarpımı — **yuvarlama gerekmez** |
| Satır KDV | Hesaplanır ve **satır seviyesinde yuvarlanır** (half-up) |
| Satır net | `lineTotal − lineVat` (yuvarlama yok, fark yutulur) |
| Satış toplamı | Yuvarlanmış satır değerlerinin **toplamı** |

Bu yaklaşım `Σ(satır) = toplam` eşitliğini garantiler — kullanıcı fişte satırları toplayınca tutar.

---

## 4. Hesaplama formülleri

Aşağıdaki formüller `domain/services/` altında saf fonksiyonlar olarak yaşar ve unit test edilir.

### 4.1 Satır tutarı

```text
lineTotalMinor = unitPriceMinor × quantity
```
Tam sayı çarpımı — kayıp yok.

### 4.2 KDV — **fiyat KDV DAHİLDİR** (BR-VAT-003, karar kapandı)

```text
lineVatMinor = roundHalfUp( lineTotalMinor × vatBp / (10000 + vatBp) )
lineNetMinor = lineTotalMinor − lineVatMinor
```

> **Bu tek geçerli formüldür.** Ürün fiyatının üzerine KDV **eklenmez**; girilen fiyatın
> içinden çıkarılır. Detay ve örnekler: [08 §2](08-vat-rules.md).

### 4.3 Sepet / satış toplamı

```text
subtotalMinor   = Σ lineNetMinor      ← KDV hariç matrah
vatTotalMinor   = Σ lineVatMinor
grandTotalMinor = Σ lineTotalMinor    ← müşteriden alınan tutar (KDV dahil)

invariant: subtotalMinor + vatTotalMinor = grandTotalMinor
```

Sepette gösterilen toplam, kullanıcının ürünlere girdiği fiyatların toplamıdır —
üzerine hiçbir ek yapılmaz.

### 4.4 Para üstü

```text
changeMinor = cashReceivedMinor − grandTotalMinor      (>= 0 olmalı, BR-SALE-008)
```

### 4.5 Maliyet ve kâr

```text
lineCostMinor   = purchasePriceSnapshotMinor × quantity
costTotalMinor  = Σ lineCostMinor

Brüt kâr = subtotalMinor − costTotalMinor        ← KDV HARİÇ matrah üzerinden
```

> **KDV işletmenin geliri değildir.** Fiyat KDV dahil olduğu için (BR-VAT-003), kâr daima
> **KDV hariç matrah** üzerinden hesaplanır (BR-FIN-004, REQ-VAT-009).
> Raporlarda KDV dahil ciro ayrı bir sütun olarak da gösterilir, ancak kâr sütunu tek anlamlıdır.

### 4.6 Net ciro (iade/iptal sonrası)

```text
netCiro = Σ (completed satışların grandTotal)
        − Σ (cancelled satışların grandTotal)
        − Σ (return_items.lineTotal)
```
Bkz. BR-RET-007.

---

## 5. `purchasePriceSnapshotMinor` nasıl belirlenir?

> **Kesinleşmiş olan:** `SaleItem` üzerinde alış fiyatı **snapshot olarak tutulacaktır**
> (BR-SALE-001). Bu tartışmaya kapalıdır — geçmiş kâr hesaplarının bozulmaması için zorunludur.
>
> **Açık olan:** Bu snapshot'a hangi değerin yazılacağı — [OD-005](28-open-decisions.md).

| Seçenek | Açıklama | Artı | Eksi |
|---|---|---|---|
| **A — Son alış fiyatı** | `Product.purchasePriceMinor` doğrudan kopyalanır | Basit, anlaşılır, hesaplama yok | Fiyat artışı geçmiş kârı bozmaz ama anlık kâr dalgalanır |
| B — Ağırlıklı ortalama maliyet | Stok girişlerinden hareketli ortalama hesaplanır | Muhasebesel olarak daha doğru | Ek alan + her stok girişinde hesaplama + negatif stokta tanımsız |
| C — FIFO katman takibi | Parti bazlı maliyet | En doğru | Bu ölçek için aşırı karmaşık |

**Öneri: A (son alış fiyatı).** Kantin ölçeğinde ürün devir hızı yüksek, alış fiyatları
sık ama küçük adımlarla değişir; ağırlıklı ortalamanın getireceği doğruluk kazancı, getireceği
karmaşıklığı karşılamaz. B'ye geçiş ileride mümkündür çünkü bu alan zaten snapshot alanıdır —
yalnızca **doldurulma biçimi** değişir, şema değişmez.

### 5.1 Satış miktarı

> **BR-SALE-011 (karar kapandı):** Satış miktarı **pozitif tam sayıdır.**
> V1'de tartılı/ondalık satış yoktur; `lineTotal = unitPrice × quantity` tam sayı çarpımıdır
> ve hiçbir kayıp oluşmaz. Ürünün gramaj bilgisi ([04 §3.5](04-domain-model.md)) yalnızca
> açıklayıcıdır ve hesaba girmez.

---

## 6. Gösterim (formatlama)

| Konu | Kural |
|---|---|
| Sembol | `₺`, tutarın **önünde**, aralıksız: `₺25,50` |
| Ondalık ayırıcı | `,` (virgül) |
| Binlik ayırıcı | `.` (nokta) |
| Ondalık basamak | Daima 2 — `₺25,00` (`₺25` değil) |
| Negatif | `−₺25,50` (rapor bağlamlarında) |
| Sıfır | `₺0,00` |
| Locale | `tr_TR` |

**Girdi kabulü:** Kullanıcı `25,50`, `25.50`, `25`, `₺25,50` yazabilmelidir; hepsi `2550`'ye normalize edilir.
Birden fazla ayırıcı içeren belirsiz girdiler (`1.234,56` vs `1,234.56`) `tr_TR` kuralına göre yorumlanır.

---

## 7. Karar durumu

**Kapanan kararlar:**

| Konu | Karar |
|---|---|
| KDV dahil mi hariç mi | ✅ **DAHİL** (BR-VAT-003) |
| Satış miktarı tipi | ✅ **INTEGER** (BR-SALE-011) |
| Alış fiyatı snapshot'ı | ✅ **Tutulacak** (BR-SALE-001) |
| Satış fiyatı snapshot'ı | ✅ **Tutulacak** (BR-SALE-001) |
| KDV oranı snapshot'ı | ✅ **Tutulacak** (BR-VAT-002) |

**Açık kalan (yalnızca hesaplama tercihi; şemayı etkilemez):**

| Konu | Kayıt |
|---|---|
| Maliyet snapshot'ına hangi değer yazılacak | [OD-005](28-open-decisions.md) |
| İndirim sisteminin V1 kapsamı | [OD-007](28-open-decisions.md) |
| Nakit ödemede 5 kuruş yuvarlaması | [OD-008](28-open-decisions.md) |

---

## 8. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-FIN-001 | Parasal değerler veritabanında tam sayı kuruş olarak saklanır; hiçbir katmanda `double` ile finansal hesaplama yapılmaz. |
| REQ-FIN-002 | Oranlar basis point tam sayı olarak saklanır. |
| REQ-FIN-003 | Yuvarlama half-up kuralıyla ve yalnızca satır seviyesinde uygulanır. |
| REQ-FIN-004 | Satış toplamı, satır tutarlarının toplamına birebir eşittir. |
| REQ-FIN-005 | Tutarlar `₺#.###,##` biçiminde `tr_TR` locale ile gösterilir. |
| REQ-FIN-006 | Kullanıcı tutar girişinde hem `,` hem `.` ondalık ayırıcısını kullanabilir. |
| REQ-FIN-007 | Alınan nakit toplam tutardan küçükse satış tamamlanamaz. |
| REQ-FIN-008 | Kâr hesabı, satış anındaki maliyet snapshot'ı üzerinden ve KDV hariç matrah kullanılarak yapılır; güncel alış fiyatı geçmişe uygulanmaz. |
| REQ-FIN-009 | Satış miktarı pozitif tam sayıdır; ondalık miktar girilemez. |

---

## 9. Acceptance criteria

**REQ-FIN-004**
```text
Given: Sepette 3 farklı satır var (₺12,33 ×1, ₺7,49 ×3, ₺0,99 ×7) — fiyatlar KDV dahil
When:  Satış tamamlanıyor
Then:  grandTotalMinor = 1233 + 2247 + 693 = 4173
And:   Müşteriden alınan tutar ₺41,73'tür (üzerine KDV eklenmez)
And:   Fişte gösterilen satır tutarlarının toplamı ₺41,73 eder
And:   subtotalMinor + vatTotalMinor = grandTotalMinor
```

**REQ-FIN-009**
```text
Given: Kullanıcı sepette miktar alanına "1,5" yazmaya çalışıyor
Then:  Ondalık ayırıcı kabul edilmez
And:   Miktar yalnızca pozitif tam sayı olabilir
```

**REQ-FIN-008**
```text
Given: Ürünün alış fiyatı ₺10,00 iken satılmış
When:  Alış fiyatı ₺15,00 olarak güncelleniyor
And:   Geçmiş tarihli kâr raporu açılıyor
Then:  O satışın maliyeti ₺10,00 olarak hesaplanır
```
