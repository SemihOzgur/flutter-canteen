# 13 — Stok Sistemi

## 1. Temel yaklaşım: hareket defteri (ledger)

> **BR-STOCK-001 — Stok bir sayaç değil, bir defterdir.**

Basit sayaç yaklaşımının problemi: `stock = 47` bilgisi "neden 47?" sorusuna cevap veremez.
Sayım tutmadığında hatanın nerede olduğu bulunamaz.

Defter yaklaşımı:

```text
Ürün: Coca Cola 330ml

Tarih        Tip              Δ      Sonuç   Referans
──────────────────────────────────────────────────────────
01.08 09:00  initial        +100      100    ilk kayıt
03.08 14:22  sale             -2       98    Satış #2026-000112
04.08 11:05  waste            -1       97    "kırıldı"
05.08 08:30  stockEntry      +20      117    Tedarikçi: Kola A.Ş.
06.08 16:40  sale             -3      114    Satış #2026-000148
07.08 10:15  saleCancellation +3      117    Satış #2026-000148 iptal
08.08 12:00  adjustment       -2      115    "sayım farkı"
──────────────────────────────────────────────────────────
                        TOPLAM        115  ═  products.stock_quantity
```

### İnvariant

```text
products.stock_quantity  ==  Σ stock_movements.quantity_delta  (o ürün için)
```

Bu eşitlik **her zaman** doğru olmalıdır (BR-STOCK-003) ve doğrulanabilir olmalıdır
(Ayarlar → Veri Tutarlılığı Kontrolü, [05 §4](05-database-architecture.md)).

`stock_quantity` alanı bir **önbellektir** — okuma performansı için vardır (her ürün listesinde
`SUM()` çalıştırmak kabul edilemez). Ama tek doğruluk kaynağı defterdir.

---

## 2. Hareket tipleri

| Tip | Yön | Kim oluşturur | `unit_cost` | Not |
|---|---|---|---|---|
| `initial` | + | Ürün oluşturma (başlangıç stoğu) | opsiyonel | Ürün başına en fazla bir kez |
| `stockEntry` | + | Kullanıcı (stok girişi ekranı) | ✅ girilebilir | Tedarikçi bağlanabilir |
| `sale` | − | Satış tamamlama (otomatik) | ❌ | `reference: sale` |
| `saleCancellation` | + | Satış iptali (otomatik) | ❌ | `reference: sale` |
| `return` | + | İade (otomatik) | ❌ | `reference: return` |
| `waste` | − | Kullanıcı (fire) | ❌ | Sebep zorunlu |
| `adjustment` | ± | Kullanıcı (sayım düzeltmesi) | ❌ | Sebep zorunlu |
| — | | | | *Tüm miktarlar tam sayıdır (BR-SALE-011)* |
| `importAdjustment` | ± | Excel/CSV import | ❌ | `reference: import` |
| `restoreBaseline` | ± | Backup restore sonrası (gerekirse) | ❌ | Bkz. [19](19-backup-restore.md) |

**Kural:** `quantity_delta` asla `0` olamaz (BR-STOCK-004 / şema CHECK).

---

## 3. Hareket kayıtlarının değişmezliği

> **BR-STOCK-005 — Stok hareketi yazıldıktan sonra UPDATE veya DELETE edilemez.**

Yanlış girilen bir hareket **düzeltilmez**; ters yönde yeni bir `adjustment` hareketi eklenir.

```text
Yanlış:  stockEntry +200  (aslında +20 olacaktı)
Düzeltme: adjustment -180  not: "Hatalı giriş düzeltmesi, hareket #1523"
```

Bu, denetim izinin (audit trail) bozulmamasını garantiler.

**UI karşılığı:** Stok hareket listesinde "Düzelt" butonu yoktur; "Ters kayıt oluştur" vardır.

---

## 4. Negatif stok

> **BR-STOCK-006 — Stok 0 veya altındayken satış engellenmez.**

Gerekçe: Kasada müşteri beklerken satışı bloklamak, yanlış stok verisinden daha zararlıdır.
Fiziksel ürün elde olabilir ama sistem stoğu yanlış olabilir (sayım hatası, kayıtsız giriş).

### Uyarı akışı

