# 17 — Kimlik Doğrulama, Oturum ve Finansal Erişim Kilidi

> **Doküman sürümü:** v3 — **recovery code** eklendi; finansal erişim kilidi **Raporlar'ı da** kapsıyor.

## 1. Kapsam

| | |
|---|---|
| Var | Login, çoklu kullanıcı, kalıcı oturum, logout, **finansal erişim kilidi**, **recovery code** |
| Yok | Rol/yetki ayrımı, OAuth, JWT, MFA, kullanıcı parolası kurtarma, sunucu tarafı kimlik doğrulama |

### İki ayrı koruma katmanı

| | **Kullanıcı parolası** | **Dashboard parolası** |
|---|---|---|
| Neyi korur | Uygulamanın tamamına giriş | **Dashboard + Raporlar** (finansal ekranlar) |
| Kaç tane | Kullanıcı başına bir tane | Sistemde **tek** tane |
| Nerede saklanır | `users.password_hash` + `password_salt` | `app_settings` (hash + salt) |
| Kime ait | Kişiye | Uygulamaya |
| Kurtarma | ❌ Yok | ✅ **Recovery code ile** |

> **Bu bir rol sistemi DEĞİLDİR.** Rol sistemi kesinlikle olmayacaktır (BR-AUTH-002).
> Tüm kullanıcılar aynı yetkilere sahiptir. Dashboard parolası, finansal bilgi içeren
> ekranlara açılan tek bir kapıdır — kullanıcıya değil, ekrana bağlıdır.

---

## 2. Çoklu kullanıcı yaklaşımı

| Kural | ID |
|---|---|
| Rol/yetki ayrımı yoktur; tüm kullanıcılar aynı yetkilere sahiptir | BR-AUTH-002 |
| `user_id` satış, stok hareketi ve audit log kayıtlarında tutulur — **kim yaptı** izlenebilir | BR-GEN-003 |
| Sistemde en az bir aktif kullanıcı bulunmak zorundadır | BR-AUTH-006 |
| Kullanıcı silinemez; pasifleştirilir | BR-AUTH-006 |

Çoklu kullanıcının tek pratik faydası **izlenebilirliktir**; yetki farkı yaratmaz.
Bkz. [RSK-004](29-risks.md).

---

## 3. Login ekranı

```text
┌───────────────────────────────────┐
│      🏪  Kantin Otomasyonu        │
│                                   │
│   Kullanıcı adı  [____________]   │  ← odak
│   Parola         [____________]   │
│                                   │
│         [   Giriş Yap   ]         │
│                                   │
│   v1.0.0                          │
└───────────────────────────────────┘
```

- `Enter` bir sonraki alana; parola alanında `Enter` giriş yapar.
- Kullanıcı adı büyük/küçük harf duyarsızdır.
- Hatalı giriş: "Kullanıcı adı veya parola hatalı" — hangisinin yanlış olduğu belirtilmez.
- Ardışık 5 hatalı denemeden sonra 30 saniye bekleme.

---

## 4. İlk kurulum sihirbazı

```text
Adım 1 — Kullanıcı hesabı                    [ZORUNLU]
        Kullanıcı adı, görünen ad, parola, parola tekrar

Adım 2 — Dashboard parolası                  [ZORUNLU]
        Dashboard parolası, tekrar
        ℹ "Dashboard ve Raporlar ekranları bu parola ile korunur."

Adım 3 — KURTARMA KODU                       [ZORUNLU — GÖSTERİM]
        ┌────────────────────────────────────────────┐
        │  🔑 Kurtarma Kodunuz                       │
        │                                            │
        │      A7K2 - M9QX - 4RTB - 8ZWD             │
        │                                            │
        │  Dashboard parolanızı unutursanız bu kod   │
        │  ile sıfırlayabilirsiniz.                  │
        │                                            │
        │  ⚠ Bu kod bir daha GÖSTERİLMEYECEK.        │
        │     Güvenli bir yere kaydedin.             │
        │                                            │
        │  [Kopyala]  [Dosyaya Kaydet]               │
        │                                            │
        │  ☐ Kodu kaydettim                          │
        │                        [Devam]  (kutu işaretlenmeden pasif) │
        └────────────────────────────────────────────┘

Adım 4 — KDV oranları                        [atlanabilir]
Adım 5 — Kategoriler                         [atlanabilir]

→ Otomatik giriş → Satış ekranı  (finansal erişim kilidi KAPALI başlar)
```

