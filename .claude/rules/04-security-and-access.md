# 04 — Kimlik Doğrulama, Finansal Erişim ve Güvenlik

> Kaynak: `docs/17-authentication.md` · `docs/24 §4`
>
> Bu alandaki her kural bir **business invariant**'tır. Değişiklik için
> [`00-source-of-truth.md §3`](00-source-of-truth.md) protokolü işletilir.

---

## 1. İki ayrı koruma katmanı

| | **Kullanıcı parolası** | **Dashboard parolası** |
|---|---|---|
| Neyi korur | Uygulamaya giriş | **Dashboard + Raporlar** |
| Kaç tane | Kullanıcı başına bir | Sistemde **tek** |
| Nerede | `users.password_hash` + `salt` | `app_settings` (hash + salt) |
| Kime ait | Kişiye | **Uygulamaya** |
| Kurtarma | ❌ Yok | ✅ **Recovery code** |

> **Bunların hiçbiri bir rol sistemi DEĞİLDİR.**

---

## 2. Rol sistemi YOKTUR

| Kural | |
|---|---|
| Admin / Kasiyer ayrımı | ❌ **YOK** |
| Yetki matrisi | ❌ **YOK** |
| `users.role` kolonu | ❌ **Oluşturulmaz** |
| Birden fazla kullanıcı | ✅ Desteklenir |
| Tüm kullanıcıların yetkisi | **Aynı** |
| `user_id` kaydı | ✅ Satış, stok hareketi ve audit log'da tutulur |

Çoklu kullanıcının tek faydası **izlenebilirliktir** — yetki farkı yaratmaz.

> "Bu işlem için yetki kontrolü ekleyeyim" **yapılmaz.** Yetki kavramı bu projede yoktur.
> Kabul edilmiş risk: [RSK-004](../../docs/29-risks.md).

---

## 3. Oturum

- Uygulama **login ekranı** ile açılır.
- **Logout yapılmadıkça oturum korunur** — uygulama yeniden açıldığında parola sorulmaz.
- Oturum `app_settings['session'] = { userId, loginAt }` içinde tutulur.
- **Token üretilmez** — yerel uygulamada yanlış güvenlik hissi verir.
- Oturum zaman aşımı **yoktur.**
- Bozuk oturum verisi uygulamayı çökertmez; sessizce temizlenir → login.
- Logout: oturum temizlenir **+ finansal erişim kilidi kapanır** **+ aktif sepet KORUNUR.**

---

## 4. Finansal erişim kilidi

> **BR-AUTH-013 — Dashboard ve Raporlar ekranları dashboard parolası gerektirir.**

### Kapsam

| 🔒 Kilit **arkasında** | 🔓 Kilit **dışında** |
|---|---|
| **Dashboard** | Satış ekranı |
| **Raporlar** (tümü) | Ürün yönetimi |
| | Stok işlemleri (giriş, fire, düzeltme, sayım) |
| | Kategori / tedarikçi / KDV yönetimi |
| | Satış geçmişi, iade, iptal |
| | Ayarlar, yedekleme, import/export |

**Normal login bu ekranlara otomatik erişim sağlamaz.**

### Kritik davranış

> **BR-AUTH-012 — Parola doğrulanmadan finansal ekranların verisi SORGULANMAZ.**

Kilit görsel bir perde değildir:

- KPI ve rapor sorguları **çalıştırılmaz**
- Grafik verileri **hesaplanmaz**
- Ekranda hiçbir ciro/kâr/maliyet rakamı — bulanık veya kısmen bile — **görünmez**

> Bu kural **servis katmanında** zorlanır (`FinancialAccessService` route guard),
> yalnızca UI'da gizleme ile değil.

### Kilidin süresi

| | |
|---|---|
| Başarılı girişten sonra | **Oturum boyunca** geçerli |
| Dashboard ↔ Raporlar geçişi | Parola **tekrar sorulmaz** |
| Logout | Kilit **yeniden devreye girer** |
| Uygulama kapanışı | Kilit **kapalı** başlar |
| Saklama | Yalnızca **bellekte** — veritabanına yazılmaz |

### Parola değiştirme

Mevcut dashboard parolası **veya** recovery code gerekir. Audit log'a yazılır — **parola değeri yazılmaz.**

---

## 5. Recovery code

### Format ve üretim

```text
XXXX-XXXX-XXXX-XXXX        örn.  A7K2-M9QX-4RTB-8ZWD
```

- Kriptografik olarak güvenli rastgele üretim
- Karışma riski olan karakterler kullanılmaz: `0/O`, `1/I/l`
- Kurulum sihirbazında **bir kez** gösterilir
- Kullanıcı **"kaydettim" onayı vermeden kurulum ilerlemez**
- Kopyalama ve dosyaya kaydetme seçenekleri sunulur