```text
Stok <= 0 olan ürün sepete eklendi
      ▼
┌───────────────────────────────────────┐
│ ⚠ Stok Uyarısı                        │
│                                       │
│ Coca Cola 330ml                       │
│ Sistemdeki stok: 0                    │
│                                       │
│ Bu ürünün stoğu tükenmiş görünüyor.   │
│ Devam ederseniz stok eksiye düşecek.  │
│                                       │
│    [İptal]        [Devam Et]          │
└───────────────────────────────────────┘
```

- Uyarı **engelleyici değildir.**
- Ayarlardan "Stok uyarısını gösterme" ile kapatılabilir (satış hızını önemseyen kullanıcı için).
- Uyarı kapalıyken bile satır sepette turuncu işaretlenir.
- Aynı satış içinde aynı ürün için uyarı bir kez gösterilir.

### Negatif stoğun görünürlüğü

Negatif stok **gizlenmez, vurgulanır** (BR-STOCK-007):

| Yer | Gösterim |
|---|---|
| Dashboard | "Negatif Stok" kartı — adet + tıklanabilir liste |
| Ürün listesi | Stok değeri kırmızı, uyarı ikonu |
| Stok raporu | Ayrı "Negatif Stok" bölümü |
| Satış ekranı ürün kartı | Kırmızı rozet |

### Düzeltme yolu

Negatif stok bir **hata sinyalidir** ve düzeltilmelidir:
- Fiziksel sayım → `adjustment` hareketi
- Unutulan alım → `stockEntry` hareketi

Dashboard'daki negatif stok kartından tek tıkla düzeltme ekranına gidilebilir.

---

## 5. Stok girişi ekranı

En sık kullanılan ikinci ekran (mal kabul).

```text
┌────────────────────────────────────────────────────────┐
│ STOK GİRİŞİ                                            │
│ Tedarikçi: [Kola A.Ş.        ▾]  Tarih: [08.08.2026]  │
│ Belge no:  [_______]  (opsiyonel)                      │
├────────────────────────────────────────────────────────┤
│ 🔍 Barkod okut veya ürün ara...                        │  ← odaklı
├────────────────────────────────────────────────────────┤
│ Ürün                Mevcut   Giriş   Alış Fiyatı  Tutar│
│ Coca Cola 330ml         98   [ 24]   [ ₺18,00 ]  ₺432  │
│ Su 500ml               150   [ 48]   [ ₺ 6,50 ]  ₺312  │
│                                                        │
│                                    TOPLAM     ₺744,00  │
│                          [Vazgeç]  [Girişi Kaydet]     │
└────────────────────────────────────────────────────────┘
```

| Özellik | Davranış |
|---|---|
| Barkod okutma | Satır ekler; aynı ürün tekrar okutulursa miktar +1 |
| Alış fiyatı | Ürünün mevcut alış fiyatı önerilir, değiştirilebilir |
| Alış fiyatı değiştirilirse | ⚠ "Ürünün alış fiyatı da güncellensin mi?" sorulur (BR-STOCK-009) |
| Kaydetme | **Tek transaction** — tüm satırlar ya kaydedilir ya hiçbiri |
| Toplu giriş | Excel/CSV ile de yapılabilir ([20](20-import-export.md)) |

Kaydedildiğinde her satır için bir `stockEntry` hareketi + `stock_quantity` güncellemesi
+ (onaylandıysa) `purchase_price_minor` güncellemesi + audit log yazılır.

---

## 6. Fire (waste) ve düzeltme (adjustment)

| | Fire | Düzeltme |
|---|---|---|
| Yön | Yalnızca negatif | Pozitif veya negatif |
| Sebep | 🔴 Zorunlu (öneri listesi: Bozulma, Kırılma, Son kullanma, Çalıntı, Diğer) | 🔴 Zorunlu (serbest metin) |
| Rapor | Fire raporunda ayrı toplanır — **maliyet kaybı olarak** | Stok hareket raporunda |
| Kâr etkisi | Fire tutarı (`qty × unitCost`) kâr raporunda gider olarak gösterilir | Yok |

Fire, kantinlerde gerçek bir maliyet kalemidir (bozulan süt, bayatlayan poğaça) ve
kâr analizinin doğru olması için ayrıca izlenir.

---

## 7. Kritik stok