Adım 4 ve 5 atlanabilir olmalıdır.

---

## 5. Parola saklama

> **KARAR ([OD-003](28-open-decisions.md)):** Parolalar **SHA-256 + rastgele salt** ile saklanır.

| ID | Kural |
|---|---|
| **BR-SEC-001** | Hiçbir parola veya kurtarma kodu sistemde düz metin olarak saklanmaz, yedeklenmez, dışa aktarılmaz veya loglanmaz. |
| **BR-AUTH-011** | Kullanıcı parolaları, dashboard parolası ve recovery code, kayıt başına rastgele salt ile SHA-256 hash'lenerek saklanır. |

### Neden bu seviye yeterli

| Tehdit | Değerlendirme |
|---|---|
| Uzaktan kaba kuvvet | ❌ Yok — ağ dinleyicisi ve API yok |
| Yerel dosya erişimi | Bilgisayara fiziksel erişimi olan zaten uygulamayı kullanabilir |
| **Yedek dosyasının sızması** | ✅ **Asıl risk buydu** — hash'leme ile ortadan kalkar |

**Kapsam dışı:** bcrypt/Argon2, parola politikası zorlaması, kullanıcı parolası kurtarma,
OAuth, JWT, MFA, sunucu tarafı kimlik doğrulama.

---

## 6. Oturum kalıcılığı

> **BR-AUTH-003 — Kullanıcı logout yapmadıkça uygulama açılışında parola sorulmaz.**

`app_settings['session'] = { userId, loginAt }`

**Neden ayrı dosya değil:** backup/restore ile tutarlı davranış, tek kalıcılık mekanizması,
kullanıcı pasifleşirse aynı transaction'da geçersizleştirilebilir. **Token üretilmez.**

### Açılış akışı

```text
Uygulama açıldı
      ▼
app_settings['session'] var mı?
      ├── Yok ────────────────────────► Login ekranı
      └── Var
            ▼
      Kullanıcı hâlâ mevcut ve aktif mi?
            ├── Hayır → oturumu temizle → Login
            └── Evet
                  ▼
            Oturum verisi okunabiliyor mu?
                  ├── Hayır → sessizce temizle → Login   [EC-AUTH-004]
                  └── Evet  → Satış ekranı + aktif sepet restore
                              (finansal erişim kilidi KAPALI)
```

**Oturum zaman aşımı yoktur.** Kantin bilgisayarı kasada durur.

---

## 7. Finansal erişim kilidi

> **BR-AUTH-013 — Dashboard ve Raporlar ekranları, kullanıcı oturumundan ayrı bir
> dashboard parolası gerektirir.**

### Kapsam

| Kilit **arkasında** (finansal) | Kilit **dışında** (normal kullanım) |
|---|---|
| 📊 **Dashboard** | 🛒 Satış ekranı |
| 📈 **Raporlar** (tüm raporlar) | 📦 Ürün yönetimi |
| | 📥 Stok işlemleri (giriş, fire, düzeltme, sayım) |
| | 🏷️ Kategori / tedarikçi / KDV yönetimi |
| | 🔁 Satış geçmişi, iade, iptal |
| | ⚙️ Ayarlar, yedekleme, import/export |

> **Neden Raporlar da dahil:** Raporlar ekranı Dashboard ile **aynı finansal bilgiyi**
> (ciro, kâr, maliyet, stok değeri) daha ayrıntılı biçimde içerir. Yalnızca Dashboard'ı
> korumak, kilidin amacını (kasadaki kişinin finansal veriyi görmemesi) etkisiz kılardı.

> **Neden satış geçmişi dahil DEĞİL:** Kasiyerin yanlış satışı iptal edebilmesi veya iade
> yapabilmesi günlük operasyonun parçasıdır. Satış geçmişi tek tek fişleri gösterir,
> dönemsel finansal özet vermez.

### Akış

