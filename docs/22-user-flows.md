# 22 — Kullanıcı Akışları

> **Doküman sürümü:** v4 — yönetici erişimi (F9) genişledi, logout akışı (F16) eklendi;
> 16 akış ([OD-030](28-open-decisions.md)).

Bu doküman uçtan uca akışları tek yerde toplar. Detaylar ilgili modül dokümanlarındadır.

---

## F1 — İlk kurulum

```text
Uygulama ilk kez açıldı
      ▼
Veri dizini oluştur → DB oluştur → şema kur → seed (Genel kategorisi)
      ▼
Kurulum sihirbazı
   ├─ Adım 1: Kullanıcı hesabı (kullanıcı adı, ad, parola)     [ZORUNLU]
   │          → parola salt'lı SHA-256 olarak saklanır
   ├─ Adım 2: DASHBOARD PAROLASI                               [ZORUNLU]
   │          ℹ "Dashboard ve Raporlar bu parola ile korunur."
   ├─ Adım 3: KURTARMA KODU  A7K2-M9QX-4RTB-8ZWD               [ZORUNLU gösterim]
   │          ⚠ "Bir daha gösterilmeyecek. Güvenli bir yere kaydedin."
   │          ☐ "Kodu kaydettim" işaretlenmeden devam edilemez
   ├─ Adım 4: KDV oranları                                     [atlanabilir]
   └─ Adım 5: Kategoriler                                      [atlanabilir]
      ▼
Otomatik giriş → Satış ekranı  (yönetici erişim kilidi KAPALI başlar)
      ▼
"Henüz ürününüz yok" boş durum ekranı:
   [Ürün Ekle]   [Excel'den İçe Aktar]
```

---

## F2 — Günlük açılış

```text
Uygulama açıldı
      ▼
Single-instance lock ──── alınamadı ──► "Uygulama zaten çalışıyor" → çık
      ▼
Kurtarma kontrolü (migration/restore yarım kalmış mı?) → gerekirse kurtarma akışı
      ▼
DB aç → migration (gerekirse) → görsel bakım taraması (arka plan)
      ▼
Oturum var mı?
   ├─ Hayır → Login
   └─ Evet  → Satış ekranı
      ▼
Yönetici erişim kilidi KAPALI olarak başlar (her açılışta)
      ▼
Aktif sepet restore → varsa "Yarım kalan satış geri yüklendi" bilgisi
      ▼
Yedek hatırlatması (7+ gün geçtiyse)
      ▼
Odak: barkod girişi
```

---

## F3 — Normal satış (en sık akış)

```text
[Barkod okut]  ──► ürün bulundu ──► sepete eklendi ──► ⏎ hazır
      │
      ├─ ürün bulunamadı ──► F4
      │
      └─ stok <= 0 ──► uyarı ──► [Devam Et] ──► sepete eklendi
      ▼
(tekrar okut / favoriden ekle / aramadan ekle)
      ▼
[F4 tuşu] Nakit hesapla (opsiyonel)
      ▼
[F12 tuşu] Satışı tamamla
      ▼
Atomik transaction: satış + satırlar + stok hareketleri + stok + yeni boş sepet
      ▼
"✅ Satış tamamlandı — 2026-000148 · ₺135,00 · Para üstü ₺65,00"
      ▼
Odak barkod girişinde, sepet boş, bir sonraki müşteriye hazır
```

**Hedef:** 3 ürünlük bir satış, hiç fareye dokunmadan, < 10 saniyede.

---

## F4 — Bilinmeyen barkod → hızlı ürün ekleme

```text
Barkod okutuldu → eşleşme yok
      ▼
"Yeni Ürün (Hızlı)" — barkod dolu, odak "Ürün adı"nda
      ▼
Ad ⏎ Satış fiyatı ⏎ (Alış fiyatı) ⏎ (Kategori) ⏎
      ▼
[Kaydet ve Sepete Ekle]
      ▼
Ürün + barkod oluşturuldu (tek transaction) → sepete eklendi
      ▼
Odak barkod girişine döner
```