```text
Kritik stok koşulu:  minimum_stock > 0  AND  stock_quantity <= minimum_stock
```

`minimum_stock = 0` olan ürünler kritik stok uyarısına **girmez** — kullanıcı o ürün için
takip istemiyor demektir.

| Yer | Gösterim |
|---|---|
| Dashboard | "Kritik Stok" kartı + liste |
| Ürün listesi | Sarı uyarı ikonu |
| Kritik stok raporu | Tedarikçiye göre gruplanabilir → sipariş listesi olarak dışa aktarılabilir |

---

## 8. Stok hareket geçmişi görünümü

Ürün detayında ve ayrı bir "Stok Hareketleri" ekranında:

| Filtre | |
|---|---|
| Ürün | |
| Tarih aralığı | |
| Hareket tipi | |
| Tedarikçi | |
| Kullanıcı | |

Her satır: tarih, tip, miktar (±), sonuç stok, referans (tıklanabilir → satışa/iadeye git), not, kullanıcı.

---

## 9. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-STOCK-001 | Stoğu değiştiren her olay için bir stok hareketi kaydedilir. |
| REQ-STOCK-002 | `products.stock_quantity` her zaman ilgili hareketlerin toplamına eşittir. |
| REQ-STOCK-003 | Stok hareketleri yazıldıktan sonra güncellenemez ve silinemez. |
| REQ-STOCK-004 | Her hareket, işlem sonrası oluşan stok değerini de saklar. |
| REQ-STOCK-005 | Stok 0 veya altındayken satış engellenmez; kullanıcı uyarılır ve devam edebilir. |
| REQ-STOCK-006 | Negatif stoklu ürünler dashboard'da ve stok raporunda ayrıca listelenir. |
| REQ-STOCK-007 | Stok girişi tek transaction'da kaydedilir; kısmi giriş oluşmaz. |
| REQ-STOCK-008 | Stok girişinde alış fiyatı değiştirilirse ürünün alış fiyatının güncellenmesi kullanıcıya sorulur. |
| REQ-STOCK-009 | Fire kayıtları sebep zorunluluğuyla oluşturulur ve maliyet etkisiyle raporlanır. |
| REQ-STOCK-010 | Ürün stok geçmişi, hareketin nasıl oluştuğunu referanslarıyla gösterir. |
| REQ-STOCK-011 | `minimum_stock = 0` olan ürünler kritik stok uyarılarına dahil edilmez. |
| REQ-STOCK-012 | Stok tutarlılığını doğrulayan ve sapmaları raporlayan bir kontrol işlevi bulunur. |

---

## 10. Acceptance criteria

**REQ-STOCK-002**
```text
Given: Bir ürün için 200 adet rastgele stok hareketi oluşturulmuş
When:  Tutarlılık kontrolü çalıştırılıyor
Then:  products.stock_quantity, hareketlerin toplamına eşittir
And:   Sapma raporlanmaz
```

**REQ-STOCK-005**
```text
Given: "Su 500ml" stoğu 0
When:  Barkodu okutuluyor
Then:  Stok uyarısı gösterilir
When:  Kullanıcı "Devam Et" seçiyor ve satışı tamamlıyor
Then:  Satış başarıyla kaydedilir
And:   products.stock_quantity = -1 olur
And:   type='sale', delta=-1, resulting_stock=-1 hareketi oluşur
And:   Ürün dashboard'daki negatif stok listesinde görünür
```

**REQ-STOCK-003**
```text
Given: Kullanıcı 200 adetlik bir stok girişini yanlışlıkla yapmış
When:  Hareket listesinde bu kaydı görüntülüyor
Then:  "Düzenle" veya "Sil" seçeneği bulunmaz
And:   "Ters kayıt oluştur" seçeneği bulunur
When:  Ters kayıt oluşturuluyor
Then:  Yeni bir adjustment hareketi eklenir
And:   Orijinal hareket olduğu gibi durur
```

**REQ-STOCK-007**
```text
Given: 15 satırlık bir stok girişi kaydediliyor
When:  10. satırda hata oluşuyor
Then:  Hiçbir stok hareketi oluşmaz
And:   Hiçbir ürünün stoğu değişmez
And:   Girilen veriler ekranda korunur, kullanıcı düzeltip tekrar deneyebilir
```