```text
Kullanıcı Dashboard (F6) veya Raporlar (F7) açmak istiyor
                            ▼
                  Finansal erişim açık mı?
                    ├── Evet → ekran doğrudan yüklenir
                    └── Hayır
                          ▼
              ┌──────────────────────────────────┐
              │  🔒 Finansal Erişim              │
              │                                  │
              │  Dashboard ve Raporlar için      │
              │  parola gerekiyor.               │
              │                                  │
              │  Parola: [________________]      │  ← odak
              │                                  │
              │  [Şifremi unuttum]               │
              │        [Vazgeç]  [Aç]            │
              └──────────────────────────────────┘
                          ▼
              ├── Doğru  → kilit açılır → audit log → ekran yüklenir
              ├── Yanlış → hata; 5 denemede 30 sn bekleme; audit log
              └── Şifremi unuttum → §8 recovery akışı
```

### Kurallar

| ID | Kural |
|---|---|
| **BR-AUTH-013** | Finansal erişim kilidi Dashboard ve Raporlar ekranlarını kapsar. |
| **BR-AUTH-014** | Diğer ekranlar (satış, ürün, stok, kategori, ayarlar) kilit kapsamı dışındadır. |
| **BR-AUTH-008** | Dashboard parolası sistem genelinde tektir; kullanıcıya bağlı değildir ve rol anlamı taşımaz. |
| **BR-AUTH-009** | Dashboard parolası salt'lı hash olarak `app_settings` içinde saklanır. |
| **BR-AUTH-010** | Dashboard parolasını değiştirmek için mevcut dashboard parolası (veya recovery code) girilmelidir. |
| **BR-AUTH-012** | Parola doğrulanmadan finansal ekranların verisi sorgulanmaz ve gösterilmez. |
| **BR-AUTH-016** | Kilit **oturum kapsamlıdır**: bir kez açıldığında logout veya uygulama kapanışına kadar açık kalır. |

**BR-AUTH-012 önemlidir:** Kilit görsel bir perde değildir. Parola doğrulanmadan dashboard ve
rapor sorguları **çalıştırılmaz** — arka planda hiçbir ciro/kâr verisi yüklenmez.
Bu kural servis katmanında zorlanır, yalnızca UI'da değil ([03 §9](03-architecture.md)).

**BR-AUTH-016 sonucu:** Kullanıcı Dashboard ile Raporlar arasında serbestçe geçiş yapabilir;
parola tekrar sorulmaz. Kilit durumu yalnızca bellekte tutulur, veritabanına yazılmaz.

---

## 8. Recovery code (kurtarma kodu)

> **BR-AUTH-015 — Dashboard parolası unutulduğunda, kurulumda üretilen tek kullanımlık
> recovery code ile sıfırlanabilir.**

### Amaç

Finansal erişimin kalıcı olarak kaybedilmesini önlemek. Recovery code olmadan, parola unutulursa
dashboard ve raporlara bir daha erişilemezdi.

### Format ve üretim

```text
XXXX-XXXX-XXXX-XXXX        örn.  A7K2-M9QX-4RTB-8ZWD
```

- 16 karakter, 4'lü gruplar, kriptografik olarak güvenli rastgele üretim.
- Karışma riski olan karakterler kullanılmaz: `0/O`, `1/I/l`.
- Kullanıcıya **yalnızca bir kez** gösterilir (kurulum sihirbazı Adım 3).
- Kullanıcı "kaydettim" onayı vermeden kurulum ilerlemez.
- Kopyalama ve dosyaya kaydetme seçenekleri sunulur.

### Saklama

```text
app_settings['dashboard_recovery_hash']    → SHA-256(kod + salt)
app_settings['dashboard_recovery_salt']    → rastgele salt
app_settings['dashboard_recovery_used_at'] → kullanıldıysa zaman damgası, yoksa NULL
```

> **Düz metin recovery code hiçbir yerde saklanmaz** (BR-SEC-001). Veritabanında, yedekte,
> log dosyasında, audit kaydında veya export dosyasında bulunmaz.

### Kullanım akışı