### Saklama — mutlak kurallar

| ❌ Asla | ✅ Doğru |
|---|---|
| Düz metin veritabanına yazılmaz | `app_settings['dashboard_recovery_hash']` — salt'lı SHA-256 |
| Düz metin loglanmaz | `dashboard_recovery_salt` |
| Düz metin yedeğe yazılmaz | `dashboard_recovery_used_at` — tek kullanımlık kontrolü |
| Düz metin audit log'a yazılmaz | |
| Düz metin export edilmez | |

### Kullanım akışı

```text
Finansal erişim ekranı → [Şifremi unuttum]
      ▼
Recovery code girilir
      ▼
├── Daha önce kullanılmış → "Bu kurtarma kodu daha önce kullanılmış"
├── Yanlış → hata; 5 denemede 30 sn bekleme; audit log
└── Doğru
      ▼
Yeni dashboard parolası belirlenir
      ▼
TEK TRANSACTION:
  1. dashboard parolası güncellenir
  2. kullanılan recovery code GEÇERSİZLEŞİR (used_at = now)
  3. YENİ recovery code üretilir
  4. audit log (kod değeri YAZILMAZ)
      ▼
Yeni kod bir kez gösterilir → "kaydettim" onayı
      ▼
Finansal erişim kilidi AÇILIR
```

### Değişmez kurallar

| # | Kural |
|---|---|
| 1 | Recovery code **tek kullanımlıktır** |
| 2 | Kullanıldıktan sonra **geçersizleşir** |
| 3 | Kullanıldığında **otomatik olarak yeni kod üretilir** (BR-AUTH-017) |
| 4 | Dört adım **tek transaction**'dır — biri başarısızsa hiçbiri uygulanmaz |
| 5 | Mevcut kod **asla tekrar gösterilemez** (yalnızca hash saklanıyor) |
| 6 | Kullanıcı, parolasını bildiği sürece Ayarlar'dan yeni kod üretebilir |

> **BR-AUTH-017 neden var:** Kod tek kullanımlık olduğu için yenisi üretilmezse, kullanıcı
> ikinci kez parola unuttuğunda kalıcı olarak kilitlenirdi.

---

## 6. Parola saklama

> **Düz metin parola saklamak YASAKTIR** (BR-SEC-001).

| | |
|---|---|
| Yöntem | **SHA-256 + kayıt başına rastgele salt** |
| Kapsam | Kullanıcı parolaları · dashboard parolası · recovery code |
| Düz metin alanı | Hiçbir tabloda **yoktur** |

### V1 kapsamı dışı — eklenmeyecek

| ❌ | |
|---|---|
| OAuth | Sunucu yok |
| JWT | Sunucu yok |
| MFA | Tehdit modeli gerektirmiyor |
| Parola sunucusu / cloud auth | Local-first |
| Kullanıcı parolası kurtarma akışı | Yalnızca dashboard parolası için recovery code var |
| bcrypt / Argon2 | Uzaktan saldırı yüzeyi yok |
| Veritabanı şifreleme | Anahtar aynı makinede — gerçek koruma sağlamaz, kurtarmayı zorlaştırır |

> **Security architecture gereksiz şekilde büyütülmez.** Tehdit modeli dardır:
> yerel, tek kullanıcılı, ağ bağlantısı olmayan masaüstü uygulaması.

---

## 7. Diğer güvenlik önlemleri

| Konu | Önlem |
|---|---|
| SQL injection | Parametreli sorgular (Drift zorlar) |
| Zip-slip | Arşivden çıkarılan her yol hedef dizin içinde doğrulanır |
| Zip bomb | Açılmadan önce sıkıştırılmamış boyut kontrol edilir |
| CSV formül enjeksiyonu | `=`, `+`, `-`, `@` ile başlayan hücreler kaçışlanır |
| Görsel dosyası | İçerik doğrulaması (magic bytes) + boyut sınırı |
| Hata mesajları | Dosya yolu ve teknik detay kullanıcıya sızdırılmaz; log dosyasına yazılır |
| Ağ | **Hiçbir veri dışarı gönderilmez** (REQ-SEC-008) |

---

## 8. Loglama yasakları

Hiçbir koşulda log dosyasına, audit log'a, export'a veya yedeğe yazılmaz:

- Parola (düz metin veya hash)
- Salt değerleri
- Recovery code (düz metin veya hash)
- Tam veritabanı satırları
- Kişisel veri

Tanılama paketi (`docs/24 §7`) log + sistem bilgisi + şema versiyonu içerir; **veri içermez.**
