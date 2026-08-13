# 05 — UI/UX, Dashboard/Raporlar ve Platform

> Kaynak: `docs/23-ux-requirements.md` · `docs/15-dashboard.md` · `docs/16-reporting.md` · `docs/24 §5`

---

## 1. UX temel hedefi

> **Modern POS odaklı.** Kantin çalışanının hızlı işlem yapması her şeyin önündedir.

```text
HEDEF: 3 ürünlük satış → fare kullanmadan → 10 saniyeden kısa
```

Bu bir slogan değil, **ölçülebilir bir kabul kriteridir** (REQ-UX-001).

### Keyboard-first

- Satış akışının tamamı (**okut → ekle → tamamla**) fare olmadan yapılabilmelidir.
- Barcode scanner girdisi **doğal klavye girdisi gibi** çalışır.
- Tüm kısayollar `F1` ekranında listelenir.

### Odak yönetimi — satış ekranının kalbi

```text
Varsayılan               → barkod/arama girişi
Dialog kapandı           → barkod/arama girişi
Satış tamamlandı         → barkod/arama girişi
Ürün eklendi             → barkod/arama girişi
Başka ekrandan dönüldü   → barkod/arama girişi
```

Kullanıcı sepette gezinirken **yazmaya başlarsa odak otomatik olarak barkod girişine döner**
ve **girilen ilk karakter kaybolmaz.** Bu, kasadaki "neden barkod çalışmıyor?" sorununun çözümüdür.

---

## 2. Satış ekranı — dokunulmaz düzen kuralları

| Kural | |
|---|---|
| Sepet paneli | **Hiçbir çözünürlükte gizlenmez veya sekmeye dönüşmez** |
| Minimum çözünürlük | 1366×768 tam işlevsel |
| Toplam tutar | Uzaktan okunabilir boyutta (32 px kalın) |
| Animasyon | Minimum; 150 ms'yi geçmez |
| Yükleme göstergesi | 300 ms altındaki işlemlerde gösterilmez |

Barkod okutulduğunda ürün **ara onay olmadan** sepete eklenir — akışı kesen dialog yasaktır.

---

## 3. Dashboard ve Raporlar

### Erişim

> **Her ikisi de finansal erişim kilidi arkasındadır.**
> Bkz. [`04-security-and-access.md §4`](04-security-and-access.md).

Parola doğrulanmadan **hiçbir sorgu çalıştırılmaz.**

### Hesaplama kuralı — mutlak

> **UI içerisinde finansal hesaplama YAPILMAZ.**

```text
❌ YASAK: Dashboard widget'ı kendi içinde KDV/kâr/ciro hesaplıyor
✅ DOĞRU: domain/service katmanı hesaplar → UI yalnızca gösterir ve formatlar
```

Dashboard, Raporlar ve satış ekranı **aynı domain implementasyonunu** kullanır.
Aynı metrik iki yerde farklı hesaplanamaz ([`01-architecture.md §2`](01-architecture.md)).

### Desteklenen dönemler

`Bugün` · `Dün` · `Bu Hafta` · `Bu Ay` · `Son 7 Gün` · `Son 30 Gün` · `Özel Tarih Aralığı`

- Gün sınırları **yerel saate** göre hesaplanır (veriler UTC saklanır — BR-GEN-004).
- Kritik/negatif stok kartları **anlıktır**; tarih aralığından etkilenmez.

### Metrik kuralları

| Metrik | Kural |
|---|---|
| Ciro | **KDV dahil** gösterilir |
| Kâr | **KDV hariç matrah** üzerinden hesaplanır |
| Tüm metrikler | **Net** — iptal ve iadeler düşülmüş |

### Performans

- Aggregation **SQL tarafında** yapılır.
- Kartlar **bağımsız** yüklenir; biri yavaşsa diğerleri beklemez.
- Hedef: 100.000 satış satırıyla < 1 sn.