```text
Finansal erişim ekranı → [Şifremi unuttum]
      ▼
┌────────────────────────────────────────────┐
│  🔑 Kurtarma Kodu                          │
│                                            │
│  Kurulumda size verilen kurtarma kodunu    │
│  girin:                                    │
│                                            │
│  [____] - [____] - [____] - [____]         │
│                                            │
│            [Vazgeç]   [Doğrula]            │
└────────────────────────────────────────────┘
      ▼
Kod doğrulanıyor (hash karşılaştırması)
      │
      ├── Kod daha önce KULLANILMIŞ → "Bu kurtarma kodu daha önce kullanılmış."
      ├── Kod YANLIŞ → hata; 5 denemede 30 sn bekleme; audit log
      └── Kod DOĞRU
            ▼
      ┌────────────────────────────────────────┐
      │  Yeni Dashboard Parolası               │
      │  Yeni parola:        [____________]    │
      │  Yeni parola (tekrar):[____________]   │
      │                    [Kaydet]            │
      └────────────────────────────────────────┘
            ▼
      TEK TRANSACTION:
        1. dashboard_password_hash / _salt güncellenir
        2. Eski recovery code GEÇERSİZLEŞTİRİLİR (used_at = now)
        3. YENİ recovery code üretilir ve hash'i saklanır
        4. Audit log yazılır (kod değeri YAZILMAZ)
            ▼
      ┌────────────────────────────────────────┐
      │  ✅ Dashboard parolanız değiştirildi.  │
      │                                        │
      │  🔑 YENİ Kurtarma Kodunuz:             │
      │      B3PN - 7WKM - 2XQD - 9FRT         │
      │                                        │
      │  ⚠ Eski kodunuz artık geçersiz.        │
      │     Bu kod bir daha gösterilmeyecek.   │
      │                                        │
      │  [Kopyala] [Dosyaya Kaydet]            │
      │  ☐ Kodu kaydettim          [Tamam]     │
      └────────────────────────────────────────┘
            ▼
      Finansal erişim kilidi AÇILIR (kullanıcı zaten doğruladı)
```

### Tek kullanımlık olma kuralı

| ID | Kural |
|---|---|
| **BR-AUTH-015** | Recovery code tek kullanımlıktır; başarıyla kullanıldıktan sonra geçersizleşir. |
| **BR-AUTH-017** | Recovery code kullanıldığında **otomatik olarak yeni bir kod üretilir** ve kullanıcıya bir kez gösterilir. |

> **BR-AUTH-017'nin gerekçesi:** Kod tek kullanımlık olduğu için, yenisi üretilmezse kullanıcı
> ikinci kez parola unuttuğunda kalıcı olarak kilitlenirdi. Yeni kod üretimi, kurtarma
> yeteneğinin sürekliliğini sağlar.

### Recovery code yeniden görüntüleme / yenileme

Kullanıcı kodu kaybederse, **dashboard parolasını bildiği sürece** Ayarlar üzerinden yeni bir kod üretebilir:

```text
Ayarlar → Finansal Erişim → [Yeni Kurtarma Kodu Üret]
      ▼
Mevcut dashboard parolası sorulur
      ▼
Doğruysa: yeni kod üretilir, eski geçersizleşir, bir kez gösterilir
```

