# 10 — Kategori, Marka, Tedarikçi ve Birim Yönetimi

## 1. Kategori

### 1.1 Model ve kurallar

Kategoriler ayrı entity'dir (BR-CAT-001). Hiyerarşi (alt kategori) **yoktur** — kantin ölçeğinde
tek seviye yeterlidir ve raporlamayı basit tutar. İhtiyaç doğarsa [30](30-future-scope.md)'da kayıtlıdır.

| İşlem | Davranış |
|---|---|
| Oluştur | İsim benzersiz olmalı (pasifler dahil) |
| Düzenle | İsim ve sıralama değiştirilebilir |
| Pasifleştir | İçinde ürün olsa bile mümkün; ürünler etkilenmez (BR-CAT-003) |
| **Sil** | 🟡 **Yalnızca hiç kullanılmamışsa** (BR-CAT-005) — §1.3 |

### 1.2b Kategori silme koşulu

Ürün silmede olduğu gibi ([09 §4](09-product-management.md)), sistem önce kullanımı kontrol eder:

```text
Kullanıcı "Sil" der
      ▼
Bu kategoriye atanmış ürün VAR MI?  (aktif veya pasif)
   veya
Bu kategori herhangi bir satış satırı snapshot'ında GEÇİYOR MU?
      │
      ├── HAYIR ──► KALICI SİLME  [BR-CAT-005]
      │             "Bu kategori hiç kullanılmamış. Kalıcı olarak silinecek."
      │
      └── EVET ───► PASİFLEŞTİRME  [BR-CAT-002]
                    "Bu kategoride 23 ürün var / geçmiş satışlarda kullanılmış.
                     Kategori silinmez, pasife alınır."
```

`Genel` sistem kategorisi her iki durumda da korunur (BR-CAT-004).

### 1.2 `Genel` sistem kategorisi

- İlk kurulumda otomatik oluşturulur.
- `is_system = true` — silinemez, pasifleştirilemez, adı değiştirilemez.
- Kategori seçilmediğinde varsayılan olarak kullanılır (BR-PROD-003).

### 1.3 Pasif kategori davranışı

```text
Kategori pasifleştirildi
      │
      ├─► Mevcut ürünler:      geçerli kalır, satılabilir, raporlanır
      ├─► Yeni ürün ataması:   kategori seçim listesinde görünmez
      ├─► Ürün düzenleme:      mevcut kategori "(pasif)" etiketiyle gösterilir
      ├─► Satış ekranı filtresi: görünmez (içinde aktif ürün varsa uyarı gösterilir)
      └─► Raporlar:            görünür
```

**Kullanıcı akışı — pasifleştirme öncesi bilgi:**
```text
"Şekerleme" kategorisi pasife alınacak.
Bu kategoride 23 aktif ürün var. Ürünler etkilenmeyecek,
satılmaya devam edecek. Yalnızca yeni ürünlere bu kategori atanamayacak.

[Vazgeç]  [Ürünleri başka kategoriye taşı]  [Pasife Al]
```

### 1.4 Kategori birleştirme

"Ürünleri başka kategoriye taşı" işlemi toplu güncelleme yapar:
- Tüm ürünlerin `category_id` değeri hedef kategoriye çekilir.
- Tek transaction.
- Audit log'a tek bir toplu kayıt (`categoryMerge`, metadata: kaynak, hedef, ürün sayısı).
- **Geçmiş satışlar etkilenmez** çünkü `sale_items.category_id_snapshot` mevcuttur.

---

## 2. Tedarikçi

### 2.1 Kurallar

| İşlem | Davranış |
|---|---|
| Oluştur | Yalnızca `name` zorunlu |
| Düzenle | Tüm alanlar |
| Pasifleştir | Mümkün; bağlı ürünler ve geçmiş stok girişleri korunur (BR-SUP-002) |
| Sil | ❌ Yasak |

