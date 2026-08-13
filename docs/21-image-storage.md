# 21 — Ürün Görselleri

> **Doküman sürümü:** v3 — optimizasyon politikası kesinleşti (yapılandırılabilir teknik politika).

## 0. Neyin kesin, neyin açık olduğu

| Konu | Durum |
|---|---|
| Görsellerin dosya sisteminde tutulması | ✅ Kesin (BR-IMG-001) |
| Veritabanına binary gömülmemesi | ✅ Kesin (BR-IMG-001) |
| Kullanıcının dosyadan seçmesi ve dosyanın local'e kopyalanması | ✅ Kesin |
| Yedeğin görselleri kapsaması | ✅ Kesin (BR-IMG-004) |
| Optimizasyonun **yapılacağı** | ✅ Kesin (BR-IMG-002) |
| Optimizasyonun sınır değerleri | ✅ **1000 px / JPEG 85 / maks. 10 MB** — yapılandırılabilir ([OD-016](28-open-decisions.md)) |
| **Orijinal büyük görselin saklanmaması** | ✅ Kesin — yalnızca optimize edilmiş dosya diskte tutulur |

> Bu dokümandaki sayısal sınırlar **yapılandırılabilir teknik politikadır, business rule değildir.**
> Koda sabit yazılmazlar; `app_settings['image_optimization']` üzerinden değiştirilebilirler.
> Başlangıç değerleri: **1000 px / JPEG 85 / maks. 10 MB.**

---

## 1. Saklama stratejisi

> **Karar: Görseller dosya sisteminde tutulur; veritabanında yalnızca göreli dosya yolu saklanır.**

| Yaklaşım | Değerlendirme |
|---|---|
| **Dosya sistemi + DB'de yol** | ✅ DB küçük kalır → yedekleme, sorgu ve migration hızlı. Görsel okuma DB'yi meşgul etmez. |
| DB içinde BLOB | ❌ 100 ürün × 200 KB = 20 MB DB şişmesi. Her `VACUUM INTO` ve migration yavaşlar. Ürün listesi sorguları ağırlaşır. |
| Sadece harici yol referansı (kullanıcının klasörü) | ❌ Kullanıcı dosyayı taşır/siler → kırık referans. Yedeklenemez. |

### Dizin yapısı

```text
<veri dizini>/
├── data/
│   └── canteen.sqlite
├── images/
│   ├── 3f9a2c81-7b4e-4d15-9a03-1c8e5f2b6d70.jpg
│   └── b1c7e903-2d68-4f11-8e5a-9c4d0a3f7b26.png
├── temp/
├── backups/auto/
└── logs/
```

### Dosya adlandırma

> **UUID v4 + orijinal uzantı.** Orijinal dosya adı **kullanılmaz.**

Gerekçeler:
- Türkçe karakter ve boşluk içeren dosya adları platformlar arası sorun çıkarır.
- Aynı adlı iki dosya çakışır.
- Ürün adı değişince dosya adı anlamsızlaşır.
- Kullanıcının dosya adı içinde kişisel bilgi bulunabilir.

DB'de saklanan değer: `images/3f9a2c81-....jpg` (veri dizinine **göreli**).
Mutlak yol saklanmaz — bilgisayar değişince veya kullanıcı adı farklı olunca kırılır.

---

## 2. Görsel ekleme akışı

```text
Ürün formu → [Görsel Seç]
      ▼
Dosya seçici (jpg, jpeg, png, webp)
      ▼
1. Format doğrula (uzantı DEĞİL, dosya içeriği/magic bytes)
2. Boyut kontrolü: yapılandırılmış üst sınırı aşarsa reddet    (varsayılan: 10 MB)
3. Görseli çöz; bozuksa reddet
4. YENİDEN BOYUTLANDIR: yapılandırılmış uzun kenar sınırına    (varsayılan: 1000 px)
5. Yeniden kodla: yapılandırılmış kalite ile                    (varsayılan: JPEG 85)
   PNG şeffaflık gerekiyorsa PNG kalır
6. temp/ klasörüne UUID adıyla yaz
7. Ürün KAYDEDİLİRKEN images/ altına taşı (aynı transaction mantığı)
   ⚠ ORİJİNAL BÜYÜK DOSYA SAKLANMAZ — yalnızca optimize edilmiş kopya kalır
8. products.image_path güncelle
9. audit_logs: productImageChanged
```

