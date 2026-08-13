# 11 — Barkod Sistemi

## 1. Donanım yaklaşımı

> **Uygulama hiçbir barkod okuyucu markasına veya SDK'sına bağımlı değildir.**

Referans cihaz **Sunlux RH10**'dur; ancak bu yalnızca bir doğrulama cihazıdır, bir bağımlılık değildir.

### Çalışma prensibi

```text
┌──────────────┐   HID    ┌──────────────┐  keyboard  ┌────────────────┐
│   Scanner    ├─────────►│  İşletim     ├───────────►│    Flutter     │
│ (USB/BT HID) │  report  │   Sistemi    │   events   │  Odaklı widget │
└──────────────┘          └──────────────┘            └────────────────┘
```

Scanner işletim sistemi tarafından **klavye** olarak görülür. Barkodu okuduğunda karakterleri
çok hızlı şekilde "yazar" ve sonuna `Enter`/`CR` ekler. Uygulama açısından bu, olağanüstü hızlı
bir klavye girişinden başka bir şey değildir.

### Cihaz gereksinimleri (satın alma kılavuzu — proje bağımlılığı değil)

| Özellik | Gereklilik |
|---|---|
| USB HID / Bluetooth HID keyboard emulation | 🔴 Zorunlu |
| `Enter` / `CR` suffix yapılandırması | 🔴 Zorunlu |
| EAN-13, EAN-8, UPC-A/E, Code 128 | 🔴 Zorunlu |
| Code 39, ITF-14 | 🟡 Tercih edilir |
| 2D / QR (Data Matrix, QR Code) | 🟡 Tercih edilir |
| Türkçe klavye düzeni uyumu | 🔴 Zorunlu — bkz. §5 |
| macOS uyumluluğu | 🟢 Tercih edilir, production gereksinimi değil |
| Serial (COM port) modu | ❌ Kullanılmaz |

---

## 2. Barkod giriş işleyicisi (Barcode Input Handler)

Uygulamanın klavye yazımı ile barkod okumasını ayırt etmesi gerekir.

### Ayırt etme kuralı

| Kriter | Değer | Not |
|---|---|---|
| Karakterler arası maksimum süre | **35 ms** | İnsan yazımı tipik olarak 80–300 ms; scanner < 15 ms |
| Minimum uzunluk | 4 karakter | Kısa girişler barkod sayılmaz |
| Maksimum uzunluk | 64 karakter | Aşılırsa buffer temizlenir |
| Sonlandırıcı | `Enter` / `CR` | Zorunlu |
| Buffer zaman aşımı | 300 ms | Sonlandırıcı gelmezse buffer atılır |

```text
Karakter geldi
     │
     ├── buffer boş ise → zamanlayıcıyı başlat, karaktere ekle
     │
     ├── önceki karakterden < 35 ms geçtiyse → buffer'a ekle
     │
     └── > 35 ms geçtiyse → buffer'ı temizle, yeni giriş başlat (insan yazımı)

Enter geldi
     │
     ├── buffer uzunluğu >= 4 ve tüm karakterler hızlı geldiyse → BARKOD OKUNDU
     │
     └── aksi halde → normal Enter olarak işle (form gönderimi vb.)
```

### Global mi, odaklı mı?

**Karar: Satış ekranında global dinleme, diğer ekranlarda alan odaklı.**

- Satış ekranında barkod, **odak nerede olursa olsun** yakalanır (kullanıcı sepette gezinirken
  bile okutabilmeli). Ancak bir metin alanına aktif yazım yapılıyorsa (arama kutusu) ve giriş
  hızı insan hızındaysa müdahale edilmez.
- Ürün formunda barkod yalnızca "Barkod" alanı odaklıyken yakalanır.
- Modal dialog açıkken barkod dinleme **devre dışıdır** (yanlış ekrana ürün eklenmesin).

---

## 3. Barkod veri modeli

Barkod, `Product` üzerinde tek bir metin alanı **değildir.**

```text
Coca Cola 330ml (Product #42)
├── ProductBarcode: 8691111111111  (primary)
├── ProductBarcode: 8692222222222
└── ProductBarcode: 8693333333333
```

Gerekçe:
- Aynı ürünün farklı ambalaj/parti barkodları olabilir.
- Üretici barkod değiştirdiğinde eski barkodlu stok tükenene kadar ikisi de geçerlidir.
- İthal/yerli aynı ürünün farklı barkodu olabilir.

