# 30 — Kapsam Dışı ve Gelecek Genişlemeler

> **Doküman sürümü:** v3 — recovery code ve Raporlar kilidi **V1'e alındı**, bu listeden çıkarıldı.

Bu doküman iki işe yarar:
1. **v1'de yapılmayacakları netleştirmek** — kapsam büyümesine karşı savunma ([RSK-012](29-risks.md)).
2. Bugünün mimarisinin bu genişlemeleri **engellemediğini** göstermek.

> **Kural:** Bu dokümandaki hiçbir madde için bugün kod yazılmaz, soyutlama eklenmez, alan açılmaz.
> Yalnızca "eklendiğinde ne gerekir" analizi yapılır.

---

## 1. Kesin olarak kapsam dışı

Proje sahibi tarafından açıkça V1 dışında bırakılmıştır.

| Konu | Neden şimdi yok |
|---|---|
| Backend / REST API | Gereksinim değil; local-first hedef |
| Web paneli | Backend'e bağımlı |
| Cloud senkronizasyon | Backend'e bağımlı |
| **Cloud backup** | Yedek local üretilir; harici ortama taşıma kullanıcı sorumluluğundadır |
| Online ödeme / banka entegrasyonu | Yalnızca nakit çalışılacak |
| POS terminali / ödeme cihazı | Donanım gereksinimi yok |
| Termal yazıcı / fiş basımı | Şu an gereksinim değil |
| Mobil uygulama | Hedef platform masaüstü |
| Multi-store / şube senkronizasyonu | Tek kantin |
| Cloud authentication | Local auth yeterli |
| **OAuth / JWT / MFA / parola kurtarma** | Güvenlik karmaşıklığı gereksiz büyütülmeyecek (BR-SEC-001 dışında) |
| Rol / yetki sistemi | Açıkça kapsam dışı (BR-AUTH-002, [RSK-004](29-risks.md)) |
| **Kasa açılışı, vardiya, kasa sayımı, kasa kapanışı, beklenen nakit, kasa farkı** | **V1'in satış sistemini bloklamamalıdır** — §3.1 |
| **Tartılı / ondalık miktarlı satış** | BR-SALE-011: miktar tam sayıdır — §3.2 |
| Müşteri / cari hesap / veresiye takibi | İstenmedi |
| Kampanya ve indirim kuralları | [OD-007](28-open-decisions.md) |
| Çoklu dil | Tek dil: Türkçe |

> **v1 dokümantasyonunda kasa/vardiya kapanışı bir "eksik" olarak işaretlenmiş ve kapsama
> alınması önerilmişti. Bu öneri proje sahibi tarafından reddedilmiştir** ve buraya taşınmıştır.
> Dashboard, raporlar veya veri modelinde kasa ile ilgili hiçbir bileşen bulunmaz.

---

## 2. Gelecekte backend stratejisi

> **Bugün hiçbir backend kodu yazılmayacaktır.** Bu bölüm yalnızca "yolu kapatmama" analizidir.

### 2.1 Bugünkü yapı

```text
Presentation
     ↓
Application (Services)
     ↓
Domain (saf model + hesap)
     ↓
Repository Interface        ← ProductRepository, SaleRepository, StockRepository
     ↓
LocalRepository (Drift)
```

Interface'ler yalnızca bu üç repository için var ([03 §4](03-architecture.md)) —
diğerleri doğrudan DAO kullanıyor. Bu, **gelecek için ödenen tek maliyettir** ve zaten
test edilebilirlik için gerekli olduğundan gerçek bir ek maliyet değildir.

### 2.2 Backend eklenirse

```text
Repository Interface
├── LocalRepository        (mevcut — offline daima çalışır)
└── SyncingRepository      (yeni — local + remote)
```

Local-first korunur: uygulama **her zaman** local veritabanına yazar; senkronizasyon arka planda yapılır.
İnternet kesilince hiçbir şey durmaz. Bu, BR-GEN-001'in doğal devamıdır.

### 2.3 Bugünden itibaren kolaylaştıran kararlar

| Karar | Backend'e faydası |
|---|---|
| Tüm zamanlar UTC (BR-GEN-004) | Sunucu/istemci saat farkı sorunu yok |
| Hard delete yok (BR-GEN-002) | Silme senkronizasyonu (tombstone) sorunu yok |
| Stok defteri (BR-STOCK-001) | Hareketler doğal olarak idempotent olay kayıtları — çakışma çözümü kolay |
| Snapshot'lı satış satırları | Satış kayıtları kendi kendine yeterli; sunucudan veri çekmeye gerek yok |
| Audit log | Değişiklik akışı zaten kayıtlı |
| Tam sayı para | Serileştirmede kayan nokta hatası yok |