**Alternatif:** [Detaylı düzenle] → tam ürün formu (nadir; kasada kullanılmaz).

---

## F5 — Mal kabul (stok girişi)

```text
Stok → Stok Girişi
      ▼
Tedarikçi seç (opsiyonel) · Belge no (opsiyonel)
      ▼
Barkod okut / ürün ara → satır ekle
      ▼
Her satır: giriş miktarı + alış fiyatı (mevcut fiyat önerilir)
      ▼
Alış fiyatı değiştiyse → "Ürünün alış fiyatı da güncellensin mi?"
      ▼
[Girişi Kaydet] → tek transaction: N adet stockEntry hareketi + stok + (fiyat)
      ▼
"12 üründe toplam 340 adet giriş yapıldı · ₺4.250,00"
```

---

## F6 — Satış iptali

```text
Satış Geçmişi → satış → [Satışı İptal Et]
      ▼
Ön kontrol: completed mi, iade var mı
      ▼
Uyarı + sebep girişi + onay
      ▼
Transaction: status=cancelled + tüm satırlar için saleCancellation hareketi + stok
      ▼
"Satış iptal edildi, stoklar geri eklendi"
```

---

## F7 — İade

```text
Satış Geçmişi → satış → [İade Oluştur]
      ▼
Satır bazında iade miktarı gir (maks. satılan − önceden iade edilen)
      ▼
İade tutarı canlı hesaplanır (snapshot fiyatlarla)
      ▼
Sebep + [İadeyi Kaydet]
      ▼
Transaction: return + return_items + returned_quantity + return hareketleri + stok + durum güncelleme
      ▼
"₺45,00 iade edildi · Satış durumu: Kısmen İade Edildi"
```

---

## F8 — Sayım ve düzeltme

```text
Stok → Sayım
      ▼
[Sayım şablonu indir] → fiziksel sayım → doldur
      ▼
[Dosya yükle] → önizleme (sistem / sayım / fark)
      ▼
Onay → her fark için adjustment hareketi (fark 0 ise hareket yok)
      ▼
"47 üründe düzeltme yapıldı · maliyet etkisi −₺340,00"
```

Tek ürün için: Ürün detayı → Stok → [Düzelt] → yeni miktar + sebep.

---

## F9 — Yönetici erişimi (yönetim ekranları kilidi)

```text
Ana ekran — kilit KAPALIYKEN yalnızca üç kutu vardır:
   🛒 Satış        🔁 Satış Geçmişi        📦 Stok        🔒 Yönetici Erişimi
      ▼
Kullanıcı [🔒 Yönetici Erişimi] diyor  —  veya kilitli bir kısayola basıyor
(F3 Ürünler · F6 Dashboard · F7 Raporlar · Ctrl+, Ayarlar)
      ▼
Yönetici erişimi bu oturumda açıldı mı?
   ├─ Evet → ekran doğrudan yüklenir
   └─ Hayır
        ▼
   🔒 Yönetici parolası sorulur
        ├─ Vazgeç          → hiçbir ekran açılmaz, hiçbir veri yüklenmez
        ├─ Yanlış          → hata; 5 denemede 30 sn bekleme; audit log
        ├─ Şifremi unuttum → F10 (recovery akışı)
        └─ Doğru           → kilit açılır (oturum boyunca) → audit log
                             → ana ekranda TÜM kutular belirir
      ▼
İş bitince: [Yönetici Erişimini Kapat]  → kilit kapanır, üç kutuya dönülür
                                          (oturum ve sepet korunur — REQ-AUTH-031)
```

