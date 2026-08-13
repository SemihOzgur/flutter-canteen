# 15 — Dashboard

> **Doküman sürümü:** v3 — kilit **Raporlar'ı da** kapsıyor; recovery code eklendi.

## 0. Finansal erişim kilidi

> **BR-AUTH-013 — Dashboard ve Raporlar ekranları, kullanıcı oturumundan ayrı bir
> dashboard parolası gerektirir.**

Bu bir rol sistemi değildir (BR-AUTH-008) — sistemde tek bir dashboard parolası vardır ve
kullanıcıya değil, **ekrana** bağlıdır.

```text
Login  →  Ana uygulama (satış / ürünler / stok / kategori / ayarlar)  ← kilit YOK
                      │
                      │ F6 (Dashboard) veya F7 (Raporlar)
                      ▼
            Finansal erişim açık mı?
              ├── Evet → ekran yüklenir
              └── Hayır
                    ▼
            ┌──────────────────────────────────┐
            │  🔒 Finansal Erişim              │
            │  Dashboard ve Raporlar için      │
            │  parola gerekiyor.               │
            │  Parola: [__________________]    │  ← odak
            │  [Şifremi unuttum]               │
            │       [Vazgeç]   [Aç]            │
            └──────────────────────────────────┘
                    ▼
              Doğru → kilit açılır → ekran yüklenir
              Yanlış → hata; 5 denemede 30 sn bekleme
              Şifremi unuttum → recovery code akışı ([17 §8](17-authentication.md))
```

### Kapsam

| Kilit arkasında | Kilit dışında |
|---|---|
| 📊 Dashboard · 📈 Raporlar | Satış · Ürünler · Stok · Kategori · Tedarikçi · Satış geçmişi · İade · Ayarlar · Yedekleme |

### Kritik davranış

> **BR-AUTH-012 — Parola doğrulanmadan hiçbir dashboard/rapor sorgusu çalıştırılmaz.**

Kilit görsel bir perde değildir. Parola girilmeden KPI sorguları çalışmaz, grafik verileri
hesaplanmaz, ekranda hiçbir ciro/kâr rakamı (bulanık veya kısmen bile) görünmez.
Bu kural servis katmanında zorlanır ([03 §9](03-architecture.md)).

### Kilidin süresi

**Oturum kapsamlıdır** (BR-AUTH-016): bir kez açıldığında logout veya uygulama kapanışına kadar
açık kalır. Dashboard ↔ Raporlar geçişlerinde parola tekrar sorulmaz.
Kilit durumu yalnızca bellekte tutulur.

### Parola unutulursa

Kurulumda üretilen **recovery code** ile sıfırlanabilir. Kod tek kullanımlıktır ve
kullanıldığında yenisi üretilir. Bkz. [17 §8](17-authentication.md).

Tam kural seti: [17 §7–§8](17-authentication.md).

---

## 1. Amaç ve tasarım ilkesi

Dashboard bir "grafik galerisi" değildir. Her bileşen bir **karar veya eylemi** desteklemelidir.

Kullanıcının dashboard'a bakarken sorduğu gerçek sorular:
1. Bugün ne kadar sattım, dün/geçen haftaya göre nasıl?
2. Ne kadar kâr ettim?
3. Neyi sipariş etmem gerekiyor? (kritik stok)
4. Nerede hata var? (negatif stok)
5. Ne satıyor, ne satmıyor?

> **Filtre:** Bir grafik bu beş sorudan birine cevap vermiyorsa dashboard'a girmez.

---

## 2. Tarih aralığı seçici

Tek bir global seçici tüm dashboard'ı yönetir:

```text
[ Bugün ][ Dün ][ Bu Hafta ][ Bu Ay ][ Son 7 Gün ][ Son 30 Gün ][ 📅 Özel ]
```

| Seçenek | Tanım (yerel saat, BR-GEN-004) |
|---|---|
| Bugün | Bugün 00:00 → şu an |
| Dün | Dün 00:00 → dün 23:59:59 |
| Bu Hafta | Pazartesi 00:00 → şu an |
| Bu Ay | Ayın 1'i 00:00 → şu an |
| Son 7 Gün | 6 gün önce 00:00 → şu an |
| Son 30 Gün | 29 gün önce 00:00 → şu an |
| Özel | Kullanıcı seçimi (maks. 5 yıl) |

Seçim `app_settings`'te saklanır; uygulama açıldığında son seçim geri gelir.

**Karşılaştırma dönemi** otomatik hesaplanır (aynı uzunlukta önceki dönem) ve KPI kartlarında
yüzde değişim olarak gösterilir.

---

## 3. Bileşenler

### 3.1 KPI kartları (üst şerit)

| Kart | Değer | Alt bilgi | Neden var |
|---|---|---|---|
| **Net Ciro** | ₺ toplam (KDV dahil) | ▲%12 önceki döneme göre | Soru 1 |
| **Net Kâr** | ₺ toplam | Kâr marjı % — **KDV hariç matrah üzerinden** (REQ-VAT-009) | Soru 2 |
| **Satış Adedi** | Fiş sayısı | Ortalama fiş tutarı | Soru 1 |
| **Satılan Ürün** | Toplam adet | — | Soru 1 |
| **Kritik Stok** | Ürün adedi | 🟡 tıklanabilir → liste | Soru 3 |
| **Negatif Stok** | Ürün adedi | 🔴 tıklanabilir → liste | Soru 4 |