### 2.4 Backend eklenirse gerekecekler

| İhtiyaç | Not |
|---|---|
| Global benzersiz kimlikler | `INTEGER PK` yerine UUID veya `<cihaz>-<sayaç>` — **migration gerektirir** |
| `synced_at` / `dirty` alanları | Her senkronize edilecek tabloya |
| Çakışma çözüm politikası | Ürün fiyatı iki yerde değişirse hangisi kazanır? |
| Kimlik doğrulama | Token, yenileme, çıkış |
| Şema versiyonu uyumu | İstemci ve sunucu farklı sürümlerde olabilir |

> **Kimlik stratejisi, backend'e geçişin en maliyetli kalemidir.**
> Bugün UUID kullanmak; sorgu performansını ve index boyutunu bugünkü tek makinelik senaryoda
> gereksiz yere kötüleştirir. Bilinçli olarak `INTEGER PK` seçilmiştir. Backend eklenirse
> bir kimlik migration'ı yapılacaktır — bu, bugün ödenmeyen ve muhtemelen hiç ödenmeyecek bir maliyettir.

---

## 3. Değerlendirilmiş ama v1'e alınmamış özellikler

### 3.1 Kasa / vardiya yönetimi — V1 dışı, ileride eklenebilir

> Proje sahibi kararıyla **V1 kapsamı dışındadır.** Aşağıdaki analiz yalnızca ileride
> eklenmek istenirse ne gerekeceğini gösterir. **Bugün hiçbir tablo, alan veya ekran açılmaz.**

| Bileşen | Ne gerekir |
|---|---|
| Kasa açılışı / kapanışı | `cash_sessions` tablosu (açılış tutarı, kapanış tutarı, açan/kapatan kullanıcı, zaman aralığı) |
| Kasa sayımı | `cash_counts` tablosu veya kapanış kaydının alanları |
| Beklenen nakit | `Σ(dönemdeki nakit satış) + açılış tutarı` — mevcut `sales` verisinden hesaplanabilir |
| Kasa farkı | Sayılan − beklenen; raporlanır |
| Vardiya bazlı rapor | `sales.completed_at` zaten var; vardiya aralığına göre filtrelenir |

**Neden bugün eklenmiyor:** Satış sistemini bloklamamalıdır. Ayrıca vardiya yönetimi,
rol sistemi olmadan sınırlı anlam taşır (herkes her vardiyayı açıp kapatabilir).

**Mevcut mimarinin engel olmaması:** `sales` kayıtları zaten zaman damgalı, kullanıcı bilgili ve
nakit tutarlıdır. Kasa modülü eklendiğinde geçmiş veriler üzerinden de çalışabilir —
**geriye dönük veri kaybı yoktur.**

### 3.2 Tartılı satış — V1 dışı, ileride eklenebilir

> BR-SALE-011 gereği V1'de satış miktarı **tam sayıdır.**

| Ne gerekir | Not |
|---|---|
| `quantity` → `quantity_milli` migration | Düz bir çarpma işlemi (× 1000), risksiz |
| Ürün bazında "tartılı mı" bayrağı | `products.is_weighted` |
| Birim entity'si | Birim artık hesaba girer → `units` tablosu anlamlı hale gelir ([10 §4.1](10-category-brand-supplier.md)) |
| Fiyat modeli | Birim fiyat "kg başına" olur; satır tutarı `unitPrice × quantityMilli / 1000` |
| Terazi entegrasyonu | Ayrı bir donanım konusu; HID veya seri port |

