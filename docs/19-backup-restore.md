# 19 — Yedekleme ve Geri Yükleme

> **Doküman sürümü:** v2 — düz metin parola riski ortadan kalktı (BR-SEC-001);
> yedek formatının hangi kısmının kesin, hangisinin açık olduğu netleştirildi.

## 1. Neden kritik

Backend yok, cloud yok. **Tek kopya veri, tek diskte.** Disk arızası, ransomware veya
bilgisayar değişimi tüm satış geçmişini yok eder. Backup bu projede bir "özellik" değil,
**varoluşsal bir gerekliliktir.**

---

## 2. Backup dosya formatı

### Konteyner

> **Kesin (BR-DATA-002):** Yedek **tek dosyadır**, `.canteenbackup` uzantısını taşır ve içinde
> veritabanı + görseller + metadata (şema versiyonu, uygulama sürümü, oluşturma tarihi) bulunur.
> **Açık olan yalnızca paketleme implementasyonudur** — [OD-012](28-open-decisions.md).
>
> **Yedek dosyası düz metin parola içermez** (BR-SEC-001) — parolalar veritabanında zaten
> salt'lı hash olarak saklanır.

| Alternatif | Değerlendirme |
|---|---|
| **ZIP** | ✅ Dart'ta `archive` paketi ile standart; sıkıştırma; kullanıcı gerekirse elle açıp içine bakabilir; görselleri doğal olarak taşır |
| Tek SQLite dosyası (görseller BLOB) | ❌ Görseller DB'ye gömülür — [21](21-image-storage.md) kararına aykırı; DB şişer |
| TAR | ❌ Windows'ta yerel destek zayıf |
| Özel binary format | ❌ Gereksiz; hata ayıklanamaz; kurtarılamaz |

**Uzantı gerekçesi:** `.zip` yerine `.canteenbackup` kullanmak, kullanıcının dosyayı yanlışlıkla
açıp içeriğini bozmasını engeller ve dosya ilişkilendirmesine izin verir. İçerik yine standart ZIP'tir —
acil durumda herhangi bir arşiv programıyla açılabilir. **Bu bilinçli bir kurtarılabilirlik kararıdır.**

### İçerik

```text
canteen_backup_20260813_1502.canteenbackup   (ZIP)
├── metadata.json
├── database.sqlite          ← VACUUM INTO ile alınmış tutarlı kopya
├── checksums.json
└── images/
    ├── a3f2c1d4-....jpg
    ├── b7e9f0a2-....png
    └── ...
```

### metadata.json

```text
{
  "backupFormatVersion": 1,        // bu dosya formatının versiyonu
  "schemaVersion": 3,              // veritabanı şema versiyonu
  "appVersion": "1.2.0",
  "createdAt": "2026-08-13T12:02:31Z",
  "createdBy": "ahmet",
  "platform": "windows",
  "counts": {
    "products": 512,
    "categories": 14,
    "suppliers": 6,
    "sales": 8340,
    "saleItems": 24102,
    "stockMovements": 31554,
    "auditLogs": 12043,
    "images": 87
  },
  "databaseBytes": 18874368,
  "imagesBytes": 4194304
}
```

`counts` alanı iki işe yarar:
1. Restore öncesi kullanıcıya **ne geleceğini gösterme.**
2. Restore sonrası **doğrulama** — beklenen sayılar geldi mi?

### checksums.json

Her dosya için SHA-256:
```text
{
  "database.sqlite": "3a7f...",
  "images/a3f2c1d4-....jpg": "9c1e...",
  ...
}
```

`metadata.json` kendi checksum'ını içermez; onun bütünlüğü JSON parse edilebilirliği ve
zorunlu alanların varlığıyla doğrulanır.

---

## 3. Yedek alma akışı

```text
Ayarlar → Yedekleme → [Yedek Oluştur]
      ▼
Kullanıcı hedef klasörü seçer (varsayılan: Belgeler/KantinYedekleri)
      ▼
1. Aktif yazma işlemi var mı? (satış tamamlanıyor mu) → bitmesini bekle, yeni yazımları kısa süre kuyrukla
2. Geçici klasör oluştur: <veri dizini>/temp/backup_<ts>/
3. VACUUM INTO 'temp/backup_<ts>/database.sqlite'
      ↳ WAL dahil tutarlı, sıkıştırılmış tek dosya kopyası üretir
      ↳ Uygulamayı durdurmaya gerek yoktur
4. images/ klasörünü kopyala (yalnızca DB'de referansı olanlar)
5. Her dosyanın SHA-256'sını hesapla → checksums.json
6. metadata.json yaz (counts sorgularla üretilir)
7. ZIP oluştur → hedef klasöre <geçici ad>.tmp olarak yaz
8. ZIP'i tekrar aç ve doğrula (okunabiliyor mu, checksum'lar tutuyor mu)
9. .tmp → .canteenbackup olarak yeniden adlandır  ← ATOMİK ADIM
10. Geçici klasörü temizle
11. audit_logs: backupCreated
12. app_settings['last_backup_at'] güncelle
```