### 2.2 Tedarikçi üzerinden erişilebilecek bilgiler

Tedarikçi detay ekranı şunları göstermelidir:

| Bilgi | Kaynak |
|---|---|
| Bağlı ürün sayısı ve listesi | `products.supplier_id` |
| Bu tedarikçiden yapılan stok girişleri | `stock_movements` (type=`stockEntry`, `supplier_id`) |
| Toplam alış tutarı (tarih aralığı) | `Σ(quantity_delta × unit_cost_minor)` |
| Son giriş tarihi | En son `stockEntry` |
| Bu tedarikçinin ürünlerinden elde edilen ciro/kâr | `sale_items` → `products.supplier_id` |

> **Not:** Son satırdaki metrik ürünün **güncel** tedarikçisine göre hesaplanır. Ürünün tedarikçisi
> değişirse geçmiş ciro yeni tedarikçiye taşınır. Bu bilinçli bir basitleştirmedir —
> `sale_items`'a tedarikçi snapshot'ı eklenmemiştir, çünkü kantin ölçeğinde tedarikçi bazlı
> geçmiş ciro analizi kritik değildir. Kullanıcı bunu isterse [30](30-future-scope.md)'a alınır.

### 2.3 Ürün–tedarikçi ilişkisi

- Bir ürünün **en fazla bir** tedarikçisi vardır (basitleştirme).
- Çoklu tedarikçi ihtiyacı doğarsa `product_suppliers` ara tablosu ile genişletilebilir — v1'de yok.
- Tedarikçi pasifleştirilirse ürünlerin bağı kopmaz.

---

## 3. Marka — V1'de neden ayrı entity değil?

> **Bu bir "asla olmayacak" kararı değildir.** V1 için gereksiz olduğu tespit edilmiştir;
> genişleme yolu §3.1'de tanımlıdır (BR-SUP-003).

Gerekçe:

| Kriter | Değerlendirme |
|---|---|
| Marka bazlı raporlama isteniyor mu? | ❌ Gereksinimlerde yok |
| Marka için ek alan (logo, iletişim) gerekiyor mu? | ❌ Hayır |
| Marka pasifleştirme/soft delete gerekiyor mu? | ❌ Hayır |
| Marka adı tutarlılığı kritik mi? | 🟡 Kısmen — otomatik tamamlama ile çözülür |

**V1 kararı:** `products.brand` serbest metin alanı.
UI'da mevcut markalardan (`SELECT DISTINCT brand`) beslenen bir otomatik tamamlama sunulur;
bu, yazım tutarsızlığının büyük kısmını engeller.

### 3.1 Gelecekte entity'ye dönüşüm yolu

Marka bazlı raporlama, marka logosu veya marka pasifleştirme ihtiyacı doğarsa:

```text
1. brands tablosu oluşturulur (id, name, is_active, ...)
2. SELECT DISTINCT brand FROM products  →  brands tablosuna doldurulur
3. products.brand_id (FK, nullable) eklenir ve eşleştirilir
4. products.brand metin alanı deprecated işaretlenir (silinmez — REQ-MIG-007)
```

Tek migration, veri kaybı yok, düşük risk. **Bu yol kapalı değildir.**

---

## 4. Birim — V1'de neden ayrı entity değil?

> **Bu da bir "asla olmayacak" kararı değildir** (BR-SUP-004).

`salesUnit` (satış birimi) ve `netWeightValue`/`netWeightUnit` (gramaj) alanları yalnızca
**açıklayıcıdır** (BR-PROD-011). Hiçbir finansal veya stok hesabına girmezler; birim dönüşümü
(ml → lt) yapılmaz. V1'de satış miktarı daima tam sayıdır (BR-SALE-011), dolayısıyla birimin
hesaplamada hiçbir rolü yoktur.

**V1 kararı:**