**Mevcut hazırlık:** Ürün üzerinde `net_weight_value` / `net_weight_unit` alanları zaten var
ancak bunlar **açıklayıcıdır** (150 g'lık paket) — tartılı satışla karıştırılmamalıdır.

### 3.3 Yakın vadede muhtemel (v1.1 – v1.3)

| Özellik | Ne gerekir | Neden şimdi değil |
|---|---|---|
| **Fiş yazdırma (termal)** | ESC/POS komutları, yazıcı seçimi, fiş şablonu | Donanım yok; satış akışını yavaşlatır |
| **Satır/fiş bazlı indirim** | `discount_total_minor` zaten şemada | [OD-007](28-open-decisions.md) |
| **Ürün arama FTS5** | Sanal tablo + trigger | 5.000 ürüne kadar gerekmiyor ([05 §3](05-database-architecture.md)) |
| **Otomatik güncelleme** | Sürüm kontrol servisi (internet gerekir) | Offline ilkesiyle çelişiyor; manuel yeterli |
| **Yedek şifreleme** | Parolalı arşiv | Yedek artık düz metin parola içermiyor → risk düşük |
| **Fiyat etiketi / raf etiketi basımı** | Etiket şablonu + yazıcı | İstenmedi |

### 3.4 Orta vadede olası

| Özellik | Not |
|---|---|
| Rol sistemi | `users.role` kolonu + yetki kontrolleri — düşük maliyetli migration |
| **Marka entity'si** | `products.brand` metninden veri taşıma ([10 §3.1](10-category-brand-supplier.md)) — yol açık |
| **Birim entity'si** | `products.sales_unit` metninden ([10 §4.1](10-category-brand-supplier.md)) — tartılı satışla birlikte anlamlı |
| **Kullanıcıya özel favoriler** | `user_favorites` tablosu — yalnızca rol/kişiselleştirme gelirse |
| **Ödeme yöntemi çeşitlenmesi** | `payments` tablosu — kart/karma ödeme gelirse |
| Çoklu tedarikçi (ürün başına) | `product_suppliers` ara tablosu |
| Alt kategoriler | `categories.parent_id` — raporlama karmaşıklaşır |
| Satış satırında tedarikçi snapshot'ı | Geçmiş tedarikçi cirosu doğruluğu ([10 §2.2](10-category-brand-supplier.md)) |
| Sipariş yönetimi | Tedarikçiye sipariş → gelen mal kabul eşleştirme |
| Son kullanma tarihi takibi | Parti (lot) bazlı stok — FIFO maliyetle birlikte anlamlı |
| Ürün varyantları | Beden/renk gibi; kantinde gereksiz |
| Rapor özet (rollup) tabloları | Dashboard 300 ms'yi aşarsa ([15 §5](15-dashboard.md)) |

### 3.3 Uzak / muhtemelen hiç

Backend, web paneli, mobil uygulama, cloud sync, çok şubeli yapı, e-fatura/e-arşiv entegrasyonu,
müşteri sadakat programı, barkod üretimi ve basımı, sesli komut, yapay zekâ destekli sipariş önerisi.

---

## 4. Genişlemeyi engellemeyen tasarım kararları

Aşağıdakiler bugünkü ihtiyaç için **de** doğru olan, ama gelecekte kapı açık bırakan kararlardır.
Hiçbiri "gelecek için" ödenen bir maliyet değildir:

| Karar | Bugünkü faydası | Gelecekteki faydası |
|---|---|---|
| Stok defteri | İzlenebilirlik, hata ayıklama | Parti takibi, FIFO, senkronizasyon |
| Fiyat/maliyet/KDV snapshot'ı | Geçmiş doğruluğu | İndirim raporlaması, e-fatura |
| Ayrı `Return` entity'si | Kısmi iade | İade nedeni analizi |
| `discount_total_minor` alanı (v1'de 0) | — | İndirim sistemi (şema değişikliği gerekmez) |
| Yönetilebilir KDV oranları | Mevzuat değişimi | Çoklu oran raporlaması |
| Audit log | Denetim | Değişiklik akışı senkronizasyonu |
| Katmanlı mimari | Test edilebilirlik | Backend eklenmesi |
| Repository interface (3 adet) | Servis testleri | Uzak veri kaynağı |
| Salt'lı parola hash'i | Yedek sızıntısı riskini kapatır | Sunucu tarafı kimlik doğrulamaya taşınabilir |
| Dashboard kilidinin ayrı servis olması | Dashboard koruması | Aynı kilit Raporlar'a veya rol sistemine genişletilebilir |
| `sales` üzerinde nakit ve zaman bilgisi | Nakit hesaplama | Kasa/vardiya modülü geçmiş veriyle çalışabilir |

> **Not:** Bu tablodaki hiçbir karar "gelecek için" ödenmiş bir maliyet değildir.
> Her biri bugünkü gereksinim için de doğru olan kararlardır; genişletilebilirlik yan faydadır.

---

## 5. Kapsam dışı taleplerin yönetimi

Geliştirme sırasında yeni bir fikir ortaya çıktığında:

```text
Yeni fikir
     ▼
v1'in 🔴 Must requirement'larından birini mi karşılıyor?
     ├── Evet → zaten kapsamda, [25](25-functional-requirements.md)'e bak
     └── Hayır
           ▼
     Olmadan v1 kullanılabilir mi?
           ├── Evet → BU DOKÜMANA yaz, faza sokma
           └── Hayır → gerçekten Must mı? Kanıtla, [25](25-functional-requirements.md)'e ekle,
                       fazı ve takvimi güncelle
```