**Adım 9 kritiktir:** Yedek dosyası ancak **tamamen ve doğrulanmış** olduğunda nihai adını alır.
Yedekleme sırasında elektrik keserse geriye yalnızca bir `.tmp` dosyası kalır —
kullanıcı bunu geçerli bir yedek sanmaz.

### Yedek hatırlatma

Kullanıcı yedek almayı unutur. Uygulama:
- 7 günden uzun süredir yedek alınmadıysa satış ekranının üstünde sarı bir çubuk gösterir.
- 30 günü geçerse kırmızı ve daha belirgin olur.
- Çubuk kapatılabilir ama ertesi gün geri gelir.

### Otomatik yedekleme

> **v1'de opsiyonel bir "günlük otomatik yedek" özelliği önerilir:**
> Uygulama kapatılırken, o gün yedek alınmamışsa, arka planda sessizce
> `<veri dizini>/backups/auto/` altına yedek alır ve son 7 kopyayı saklar.
>
> Bu, "kullanıcı hiç yedek almadı" senaryosunu tek başına ortadan kaldırır ve
> geliştirme maliyeti düşüktür (aynı BackupService). **Ancak aynı diskte tutulduğu için
> disk arızasına karşı koruma sağlamaz** — kullanıcıya bu açıkça belirtilir ve harici
> ortama manuel yedek alması önerilir.

---

## 4. Geri yükleme akışı

Restore, uygulamanın **en tehlikeli işlemidir** — mevcut tüm veriyi değiştirir.

```text
Ayarlar → Yedekleme → [Yedekten Geri Yükle] → dosya seç
      ▼
─── DOĞRULAMA AŞAMASI (hiçbir şey değiştirilmez) ───
1. Dosya okunabiliyor mu, geçerli ZIP mi?
2. metadata.json var mı, parse edilebiliyor mu, zorunlu alanlar dolu mu?
3. backupFormatVersion destekleniyor mu?
      ↳ Daha yeni ise: REDDET — "Bu yedek daha yeni bir uygulama sürümüyle alınmış"
4. schemaVersion kontrolü:
      = mevcut     → doğrudan
      < mevcut     → restore sonrası migration çalıştırılacak (kullanıcıya bildirilir)
      > mevcut     → REDDET
5. database.sqlite ve checksums.json var mı?
6. Tüm dosyaların SHA-256'ları checksums.json ile eşleşiyor mu?
      ↳ Eşleşmiyorsa REDDET — "Yedek dosyası bozulmuş"
7. database.sqlite'ı geçici konuma çıkar → PRAGMA integrity_check
8. Beklenen tablolar mevcut mu?
9. Eksik görsel var mı? (uyarı, engelleyici değil)
      ▼
─── ÖZET VE ONAY ───
┌──────────────────────────────────────────────────────┐
│ Yedek Geri Yükleme                                   │
│                                                      │
│ Yedek tarihi:  13.08.2026 15:02                      │
│ Alan:          ahmet · Sürüm 1.2.0                   │
│                                                      │
│              YEDEKTEKİ      ŞU ANKİ                  │
│ Ürün             512           489                   │
│ Satış          8.340         8.401    ⚠ 61 satış     │
│ Stok hareketi 31.554        31.980      kaybolacak   │
│ Görsel            87            85                   │
│                                                      │
│ ⚠ Mevcut verileriniz bu yedekle DEĞİŞTİRİLECEK.      │
│   İşlem öncesi otomatik güvenlik yedeği alınacak.    │
│                                                      │
│ Onaylamak için "GERİ YÜKLE" yazın: [__________]      │
│                    [Vazgeç]    [Geri Yükle]          │
└──────────────────────────────────────────────────────┘
```

**Yazarak onay**, geri alınamaz bir işlem için kasıtlı bir sürtünmedir.
Özellikle "şu anki veri daha fazla kayıt içeriyor" durumu **açıkça vurgulanır.**

