# 01 — Proje Genel Bakış

> **Doküman sürümü:** v2 — kapsam sınırları ve terimler sözlüğü güncellendi.

## 1. Proje tanımı

**Kantin Otomasyonu**, küçük/orta ölçekli bir kantinin günlük operasyonunu yöneten,
**tek makinede, internet gerektirmeden çalışan bir Windows masaüstü uygulamasıdır.**

Kapsadığı operasyon alanları:

- Barkodlu ve barkodsuz hızlı satış (POS)
- Ürün, kategori, tedarikçi yönetimi
- Stok hareket defteri tabanlı stok takibi
- Satış iptali ve iade
- Dashboard ve raporlama
- Backup / restore
- Excel / CSV import & export
- Denetim kaydı (audit log)

Temel akış:

```text
Barkod okut → Ürünü bul → Sepete ekle → Satışı tamamla
      → Stoktan düş → Satış kaydı oluştur → Raporlara yansıt
```

Bu proje **bağımsız bir kişisel projedir.** Başka hiçbir proje ile veri, kod veya altyapı paylaşmaz.

---

## 2. Platform kararları

| Konu | Karar |
|---|---|
| Framework | Flutter (stable channel) |
| Production platform | **Windows Desktop** |
| Development / test platformu | **macOS** |
| Backend | **Yok** (bu fazda kesinlikle geliştirilmeyecek) |
| Veri kaynağı | Local relational database (SQLite tabanlı) |
| İnternet bağımlılığı | **Yok** — tüm temel operasyonlar offline çalışır |
| Ödeme | Yalnızca nakit; entegrasyon yok |
| Kullanıcı sayısı | Tek makine, tek eşzamanlı oturum |

Mevcut repo durumu: `flutter create` iskeleti (`lib/main.dart` varsayılan counter uygulaması),
`windows/` ve `macos/` platform klasörleri mevcut, ek dependency yok.

> **macOS ≠ production.** macOS üzerinde UI, veritabanı, satış, stok, backup, restore, import/export
> fonksiyonlarının tamamı test edilir; ancak **dosya yolları, installer, kalıcı veri konumu ve
> barkod klavye girişi Windows üzerinde ayrıca doğrulanmak zorundadır.** Bkz. [24 §5](24-non-functional-requirements.md).

---

## 3. Ürün felsefesi

Bu bir "barkod okut, tutarı topla" uygulaması değildir. Hedeflenen:

> **Satış + stok + ürün + tedarik + raporlama + yedekleme + veri yönetimi bütünü.**

Öncelik sırası (çakışma olduğunda bu sıra belirleyicidir):

1. **Veri bütünlüğü** — Kayıp veya tutarsız satış/stok verisi kabul edilemez.
2. **Satış hızı** — Kasadaki kullanıcı asla beklememelidir.
3. **İzlenebilirlik** — Her stok ve fiyat değişikliği geçmişten okunabilmelidir.
4. **Basitlik** — Gereksiz soyutlama, gereksiz ekran, gereksiz alan yok.
5. **Genişletilebilirlik** — Gelecekte backend eklenebilir olmalı; ama bugün için bedel ödenmemeli.

---

## 4. Kapsam sınırları

### 4.1 Bu fazda YAPILACAK

Bkz. [25 — Functional Requirements](25-functional-requirements.md). Özetle:
authentication, ürün/kategori/tedarikçi yönetimi, barkod sistemi, satış, sepet kalıcılığı,
stok hareketleri, iade/iptal, dashboard, raporlar, audit log, backup/restore, import/export, görsel yönetimi.

### 4.2 Bu fazda YAPILMAYACAK

| Kapsam dışı | Neden |
|---|---|
| Backend / API | Gereksinim değil; local-first hedef |
| Web panel | Backend'e bağımlı |
| Cloud sync | Backend'e bağımlı |
| Online ödeme / banka entegrasyonu | Sadece nakit çalışılacak |
| POS terminali entegrasyonu | Donanım gereksinimi yok |
| Termal yazıcı / fiş basımı | Şu an gereksinim değil |
| Mobil uygulama | Hedef platform masaüstü |
| Multi-store / şube senkronizasyonu | Tek kantin |
| Cloud authentication | Local auth yeterli |
| Cloud backup | Yedek local üretilir; harici ortama taşıma kullanıcı sorumluluğundadır |
| Rol/yetki sistemi | Açıkça kapsam dışı bırakıldı (bkz. [RSK-004](29-risks.md)) |
| **Kasa açılışı / vardiya / kasa sayımı / kasa farkı** | **V1'in satış sistemini bloklamamalıdır** ([30 §3.1](30-future-scope.md)) |
| **Tartılı / ondalık miktarlı satış** | Miktar tam sayıdır (BR-SALE-011) |
| OAuth / JWT / MFA / parola kurtarma | Güvenlik karmaşıklığı büyütülmeyecek |