> Kapsam: **Dashboard, Raporlar ve tüm yönetim ekranları** ([17 §7](17-authentication.md)).
> Kilit dışında yalnızca **satış, satış geçmişi (iade/iptal) ve stok** vardır.
> Parola doğrulanmadan **hiçbir finansal sorgu çalıştırılmaz** (BR-AUTH-012) ve kilitli
> ekranlar **hiç kurulmaz** (BR-AUTH-018).
> **İstisna:** satıştaki bilinmeyen barkod → hızlı ürün ekleme akışı (F4) kilit dışıdır
> (BR-AUTH-019).
> Kilit oturum kapsamlıdır; ekranlar arası geçişte tekrar sorulmaz.
> Logout, uygulama kapanışı veya elle kapatma ile sıfırlanır.

---

## F10 — Yönetici parolası kurtarma (recovery code)

```text
Yönetici erişim ekranı → [Şifremi unuttum]
      ▼
Kurtarma kodu girilir:  [____]-[____]-[____]-[____]
      ▼
   ├─ Kod daha önce kullanılmış → "Bu kurtarma kodu daha önce kullanılmış."
   ├─ Kod yanlış → hata; 5 denemede 30 sn bekleme; audit log
   └─ Kod doğru
        ▼
   Yeni yönetici parolası belirlenir (iki kez)
        ▼
   TEK TRANSACTION:
     yönetici parolası güncellenir
     + eski recovery code geçersizleşir (used_at = now)
     + YENİ recovery code üretilir
     + audit log (kod değeri YAZILMAZ)
        ▼
   🔑 Yeni kurtarma kodu bir kez gösterilir
      ☐ "Kodu kaydettim" onayı
        ▼
   Yönetici erişim kilidi AÇILIR
```

> Hem parola hem recovery code kaybedilirse yönetici erişimi kurtarılamaz; **satış, satış
> geçmişi ve stok çalışmaya devam eder**, ancak ürün yönetimi, ayarlar ve **yedekleme**
> erişilemez olur ([RSK-016](29-risks.md)).

---

## F11 — Günlük kapanış (önerilen rutin)

> Bu akış bir özellik değil, **kullanıcı rutinidir.** Uygulama bunu desteklemeli ama dayatmamalıdır.

```text
Dashboard (yönetici erişimi açılır) → "Bugün"
      ▼
Net ciro, satış adedi, kâr kontrol edilir
      ▼
Kritik stok listesi → sipariş listesi dışa aktar
      ▼
Negatif stok varsa → düzeltme
      ▼
(Uygulama kapatılırken otomatik günlük yedek — [19 §3](19-backup-restore.md))
```

> **Kasa sayımı, vardiya kapanışı ve kasa farkı V1 kapsamı dışındadır**
> (proje sahibi kararı — [30 §3.1](30-future-scope.md)). Uygulama bu rutini dayatmaz;
> kullanıcı isterse dashboard'daki nakit satış toplamını kendi sayımıyla karşılaştırır.

---

## F12 — Yedekleme

```text
Ayarlar → Yedekleme → [Yedek Oluştur] → klasör seç
      ▼
VACUUM INTO → görseller → checksum → metadata → ZIP → doğrula → yeniden adlandır
      ▼
"Yedek oluşturuldu: canteen_backup_20260813_1502.canteenbackup (4,2 MB)"
      ▼
💡 "Bu dosyayı USB bellek veya bulut depolamaya kopyalayın —
    aynı diskte tutulan yedek disk arızasına karşı korumaz."
```

---

## F13 — Geri yükleme

```text
Ayarlar → Yedekleme → [Yedekten Geri Yükle] → dosya seç
      ▼
Doğrulama (format, sürüm, şema, checksum, integrity)
      ▼
Karşılaştırmalı özet ekranı (yedekteki vs mevcut kayıt sayıları)
      ▼
"GERİ YÜKLE" yazarak onay
      ▼
Güvenlik yedeği → dosya değişimi → doğrulama → (gerekirse migration) → sayaç düzeltme
      ▼
Oturum sonlandırılır + yönetici erişim kilidi kapatılır → Login ekranı
      ▼
⚠ "Parolalar yedekteki değerlerle değişti" bilgisi
```

---

## F14 — Ürün import