```text
─── UYGULAMA AŞAMASI ───
10. <veri dizini>/restore_in_progress.json = {startedAt, sourceFile, stamp}
       ↳ VERİTABANININ DIŞINDA — adım 13 veritabanı dosyasını takas eder ve
         içerideki bir bayrak tam da kesinti anında kaybolurdu (OD-027)
11. GÜVENLİK YEDEĞİ:
       mevcut DB + görseller → <veri dizini>/backups/auto/pre_restore_<ts>.canteenbackup
       (aynı BackupService, doğrulanır)
       ↳ başarısızsa: DURDUR, restore yapma
12. Veritabanı bağlantısını kapat
13. Mevcut dosyaları yeniden adlandır (silme değil):
       canteen.sqlite → canteen.old_<ts>.sqlite
       images/        → images.old_<ts>/
14. Yedekten çıkarılan dosyaları yerlerine taşı
15. Veritabanını aç, integrity_check
16. schemaVersion < mevcut ise migration çalıştır ([06 §5](06-database-migrations.md))
17. Doğrulama: metadata.counts ile gerçek satır sayıları karşılaştırılır
       ↳ tutmuyorsa: GERİ AL (adım 13'teki dosyaları geri koy)
18. Satış numarası sayacını düzelt (§5)
19. Oturumu sonlandır → login ekranına dön
20. restore_in_progress.json sil
21. audit_logs: backupRestored (restore ÖNCESİ sayılarla birlikte)
22. .old_<ts> dosyaları 7 gün sonra otomatik temizlenir
```

**Adım 13'ün önemi:** Eski veri **silinmez, yeniden adlandırılır.** Restore beklenmedik şekilde
başarısız olsa bile veri diskte durur ve elle kurtarılabilir.

### Restore sırasında çökme

Açılışta `restore_in_progress.json` bulunursa (**veritabanı açılmadan önce** —
OD-027):

```text
"Geri yükleme yarım kaldı."

Sistem durumu inceler:
  - Yeni DB yerinde ve integrity_check geçiyor      → restore tamamlanmış say, doğrula, devam et
  - Yeni DB yok veya bozuk, .old_<ts> mevcut        → .old_<ts>'i geri koy, kullanıcıyı bilgilendir
  - İkisi de bozuk                                   → pre_restore güvenlik yedeğinden geri yükle
  - Hiçbiri yoksa                                    → hata ekranı + log dosyası yolu + elle kurtarma yönergesi
```

---

## 5. Restore sonrası düzeltmeler

| Konu | İşlem |
|---|---|
| Oturum | **Sonlandırılır** — geri yüklenen veritabanındaki kullanıcı listesi farklı olabilir |
| **Dashboard kilidi** | **Kapatılır.** Dashboard parolası `app_settings` içinde olduğu için geri yüklenen yedeğin parolası geçerli olur — kullanıcı bu konuda restore özetinde uyarılır |
| Kullanıcı parolaları | Geri yüklenen yedeğin parolaları geçerli olur; mevcut parolalar geçersizleşir (özet ekranında belirtilir) |
| Aktif sepet | Geri yüklenen veritabanındaki sepet geçerlidir; mevcut sepet kaybolur (özet ekranında belirtilir) |
| Satış numarası sayacı | `MAX(sale_number)` okunarak `app_settings` sayacı düzeltilir — aksi halde numara çakışması olur |
| Görseller | Yedekte olmayan ama DB'de referans verilen görseller "eksik görsel" olarak işaretlenir; ürün varsayılan ikonla gösterilir |
| Orphan görseller | Yedekte olup DB'de referansı olmayan görseller temizlik taramasına alınır |
| Denormalize alanlar | Tutarlılık kontrolü otomatik çalıştırılır ([05 §4](05-database-architecture.md)) |

---