- Kritik ve negatif stok kartları **tarih aralığından bağımsızdır** (anlık durum) — bu ayrım
  kartta görsel olarak belirtilir ("şu an").
- Sayı `0` olduğunda kart yeşil ve sakin görünür; dikkat çekmez.

### 3.2 Ciro trendi (ana grafik)

- **Tip:** Çizgi grafik (alan dolgulu)
- **X ekseni:** Aralığa göre otomatik granülerlik
  - ≤ 2 gün → saatlik
  - ≤ 31 gün → günlük
  - ≤ 12 ay → haftalık
  - \> 12 ay → aylık
- **Seriler:** Net ciro (birincil) + önceki dönem (soluk, karşılaştırma)
- **Neden:** Trendi görmek, yoğun saatleri/günleri tespit etmek

### 3.3 Saatlik yoğunluk

- **Tip:** Sütun grafik (0–23 saat)
- **Değer:** Ortalama satış adedi
- **Neden:** Kantinde teneffüs/öğle yoğunluğunu görmek → personel ve hazırlık planlaması.
  Bu, kantin bağlamında gerçekten eyleme dönük bir metriktir.
- Yalnızca aralık ≥ 2 gün olduğunda gösterilir.

### 3.4 En çok satan ürünler

- **Tip:** Yatay sütun, ilk 10
- **Ölçüt seçilebilir:** Adet ▾ / Ciro / Kâr
- **Neden:** Soru 5 — stok planlaması ve raf yerleşimi

### 3.5 Hiç/az satan ürünler

- **Tip:** Tablo, ilk 10 (stoğu olan, aktif ürünler arasından)
- **Sütunlar:** Ürün, stok, son satış tarihi, bağlı sermaye (`stok × alış fiyatı`)
- **Neden:** Ölü stok tespiti — kantinde bağlı sermaye ve bozulma riski

> "En az satan" listesinin **stok değeriyle birlikte** gösterilmesi kritiktir; 0 adet satan
> ama 0 stoğu olan ürün sorun değildir, 0 satan ve 200 adet stoğu olan ürün sorundur.

### 3.6 Kategori dağılımı

- **Tip:** Donut grafik + yanında tablo
- **Değer:** Kategori bazında ciro payı
- **Neden:** Soru 5 — ürün karması analizi
- 8'den fazla kategori varsa ilk 7 + "Diğer"

### 3.7 Kritik stok listesi

- **Tip:** Tablo
- **Sütunlar:** Ürün, mevcut stok, minimum stok, tedarikçi, son giriş tarihi
- **Aksiyon:** "Sipariş listesi olarak dışa aktar" (tedarikçiye göre gruplu CSV)
- **Neden:** Soru 3 — doğrudan eyleme dönük

### 3.8 Son satışlar

- **Tip:** Liste, son 10
- **Sütunlar:** Saat, fiş no, adet, tutar, durum
- **Neden:** Hızlı doğrulama ve yanlış satışa hızlı erişim (iptal/iade için)

---

## 4. Dahil EDİLMEYEN bileşenler ve gerekçeleri

| İstenmiş/akla gelen | Neden yok |
|---|---|
| Tedarikçi bazlı ciro grafiği | Kantin genelde 3–5 tedarikçiyle çalışır; grafik gereksiz. Tedarikçi detay ekranında tablo olarak var ([10 §2.2](10-category-brand-supplier.md)). |
| Kullanıcı bazlı satış performansı | Rol ayrımı yok, tipik olarak 1–2 kullanıcı var. Rapor olarak mevcut ([16](16-reporting.md)). |
| Ödeme yöntemi dağılımı | Yalnızca nakit var — sabit %100 pasta grafiği anlamsız. |
| Stok değeri zaman serisi | Geçmiş stok değerini hesaplamak defter üzerinden pahalı; kantin ölçeğinde karar değeri düşük. |
| Ortalama sepet büyüklüğü grafiği | KPI kartında sayı olarak yeterli. |
| Isı haritası (gün × saat) | Saatlik yoğunluk grafiği aynı bilgiyi daha okunaklı veriyor. Aralık > 30 gün olduğunda değerlendirilebilir. |
| **Kasa durumu / beklenen nakit / kasa farkı** | **V1 kapsamı dışıdır** (proje sahibi kararı). Kasa açılışı, vardiya, sayım ve kapanış özellikleri yoktur → dashboard'da da karşılığı yoktur. [30 §3.1](30-future-scope.md) |

---

## 5. Performans

Dashboard, veri büyüdükçe en çok yavaşlayacak ekrandır. Hedef: **< 1 saniye** (100.000 satış satırıyla).