Mevcut kod **asla tekrar gösterilemez** (yalnızca hash'i saklanıyor).

### Hem parola hem recovery code kaybedilirse

Bu durumda finansal erişim kurtarılamaz. Kalan tek yol, dashboard parolasının bilindiği bir
tarihe ait **yedeğin geri yüklenmesidir** — bu, o tarihten sonraki tüm veriyi kaybettirir ve
pratikte önerilmez. Bkz. [RSK-016](29-risks.md).

**Etkinin sınırı:** Bu durumda bile satış, ürün, stok, iade ve yedekleme dahil
**tüm operasyonel işlevler çalışmaya devam eder.** Yalnızca Dashboard ve Raporlar erişilemez olur.

---

## 9. Dashboard parolası değiştirme

```text
Ayarlar → Finansal Erişim → Parolayı Değiştir
   Mevcut dashboard parolası:  [________]   ← zorunlu
   Yeni parola:                [________]
   Yeni parola (tekrar):       [________]
```

Audit log'a yazılır (`dashboardPasswordChanged`) — **parola değeri yazılmaz.**
Recovery code bu işlemden **etkilenmez** (geçerli kalır).

---

## 10. Logout

```text
Kullanıcı "Çıkış Yap" der
      ▼
Aktif sepette ürün var mı?
      ├── Evet → "Sepetinizde 3 ürün var. Çıkış yaparsanız sepet korunur ve
      │           bir sonraki girişte geri yüklenir."
      │          [Vazgeç] [Sepeti Temizle ve Çık] [Çıkış Yap]
      └── Hayır → doğrudan
      ▼
app_settings['session'] silinir
FİNANSAL ERİŞİM KİLİDİ KAPATILIR
Bellekteki kullanıcı durumu temizlenir
      ▼
Login ekranı
```

> **BR-AUTH-005 — Logout aktif sepeti silmez.**

### Farklı kullanıcı giriş yaparsa

```text
"Bu bilgisayarda <Ahmet> kullanıcısına ait yarım kalan bir satış var (3 ürün, ₺95,00)."

[Sepeti Devral]   → carts.user_id yeni kullanıcıya geçer, audit log'a yazılır
[Sepeti Sakla]    → sepet 'abandoned' yapılır ve saklanır, yeni boş sepet açılır
[Sepeti Temizle]  → sepet 'abandoned' yapılır, yeni boş sepet açılır
```

Varsayılan: **Sepeti Devral**.

---

## 11. Kullanıcı yönetimi

| İşlem | Kural |
|---|---|
| Kullanıcı ekle | Kullanıcı adı benzersiz |
| Parola değiştir | Kendi parolası için mevcut parola sorulur |
| Görünen ad değiştir | Serbest |
| Pasifleştir | Son aktif kullanıcı pasifleştirilemez (BR-AUTH-006) |
| Sil | ❌ Yasak — audit log ve satış kayıtları kullanıcıya referans veriyor |

---

## 12. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-AUTH-001 | Uygulama, oturum yoksa login ekranıyla başlar. |
| REQ-AUTH-002 | Veritabanında kullanıcı yoksa kurulum sihirbazı açılır. |
| REQ-AUTH-003 | Oturum, kullanıcı logout yapana kadar kalıcıdır. |
| REQ-AUTH-004 | Logout oturum verisini temizler ve finansal erişim kilidini kapatır. |
| REQ-AUTH-005 | Logout aktif sepeti silmez. |
| REQ-AUTH-006 | Oturumdaki kullanıcı silinmiş veya pasifleşmişse oturum geçersiz sayılır. |
| REQ-AUTH-007 | Bozuk oturum verisi uygulamanın açılmasını engellemez. |
| REQ-AUTH-008 | Kullanıcılar eklenebilir, düzenlenebilir ve pasifleştirilebilir; silinemez. |
| REQ-AUTH-009 | Sistemde en az bir aktif kullanıcı bulunmak zorundadır. |
| REQ-AUTH-010 | Aktif sepet varken farklı kullanıcı giriş yaparsa sepetin akıbeti sorulur. |
| REQ-AUTH-011 | Ardışık 5 hatalı denemeden sonra kısa bir bekleme uygulanır. |
| REQ-AUTH-012 | Kullanıcı adı büyük/küçük harf duyarsızdır. |
| REQ-AUTH-013 | Tüm kullanıcılar aynı yetkilere sahiptir; rol veya yetki ayrımı bulunmaz. |
| REQ-AUTH-014 | Parolalar ve recovery code salt'lı SHA-256 hash olarak saklanır; düz metin yok. |
| **REQ-AUTH-015** | **Dashboard ve Raporlar ekranları ayrı bir dashboard parolası gerektirir.** |
| **REQ-AUTH-016** | **Dashboard parolası kurulum sihirbazında zorunlu olarak belirlenir.** |
| **REQ-AUTH-017** | **Dashboard parolası salt'lı hash olarak saklanır.** |
| **REQ-AUTH-018** | **Parolayı değiştirmek için mevcut parola veya recovery code gerekir.** |
| **REQ-AUTH-019** | **Parola doğrulanmadan finansal ekranların verisi sorgulanmaz.** |
| **REQ-AUTH-020** | **Kilit olayları audit log'a yazılır; parola ve kod değerleri yazılmaz.** |
| **REQ-AUTH-021** | **Kilit oturum kapsamlıdır; logout ve uygulama kapanışında sıfırlanır.** |
| **REQ-AUTH-022** | **Kurulumda `XXXX-XXXX-XXXX-XXXX` formatında bir recovery code üretilir ve kullanıcıya bir kez gösterilir.** |
| **REQ-AUTH-023** | **Recovery code hash olarak saklanır; düz metni hiçbir yerde bulunmaz.** |
| **REQ-AUTH-024** | **Kullanıcı, kodu kaydettiğini onaylamadan kurulum ilerlemez.** |
| **REQ-AUTH-025** | **Recovery code ile dashboard parolası sıfırlanabilir.** |
| **REQ-AUTH-026** | **Recovery code tek kullanımlıktır; kullanıldıktan sonra geçersizleşir.** |
| **REQ-AUTH-027** | **Recovery code kullanıldığında yeni bir kod üretilir ve bir kez gösterilir.** |
| **REQ-AUTH-028** | **Kullanıcı, mevcut dashboard parolasıyla yeni bir recovery code üretebilir.** |

---

## 13. Acceptance criteria

**REQ-AUTH-015 / REQ-AUTH-019 — kapsam**
```text
Given: Kullanıcı giriş yapmış, finansal erişim kilidi kapalı
When:  F6 (Dashboard) veya F7 (Raporlar) açılmak isteniyor
Then:  Finansal erişim parolası ekranı gösterilir
And:   Arka planda hiçbir dashboard/rapor sorgusu çalıştırılmamıştır
And:   Hiçbir ciro, kâr veya maliyet rakamı ekranda görünmez
When:  Kullanıcı Satış, Ürünler, Stok veya Kategori ekranına gidiyor
Then:  Hiçbir parola sorulmaz
```

**REQ-AUTH-021 — oturum kapsamı**
```text
Given: Kullanıcı Dashboard için doğru parolayı girmiş
When:  Raporlar ekranına geçiyor
Then:  Parola tekrar sorulmaz
When:  Satış ekranına gidip tekrar Dashboard'a dönüyor
Then:  Parola tekrar sorulmaz
When:  Logout yapıp tekrar giriş yapıyor ve Dashboard'a gidiyor
Then:  Parola tekrar sorulur
When:  Uygulama kapatılıp açılıyor ve Raporlar'a gidiliyor
Then:  Parola tekrar sorulur
```

**REQ-AUTH-022 / REQ-AUTH-024 — kurulum**
```text
Given: Kurulum sihirbazı çalışıyor
When:  Dashboard parolası belirlendi
Then:  XXXX-XXXX-XXXX-XXXX formatında bir recovery code gösterilir
And:   Kod 0/O ve 1/I/l karakterlerini içermez
And:   "Kodu kaydettim" işaretlenmeden "Devam" pasiftir
And:   Kopyala ve dosyaya kaydet seçenekleri sunulur
```

**REQ-AUTH-025 / REQ-AUTH-026 / REQ-AUTH-027 — kurtarma**
```text
Given: Kullanıcı dashboard parolasını unutmuş
When:  Finansal erişim ekranında "Şifremi unuttum" seçiliyor
And:   Doğru recovery code giriliyor
Then:  Yeni dashboard parolası belirleme ekranı açılır
When:  Yeni parola kaydediliyor
Then:  Dashboard parolası tek transaction içinde güncellenir
And:   Kullanılan recovery code geçersizleşir (used_at dolar)
And:   YENİ bir recovery code üretilir ve kullanıcıya bir kez gösterilir
And:   Finansal erişim kilidi açılır
And:   Audit log'a kayıt yazılır, kod değeri yazılmaz
When:  Aynı (eski) recovery code tekrar kullanılmak isteniyor
Then:  "Bu kurtarma kodu daha önce kullanılmış" hatası verilir
```

**REQ-AUTH-014 / REQ-AUTH-023 — saklama**
```text
Given: Kullanıcı, dashboard parolası ve recovery code belirlenmiş
When:  Veritabanı dosyası bir SQLite tarayıcısıyla açılıyor
Then:  users.password_hash alanında düz metin parola görünmez
And:   app_settings içinde düz metin dashboard parolası görünmez
And:   app_settings içinde düz metin recovery code görünmez
And:   Her kayıt için farklı bir salt bulunur
When:  Yedek dosyası oluşturulup tüm içeriği taranıyor
Then:  Hiçbir dosyada düz metin parola veya recovery code bulunmaz
```

**REQ-AUTH-003**
```text
Given: Kullanıcı giriş yapmış ve logout yapmamış
When:  Uygulama kapatılıp tekrar açılıyor
Then:  Login ekranı gösterilmez ve satış ekranı açılır
And:   Aktif sepet geri yüklenir
And:   Finansal erişim kilidi KAPALI durumdadır
```