---

## 4. Türkçe arayüz

| Kural | |
|---|---|
| Dil | **Türkçe** (V1 tek dil) |
| Metinler | **Merkezî metin dosyasında** — widget içine dağınık hard-code **yasak** |
| Konum | `lib/app/l10n/app_strings_tr.dart` |
| Çoklu dil altyapısı | V1'de **geliştirilmez** |
| Gelecek | Metinler toplu olduğu için ARB'ye geçiş düşük maliyetli kalır |

### Para ve sayı biçimi

```text
₺25,50        ondalık: virgül · binlik: nokta · locale: tr_TR
₺1.234,00     daima 2 ondalık basamak
```

Girdide `25,50` · `25.50` · `25` · `₺25,50` kabul edilir.

---

## 5. Hata mesajları

Format: **ne oldu + ne yapmalıyım + eylem**

| ❌ Kötü | ✅ İyi |
|---|---|
| "Hata oluştu" | "Ürün kaydedilemedi. Bu barkod zaten 'Coca Cola 330ml' ürününe ait. [Ürüne Git]" |
| "Invalid input" | "Satış fiyatı geçersiz. Örnek: 25,50" |
| "SQLITE_BUSY" | "Veritabanı meşgul, işlem tekrar deneniyor..." |

### Kurallar

- Tüm mesajlar **Türkçe**dir.
- **Teknik hata kodu ve stack trace kullanıcıya gösterilmez** — log dosyasına yazılır.
- Onay yalnızca **geri alınamaz** işlemlerde istenir (sepetten ürün silmek onay istemez; satış iptali ister).
- Renkle iletilen her durum **ikon veya metinle de** ifade edilir.
- Her liste ekranının **eyleme yönlendiren boş durumu** vardır.

---

## 6. Platform

| | |
|---|---|
| Production | **Windows** 10 (1809+) / 11, x64 |
| Development | macOS |

### macOS ≠ production garantisi

> **macOS'ta çalışan bir şeyin Windows'ta çalıştığı VARSAYILAMAZ.**

Windows'ta **ayrıca test edilmesi zorunlu** alanlar:

| Alan | Neden farklı |
|---|---|
| Dosya sistemi yolları | `%APPDATA%` çözümlemesi, 260 karakter yol sınırı |
| **Dosya kilitleme** | Windows Unix'ten katıdır — açık DB dosyası taşınamaz |
| Installer | Inno Setup, `%APPDATA%`'ya dokunmama garantisi |
| **Single instance** | Kilit dosyası davranışı |
| **Klavye / scanner** | Türkçe Q/F düzeninde alfanümerik barkod ([RSK-006](../../docs/29-risks.md)) |
| DPI ölçekleme | %100 / %125 / %150 |

Manuel test listesi: `docs/27 §8` (W1–W15). **Her faz sonunda tekrarlanır.**

### Yol işlemleri

- `path` paketi kullanılır; elle string birleştirme **yapılmaz**.
- Mutlak yol veritabanına **yazılmaz** (bilgisayar değişince kırılır).

---

## 7. Erişilebilirlik (temel düzey)

- Tüm etkileşimli öğelere `Tab` ile ulaşılabilir; sıra mantıklıdır.
- Odaklanan öğe belirgin çerçeveyle işaretlenir.
- Kontrast oranı en az 4.5:1.
- Ekran okuyucu desteği hedeflenmez; ancak Flutter'ın varsayılan semantikleri bozulmaz.

---

## 8. UI'da yapılmayacaklar

| ❌ | Nereye ait |
|---|---|
| Veritabanı sorgusu | `data/` |
| Dosya sistemi erişimi | `data/files/` |
| KDV / kâr / ciro hesabı | `domain/services/` |
| İş kuralı validasyonu | `domain/` + `application/` |
| Transaction açma | `application/` |
| `import 'package:drift/...'` | Yalnızca `data/` |