| Kural | ID |
|---|---|
| Bir ürünün **0, 1 veya N** barkodu olabilir | BR-PROD-004 |
| Bir barkod yalnızca bir ürüne ait olabilir (global UNIQUE) | BR-PROD-005 |
| **Barkodsuz ürünler desteklenir**; satış ekranında arama, kategori filtresi veya favoriler üzerinden **tıklanarak** sepete eklenir | BR-BARC-008 |
| Barkodlar metin olarak saklanır; baştaki sıfırlar korunur | BR-BARC-009 |

### Barkodsuz ürün satışı

Barkodsuz ürünler (tost, çay, poğaça, açık ürünler) satışın normal bir parçasıdır ve
**hiçbir şekilde ikinci sınıf değildir.** Satış ekranında üç yoldan eklenir:

```text
1. FAVORİLER      → tek tıkla (en hızlı, sık satılan barkodsuz ürünler için)
2. KATEGORİ       → kategori seç → ürün listesinden tıkla
3. ARAMA          → ad yaz → Enter veya tıkla
```

Bkz. [12 §3](12-sales-system.md).

### Barkod normalizasyonu

Kaydetmeden ve aramadan önce:
1. Baştaki/sondaki boşluklar kırpılır.
2. Görünmez karakterler (`\r`, `\n`, `\t`, sıfır genişlikli) temizlenir.
3. Büyük harfe çevrilir (Code 39 alfanümerik barkodlar için).
4. **Baştaki sıfırlar korunur** — `0123456789012` ile `123456789012` farklı barkodlardır.

> Baştaki sıfırın korunması kritiktir: UPC-A (12 hane) ile EAN-13 (13 hane) arasındaki fark
> genellikle baştaki sıfırdır. Sayısal tipe dönüştürme yapılmaz; barkod **daima metindir.**

### Checksum doğrulaması

EAN-13/EAN-8/UPC için kontrol hanesi doğrulanabilir. **Karar: doğrulama yapılır ama engellenmez.**
Geçersiz checksum'lı barkod kaydedilirken kullanıcı uyarılır ("Bu barkod standart bir EAN-13
kontrol hanesine sahip değil, yine de kaydedilsin mi?"). Sebep: mağaza içi üretilmiş özel
barkodlar ve fiyat gömülü barkodlar checksum kuralına uymayabilir.

---

## 4. Okutma akışları

### 4.1 Ürün bulundu

```text
Barkod okutuldu
      ▼
product_barcodes'ta ara (UNIQUE index — O(log n))
      ▼
Ürün bulundu ve aktif
      ▼
Sepette bu ürün + aynı fiyat var mı?
      ├── Evet → miktarı +1                (BR-BARC-006)
      └── Hayır → yeni sepet satırı
      ▼
Stok <= 0 mı?
      ├── Evet → uyarı göster (bkz. [13 §4](13-stock-system.md))
      └── Hayır → devam
      ▼
Sepet güncellendi, sesli/görsel geri bildirim, odak barkod girişinde
```

**Toplam hedef süre: < 100 ms** (okutmadan sepette görünmeye kadar).

### 4.2 Ürün bulunamadı

```text
Barkod okutuldu → eşleşme yok
      ▼
"Yeni Ürün (Hızlı)" dialogu açılır, barkod alanı dolu ve salt okunur
      ▼
Kullanıcı ad + satış fiyatı girer (min. zorunlu alanlar)
      ▼
[Kaydet ve Sepete Ekle]
      ▼
Ürün + barkod tek transaction'da kaydedilir
      ▼
Ürün sepete eklenir (BR-BARC-005)
      ▼
Odak barkod girişine döner
```

**İptal edilirse:** Ürün oluşmaz, sepete bir şey eklenmez, barkod alanı temizlenir.

### 4.3 Pasif ürün bulundu

```text
"Bu ürün pasif durumda: <ürün adı>"
[Vazgeç]  [Aktifleştir ve Sepete Ekle]
```

### 4.4 Ürün formu içinde okutma

Barkod alanı odaklıyken okutulan barkod:
- Zaten başka bir ürüne aitse → hata + o ürüne gitme seçeneği (REQ-PROD-005)
- Aynı üründe zaten varsa → "Bu barkod bu üründe zaten kayıtlı" (yinelenmez)
- Boştaysa → barkod listesine eklenir, odak korunur (art arda birden fazla barkod okutulabilir)

---

## 5. Klavye düzeni riski (Windows)

> ⚠️ **Bilinen risk — [RSK-006](29-risks.md)**

