# 23 — UX Gereksinimleri

> **Doküman sürümü:** v3 — finansal erişim kilidi kısayol davranışı güncellendi.

## 1. Tasarım ilkeleri

| İlke | Anlamı |
|---|---|
| **Klavye önce** | Satış akışının tamamı fare olmadan yapılabilmelidir |
| **Odak asla kaybolmaz** | Satış ekranında odak varsayılan olarak daima barkod girişindedir |
| **Sıfır gereksiz tıklama** | Barkod okutmadan satış tamamlamaya en fazla 2 tuş |
| **Onay yalnızca geri alınamaz işlemlerde** | Sepetten ürün silmek onay istemez; satış iptali ister |
| **Hata mesajı = ne oldu + ne yapmalıyım** | "Hata: -2147" yasak |
| **Masaüstü uygulaması gibi davran** | Web sayfası taklidi değil; kısayollar, menü, pencere davranışı |
| **Rakamlar okunabilir** | Kasa ekranı uzaktan görünür; tutarlar büyük ve kalın |

---

## 2. Klavye kısayolları

### Genel

| Tuş | İşlev |
|---|---|
| `F1` | Yardım / kısayol listesi |
| `F2` | Satış ekranı |
| `F3` | Ürünler |
| `F5` | Stok |
| `F6` | Dashboard — **finansal erişim kilidi kapalıysa parola sorulur** ([15 §0](15-dashboard.md)) |
| `F7` | Raporlar — **aynı kilit geçerlidir** (BR-AUTH-013) |
| `F8` | Satış geçmişi |
| `Ctrl+,` | Ayarlar |
| `Esc` | Geri / dialog kapat |

### Satış ekranı

| Tuş | İşlev |
|---|---|
| *(yazma)* | Barkod / arama girişi — odak nerede olursa olsun |
| `Enter` | Arama sonucundaki ilk/seçili ürünü ekle |
| `↑` `↓` | Sepet satırları arasında gezin |
| `+` / `-` | Seçili satırın miktarını değiştir |
| `*` + sayı + `Enter` | Miktarı doğrudan gir |
| `Del` | Seçili satırı sil |
| `Ctrl+Z` | Son sepet işlemini geri al |
| `Alt+1..9` | Favori ürün ekle |
| `F2` | Seçili satırın fiyatını değiştir |
| `F4` | Nakit hesaplama |
| `F12` | **Satışı tamamla** |
| `Ctrl+Del` | Sepeti temizle (onaylı) |

### Listeler ve formlar

| Tuş | İşlev |
|---|---|
| `Ctrl+N` | Yeni kayıt |
| `Ctrl+F` | Ara |
| `Ctrl+S` | Kaydet |
| `Enter` | Sonraki alan (son alanda: kaydet) |
| `Esc` | Vazgeç |
| `Ctrl+E` | Dışa aktar |

> Tüm kısayollar `F1` ekranında listelenir ve yazdırılabilir/dışa aktarılabilir.

---

## 3. Odak yönetimi

Satış ekranında odak **her zaman** aşağıdaki kurala uyar:

```text
Varsayılan          → barkod/arama girişi
Dialog açıldı       → dialogun ilk alanı
Dialog kapandı      → barkod/arama girişi
Satış tamamlandı    → barkod/arama girişi
Ürün eklendi        → barkod/arama girişi
Başka ekrandan dönüldü → barkod/arama girişi
```

Kullanıcı `↑`/`↓` ile sepette gezindiğinde odak sepettedir; **ancak yazmaya başlarsa
otomatik olarak barkod girişine döner** ve yazılan karakter kaybolmaz.

Bu davranış, kasada "neden barkod çalışmıyor?" sorununu tamamen ortadan kaldırır.

---

## 4. Ekran düzeni ve responsive davranış

| Çözünürlük | Davranış |
|---|---|
| 1920×1080 (hedef) | Tam düzen; ürün ızgarası 5 sütun |
| 1600×900 | Ürün ızgarası 4 sütun |
| 1366×768 (minimum) | Ürün ızgarası 3 sütun; sepet paneli daralır ama korunur |
| < 1366×768 | Desteklenmez; uyarı gösterilir |

- Minimum pencere boyutu: 1280×720 (altına küçültülemez).
- Pencere boyutu ve konumu `app_settings`'te saklanır ve geri yüklenir.
- Tam ekran modu (`F11`) desteklenir — kasa bilgisayarında tipik kullanım.
- **Sepet paneli asla gizlenmez veya sekmeye dönüşmez** — satış ekranının vazgeçilmezidir.

---

## 5. Görsel dil

| Öğe | Kural |
|---|---|
| Tema | Açık tema varsayılan; koyu tema opsiyonel (kasa ekranı genelde aydınlık ortamda) |
| Ana font boyutu | 14 px taban; sepet tutarları 18 px, genel toplam 32 px kalın |
| Tıklanabilir alan | Minimum 40×40 px |
| Renk kodu | 🟢 başarı · 🟡 uyarı/kritik stok · 🔴 hata/negatif stok · 🔵 bilgi |
| Renk tek başına anlam taşımaz | Her renkli durum ikon + metinle de ifade edilir |
| Animasyon | Minimum; 150 ms'yi geçmez. Kasa akışında animasyon = beklenen süre |
| Yükleme göstergesi | 300 ms'den kısa işlemler için gösterilmez (titreşim etkisi) |

---

## 6. Geri bildirim ve hata mesajları

