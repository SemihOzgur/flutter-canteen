# 33 — Kısa Kullanım Kılavuzu

> **Kime:** kantini işleten kişiye.
> **Kapsam:** günlük kullanım. Geliştirici dokümanı değildir.
>
> Bu kılavuz `docs/31` Faz 12 kapsamındadır ve uygulamanın **mevcut**
> davranışını anlatır. Uygulama değişirse burası da değişir; çelişki hâlinde
> `docs/23` ve `docs/25` geçerlidir.

---

## 1. Kurulum

1. `KantinOtomasyonu-1.0.0-kurulum.exe` dosyasını çalıştırın.
2. Kurulum **Program Files** altına yapılır.
3. İlk açılışta **kurulum sihirbazı** gelir.

| Gereken | |
|---|---|
| İşletim sistemi | Windows 10 (1809 ve üzeri) veya Windows 11 |
| Mimari | 64-bit |
| Ekran | En az 1366×768 önerilir |
| İnternet | **Gerekmez** — uygulama tamamen çevrimdışı çalışır |

### Verileriniz nerede

```text
C:\Users\<kullanıcı>\AppData\Roaming\CanteenApp\
```

> Kurulum ve **güncelleme** bu klasöre dokunmaz. Uygulamayı kaldırsanız bile
> ürünleriniz, satışlarınız ve yedekleriniz burada kalır.

---

## 2. İlk kurulum sihirbazı — atlanamaz

| Adım | Ne yapılır |
|---|---|
| 1 | Kullanıcı adı ve **parola** belirlenir |
| 2 | **Dashboard parolası** belirlenir — ciro/kâr ekranlarını korur |
| 3 | **Kurtarma kodu** gösterilir |

> ⚠️ **Kurtarma kodu bir kez gösterilir.** Kopyalayın veya dosyaya kaydedin.
> Dashboard parolasını unutursanız finansal ekranlara girmenin **tek yolu**
> budur. Kod tek kullanımlıktır; kullanınca yenisi verilir, onu da saklayın.
>
> Hem parolayı hem kodu kaybederseniz **finansal ekranlar kalıcı olarak
> kapanır** — ancak satış, stok ve ürün işlemleri normal çalışmaya devam eder.

---

## 3. Günlük iş: satış

Satış ekranı **klavyeyle** çalışacak şekilde tasarlandı. Fareye gerek yoktur.

```text
Barkodu okut  →  ürün sepete düşer  →  F12  →  satış biter
```

- Barkod okutulduğunda **ara onay yoktur**; ürün doğrudan sepete girer.
- Aynı ürünü tekrar okutursanız yeni satır açılmaz, **miktar artar**.
- **Barkodsuz ürünler** arama kutusundan, kategoriden veya favorilerden
  tıklanarak eklenir.
- Sepetteyken yazmaya başlarsanız odak kendiliğinden arama kutusuna döner ve
  **yazdığınız ilk karakter kaybolmaz.**

### Bilinmeyen barkod

Sistemde olmayan bir barkod okutulursa **Yeni Ürün** ekranı açılır, barkod
alanı doludur. Ad ve fiyatı yazıp kaydedin — ürün otomatik olarak sepete
eklenir.

### Stok bitmişse

Stoğu tükenmiş bir ürün eklenirken uyarı çıkar:

```text
⚠ Bu ürünün stoğu tükenmiş.
   [İptal]        [Devam Et]
```

**"Devam Et" satışı yapar** ve stok eksiye düşer. Bu normaldir: müşteri
kasadaysa satış durmaz, sayım sonra düzeltilir.

### Klavye kısayolları

Tam liste satış ekranında **F1** ile açılır.

| Tuş | |
|---|---|
| yazma | Odak nerede olursa olsun barkod/arama girişine döner |
| `Enter` | Aramadaki ilk ürünü sepete ekler |
| `↑ ↓` | Sepet satırları arasında gezinir |
| `+ / -` | Seçili satırın miktarını değiştirir |
| `Del` | Seçili satırı siler |
| `Alt+1…9` | Favori ürünü sepete ekler |
| `F2` | Seçili satırın fiyatını değiştirir |
| `F3` | Ürün yönetimini açar |
| `F4` | Nakit hesaplama |
| `F12` | **Satışı tamamlar** |
| `Ctrl+Del` | Sepeti temizler (onay ister) |
| `F1` | Kısayol listesi |
| `Esc` | Açık pencereyi kapatır |

> Uygulama kapanırsa veya elektrik giderse **sepetiniz kaybolmaz**; aynı
> hâliyle geri gelir.

---

## 4. Fiyat ve KDV

> **Girdiğiniz satış fiyatı KDV DAHİLDİR.**

₺120,00 yazıp KDV oranını %20 seçerseniz müşteri **₺120,00** öder; KDV bu
tutarın **içinden** hesaplanır (₺20,00), matrah ₺100,00 olur.

- Kurulumda yalnızca **`%0 — KDV Yok`** oranı vardır. Kendi oranlarınızı
  Ayarlar → KDV Oranları'ndan tanımlarsınız.
- Kendi oranınızı tanımlayana kadar KDV `0` hesaplanır.
- Satış sırasında `F2` ile satır fiyatını değiştirebilirsiniz; bu **ürünün
  fiyatını değiştirmez** ve kayda geçer.

---

## 5. Stok

Stok bir **defterdir**: her değişiklik bir hareket olarak yazılır ve silinmez.
"Bu ürünün stoğu neden 12?" sorusu her zaman geriye dönük yanıtlanabilir.