| Alan | Tip | Öneri listesi |
|---|---|---|
| `sales_unit` | serbest metin | `adet`, `paket`, `kutu`, `koli` |
| `net_weight_value` | int (milli hassasiyet) | 150 g → `150000` |
| `net_weight_unit` | serbest metin | `g`, `kg`, `ml`, `lt` |

```text
Örnek:  Cips · Net ağırlık: 150 g · Satış birimi: adet
        → 150 gramlık paket, adetle satılır, miktar tam sayıdır
```

### 4.1 Gelecekte entity'ye dönüşüm yolu

`units` tablosu + `products.unit_id` ile dönüştürülebilir. Ancak bu, asıl olarak
**tartılı satış** desteği eklenirse anlamlı olur — o zaman birim hesaplamaya girer ve
dönüşüm katsayıları gerekir. İkisi birlikte değerlendirilmelidir ([30 §3.2](30-future-scope.md)).

---

## 5. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-CAT-001 | Kategoriler oluşturulabilir, düzenlenebilir ve pasifleştirilebilir. |
| REQ-CAT-002 | `Genel` sistem kategorisi silinemez, pasifleştirilemez ve adı değiştirilemez. |
| REQ-CAT-003 | Kategori pasifleştirildiğinde bağlı ürünler geçerliliğini ve satılabilirliğini korur. |
| REQ-CAT-004 | Kategori pasifleştirilirken kullanıcıya ürünleri başka kategoriye taşıma seçeneği sunulur. |
| REQ-CAT-005 | Kategori adı sistem genelinde benzersizdir. |
| REQ-SUP-001 | Tedarikçi yalnızca ad ile oluşturulabilir; diğer alanlar opsiyoneldir. |
| REQ-SUP-002 | Tedarikçi silinemez; pasifleştirilir. |
| REQ-SUP-003 | Tedarikçi detayında bağlı ürünler ve stok girişleri listelenir. |
| REQ-SUP-004 | Ürün tedarikçisiz kaydedilebilir. |
| REQ-CAT-006 | Hiçbir ürüne atanmamış ve hiçbir satış satırı snapshot'ında geçmemiş kategori kalıcı olarak silinebilir; diğer kategoriler yalnızca pasifleştirilebilir. |
| REQ-SUP-005 | Marka ve satış birimi V1'de ürün üzerinde serbest metin alanı olarak tutulur; ileride ayrı entity'ye dönüştürülebilecek şekilde tasarlanır. |

---

## 6. Acceptance criteria

**REQ-CAT-003**
```text
Given: "İçecek" kategorisinde 15 aktif ürün var
When:  Kategori pasifleştiriliyor
Then:  15 ürün de is_active = true kalır
And:   Barkodları okutulduğunda sepete eklenebilirler
And:   Yeni ürün formundaki kategori listesinde "İçecek" görünmez
And:   Bu ürünlerin düzenleme ekranında kategori "İçecek (pasif)" olarak gösterilir
```

**REQ-CAT-006**
```text
Given: Kullanıcı yanlışlıkla "Test Kategori" adında bir kategori oluşturmuş
And:   Bu kategoriye hiç ürün atanmamış ve hiç satışta kullanılmamış
When:  Kullanıcı kategoriyi siliyor
Then:  "Kalıcı olarak silinecek" onayı gösterilir ve kategori tamamen silinir
Given: "İçecek" kategorisinde 15 ürün var
When:  Kullanıcı bu kategoriyi siliyor
Then:  Kalıcı silme sunulmaz; yalnızca pasifleştirme önerilir
```

**REQ-CAT-004**
```text
Given: Kullanıcı "Şekerleme" kategorisini pasifleştiriyor
When:  "Ürünleri başka kategoriye taşı" seçiliyor ve hedef "Atıştırmalık" olarak belirleniyor
Then:  Tüm ürünlerin kategorisi tek transaction ile güncellenir
And:   Audit log'a bir adet toplu taşıma kaydı yazılır
And:   Geçmiş satışların kategori raporu değişmez
```