## 6. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-BKUP-001 | Kullanıcı tek dosyalık bir yedek oluşturabilir. |
| REQ-BKUP-002 | Yedek dosyası veritabanı, ürün görselleri, metadata ve checksum bilgilerini içerir. |
| REQ-BKUP-003 | Veritabanı kopyası, uygulamayı durdurmadan tutarlı bir anlık görüntü olarak alınır. |
| REQ-BKUP-004 | Yedek dosyası ancak tamamen yazılıp doğrulandıktan sonra nihai adını alır. |
| REQ-BKUP-005 | Yedek oluşturulduktan sonra dosya tekrar okunarak doğrulanır. |
| REQ-BKUP-006 | Geri yükleme öncesi dosya formatı, sürüm, şema versiyonu ve checksum doğrulaması yapılır. |
| REQ-BKUP-007 | Geri yükleme öncesi kullanıcıya yedek ve mevcut veri karşılaştırmalı özeti gösterilir. |
| REQ-BKUP-008 | Geri yükleme, kullanıcının açık ve kasıtlı onayı olmadan başlatılamaz. |
| REQ-BKUP-009 | Geri yükleme öncesi mevcut verinin otomatik güvenlik yedeği alınır. |
| REQ-BKUP-010 | Geri yükleme sırasında mevcut veri silinmez, yeniden adlandırılarak saklanır. |
| REQ-BKUP-011 | Geri yükleme başarısız olursa sistem önceki haline döner. |
| REQ-BKUP-012 | Yarım kalmış geri yükleme açılışta tespit edilir ve kurtarma uygulanır. |
| REQ-BKUP-013 | Daha yeni bir uygulama sürümüyle alınmış yedek reddedilir. |
| REQ-BKUP-014 | Daha eski şemalı yedek, geri yükleme sonrası migration ile güncellenir. |
| REQ-BKUP-015 | Geri yükleme sonrası oturum sonlandırılır ve satış numarası sayacı düzeltilir. |
| REQ-BKUP-016 | 7 günden uzun süredir yedek alınmadıysa kullanıcı uyarılır. |
| REQ-BKUP-017 | Yedekleme ve geri yükleme işlemleri audit log'a yazılır. |
| REQ-BKUP-018 | Bozuk veya eksik görsel içeren yedek, geri yüklemeyi engellemez; kullanıcı uyarılır. |
| REQ-BKUP-019 | Yedek dosyası hiçbir dosyasında düz metin parola içermez. |
| REQ-BKUP-020 | Geri yükleme sonrası dashboard kilidi kapatılır ve kullanıcı, parolaların yedekteki değerlerle değiştiği konusunda bilgilendirilir. |

---

## 7. Acceptance criteria

**REQ-BKUP-004 / REQ-BKUP-005**
```text
Given: Yedek oluşturuluyor
When:  ZIP yazımı sırasında uygulama sonlandırılıyor
Then:  Hedef klasörde .canteenbackup uzantılı dosya bulunmaz
And:   Yalnızca .tmp uzantılı yarım dosya bulunur
And:   Bu dosya geri yükleme ekranında seçilebilir dosya olarak listelenmez
```

**REQ-BKUP-006**
```text
Given: Yedek dosyasının içindeki database.sqlite bir hex editörle değiştirilmiş
When:  Geri yükleme deneniyor
Then:  Checksum doğrulaması başarısız olur
And:   "Yedek dosyası bozulmuş" mesajı gösterilir
And:   Mevcut verilere hiç dokunulmaz
```

**REQ-BKUP-011 / REQ-BKUP-012**
```text
Given: Geri yükleme adım 14'te (dosya taşıma) elektrik kesintisiyle kesiliyor
When:  Uygulama tekrar açılıyor
Then:  "Geri yükleme yarım kaldı" ekranı gösterilir
And:   Sistem .old_<ts> dosyalarını tespit eder ve geri koyar
And:   Kullanıcının geri yükleme öncesi verileri eksiksiz geri gelir
And:   Olay audit log'a ve hata log'una yazılır
```

**REQ-BKUP-015**
```text
Given: Mevcut sistemde son satış numarası 2026-000500
And:   Geri yüklenen yedekte son satış numarası 2026-000340
When:  Geri yükleme tamamlanıyor
Then:  Sayaç 340 olarak düzeltilir
And:   Sonraki satış 2026-000341 numarasını alır
And:   Kullanıcı login ekranına yönlendirilir
```

**REQ-BKUP-019**
```text
Given: Sistemde kullanıcı hesapları ve dashboard parolası tanımlı
When:  Yedek oluşturuluyor ve arşiv açılıp içeriği inceleniyor
Then:  database.sqlite içinde yalnızca hash ve salt değerleri bulunur
And:   metadata.json içinde parola bilgisi bulunmaz
And:   Hiçbir dosyada düz metin parola yoktur
```

**REQ-BKUP-020**
```text
Given: Kullanıcı dashboard kilidini açmış ve dashboard'ı görüntülüyor
When:  Bir yedek geri yükleniyor
Then:  Oturum sonlandırılır ve login ekranı gösterilir
And:   Dashboard kilidi kapalı duruma döner
And:   Restore özetinde "parolalar yedekteki değerlerle değişecek" uyarısı gösterilmiştir
```

**REQ-BKUP-003**
```text
Given: Veritabanı 50 MB ve WAL dosyasında bekleyen yazımlar var
When:  Yedek alınıyor
Then:  Yedekteki database.sqlite tüm tamamlanmış işlemleri içerir
And:   Yedekleme sırasında uygulama kullanılabilir kalır
And:   Yedekteki veritabanı integrity_check'ten geçer
```
