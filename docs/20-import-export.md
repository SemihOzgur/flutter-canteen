# 20 — Import / Export

> **Doküman sürümü:** v3 — CSV birincil format olarak kesinleşti; Excel ayrı abstraction.

## 1. Kapsam

| | Import | Export |
|---|---|---|
| Ürünler | ✅ | ✅ |
| Stok girişi (toplu) | ✅ | — |
| Stok düzeltme (sayım) | ✅ | ✅ (sayım şablonu) |
| Kategoriler | ✅ (ürün import'u içinde otomatik) | ✅ |
| Tedarikçiler | ✅ (ürün import'u içinde otomatik) | ✅ |
| Satışlar | ❌ **Asla** | ✅ |
| Satış satırları | ❌ **Asla** | ✅ |
| Stok hareketleri | ❌ **Asla** | ✅ |
| Raporlar | — | ✅ |
| Audit log | ❌ | ✅ |

> **Satış, satış satırı ve stok hareketi import edilemez.** Bunlar denetim izinin temelidir;
> dışarıdan yazılabilmeleri tüm finansal veriyi güvenilmez kılar. Veri taşıma ihtiyacı
> **backup/restore** ile karşılanır ([19](19-backup-restore.md)).

---

## 2. Desteklenen formatlar

| Format | Import | Export | Öncelik | Not |
|---|---|---|---|---|
| **CSV** | ✅ | ✅ | 🔴 **Birincil** | UTF-8 + BOM, ayırıcı `;`. V1'de öncelikli olarak geliştirilir |
| Excel (.xlsx) | ✅ | ✅ | 🟡 İkincil | **Ayrı abstraction arkasından** ([OD-009](28-open-decisions.md)) |
| Excel (.xls eski) | ❌ | ❌ | — | Desteklenmez; kullanıcı .xlsx olarak kaydetmelidir |

### Format abstraction'ı (BR-DATA-006)

```text
ImportSource (arayüz)          ExportTarget (arayüz)
├── CsvImportSource  ← V1 önceliği   ├── CsvExportTarget  ← V1 önceliği
└── ExcelImportSource            └── ExcelExportTarget
```

CSV yolu Excel'den bağımsız çalışır. Excel kütüphanesinde sorun çıkarsa (bellek, uyumluluk)
yalnızca o implementasyon devre dışı bırakılır; import/export özelliği çalışmaya devam eder.
5.000 satırın üzerindeki `.xlsx` dosyalarında kullanıcı CSV'ye yönlendirilir.

### CSV kuralları

| Konu | Kural |
|---|---|
| Kodlama | UTF-8, BOM ile (Excel Türkçe karakter uyumu) |
| Ayırıcı | `;` — Türkçe Excel varsayılanı. Import'ta `;` ve `,` otomatik algılanır |
| Ondalık | `,` veya `.` kabul edilir |
| Satır sonu | `\r\n` ve `\n` |
| Başlık satırı | Zorunlu |
| Metin kaçışı | RFC 4180 (`"` ile sarma, içindeki `"` çiftlenir) |

---

## 3. Ürün import akışı

```text
Ayarlar → İçe Aktar → Ürünler
      ▼
1. ŞABLON İNDİR  ← kullanıcı önce doğru şablonu alır
      ▼
2. DOSYA SEÇ
      ▼
3. SÜTUN EŞLEŞTİRME
   Dosyadaki sütunlar sistem alanlarına eşleştirilir.
   Başlıklar şablonla birebir aynıysa otomatik eşleşir.
   ┌────────────────────────────────────────┐
   │ Dosya sütunu      →  Sistem alanı      │
   │ "Ürün Adı"        →  [Ürün adı    ▾]  │
   │ "Fiyat"           →  [Satış fiyatı ▾]  │
   │ "Barkod No"       →  [Barkod      ▾]  │
   │ "Açıklama"        →  [— Kullanma  ▾]  │
   └────────────────────────────────────────┘
      ▼
4. VALİDASYON (§4)
      ▼
5. ÖNİZLEME (§5)
      ▼
6. KULLANICI ONAYI
      ▼
7. İÇE AKTARMA (tek transaction)
      ▼
8. SONUÇ RAPORU
```

**Sütun eşleştirme adımı kritiktir:** Kullanıcının elindeki dosya (tedarikçiden gelen liste,
eski programdan çıktı) asla tam olarak beklenen formatta olmaz. Katı bir format dayatmak
import özelliğini kullanılmaz hale getirir.

### Ürün şablonu sütunları

| Sütun | Zorunlu | Örnek | Not |
|---|---|---|---|
| Ürün adı | ✅ | Coca Cola 330ml | |
| Satış fiyatı (KDV dahil) | ✅ | 25,00 | **KDV dahil tutar** (BR-VAT-003) |
| Alış fiyatı | ⚪ | 18,00 | Boşsa 0 |
| Kategori | ⚪ | İçecek | Yoksa oluşturulur, boşsa `Genel` |
| Barkod | ⚪ | 8690000000001 | Çoklu barkod `|` ile ayrılır |
| Marka | ⚪ | Coca Cola | |
| Satış birimi | ⚪ | adet | Açıklayıcı |
| Net ağırlık | ⚪ | 330 | Birimle birlikte |
| Ağırlık birimi | ⚪ | ml | |
| KDV oranı | ⚪ | 20 | Yüzde olarak; tanımsızsa uyarı |
| Tedarikçi | ⚪ | Kola A.Ş. | Yoksa oluşturulur |
| Başlangıç stoğu | ⚪ | 100 | `initial`/`importAdjustment` hareketi oluşturur |
| Minimum stok | ⚪ | 20 | |
| Raf konumu | ⚪ | A-3 | |
| Açıklama | ⚪ | | |

> **Görsel import edilemez** — dosya yolu güvenilmez ve taşınabilir değil.

---

## 4. Validasyon

Her satır için, **içe aktarmadan önce**:

| Kontrol | Sonuç | Davranış |
|---|---|---|
| Ürün adı boş | 🔴 Hata | Satır alınmaz |
| Ürün adı > 120 karakter | 🟡 Uyarı | Kırpılır |
| Satış fiyatı boş / sayıya çevrilemiyor | 🔴 Hata | Satır alınmaz |
| Satış fiyatı negatif | 🔴 Hata | Satır alınmaz |
| Alış fiyatı geçersiz | 🟡 Uyarı | `0` kabul edilir |
| Alış fiyatı > satış fiyatı | 🟡 Uyarı | Alınır (zararına satış olabilir) |
| Barkod zaten sistemde var | ⚙️ Çakışma | §4.1 politikası |
| Barkod dosya içinde tekrarlanıyor | 🔴 Hata | İlgili satırların **tamamı** alınmaz |
| Barkod geçersiz karakter içeriyor | 🟡 Uyarı | Normalize edilir ([11 §3](11-barcode-system.md)) |
| Barkod checksum'ı geçersiz | 🟡 Uyarı | Alınır |
| Kategori yok | ⚙️ Bilgi | Otomatik oluşturulur |
| Tedarikçi yok | ⚙️ Bilgi | Otomatik oluşturulur |
| KDV oranı sistemde tanımsız | 🟡 Uyarı | Varsayılan oran kullanılır |
| Stok sayı değil | 🟡 Uyarı | `0` kabul edilir |
| Stok negatif | 🟡 Uyarı | Alınır |
| Net ağırlık var / birim yok (veya tersi) | 🟡 Uyarı | İkisi de boşaltılır (BR-PROD-011) |
| Başlangıç stoğu ondalık girilmiş | 🟡 Uyarı | Tam sayıya yuvarlanır (BR-SALE-011) |
| Aynı ad + aynı kategori zaten var | 🟡 Uyarı | Alınır (BR-PROD-013) |
| Beklenen sütun eşleşmemiş | 🔴 Hata | Import başlatılamaz |

### 4.1 Barkod çakışma politikası — **kesin business rule**

> **BR-IMEX-001 ve BR-IMEX-002** olarak kayıt altına alınmıştır
> ([02 §10](02-product-and-business-requirements.md)). Bu bir açık karar değildir.

**İki farklı çakışma türü ve kesin davranışları:**

| Çakışma | Kural | Davranış |
|---|---|---|
| Barkod **sistemde zaten kayıtlı** | BR-IMEX-001 | Kullanıcı import öncesi bir politika seçer (aşağıda) |
| Barkod **dosya içinde tekrarlanıyor** | BR-IMEX-002 | O barkoda ait **tüm satırlar reddedilir** — hangisinin doğru olduğuna sistem karar veremez |

Import başlamadan önce kullanıcı **tek bir politika** seçer:

```text
Dosyadaki 47 barkod sistemde zaten kayıtlı. Ne yapılsın?

( ) Bu satırları atla              ← varsayılan, en güvenli
( ) Mevcut ürünleri güncelle       ← ad, fiyat, kategori vb. güncellenir; barkod korunur
( ) İçe aktarmayı iptal et
```

"Mevcut ürünleri güncelle" seçilirse:
- **Stok import edilmez** — stok yalnızca hareketle değişir; toplu stok için ayrı import kullanılır.
- Güncellenen her ürün için audit log kaydı yazılır.
- Önizlemede hangi alanların değişeceği gösterilir.

---

## 5. Önizleme

```text
┌──────────────────────────────────────────────────────────────────┐
│ İÇE AKTARMA ÖNİZLEMESİ — urunler.xlsx                            │
│                                                                  │
│  ✅ 312 satır aktarılacak (yeni ürün)                            │
│  🔄  47 satır güncellenecek                                      │
│  🟡  23 satır uyarı ile aktarılacak                              │
│  🔴  18 satır aktarılamayacak                                    │
│  ➕   4 yeni kategori,  2 yeni tedarikçi oluşturulacak            │
│                                                                  │
│ [Tümü] [Sorunlular] [Hatalar] [Uyarılar]                         │
│ ┌──────────────────────────────────────────────────────────────┐ │
│ │ Satır  Ürün adı        Sorun                                 │ │
│ │  14    (boş)           🔴 Ürün adı zorunlu                    │ │
│ │  27    Su 500ml        🔴 Satış fiyatı okunamadı: "on lira"   │ │
│ │  33    Ayran           🟡 Alış fiyatı satış fiyatından yüksek │ │
│ │  55    Cola            🔴 Barkod dosyada 2 kez geçiyor (s.98) │ │
│ └──────────────────────────────────────────────────────────────┘ │
│                                                                  │
│ [Hata listesini CSV indir]     [Vazgeç]   [İçe Aktar (359)]      │
└──────────────────────────────────────────────────────────────────┘
```

**"Hata listesini CSV indir"** özelliği önemlidir: Kullanıcı hatalı satırları kendi dosyasında
düzeltip tekrar deneyebilir. Yüzlerce satırlık bir dosyada hataları ekrandan tek tek not almak
gerçekçi değildir.

---

## 6. İçe aktarma ve atomiklik

> **BR-DATA-005 — All-or-nothing.**

```text
BEGIN TRANSACTION
  Yeni kategoriler oluştur
  Yeni tedarikçiler oluştur
  Her geçerli satır için:
    ürün oluştur veya güncelle
    barkodları ekle
    başlangıç stoğu varsa stok hareketi oluştur
  audit_logs: dataImported
COMMIT
```

- Hata oluşursa **tam rollback** — hiçbir kayıt oluşmaz.
- Hatalı satırlar (🔴) zaten transaction'a dahil edilmez; bu "kısmi import" değil,
  kullanıcının **önizlemede gördüğü ve onayladığı** kapsamdır.
- 1.000+ satırlık import isolate'te çalışır, ilerleme çubuğu gösterilir, iptal edilebilir.
- Import öncesi otomatik yedek alınması **önerilir** (kullanıcıya sorulur, varsayılan: evet).

### Sonuç raporu

```text
✅ İçe aktarma tamamlandı
   312 yeni ürün · 47 güncellenen · 18 atlanan
   4 yeni kategori · 2 yeni tedarikçi
   Süre: 3,2 sn
   [Atlanan satırları indir]  [Ürünlere git]
```

---

## 7. Stok import (sayım)

Ayrı bir akış — fiziksel sayım sonuçlarını sisteme işlemek için.

| Sütun | Not |
|---|---|
| Barkod veya Ürün adı | Eşleştirme anahtarı |
| Sayılan miktar | Fiziksel sayım sonucu |

```text
Önizleme:
  Ürün              Sistem   Sayım   Fark
  Coca Cola 330ml      98      95     -3
  Su 500ml            150     155     +5
  Tost                 12      12      0   (hareket oluşmaz)

  Toplam fark: 47 üründe düzeltme, maliyet etkisi -₺340,00
```

Onaylandığında her fark için bir `adjustment` hareketi oluşur (not: "Sayım — <tarih>").
Farkı `0` olan ürünler için hareket oluşmaz.

---

## 8. Export

| Ne | Kapsam |
|---|---|
| Ürünler | Tüm alanlar + barkodlar (`|` ayrılmış) + güncel stok. **Import şablonuyla uyumlu** — dışa aktar, düzenle, içe aktar döngüsü çalışır |
| Stok durumu | [16 R3](16-reporting.md) |
| Satışlar | Fiş bazında, tarih aralığıyla |
| Satış satırları | Satır bazında, snapshot değerlerle |
| Stok hareketleri | Tarih aralığıyla |
| Kategoriler / Tedarikçiler | Tam liste |
| Raporlar | Her rapor kendi ekranından |
| Audit log | Tarih aralığıyla |

Tüm export'lar audit log'a yazılır (REQ-AUDIT-001).

---

## 9. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-IMEX-001 | Ürünler CSV ve Excel dosyalarından içe aktarılabilir. |
| REQ-IMEX-002 | İçe aktarma öncesi kullanıcıya doğru formatta bir şablon indirtilebilir. |
| REQ-IMEX-003 | Dosya sütunları sistem alanlarına kullanıcı tarafından eşleştirilebilir. |
| REQ-IMEX-004 | Her satır içe aktarmadan önce doğrulanır ve sonuçlar önizlemede gösterilir. |
| REQ-IMEX-005 | Hatalı satırlar satır numarası ve hata sebebiyle listelenir. |
| REQ-IMEX-006 | Hatalı satır listesi CSV olarak indirilebilir. |
| REQ-IMEX-007 | İçe aktarma kullanıcı onayı olmadan başlatılmaz. |
| REQ-IMEX-008 | İçe aktarma tek transaction'da uygulanır; hata durumunda hiçbir kayıt oluşmaz. |
| REQ-IMEX-009 | Mevcut barkodla çakışan satırlar için kullanıcı bir çakışma politikası seçer. |
| REQ-IMEX-010 | Aynı barkodu birden fazla kez içeren dosyada ilgili satırlar reddedilir. |
| REQ-IMEX-011 | İçe aktarmada oluşturulan stok değişiklikleri stok hareketi olarak kaydedilir. |
| REQ-IMEX-012 | Satış, satış satırı ve stok hareketi kayıtları içe aktarılamaz. |
| REQ-IMEX-013 | Ürün export dosyası, ürün import şablonuyla uyumludur. |
| REQ-IMEX-014 | CSV dosyaları UTF-8 BOM ile yazılır ve Türkçe Excel'de doğru açılır. |
| REQ-IMEX-015 | 1.000 satırdan büyük içe aktarmalar UI'yi bloklamaz ve iptal edilebilir. |
| REQ-IMEX-016 | İçe ve dışa aktarma işlemleri audit log'a yazılır. |

---

## 10. Acceptance criteria

**REQ-IMEX-008**
```text
Given: 500 satırlık bir ürün dosyası içe aktarılıyor
When:  480. satırda beklenmedik bir veritabanı hatası oluşuyor
Then:  Hiçbir ürün oluşturulmaz
And:   Hiçbir kategori veya tedarikçi oluşturulmaz
And:   Hiçbir stok hareketi oluşmaz
And:   Kullanıcıya hata gösterilir ve dosyayı tekrar deneyebilir
```

**REQ-IMEX-010**
```text
Given: Dosyanın 55. ve 98. satırlarında aynı barkod var
When:  Validasyon çalışıyor
Then:  Her iki satır da hata olarak işaretlenir
And:   Hata mesajı diğer satırın numarasını içerir
And:   Bu satırlar içe aktarılmaz
And:   Dosyanın geri kalanı aktarılabilir
```

**REQ-IMEX-013**
```text
Given: Kullanıcı 500 ürünü dışa aktarıyor
When:  Dosyadaki fiyatları düzenleyip aynı dosyayı içe aktarıyor
And:   Çakışma politikası "Mevcut ürünleri güncelle" seçiliyor
Then:  Sütunlar otomatik eşleşir
And:   500 ürünün fiyatı güncellenir
And:   Yeni ürün oluşmaz
And:   Stok miktarları değişmez
```

**REQ-IMEX-011**
```text
Given: İçe aktarılan dosyada "Başlangıç stoğu = 100" olan yeni bir ürün var
When:  İçe aktarma tamamlanıyor
Then:  Ürünün stoğu 100 olur
And:   type='initial', reference_type='import' olan bir stok hareketi oluşur
And:   Hareketin resulting_stock değeri 100'dür
```