| Teknik | Uygulama |
|---|---|
| SQL aggregation | Hesaplama Dart'ta değil, `SUM`/`GROUP BY` ile veritabanında yapılır |
| Index | `sales(completed_at)`, `sales(status, completed_at)`, `sale_items(product_id)` — [05 §3](05-database-architecture.md) |
| Paralel yükleme | Her kart/grafik kendi sorgusunu bağımsız çalıştırır; biri yavaşsa diğerleri beklemez |
| Iskelet (skeleton) yükleme | Kartlar boş çerçeveyle görünür, veri gelince dolar |
| Önbellek | Aynı tarih aralığı için sonuçlar bellekte tutulur; satış tamamlandığında geçersizleştirilir |
| Isolate | 1 yıldan uzun aralıklarda aggregation isolate'te çalışır |

> **Ölçüm eşiği:** Herhangi bir dashboard sorgusu 300 ms'yi aşarsa özet (rollup) tablosu
> değerlendirilir. v1'de rollup **yapılmaz** — erken optimizasyon.

---

## 6. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-DASH-001 | Dashboard bugün, dün, bu hafta, bu ay, son 7 gün, son 30 gün ve özel tarih aralığını destekler. |
| REQ-DASH-002 | Tarih aralığı değiştiğinde ilgili tüm kart ve grafikler yeniden hesaplanır. |
| REQ-DASH-003 | KPI kartları önceki eşdeğer dönemle karşılaştırma yüzdesi gösterir. |
| REQ-DASH-004 | Kritik ve negatif stok kartları anlık durumu gösterir ve tarih aralığından etkilenmez. |
| REQ-DASH-005 | Ciro trendi grafiğinin zaman granülerliği seçilen aralığa göre otomatik belirlenir. |
| REQ-DASH-006 | Kritik stok listesi tedarikçiye göre gruplanmış sipariş listesi olarak dışa aktarılabilir. |
| REQ-DASH-007 | Ciro, kâr ve adet metrikleri iptal ve iadeler düşülmüş net değerlerdir. |
| REQ-DASH-008 | Dashboard, 100.000 satış satırı içeren veritabanında 1 saniye içinde yüklenir. |
| REQ-DASH-009 | Kartlar bağımsız yüklenir; bir sorgunun yavaşlığı diğerlerini engellemez. |
| REQ-DASH-010 | Negatif ve kritik stok kartlarından ilgili düzeltme ekranına geçilebilir. |
| REQ-DASH-011 | Dashboard'a erişim, finansal erişim kilidi açılmadan mümkün değildir (bkz. REQ-AUTH-015…028). |
| REQ-DASH-012 | Dashboard verileri, parola doğrulanmadan sorgulanmaz ve ekranda hiçbir biçimde görünmez. |
| REQ-DASH-013 | Kâr metrikleri KDV hariç matrah üzerinden hesaplanır; ciro metrikleri KDV dahil gösterilir ve bu ayrım ekranda belirtilir. |

---

## 7. Acceptance criteria

**REQ-DASH-007**
```text
Given: Bugün 10 satış (₺1.000), 1 iptal (₺100) ve 1 iade (₺50) var
When:  Dashboard "Bugün" aralığında açılıyor
Then:  Net Ciro ₺850 gösterilir
And:   Satış Adedi 9 gösterilir (iptal edilen sayılmaz)
```

**REQ-DASH-004**
```text
Given: minimum_stock > 0 ve stock <= minimum_stock olan 5 ürün var
And:   Stoğu negatif olan 2 ürün var
When:  Tarih aralığı "Dün" olarak değiştiriliyor
Then:  Kritik Stok kartı hâlâ 5 gösterir
And:   Negatif Stok kartı hâlâ 2 gösterir
And:   Kartlarda "şu an" ibaresi bulunur
```

**REQ-DASH-008**
```text
Given: Veritabanında 100.000 sale_items satırı var
And:   Dashboard kilidi açılmış
When:  Dashboard "Son 30 Gün" aralığında açılıyor
Then:  Tüm kartlar ve grafikler 1 saniye içinde dolar
```

**REQ-DASH-011 / REQ-DASH-012**
```text
Given: Kullanıcı giriş yapmış, finansal erişim kilidi kapalı
When:  F6 ile Dashboard açılmak isteniyor
Then:  Finansal erişim parolası ekranı gösterilir
And:   Hiçbir dashboard sorgusu veritabanında çalıştırılmaz
And:   Ekranda hiçbir ciro, kâr veya satış rakamı görünmez
When:  Yanlış parola 5 kez giriliyor
Then:  30 saniye bekleme uygulanır
And:   Başarısız denemeler audit log'a yazılır
When:  Doğru parola giriliyor ve ardından F7 (Raporlar) açılıyor
Then:  Parola tekrar sorulmaz — aynı kilit her iki ekranı da kapsar
```

**REQ-DASH-013**
```text
Given: Dönemde ₺120,00'lik (KDV dahil, %20) tek satış var, ürünün maliyeti ₺60,00
When:  Dashboard açılıyor
Then:  Net Ciro kartı ₺120,00 gösterir
And:   Net Kâr kartı ₺40,00 gösterir (₺100,00 matrah − ₺60,00 maliyet)
```