Bu maddeler [30 — Future Scope](30-future-scope.md) altında, mimarinin bunları engellememesi
şartıyla dokümante edilmiştir.

---

## 5. Kullanıcı profili

Tek tip kullanıcı vardır: **kantin işletmecisi / kasiyer.** Rol ayrımı yoktur.

Varsayılan davranış profili:

- Gün içinde uzun süre satış ekranında kalır.
- Elleri klavye ve barkod okuyucudadır; fare kullanımı yavaşlatıcıdır.
- Teknik kullanıcı değildir; hata mesajları Türkçe ve eyleme dönük olmalıdır.
- Yedek alma gibi bakım işlerini unutur — sistem hatırlatmalıdır.

---

## 6. Donanım varsayımları

| Bileşen | Varsayım |
|---|---|
| Bilgisayar | Windows 10/11 x64, 4 GB+ RAM, HDD veya SSD |
| Ekran | Minimum 1366×768, hedef 1920×1080 |
| Barkod okuyucu | **HID keyboard emulation destekleyen USB/Bluetooth** cihazlar. Referans doğrulama cihazı Sunlux RH10'dur; uygulama bu modele veya herhangi bir SDK'ya bağımlı değildir |
| Yazıcı | Yok |
| Kesintisiz güç | **Yok varsayılır** — elektrik kesintisi normal bir senaryodur |

Elektrik kesintisinin normal senaryo kabul edilmesi, [24 §3 Data Integrity](24-non-functional-requirements.md)
bölümündeki transaction ve WAL kararlarının temel gerekçesidir.

---

## 7. Terimler sözlüğü

| Terim | Anlam |
|---|---|
| **Aktif sepet (Active Cart)** | Henüz tamamlanmamış, üzerinde çalışılan satış taslağı. Satış **değildir**. |
| **Satış (Sale)** | Tamamlanmış, finansal olarak bağlayıcı, silinemez kayıt. |
| **SaleItem** | Satış satırı. Fiyat/KDV/maliyet bilgilerini **snapshot** olarak taşır. |
| **Snapshot** | Kayıt anındaki değerin kopyalanarak saklanması; kaynak değişse bile değişmez. |
| **Stock Movement** | Stoğu değiştiren her olayın defter kaydı (giriş, satış, iade, fire, düzeltme). |
| **Minor unit (kuruş)** | Paranın tam sayı olarak saklandığı en küçük birim. ₺25,50 → `2550`. |
| **Dashboard parolası** | Dashboard ekranına erişimi koruyan, kullanıcı parolasından **ayrı** ve sistem genelinde **tek** olan parola. Rol sistemi değildir. |
| **Matrah** | KDV hariç tutar. Satış fiyatı KDV dahil olduğu için matrah, fiyattan KDV çıkarılarak bulunur. |
| **Net ağırlık / gramaj** | Ambalajdaki miktar (150 g). Yalnızca açıklayıcıdır; hesaba girmez. |
| **Satış birimi** | Ürünün nasıl satıldığı (adet, paket). V1'de miktar daima tam sayıdır. |
| **Basis point (bp)** | Oranların tam sayı gösterimi. %20 KDV → `2000` bp. |
| **Soft delete** | Kaydın fiziksel olarak silinmeyip pasifleştirilmesi. |
| **HID keyboard emulation** | Barkod okuyucunun işletim sistemine klavye olarak görünmesi. |
| **Kritik stok** | `stockQuantity <= minimumStock` ve `minimumStock > 0` olan ürün. |
| **Negatif stok** | `stockQuantity < 0` olan ürün. Sistem buna izin verir, ancak raporlar. |
| **Fire (Waste)** | Bozulma/kırılma nedeniyle stoktan düşülen, satılmayan miktar. |

---

## 8. Başarı kriterleri (Definition of Done — proje seviyesi)

Proje v1.0.0 için "bitti" sayılabilmesi için:

1. Barkod okutmadan satış tamamlamaya kadar geçen sürede uygulama hiçbir noktada 100 ms üzeri takılma yaşamaz.
2. Uygulama satış ortasında kapatıldığında, yeniden açıldığında sepet aynen geri gelir.
3. 10.000 ürün ve 100.000 satış satırı ile dashboard 1 saniyenin altında yüklenir.
4. Backup dosyası başka bir Windows makinede restore edilip aynı verileri gösterir.
5. Uygulamanın yeni sürümü kurulduğunda hiçbir veri kaybolmaz.
6. Her stok değeri, stok hareket defterinden birebir yeniden üretilebilir.

Bkz. [31 — Roadmap](31-roadmap.md) faz çıkış kriterleri.