| İşlem | Ne zaman |
|---|---|
| **Stok Girişi** | Mal geldiğinde |
| **Fire** | Bozulan/kırılan ürün — **sebep zorunlu** |
| **Düzeltme** | Sayım farkı — **sebep zorunlu** |

Yanlış bir hareketi silemezsiniz; **ters kayıt** oluşturarak düzeltirsiniz.
Bu kasıtlıdır: defter değişirse geçmiş güvenilirliğini kaybeder.

---

## 6. İade ve iptal

| | Satış İptali | İade |
|---|---|---|
| Kapsam | Satışın tamamı | Satırların bir kısmı veya tamamı |
| Tekrar edilebilir | Hayır | Evet — kalan miktar kadar |
| Ön koşul | Hiç iade yapılmamış olmalı | Satış iptal edilmemiş olmalı |

- İade tutarı **satış anındaki fiyattan** hesaplanır; ürünün güncel fiyatı
  ne olursa olsun müşteri ödediğini geri alır.
- Satış kayıtları **silinmez**, yalnızca durumu değişir.
- İade **yapıldığı tarihe** göre raporlanır; geçmiş ayın cirosu değişmez.

---

## 7. Dashboard ve Raporlar — ayrı parola

Bu iki ekran **dashboard parolası** ister. Uygulamaya girmiş olmanız yetmez.

- Parola girilene kadar **hiçbir ciro/kâr sorgusu çalışmaz.**
- Bir kez girdikten sonra oturum boyunca tekrar sorulmaz.
- **Çıkış yapınca** kilit yeniden devreye girer.

| Rakam | Nasıl okunur |
|---|---|
| Ciro | **KDV dahil** — kasaya giren para |
| Kâr | **KDV hariç** matrah üzerinden (KDV sizin geliriniz değildir) |
| Tümü | **Net** — iptal ve iadeler düşülmüş |

---

## 8. Yedekleme — en önemli bölüm

> Bu uygulamanın sunucusu yoktur. Veriniz **tek bilgisayarda, tek kopya**
> durur. Diskiniz bozulursa yedeğiniz yoksa **her şey gider.**

### Yedek alma

`Yedekleme` → `Yedek Oluştur`. Tek bir `.canteenbackup` dosyası oluşur;
veritabanı, ürün görselleri ve doğrulama bilgileri içindedir.

**Yedeği başka bir yere kopyalayın** — USB bellek, harici disk, başka bir
bilgisayar. Aynı diskte duran yedek, disk bozulduğunda işe yaramaz.

7 gün yedek alınmazsa satış ekranında uyarı çıkar; 30 günde acil hâle gelir.

### Geri yükleme

1. Dosya seçilir → **doğrulanır** (bu adımda mevcut verinize dokunulmaz)
2. Karşılaştırmalı özet gösterilir: yedekte kaç kayıt var, şu an kaç kayıt var
3. Onay için **`GERİ YÜKLE`** yazmanız istenir
4. Mevcut veriniz önce **otomatik olarak yedeklenir**
5. Geri yükleme yapılır ve doğrulanır; bir sorun çıkarsa **eski hâle dönülür**
6. Oturum kapanır, tekrar giriş yaparsınız

> Yedekteki bir ürün fotoğrafı bozuksa geri yükleme **durmaz**; o görsel
> atlanır ve size bildirilir.

---

## 9. Ürün aktarma (CSV)

`İçe/Dışa Aktarma` ekranından şablonu indirin, Excel'de doldurun, CSV olarak
kaydedip geri yükleyin.

- İçe aktarma **önizleme** gösterir; onaylamadan hiçbir kayıt oluşmaz.
- **Ya hepsi ya hiçbiri**: bir satır hatalıysa hiçbir ürün oluşmaz — hangi
  satırın neden reddedildiği listelenir.
- Aynı barkod dosyada iki kez geçiyorsa **iki satır da** reddedilir; sistem
  hangisinin doğru olduğuna karar veremez.
- **Satış ve stok hareketi içe aktarılamaz.**

---

## 10. Sık karşılaşılanlar

| Durum | Ne yapmalı |
|---|---|
| Barkod okuyucu çalışmıyor gibi | Ana ekran → **Barkod Tanılama**'dan okutmayı deneyin |
| "Uygulama zaten çalışıyor" | Aynı anda tek örnek açılabilir; açık pencereyi kullanın |
| Dashboard parolası unutuldu | Finansal erişim ekranı → **Şifremi unuttum** → kurtarma kodu |
| Kullanıcı parolası unutuldu | Kurtarma **yoktur**. Başka bir kullanıcıyla girin |
| Stok sayımla tutmuyor | Ana ekran → **Tutarlılık Kontrolü** |
| Pencere küçük, ekranlar sıkışık | Uygulama 1366×768 ve üzeri için tasarlandı |

---

## 11. Yapmayın

| ❌ | Neden |
|---|---|
| `AppData\Roaming\CanteenApp` içindeki dosyaları elle taşımak/silmek | Veritabanı bozulur; yedekten dönmek gerekir |
| Yedeği yalnızca aynı diskte tutmak | Disk bozulduğunda yedek de gider |
| Kurtarma kodunu saklamamak | Dashboard parolası unutulursa geri dönüşü yoktur |
| Uygulama açıkken kurulum yapmak | Dosyalar kilitlidir; kurulum yarım kalır |