### Neden optimizasyon zorunlu (BR-IMG-002)

| | Ham dosya | İşlenmiş (varsayılan profil) |
|---|---|---|
| Tipik telefon fotoğrafı | 3–5 MB | ~80–120 KB |
| 500 ürün | 1,5–2,5 GB | ~40–60 MB |
| Yedek dosyası | Taşınamaz | Taşınabilir |

Optimizasyon yapılmazsa yedek dosyası kullanılamaz hale gelir — bu **kesin** bir gerekliliktir
(BR-IMG-002). Sınır değerleri yapılandırılabilir teknik politikadır
([OD-016](28-open-decisions.md)); başlangıç profili 1000 px / JPEG 85'tir.

---

## 3. Görüntüleme

| Yer | Boyut | Kaynak |
|---|---|---|
| Satış ekranı ürün kartı | 64×64 | Bellek önbelleğinden |
| Ürün listesi satırı | 40×40 | Bellek önbelleğinden |
| Ürün detay/form | 200×200 | Diskten |

- Flutter'ın `ImageCache`'i kullanılır; boyut sınırı 200 görsel / 50 MB.
- Görsel yoksa veya okunamıyorsa **kategori ikonu** gösterilir — hata gösterilmez.
- Ürün listesi kaydırılırken görseller tembel (lazy) yüklenir.

---

## 4. Orphan (sahipsiz) dosya yönetimi

İki yönlü tutarsızlık olabilir:

| Durum | Adı | Etki |
|---|---|---|
| Diskte var, DB'de referansı yok | **Orphan** | Disk israfı, yedek şişmesi |
| DB'de referans var, diskte yok | **Kırık referans** | Görsel gösterilemez |

### Orphan oluşma anları

```text
1. Kullanıcı görseli değiştirdi        → eski dosya sahipsiz kaldı
2. Kullanıcı görseli kaldırdı          → dosya sahipsiz kaldı
3. Ürün formu kaydedilmeden kapatıldı  → temp/'te dosya kaldı
4. Backup restore                      → eski görseller sahipsiz kaldı
5. Uygulama görsel yazarken çöktü      → yarım dosya
```

### Strateji: geciktirmeli silme + tarama

> **Görsel dosyaları asla anında silinmez.**

Gerekçe: Ürün kaydı geri alınırsa (transaction rollback, kullanıcı vazgeçti) dosya silinmiş olur
ve veri kaybı yaşanır. Dosya sistemi transaction'a katılmaz.

```text
Görsel değiştirildi/kaldırıldı
      ▼
Eski dosya  images/xxx.jpg  →  images/.trash/xxx.jpg  (taşınır)
      ▼
Uygulama açılışında (arka planda, düşük öncelikli):
   1. .trash/ içindeki 7 günden eski dosyaları sil
   2. temp/ içindeki 1 günden eski dosyaları sil
   3. ORPHAN TARAMASI:
        images/ içindeki her dosya için DB'de referans var mı?
        yoksa → .trash/'a taşı
   4. KIRIK REFERANS TARAMASI:
        products.image_path dolu ama dosya yok mu?
        varsa → products.image_path = NULL, log'a yaz
```