```text
Ayarlar → İçe Aktar → Ürünler
      ▼
[Şablon indir] → dosya hazırla → [Dosya seç]
      ▼
Sütun eşleştirme → validasyon → önizleme (✅🔄🟡🔴 sayıları)
      ▼
Barkod çakışma politikası seç
      ▼
(opsiyonel otomatik yedek) → [İçe Aktar] → tek transaction
      ▼
Sonuç raporu + [Atlanan satırları indir]
```

---

## F15 — Sistem kurtarma akışları

| Tetikleyici | Akış |
|---|---|
| `migration_in_progress` bulundu | Bilgilendir → pre-migration snapshot geri yükle → migration tekrar dene |
| `restore_in_progress` bulundu | Durum analizi → `.old_<ts>` geri koy veya güvenlik yedeğinden yükle |
| DB `integrity_check` başarısız | Bozuk DB'yi yeniden adlandır → son otomatik yedeği öner |
| Single-instance lock alınamadı | "Uygulama zaten çalışıyor" → mevcut pencereyi öne getir → çık |
| Oturum verisi bozuk | Sessizce temizle → login |
| Aktif sepet bozuk/tutarsız | Sepeti `abandoned` yap → yeni boş sepet → kullanıcıyı bilgilendir |

---

## Akış → Requirement eşlemesi

| Akış | İlgili requirement'lar |
|---|---|
| F1 | REQ-AUTH-002, **REQ-AUTH-016, 022, 023, 024**, REQ-VAT-005, REQ-CAT-002 |
| F2 | REQ-ARCH-005, REQ-AUTH-003, **REQ-AUTH-021**, REQ-CART-003, REQ-MIG-006, REQ-BKUP-012, REQ-IMG-007 |
| F3 | REQ-BARC-004, REQ-BARC-005, REQ-STOCK-005, REQ-SALE-001, REQ-SALE-006, REQ-UX-001 |
| F4 | REQ-BARC-006, REQ-BARC-007, REQ-PROD-001, REQ-PROD-014 |
| F5 | REQ-STOCK-007, REQ-STOCK-008 |
| F6 | REQ-RET-002, REQ-RET-010 |
| F7 | REQ-RET-003, REQ-RET-004, REQ-RET-005, REQ-RET-007 |
| F8 | REQ-STOCK-001, REQ-IMEX-011 |
| F9 | **REQ-AUTH-015, 017, 019, 020, 021, REQ-DASH-011/012, REQ-REP-014, REQ-AUDIT-012** |
| F10 | **REQ-AUTH-018, 023, 025, 026, 027** |
| F11 | REQ-DASH-001, REQ-DASH-006, REQ-REP-010 |
| F12 | REQ-BKUP-001…005, REQ-BKUP-016, REQ-BKUP-019 |
| F13 | REQ-BKUP-006…015, REQ-BKUP-020 |
| F14 | REQ-IMEX-001…011 |
| F15 | REQ-MIG-006, REQ-BKUP-012, REQ-AUTH-007, REQ-DATA-* |

---

## F16 — Çıkış (logout)

```text
Ana ekran → [Çıkış Yap]
      ▼
Aktif sepette ürün var mı?
   ├─ Hayır → doğrudan çıkılır
   └─ Evet
        ▼
   "Sepetinizde N ürün var. Çıkış yaparsanız sepet korunur ve bir sonraki
    girişte geri yüklenir."
        [Vazgeç]   [Sepeti Temizle ve Çık]   [Çıkış Yap]
      ▼
app_settings['session'] silinir
YÖNETİCİ ERİŞİM KİLİDİ KAPATILIR
      ▼
Login ekranı
```

> **BR-AUTH-005 · REQ-AUTH-005 — logout aktif sepeti SİLMEZ.** "Sepeti Temizle ve Çık"
> kullanıcının **açık** tercihidir; varsayılan davranış sepeti korumaktır.
> Ayrıntı: [17 §10](17-authentication.md).