Scanner karakterleri **tuş basımı (scan code)** olarak gönderir. Windows'ta aktif klavye düzeni
Türkçe Q/F ise, bazı karakterler farklı yorumlanabilir. Sayısal barkodlarda (EAN/UPC) sorun
oluşmaz çünkü rakam tuşları düzenden bağımsızdır. Ancak **Code 39/Code 128 alfanümerik** barkodlarda
`-`, `.`, `/`, `+`, `%` gibi karakterler yanlış gelebilir.

**Azaltma:**
1. Ayarlar → "Barkod Okuyucu Testi" ekranı: kullanıcı okutur, uygulama ham girdiyi gösterir,
   beklenen değerle karşılaştırılabilir.
2. Sorun tespit edilirse scanner'ın kendi yapılandırma barkoduyla US klavye düzenine alınması önerilir.
3. Uygulama ayarlarında opsiyonel bir "karakter eşleme tablosu" — v1'de yapılmaz, gerekirse eklenir.

---

## 6. Geri bildirim

| Olay | Görsel | Sesli |
|---|---|---|
| Ürün bulundu, sepete eklendi | Sepet satırı yeşil flaş, ürün adı büyük gösterilir | Kısa `beep` |
| Ürün bulunamadı | Kırmızı flaş + dialog | Farklı tonda `beep` |
| Stok tükenmiş, uyarıyla eklendi | Turuncu flaş | Uyarı tonu |
| Barkod okunamadı / geçersiz | Kırmızı flaş | Hata tonu |

Sesler ayarlardan kapatılabilir. Görsel geri bildirim kapatılamaz.

---

## 7. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-BARC-001 | Barkod okuyucu HID klavye girişi olarak işlenir; cihaza özel SDK kullanılmaz. |
| REQ-BARC-002 | Uygulama, karakterler arası süre eşiği ve `Enter` sonlandırıcısı ile barkod girişini klavye yazımından ayırt eder. |
| REQ-BARC-003 | Satış ekranında barkod, odak konumundan bağımsız olarak yakalanır. |
| REQ-BARC-004 | Barkod bulunduğunda ürün ara onay olmadan sepete eklenir. |
| REQ-BARC-005 | Aynı ürün tekrar okutulduğunda yeni satır açılmaz, mevcut satırın miktarı artar. |
| REQ-BARC-006 | Barkod bulunamadığında barkod alanı önceden doldurulmuş hızlı ürün ekleme ekranı açılır. |
| REQ-BARC-007 | Hızlı ürün ekleme sonrasında ürün otomatik olarak sepete eklenir. |
| REQ-BARC-008 | Barkodlar metin olarak saklanır; baştaki sıfırlar korunur. |
| REQ-BARC-009 | Barkod aramasında sonuç 100 ms içinde döner. |
| REQ-BARC-010 | Barkod okuyucu davranışını test etmeye yarayan bir tanılama ekranı bulunur. |
| REQ-BARC-011 | Modal dialog açıkken barkod dinleme devre dışıdır. |
| REQ-BARC-012 | Barkodsuz ürünler satış ekranından arama veya favoriler ile satılabilir. |

---

## 8. Acceptance criteria

**REQ-BARC-004**
```text
Given: "8690000000001" barkodu "Su 500ml" ürününe kayıtlı
And:   Satış ekranı açık
When:  Barkod okutuluyor
Then:  "Su 500ml" hiçbir onay istenmeden sepete eklenir
And:   İşlem 100 ms içinde ekranda görünür
And:   Odak barkod girişinde kalır
```

**REQ-BARC-005**
```text
Given: Sepette "Su 500ml" ×1 var
When:  Aynı barkod tekrar okutuluyor
Then:  Sepette tek satır kalır ve miktarı 2 olur
And:   Yeni bir sepet satırı oluşmaz
```

**REQ-BARC-006 / REQ-BARC-007**
```text
Given: "8699999999999" barkodu sistemde kayıtlı değil
When:  Barkod okutuluyor
Then:  Hızlı ürün ekleme ekranı açılır
And:   Barkod alanı "8699999999999" ile dolu ve düzenlenemez
And:   Odak "Ürün adı" alanındadır
When:  Kullanıcı ad ve fiyat girip kaydediyor
Then:  Ürün, barkodu ile birlikte tek transaction'da oluşturulur
And:   Ürün sepete eklenir
And:   Odak barkod girişine döner
```

**REQ-BARC-002**
```text
Given: Kullanıcı arama kutusuna elle "su" yazıyor (karakterler arası ~200 ms)
When:  Enter'a basıyor
Then:  Bu giriş barkod olarak yorumlanmaz
And:   Normal arama davranışı çalışır
```