Tarama yalnızca uygulama açılışında ve haftada en fazla bir kez çalışır (son tarama tarihi
`app_settings`'te tutulur). 500 dosyalık bir klasörde < 100 ms sürer.

**Ayarlar → Bakım** altında elle çalıştırma seçeneği bulunur ve sonuç raporlanır
("12 sahipsiz dosya temizlendi, 3,4 MB yer açıldı").

---

## 5. Sınırlar

| Sınır | Durum | Varsayılan değer | Gerekçe |
|---|---|---|---|
| Ürün başına görsel | ✅ **Kesin** | 1 | BR-PROD-012 |
| Optimizasyon yapılması | ✅ **Kesin** | — | BR-IMG-002 |
| Maksimum yükleme boyutu | ✅ Yapılandırılabilir | 10 MB | Kullanıcı hatasını yakalar |
| İşlenmiş uzun kenar | ✅ Yapılandırılabilir | 1000 px | Masaüstü detay ekranı için yeterli |
| Yeniden kodlama kalitesi | ✅ Yapılandırılabilir | JPEG 85 | Kalite/boyut dengesi |
| Desteklenen formatlar | ✅ Yapılandırılabilir | jpg, jpeg, png, webp | |
| Toplam görsel klasörü uyarısı | ✅ Yapılandırılabilir | 500 MB | Uyarılır, engellenmez |

Bu değerler `app_settings['image_optimization']` içinde saklanır ve kullanıcı/geliştirici
tarafından değiştirilebilir. Koda sabit yazılmazlar ([OD-016](28-open-decisions.md)).

---

## 6. Backup ile ilişki

- Yedek yalnızca **DB'de referansı olan** görselleri içerir ([19 §3](19-backup-restore.md) adım 4).
  `.trash/` ve `temp/` yedeklenmez.
- Restore'da eksik görsel **engelleyici değildir**; ürün varsayılan ikonla gösterilir ve
  kullanıcı "N görsel eksik" uyarısı alır (REQ-BKUP-018).
- Restore sonrası eski `images.old_<ts>/` klasörü 7 gün saklanır, sonra silinir.

---

## 7. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-IMG-001 | Ürün görselleri dosya sisteminde saklanır; veritabanında yalnızca göreli yol tutulur. |
| REQ-IMG-002 | Görsel dosyaları UUID ile adlandırılır; orijinal dosya adı kullanılmaz. |
| REQ-IMG-003 | Yüklenen görseller, yapılandırılmış sınır değerlerine göre yeniden boyutlandırılır ve yeniden kodlanır; sınır değerleri koda sabit yazılmaz. |
| REQ-IMG-004 | Yapılandırılmış üst sınırı aşan veya bozuk dosyalar reddedilir. |
| REQ-IMG-005 | Görsel formatı dosya içeriğinden doğrulanır, uzantıdan değil. |
| REQ-IMG-006 | Görsel dosyaları anında silinmez; çöp klasörüne taşınır ve gecikmeli temizlenir. |
| REQ-IMG-007 | Uygulama açılışında sahipsiz görsel ve kırık referans taraması yapılır. |
| REQ-IMG-008 | Kırık referanslar temizlenir ve ürün varsayılan ikonla gösterilir. |
| REQ-IMG-009 | Görseli bulunamayan ürün hata göstermez. |
| REQ-IMG-010 | Yedek dosyası yalnızca kullanımdaki görselleri içerir. |
| REQ-IMG-011 | Bir ürünün en fazla bir görseli olabilir. |
| REQ-IMG-012 | Kullanıcı görsel bakım işlemini elle çalıştırıp sonucunu görebilir. |
| REQ-IMG-013 | Orijinal (optimize edilmemiş) görsel dosyası saklanmaz; yalnızca optimize edilmiş kopya diskte tutulur. |

---

## 8. Acceptance criteria

**REQ-IMG-003 / REQ-IMG-004**
```text
Given: Optimizasyon profili "uzun kenar 1000 px, JPEG 85" olarak yapılandırılmış
And:   Kullanıcı 4032×3024 piksel, 4,8 MB bir telefon fotoğrafı seçiyor
When:  Görsel ürüne ekleniyor
Then:  Diskteki dosyanın uzun kenarı en fazla 1000 pikseldir
And:   Dosya boyutu ham dosyanın %10'undan küçüktür
And:   Dosya adı bir UUID'dir
When:  Profil değiştirilip yeni bir görsel yükleniyor
Then:  Yeni sınır değerleri uygulanır (mevcut görseller etkilenmez)
```

**REQ-IMG-006 / REQ-IMG-007**
```text
Given: Bir ürünün görseli değiştiriliyor
When:  Kayıt tamamlanıyor
Then:  Eski dosya images/ klasöründen .trash/ klasörüne taşınmıştır
And:   Eski dosya hemen silinmemiştir
When:  8 gün sonra uygulama açılıyor
Then:  Eski dosya kalıcı olarak silinir
```

**REQ-IMG-008 / REQ-IMG-009**
```text
Given: products.image_path dolu ama dosya diskten elle silinmiş
When:  Ürün listesi açılıyor
Then:  Ürün kategori ikonuyla gösterilir
And:   Hata mesajı veya kırık görsel ikonu gösterilmez
When:  Uygulama yeniden açılıyor ve tarama çalışıyor
Then:  products.image_path NULL yapılır
And:   Olay log dosyasına yazılır
```
