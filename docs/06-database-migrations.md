# 06 — Database Migration Stratejisi

> **Kesin kural (BR-DATA-004):** Schema doğrudan değiştirilemez. Her değişiklik versiyonlu bir migration adımıdır.

## 1. Versiyonlama modeli

```text
schemaVersion = 1  →  v1.0.0 ile yayınlanan ilk şema
schemaVersion = 2  →  categories.icon_key eklendi (OD-029)
schemaVersion = 3  →  sonraki şema değişikliği
...
```

- `schemaVersion` **uygulama sürümünden bağımsızdır.** Bir uygulama sürümü şemayı değiştirmeyebilir.
- Şema versiyonu SQLite'ın `user_version` alanında tutulur (Drift bunu yönetir).
- Uygulama, `user_version` > beklenen değer ise **çalışmayı reddeder** (eski sürüm, yeni veri → veri bozma riski).

| Durum | Davranış |
|---|---|
| `db.version < app.expectedVersion` | Migration çalıştır |
| `db.version = app.expectedVersion` | Normal başlat |
| `db.version > app.expectedVersion` | **Başlatma. Hata:** "Bu veritabanı daha yeni bir sürümle oluşturulmuş. Lütfen uygulamayı güncelleyin." |

---

## 2. Migration yazım kuralları

1. **Migration'lar değişmezdir.** Yayınlanmış bir migration adımı sonradan düzenlenmez; yeni adım eklenir.
2. **Veri kaybettiren işlem yasaktır** (kolon silme, tablo silme) — bunun yerine kolon kullanımdan kaldırılır (deprecated) ve bir sonraki büyük sürümde temizlenir.
3. Her migration **idempotent kontrol** ile başlar (adım zaten uygulanmış mı?).
4. Yeni `NOT NULL` kolon eklenirken **daima varsayılan değer** verilir.
5. Migration içinde iş kuralı çalıştırılmaz; yalnızca şema + veri dönüşümü yapılır.
6. Her migration için **geri alma (down) betiği yazılmaz** — SQLite'ta güvenilir değildir. Geri alma **dosya restore** ile yapılır (§4).

### Tipik değişiklik türleri

| Değişiklik | Yaklaşım |
|---|---|
| Yeni tablo | Doğrudan `CREATE TABLE` |
| Yeni nullable kolon | `ALTER TABLE ADD COLUMN` |
| Yeni NOT NULL kolon | `ADD COLUMN ... DEFAULT <x>` → gerekiyorsa veri doldurma UPDATE'i |
| Kolon tipi/kısıt değişikliği | Yeni tablo oluştur → veri kopyala → eski tabloyu yeniden adlandır → index'leri yeniden kur |
| Index ekleme/silme | Doğrudan |
| Kolon silme | **Yapılmaz** — deprecated işaretlenir |

---

## 3. Migration çalıştırma protokolü

```text
Uygulama açılışı
     │
     ▼
user_version okunur
     │
     ├── eşitse ──────────────────────────► normal başlat
     │
     ├── büyükse ─────────────────────────► başlatma, kullanıcıyı uyar
     │
     └── küçükse
           │
           ▼
     1. Kullanıcıya bilgi ekranı: "Veritabanı güncelleniyor, lütfen kapatmayın."
     2. PRE-MIGRATION SNAPSHOT
        <veri dizini>/backups/auto/premigration_v<eski>_<timestamp>.sqlite
        (VACUUM INTO ile bütünlüklü kopya)
     3. Snapshot doğrula (integrity_check + boyut > 0)
        └── başarısızsa: DURDUR, hata göster, migration yapma
     4. app_settings['migration_in_progress'] = {from, to, startedAt}
     5. Migration adımlarını sırayla, tek transaction içinde çalıştır
     6. PRAGMA foreign_key_check
     7. Doğrulama sorguları (kritik tablolar okunabiliyor mu, satır sayıları korunmuş mu)
     8. user_version güncelle
     9. app_settings['migration_in_progress'] temizle
    10. Migration özetini audit log'a yaz
```

### Başarısızlık durumunda

```text
Adım 5–7'de hata
     │
     ▼
Transaction rollback (SQLite otomatik)
     │
     ▼
Yine de veritabanı şüpheli mi? (integrity_check başarısız)
     │
     ├── Hayır ──► Uygulamayı eski şemayla açma, hata ekranı göster
     │
     └── Evet ──► canteen.sqlite  →  canteen.corrupt_<timestamp>.sqlite (taşınır, silinmez)
                  premigration snapshot  →  canteen.sqlite (geri yüklenir)
                  Kullanıcıya: "Güncelleme başarısız oldu, verileriniz güncelleme
                  öncesi haline geri alındı." + log dosyası yolu
```