### Format

```text
[İkon] <Ne oldu>
       <Neden / ne yapmalıyım>
       [Eylem butonu]
```

### Örnekler

| ❌ Kötü | ✅ İyi |
|---|---|
| "Hata oluştu" | "Ürün kaydedilemedi. Bu barkod zaten 'Coca Cola 330ml' ürününe ait. [Ürüne Git]" |
| "Invalid input" | "Satış fiyatı geçersiz. Örnek: 25,50" |
| "Yetkiniz yok" | "Dashboard ve Raporlar için parola gerekir. [Şifremi unuttum]" |
| "Miktar hatalı" | "Miktar tam sayı olmalıdır. Örnek: 1, 2, 3" |
| "SQLITE_BUSY" | "Veritabanı meşgul, işlem tekrar deneniyor..." |
| "Stok yetersiz" | "Bu ürünün stoğu tükenmiş (0 adet). Devam ederseniz stok eksiye düşer. [İptal] [Devam Et]" |

### Bildirim türleri

| Tür | Kullanım | Süre |
|---|---|---|
| Toast (alt orta) | Başarı bildirimleri | 3 sn, tıklayınca kapanır |
| Satır içi | Form validasyonu | Kalıcı |
| Dialog | Onay gerektiren, geri alınamaz | Kullanıcı kapatana kadar |
| Üst çubuk | Sistem uyarıları (yedek hatırlatması) | Kalıcı, kapatılabilir |

---

## 7. Boş durumlar

Her liste ekranının anlamlı bir boş durumu olmalıdır:

| Ekran | Boş durum |
|---|---|
| Ürünler | "Henüz ürün eklemediniz. [Ürün Ekle] [Excel'den İçe Aktar]" |
| Satış geçmişi | "Bu tarih aralığında satış bulunmuyor. [Tarih aralığını genişlet]" |
| Sepet | "Barkod okutun veya ürün arayın" + kısayol ipuçları |
| Dashboard | "Henüz satış verisi yok. İlk satışınızı yapın. [Satış Ekranı]" |
| Kritik stok | "✅ Kritik stokta ürün yok" (olumlu, yeşil) |
| Rapor | "Seçilen kriterlere uygun kayıt bulunamadı. [Filtreleri temizle]" |

---

## 8. Erişilebilirlik (temel düzey)

- Tüm etkileşimli öğelere `Tab` ile ulaşılabilir; sıra mantıklıdır.
- Odaklanan öğe belirgin bir çerçeveyle işaretlenir.
- Metin/arka plan kontrast oranı en az 4.5:1.
- Ekran okuyucu desteği hedeflenmez (masaüstü kasa uygulaması), ancak Flutter'ın
  varsayılan semantik davranışları bozulmaz.

---

## 9. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-UX-001 | Satış akışının tamamı (okut → ekle → tamamla) fare kullanılmadan yapılabilir. |
| REQ-UX-002 | Satış ekranında odak varsayılan olarak barkod girişindedir ve her işlem sonrası oraya döner. |
| REQ-UX-003 | Kullanıcı sepette gezinirken yazmaya başlarsa odak otomatik olarak barkod girişine geçer ve girilen karakter kaybolmaz. |
| REQ-UX-004 | Uygulama 1366×768 çözünürlükte tam işlevsel çalışır. |
| REQ-UX-005 | Sepet paneli hiçbir çözünürlükte gizlenmez. |
| REQ-UX-006 | Pencere boyutu ve konumu kapanışta saklanır, açılışta geri yüklenir. |
| REQ-UX-007 | Tüm hata mesajları Türkçedir ve ne yapılması gerektiğini belirtir. |
| REQ-UX-008 | Teknik hata kodları ve stack trace kullanıcıya gösterilmez. |
| REQ-UX-009 | Geri alınamaz işlemler onay ister; geri alınabilir işlemler istemez. |
| REQ-UX-010 | Tüm klavye kısayolları `F1` ekranında listelenir. |
| REQ-UX-011 | Her liste ekranının eyleme yönlendiren bir boş durumu vardır. |
| REQ-UX-012 | Renkle iletilen her durum ikon veya metinle de ifade edilir. |
| REQ-UX-013 | 300 ms'den uzun süren işlemler ilerleme göstergesi gösterir. |
| REQ-UX-014 | Satış ekranında toplam tutar uzaktan okunabilecek boyutta gösterilir. |

---

## 10. Acceptance criteria

**REQ-UX-001**
```text
Given: Fare bilgisayardan çıkarılmış
When:  Kullanıcı 3 ürün okutup F12'ye basıyor
Then:  Satış başarıyla tamamlanır
And:   Hiçbir adımda fare gerekmemiştir
```

**REQ-UX-003**
```text
Given: Kullanıcı ↓ tuşuyla sepetteki 2. satırı seçmiş
When:  Barkod okuyucu bir barkod okutuyor
Then:  Barkod tam olarak yakalanır (ilk karakter kaybolmaz)
And:   Ürün sepete eklenir
And:   Odak barkod girişine döner
```

**REQ-UX-004 / REQ-UX-005**
```text
Given: Uygulama 1366×768 çözünürlükte çalışıyor
When:  Satış ekranı açılıyor
Then:  Barkod girişi, ürün listesi ve sepet paneli aynı anda görünür
And:   Hiçbir kaydırma çubuğu satış akışını engellemez
And:   "Satışı Tamamla" butonu görünür durumdadır
```
