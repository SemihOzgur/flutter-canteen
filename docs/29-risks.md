# 29 — Risk Kaydı

> **Doküman sürümü:** v3 — RSK-017 kapandı; RSK-016 recovery code ile 🟡'dan 🟢'a düştü.
> Aktif risk sayısı: 13 (4 kritik).

Değerlendirme: **Olasılık × Etki**. Etki, veri kaybı ve finansal doğruluk üzerinden ölçülür.

## Aktif riskler

| ID | Risk | Olasılık | Etki | Seviye |
|---|---|---|---|---|
| [RSK-002](#rsk-002) | Güncellemede veri kaybı | Düşük | **Kritik** | 🔴 |
| [RSK-003](#rsk-003) | Aynı DB'ye iki uygulama örneği | Orta | Yüksek | 🔴 |
| [RSK-005](#rsk-005) | Tek kopya veri — disk arızası | Orta | **Kritik** | 🔴 |
| [RSK-011](#rsk-011) | Migration hatası | Düşük | **Kritik** | 🔴 |
| [RSK-016](#rsk-016) | Dashboard parolası **ve** recovery code'un birlikte kaybedilmesi | Düşük | Düşük | 🟢 |
| [RSK-004](#rsk-004) | Rol/yetki sisteminin olmaması | Yüksek | Orta | 🟡 |
| [RSK-006](#rsk-006) | Klavye düzeni barkod uyumsuzluğu | Orta | Orta | 🟡 |
| [RSK-007](#rsk-007) | macOS'ta çalışanın Windows'ta çalışmaması | Yüksek | Orta | 🟡 |
| [RSK-008](#rsk-008) | Denormalize stok değerinin defterden sapması | Düşük | Yüksek | 🟡 |
| [RSK-010](#rsk-010) | Negatif stoğun normalleşmesi | Yüksek | Orta | 🟡 |
| [RSK-012](#rsk-012) | Kapsam büyümesi | Yüksek | Orta | 🟡 |
| [RSK-013](#rsk-013) | Görsel klasörünün kontrolsüz büyümesi | Orta | Düşük | 🟢 |
| [RSK-014](#rsk-014) | Sistem saati değişikliği | Düşük | Orta | 🟢 |
| [RSK-015](#rsk-015) | Antivirüs / SmartScreen engellemesi | Orta | Düşük | 🟢 |

## Kapanan riskler

| ID | Risk | Nasıl kapandı |
|---|---|---|
| ~~RSK-001~~ | Yedek dosyasında düz metin parola | ✅ **BR-SEC-001 + BR-AUTH-011** — parolalar salt'lı SHA-256 olarak saklanır; hiçbir yerde düz metin bulunmaz |
| ~~RSK-009~~ | KDV kararının geç verilmesi | ✅ **BR-VAT-003** — KDV dahil kararı kesinleşti; geriye dönük fiyat dönüşümü riski ortadan kalktı |
| ~~RSK-017~~ | Dashboard kilidinin Raporlar'ı kapsamaması | ✅ **BR-AUTH-013** — kilit kapsamı Dashboard + Raporlar olarak genişletildi |

---

## RSK-002
### Güncellemede veri kaybı

**Risk:** Yeni sürüm kurulumu veritabanını, görselleri veya ayarları siler.
**Projenin en yıkıcı başarısızlık senaryosu** — yılların satış geçmişi kaybolur.

**Nasıl oluşur:** veri kurulum dizininde tutulursa installer temizlerken siler; migration veri kaybettiren bir işlem içerirse; installer "önceki sürümü kaldır" adımında veri klasörünü de silerse.

**Azaltma:**
- BR-DATA-001: veri **daima** `%APPDATA%\CanteenApp\` altında
- REQ-MIG-007: veri kaybettiren migration yasak
- REQ-MIG-002: migration öncesi otomatik snapshot
- Installer betiği veri dizinine dokunmayacak şekilde yazılır ve **test edilir** (W5, W6)

**Test:** Manuel test W5/W6 her sürümde zorunlu.

---

## RSK-003
### Aynı DB'ye iki uygulama örneği

**Risk:** İki örnek aynı SQLite dosyasına yazar. WAL çoklu bağlantıyı destekler ama uygulama seviyesindeki durum (aktif sepet, satış numarası sayacı, bellek önbelleği) bozulur: iki farklı sepet, çakışan satış numarası, kaybolan satırlar.

**Azaltma:** BR-GEN-005 / REQ-ARCH-005 — veri dizininde kilit dosyası; ikinci örnek mevcut pencereyi öne getirip kapanır; çökme sonrası kalan kilit PID kontrolüyle temizlenir.

**Test:** W11.

---

## RSK-005
### Tek kopya veri — disk arızası

**Risk:** Backend yok, cloud yok, cloud backup V1'de yok. Veri tek diskte. Disk arızası, ransomware veya bilgisayarın bozulması **tüm satış geçmişini yok eder.**

**Azaltma:**
- Yedekleme sistemi ([19](19-backup-restore.md))
- 7 gün yedek alınmadığında uyarı (REQ-BKUP-016)
- Kapanışta otomatik günlük yedek
- **Kullanıcıya açık uyarı:** "Aynı diskteki yedek disk arızasına karşı korumaz — USB veya harici bir konuma kopyalayın"

**Kalan risk:** Yedeğin harici ortama taşınması **kullanıcı sorumluluğundadır** (proje sahibi kararı). Uygulama bunu zorlayamaz, yalnızca hatırlatır. Backend'siz bir sistemin kaçınılmaz sonucudur ve bilinçli kabul edilmiştir.

---

## RSK-011
### Migration hatası

**Risk:** Hatalı bir migration adımı veriyi bozar veya siler.

**Azaltma:** Pre-migration otomatik snapshot + doğrulama (REQ-MIG-002); tek transaction (REQ-MIG-004); veri kaybettiren işlem yasağı (REQ-MIG-007); yarım migration kurtarma (REQ-MIG-006); şema anlık görüntüleriyle migration testleri ([27 §6.4](27-testing-strategy.md)).

---

## RSK-016
### Dashboard parolası ve recovery code'un birlikte kaybedilmesi

> **v3'te büyük ölçüde azaltıldı.** Önceki sürümde kurtarma yolu hiç yoktu (🟡 Orta);
> recovery code ile artık yalnızca **her ikisinin birden** kaybedilmesi durumu kalmıştır (🟢 Düşük).

**Risk:** Kullanıcı hem dashboard parolasını unutur hem de kurulumda verilen recovery code'u
kaybederse finansal erişim kurtarılamaz.

**Azaltma (uygulanmış):**
- Kurulumda recovery code üretilir ve kullanıcı **"kaydettim" onayı vermeden kurulum ilerlemez** (REQ-AUTH-024)
- Kopyala / dosyaya kaydet seçenekleri sunulur
- Recovery code kullanıldığında **otomatik olarak yenisi üretilir** (BR-AUTH-017) — kurtarma yeteneği süreklidir
- Kullanıcı, parolasını bildiği sürece Ayarlar'dan istediği zaman yeni bir kod üretebilir (REQ-AUTH-028)

**Kalan etkinin sınırı:** Bu durumda bile **satış, ürün yönetimi, stok, iade, yedekleme ve
import/export dahil tüm operasyonel işlevler çalışmaya devam eder.** Yalnızca Dashboard ve
Raporlar erişilemez olur. Veri kaybı yaşanmaz.

**Son çare:** Dashboard parolasının bilindiği bir tarihe ait yedeğin geri yüklenmesi
(o tarihten sonraki veriyi kaybettirir — pratikte önerilmez).

---

## RSK-004
### Rol/yetki sisteminin olmaması

**Risk:** Tüm kullanıcılar her şeyi yapabilir: satış iptali, ürün pasifleştirme, fiyat değiştirme, **yedekten geri yükleme** (tüm veriyi değiştirme).

**Neden var:** Rol sistemi proje sahibi tarafından açıkça kapsam dışı bırakılmıştır (BR-AUTH-002).

**Azaltma:**
- Audit log her kritik işlemi `user_id` ile kaydeder ([18](18-audit-log.md)) — **tespit edilebilir, engellenemez**
- Yıkıcı işlemler (restore) yazarak onay ister
- Satış ve stok hareketleri silinemez
- Finansal erişim kilidi, Dashboard ve Raporlar için ayrı bir sınır oluşturur (BR-AUTH-013)

**Kalan risk:** Kabul edilmiştir. Rol ihtiyacı doğarsa `users.role` kolonu eklemek düşük maliyetli bir migration'dır ([30 §3.2](30-future-scope.md)).

---

## RSK-006
### Klavye düzeni barkod uyumsuzluğu

**Risk:** Windows'ta Türkçe Q/F klavye düzeni aktifken alfanümerik barkodlardaki `-`, `.`, `/`, `+`, `%` karakterleri yanlış yorumlanabilir. Sayısal EAN/UPC barkodlar etkilenmez.

**Azaltma:** Barkod tanılama ekranı (REQ-BARC-010); scanner'ın US klavye düzenine alınması önerisi; manuel test W3.

**Kalan risk:** Yalnızca alfanümerik barkodlu ürünlerde; kantinde nadirdir.

---

## RSK-007
### macOS'ta çalışanın Windows'ta çalışmaması

**Risk:** Geliştirme macOS'ta, production Windows'ta. Farklı davranan alanlar: dosya kilitleme (Windows daha katı), yol ayırıcı ve uzunluk sınırı, klavye olayları, DPI ölçekleme, dosya izinleri.

**Azaltma:** Her faz sonunda Windows doğrulaması ([31](31-roadmap.md)); yol işlemlerinde `path` paketi; dosya taşıma öncesi DB bağlantısının kapatılması; manuel test listesi W1–W15.

---

## RSK-008
### Denormalize stok değerinin defterden sapması

**Risk:** `products.stock_quantity` bir önbellektir. Bir kod yolu defteri yazıp özeti güncellemezse stok sessizce yanlışa döner ve **haftalarca fark edilmez.**

**Azaltma:** BR-STOCK-002 (aynı transaction); tüm stok değişikliklerinin tek servisten (`StockService`) geçmesi; tutarlılık kontrolü ([24 §3.3](24-non-functional-requirements.md)); her yedek öncesi hızlı kontrol; property test ([27 §3.4](27-testing-strategy.md)).

---

## RSK-010
### Negatif stoğun normalleşmesi

**Risk:** Negatif stoğa izin verildiği için ([13 §4](13-stock-system.md)) kullanıcı uyarıları kapatabilir ve zamanla stok verisi anlamsızlaşır; kritik stok ve sipariş önerileri güvenilmez olur.

**Azaltma:** Negatif stok dashboard'da sürekli görünür; ayrı rapor (R9) + karttan doğrudan düzeltme; uyarı kapalıyken bile satırlar görsel olarak işaretlenir.

**Kalan risk:** Kullanıcı davranışına bağlıdır. Bilinçli tasarım ödünüdür (satış hızı > anlık stok doğruluğu — BR-STOCK-006).

---

## RSK-012
### Kapsam büyümesi

**Risk:** 285 requirement'lık bir kapsam var. "Bu da olsa iyi olur" eklemeleri v1'in hiç bitmemesine yol açar.

**Azaltma:**
- MoSCoW önceliklendirmesi ([25](25-functional-requirements.md))
- Faz çıkış kriterleri ([31](31-roadmap.md))
- Yeni fikirler doğrudan [30 — Future Scope](30-future-scope.md)'a yazılır
- **v2 revizyonunda kanıtlandı:** kasa/vardiya önerisi proje sahibi tarafından reddedilip Future Scope'a taşındı — bu mekanizma çalışıyor

---

## RSK-013
### Görsel klasörünün kontrolsüz büyümesi

**Risk:** Ham telefon fotoğrafları (3–5 MB) doğrudan saklanırsa 500 ürün ≈ 2 GB; yedek dosyası taşınamaz.

**Azaltma:** Optimizasyon zorunludur (BR-IMG-002); yükleme boyutu sınırı; orphan temizliği. Sınır değerleri [OD-016](28-open-decisions.md) kapandığında netleşir — **karar gecikirse risk açık kalır.**

---

## RSK-014
### Sistem saati değişikliği

**Risk:** Sistem saati değiştirilirse satış tarihleri tutarsız olur; geriye alınmış saatle yapılan satışlar geçmiş dönem raporlarını değiştirir.

**Azaltma:** Zamanlar UTC saklanır (BR-GEN-004); açılışta son satış tarihi kontrol edilir, sistem saati bundan geriyse kullanıcı uyarılır.

---

## RSK-015
### Antivirüs / SmartScreen engellemesi

**Risk:** İmzasız installer SmartScreen uyarısı verir; antivirüs `.canteenbackup` dosyasını şüpheli görebilir.

**Azaltma:** Yedek standart bir arşiv formatıdır (şifreli/özel değil) — taranabilir; kullanıcıya kurulumda ne bekleyeceği anlatılır; kod imzalama [OD-013](28-open-decisions.md) kapsamında.

---

## Risk izleme

| Ne zaman | Ne yapılır |
|---|---|
| Her faz başında | İlgili riskler gözden geçirilir |
| Her faz sonunda | Azaltma önlemleri uygulandı mı doğrulanır |
| Yeni risk tespit edilince | Bu dokümana eklenir, ilgili requirement güncellenir |
| v1.0.0 öncesi | Tüm 🔴 risklerin azaltmaları test edilmiş olmalıdır |