### Açılışta yarım kalmış migration tespiti

`app_settings['migration_in_progress']` dolu bulunursa (= uygulama migration ortasında kapanmış):

1. Kullanıcıya durum bildirilir.
2. Pre-migration snapshot varsa **otomatik geri yükleme önerilir**.
3. Kullanıcı onaylarsa snapshot geri yüklenir ve migration yeniden denenir.
4. Onaylamazsa uygulama kapanır (yarım şema ile çalışmaya izin verilmez).

---

## 4. Geri alma (rollback) stratejisi

| Senaryo | Çözüm |
|---|---|
| Migration transaction içinde hata verdi | SQLite rollback — veri değişmedi |
| Migration bitti ama uygulama açılmıyor / veri bozuk | Pre-migration snapshot elle geri yüklenir (Ayarlar → Yedekler → Otomatik yedekler) |
| Kullanıcı eski uygulama sürümüne dönmek istiyor | Yalnızca pre-migration snapshot ile mümkündür; yeni şemadaki veri eski sürümde okunamaz. Kullanıcı bu konuda uyarılır. |

**Otomatik snapshot saklama:** Son 5 pre-migration snapshot tutulur, eskisi silinir.

---

## 5. Backup ile ilişki

Backup dosyası kendi `schemaVersion`ını taşır ([19 §2](19-backup-restore.md)).

| Backup versiyonu | Davranış |
|---|---|
| = mevcut | Doğrudan restore |
| < mevcut | Restore → migration çalıştır → kullanıcıya "yedek güncellendi" bilgisi |
| > mevcut | **Reddet.** "Bu yedek daha yeni bir uygulama sürümüyle alınmış." |

---

## 6. Migration testi

Bkz. [27 §6](27-testing-strategy.md). Zorunlu testler:

| Test | Amaç |
|---|---|
| Her `vN → vN+1` adımı için şema doğrulama | Beklenen şema oluşuyor mu |
| `v1 → vSON` zincir testi | Tüm adımlar arka arkaya çalışıyor mu |
| Veri koruma testi | Her adımdan önce örnek veri yazılır, sonra **satır sayısı ve kritik alan değerleri** doğrulanır |
| Bozuk/yarım migration testi | Adım ortasında hata enjekte edilir → rollback doğrulanır |
| Foreign key testi | Migration sonrası `foreign_key_check` boş dönmelidir |

Drift'in şema dump mekanizması ile her yayınlanan şema versiyonu repoda saklanır
(`test/db/schema/vN.json`) — bu, gelecekteki migration'ların eski şemalara karşı test edilmesini sağlar.

---

## 7. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-MIG-001 | Şema değişiklikleri yalnızca versiyonlu migration adımlarıyla yapılır. |
| REQ-MIG-002 | Migration öncesi otomatik, bütünlüğü doğrulanmış bir veritabanı snapshot'ı alınır. |
| REQ-MIG-003 | Migration başarısız olursa veri, migration öncesi haline geri döner. |
| REQ-MIG-004 | Migration tüm adımları tek transaction içinde uygular. |
| REQ-MIG-005 | Uygulama, kendi desteklediğinden daha yeni bir şema versiyonuyla açılmayı reddeder. |
| REQ-MIG-006 | Yarım kalmış migration açılışta tespit edilir ve kullanıcıya kurtarma sunulur. |
| REQ-MIG-007 | Hiçbir migration kullanıcı verisini kaybettiren bir işlem (kolon/tablo silme) içermez. |
| REQ-MIG-008 | Yayınlanan her şema versiyonu test amacıyla repoda saklanır. |

---

## 8. Acceptance criteria

**REQ-MIG-003**
```text
Given: v1 şemasında 500 ürün ve 2.000 satış içeren bir veritabanı var
When:  v2 migration'ı 3. adımda hata veriyor
Then:  Uygulama açılmaz, kullanıcıya hata gösterilir
And:   Veritabanı v1 şemasındadır
And:   500 ürün ve 2.000 satış eksiksizdir
```

**REQ-MIG-006**
```text
Given: Migration sırasında bilgisayarın elektriği kesilmiş
When:  Uygulama tekrar açılıyor
Then:  "Güncelleme yarım kaldı" ekranı gösterilir
And:   Kullanıcı onayıyla migration öncesi snapshot geri yüklenir
And:   Migration yeniden çalıştırılır
```
