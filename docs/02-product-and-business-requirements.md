# 02 — Ürün ve Business Requirements

> **Doküman sürümü:** v3 (revizyon: 2026-08-13)
> Bu doküman **business rule kataloğudur.** Kurallar `BR-<MODÜL>-NNN` ile numaralanır.

> **Tek tanım kuralı:** Bir business rule yalnızca burada tanımlanır. Diğer dokümanlar açıklar,
> genişletir, ama **yeniden tanımlamaz.**

**Toplam: 115 business rule.** (v3'te +5: finansal erişim kilidi kapsamı ve recovery code)

---

## 1. Genel

| ID | Kural |
|---|---|
| BR-GEN-001 | Uygulamanın hiçbir temel işlevi internet bağlantısına bağımlı olamaz. |
| BR-GEN-002 | Finansal veya stok etkisi olan hiçbir kayıt fiziksel olarak silinemez. Soft delete veya durum değişikliği kullanılır. |
| BR-GEN-003 | Geçmişi etkileyen her işlem audit log'a kullanıcı bilgisiyle yazılır. Bkz. [18](18-audit-log.md). |
| BR-GEN-004 | Tüm tarih/saat değerleri **UTC** olarak saklanır, kullanıcıya **yerel saat** olarak gösterilir. Rapor gün sınırları yerel saate göre hesaplanır. |
| BR-GEN-005 | Aynı veritabanı üzerinde aynı anda birden fazla uygulama örneği çalışamaz. |

---

## 2. Ürün

| ID | Kural |
|---|---|
| BR-PROD-001 | Bir ürünün **adı**, **satış fiyatı**, **alış fiyatı** ve **kategorisi** zorunludur. |
| BR-PROD-002 | Alış fiyatı hızlı ürün ekleme sırasında boş bırakılabilir; sistem `0` kuruş olarak saklar. Alan asla `null` olamaz. |
| BR-PROD-003 | Kategori zorunludur. Kurulumda `Genel` kategorisi oluşturulur ve kullanıcı seçim yapmazsa varsayılan olarak kullanılır. |
| BR-PROD-004 | Barkod zorunlu değildir. Bir ürünün **0, 1 veya N** barkodu olabilir. |
| BR-PROD-005 | Bir barkod değeri **sistem genelinde benzersizdir**; iki farklı ürüne aynı barkod atanamaz. |
| BR-PROD-006 | Satış fiyatı negatif olamaz. `0` olabilir (ikram/promosyon ürünü). Satış fiyatı **KDV dahildir** (BR-VAT-003). |
| BR-PROD-007 | Alış fiyatı negatif olamaz. |
| BR-PROD-008 | Yeni ürün varsayılanları: `stockQuantity = 0`, `minimumStock = 0`, `isActive = true`, `isFavorite = false`. |
| BR-PROD-009 | Satılmış veya stok hareketi olan ürün **silinemez**; yalnızca pasifleştirilir (`isActive = false`). Pasif ürün satış ekranında görünmez, raporlarda görünür. |
| BR-PROD-010 | Pasif ürünün barkodu benzersizlik kısıtını işgal etmeye **devam eder.** |
| BR-PROD-011 | Satış birimi (`salesUnit`) ve net ağırlık/gramaj (`netWeightValue` + `netWeightUnit`) yalnızca **açıklayıcıdır**; hiçbir finansal veya stok hesabında kullanılmaz. Ağırlık değeri ve birimi ya birlikte doldurulur ya ikisi de boş bırakılır. |
| BR-PROD-012 | Bir ürünün en fazla **bir** görseli olur. |
| BR-PROD-013 | Ürün adı benzersiz olmak zorunda değildir; aynı isim + aynı kategori kombinasyonunda kullanıcı uyarılır (engellenmez). |
| **BR-PROD-014** | **Hiç satılmamış ve hiçbir stok hareketi bulunmayan ürün kalıcı olarak silinebilir.** Bu, yanlış girilen ürünün temizlenmesi içindir ve hiçbir geçmiş kaydı bozmaz. Diğer tüm durumlarda BR-PROD-009 geçerlidir. |

---

## 3. Kategori / Tedarikçi / Marka / Birim

| ID | Kural |
|---|---|
| BR-CAT-001 | Kategoriler ayrı entity'dir; oluşturulabilir, düzenlenebilir, pasifleştirilebilir. |
| BR-CAT-002 | Kullanımdaki (ürünü olan veya geçmiş satışlarda snapshot'ı geçen) kategori **silinemez**; yalnızca pasifleştirilebilir. |
| BR-CAT-003 | Pasif kategoriye bağlı ürünler geçerli kalır ve satılabilir; yalnızca yeni ürün ataması engellenir. |
| BR-CAT-004 | `Genel` kategorisi sistem kategorisidir; silinemez, pasifleştirilemez, adı değiştirilemez. |
| **BR-CAT-005** | **Hiçbir ürüne atanmamış ve hiçbir satış satırı snapshot'ında geçmemiş kategori kalıcı olarak silinebilir.** |
| BR-SUP-001 | Tedarikçi zorunlu değildir; ürün tedarikçisiz olabilir. |
| BR-SUP-002 | Tedarikçi silinemez; pasifleştirilir. Geçmiş stok girişleri ve raporlar korunur. |
| BR-SUP-003 | **V1'de** marka ayrı entity değildir; ürün üzerinde serbest metin + otomatik tamamlama alanıdır. İhtiyaç doğarsa entity'ye dönüştürülebilir ([10 §3](10-category-brand-supplier.md)). |
| BR-SUP-004 | **V1'de** birim ayrı entity değildir; ürün üzerinde serbest metin + öneri listesi alanıdır. İhtiyaç doğarsa entity'ye dönüştürülebilir ([10 §4](10-category-brand-supplier.md)). |

---

## 4. Barkod

| ID | Kural |
|---|---|
| BR-BARC-001 | Barkod okuyucu **USB/Bluetooth HID klavye emülasyonu** ile çalışır; uygulama cihaza özel SDK kullanmaz. |
| BR-BARC-002 | Barkod girişi, karakterler arası süre eşiğine göre klavye yazımından ayırt edilir; sonlandırıcı `Enter`/`CR` karakteridir. |
| BR-BARC-003 | Okutulan barkod veritabanında bulunursa ürün **doğrudan aktif sepete eklenir**; ara onay ekranı gösterilmez. |
| BR-BARC-004 | Barkod bulunamazsa "Yeni Ürün" ekranı açılır ve barkod alanı otomatik doldurulur. |
| BR-BARC-005 | Yeni ürün kaydedildikten sonra ürün otomatik olarak aktif sepete eklenir. |
| BR-BARC-006 | Aynı ürün art arda okutulursa yeni satır açılmaz; mevcut satırın miktarı artırılır. |
| BR-BARC-007 | Barkod arama önce aktif ürünler üzerinde yapılır; yalnızca pasif ürün eşleşirse kullanıcıya "ürün pasif" uyarısı gösterilir. |
| BR-BARC-008 | Barkodsuz ürünler satış ekranında **arama, kategori filtresi veya favoriler üzerinden tıklanarak** sepete eklenebilir. |
| BR-BARC-009 | Barkodlar metin olarak saklanır; baştaki sıfırlar korunur, sayısal tipe dönüştürülmez. |

---

## 5. Sepet ve satış

| ID | Kural |
|---|---|
| BR-CART-001 | Aynı anda yalnızca **bir aktif sepet** bulunabilir. |
| BR-CART-002 | Aktif sepet her değişiklikte kalıcı olarak saklanır; uygulama çökse bile geri yüklenir. |
| BR-CART-003 | Aktif sepet ile tamamlanmış satış **farklı veri yapılarında** tutulur; aktif sepet asla rapora, ciroya veya stoğa yansımaz. |
| BR-CART-004 | Aktif sepet stok rezerve **etmez**. Stok yalnızca satış tamamlandığında düşer. |
| BR-CART-005 | Boş sepet ile satış tamamlanamaz. |
| BR-SALE-001 | Satış tamamlandığında `SaleItem` üzerinde **ürün adı, birim satış fiyatı, birim alış fiyatı (maliyet), KDV oranı ve kategori** snapshot olarak saklanır. |
| BR-SALE-002 | Ürünün güncel fiyatı sonradan değişse bile geçmiş satışlar **değişmez.** |
| BR-SALE-003 | Satış sırasında satır fiyatı değiştirilebilir; bu değişiklik `Product.salePrice` değerini **değiştirmez.** |
| BR-SALE-004 | Satış sırasında yapılan fiyat değişikliği `SaleItem.originalUnitPrice` ile birlikte saklanır ve audit log'a yazılır. |
| BR-SALE-005 | Satış kaydı, satış satırları, stok hareketleri ve stok güncellemesi **tek bir atomik transaction** içinde yazılır. Kısmen yazılmış satış olamaz. |
| BR-SALE-006 | Tamamlanmış satış silinemez. Durumları: `completed`, `cancelled`, `partiallyReturned`, `returned`. |
| BR-SALE-007 | Ödeme yalnızca nakittir. Nakit hesaplama (alınan / para üstü) opsiyoneldir ve satışı bloklamaz. |
| BR-SALE-008 | Alınan nakit, toplam tutardan küçük olamaz (girildiyse). |
| BR-SALE-009 | Her satışın kullanıcıya gösterilen benzersiz bir satış numarası vardır. |
| BR-SALE-010 | Bir satış tamamlandığında ilgili aktif sepet kapatılır ve yenisi boş olarak açılır. |
| **BR-SALE-011** | **Satış miktarı pozitif tam sayıdır (`> 0`).** V1'de ondalık/tartılı satış yoktur. |

---

## 6. Stok

| ID | Kural |
|---|---|
| BR-STOCK-001 | Stok, basit sayaç olarak değil, **hareket defteri (ledger)** olarak tutulur. |
| BR-STOCK-002 | `Product.stockQuantity`, hareket defterinin türetilmiş özetidir ve defterle **aynı transaction içinde** güncellenir. |
| BR-STOCK-003 | Herhangi bir andaki stok, o ana kadarki tüm hareketlerin toplamına **eşit olmak zorundadır.** |
| BR-STOCK-004 | Hareket tipleri: `initial`, `stockEntry`, `sale`, `saleCancellation`, `return`, `waste`, `adjustment`, `importAdjustment`. `quantityDelta` asla `0` olamaz. |
| BR-STOCK-005 | Stok hareketi kaydı hiçbir koşulda güncellenmez veya silinmez; düzeltme yeni bir ters hareketle yapılır. |
| BR-STOCK-006 | Stok 0 veya altındayken satış **engellenmez**; kullanıcı uyarılır ve "Devam Et" ile satışa devam edebilir. |
| BR-STOCK-007 | Negatif stok geçerli bir durumdur; dashboard ve raporlarda ayrıca listelenir. |
| BR-STOCK-008 | Her stok hareketi, işlem sonrası oluşan stok değerini (`resultingStock`) de kaydeder. |
| BR-STOCK-009 | Stok girişinde birim alış fiyatı girilebilir; girilirse ürünün güncel alış fiyatının güncellenmesi kullanıcıya sorulur. |
| BR-STOCK-010 | Her stok hareketi bir **sebep veya referans** taşır: sistem hareketleri referans (satış/iade/import), kullanıcı hareketleri (fire, düzeltme) zorunlu sebep alanı. |

---

## 7. İade / iptal

| ID | Kural |
|---|---|
| BR-RET-001 | Satış iptali (`cancelled`) satışın **tamamını** geri alır ve tüm satırların stoğunu iade eder. |
| BR-RET-002 | İade (`return`) satırların **bir kısmı veya tamamı** için yapılabilir; `Return` + `ReturnItem` entity'leriyle modellenir. |
| BR-RET-003 | Bir satır için toplam iade edilen miktar, satılan miktarı aşamaz. |
| BR-RET-004 | İade/iptal, stok defterine pozitif hareket olarak yazılır; orijinal satış hareketi silinmez. |
| BR-RET-005 | İade tutarı, orijinal `SaleItem.unitPrice` snapshot'ı üzerinden hesaplanır; güncel ürün fiyatı kullanılmaz. |
| BR-RET-006 | İptal edilmiş satış tekrar iptal edilemez ve iade edilemez; iade edilmiş miktar tekrar iade edilemez. |
| BR-RET-007 | Ciro, kâr ve satış adedi raporları iptal ve iadeleri **net** olarak yansıtır (`net = satış − iptal − iade`). |
| BR-RET-008 | **İade, iade tarihine (`returns.createdAt`) göre raporlanır.** Orijinal satışın tarihi ve tutarı değiştirilmez. |

---

## 8. Finansal

| ID | Kural |
|---|---|
| BR-FIN-001 | Tüm parasal değerler veritabanında **tam sayı kuruş** olarak saklanır. Floating point yasaktır. |
| BR-FIN-002 | Tüm oranlar (KDV, indirim) **basis point** tam sayı olarak saklanır. |
| BR-FIN-003 | Yuvarlama gerektiğinde **half-up** kullanılır ve yalnızca satır seviyesinde uygulanır. |
| BR-FIN-004 | Kâr = KDV hariç ciro − (satış anındaki birim maliyet × miktar). Güncel alış fiyatı geçmiş kâra uygulanmaz. |
| BR-FIN-005 | Para gösterimi Türkçe formatındadır: `₺25,50` (binlik `.`, ondalık `,`). |

---

## 9. KDV

| ID | Kural |
|---|---|
| BR-VAT-001 | KDV oranları veritabanında yönetilir; koda gömülmez ve seed edilmez. |
| BR-VAT-002 | Her `SaleItem` kendi KDV oranının snapshot'ını taşır. |
| **BR-VAT-003** | **Ürünün satış fiyatı KDV DAHİLDİR.** Kullanıcı ₺120 girdiğinde müşteriden alınan tutar ₺120'dir. |
| BR-VAT-004 | KDV oranı değişikliği geçmiş satışların KDV tutarını değiştirmez. |
| BR-VAT-005 | Sistemde tanımlı KDV oranı yoksa uygulama KDV'siz çalışır ve KDV alanları gizlenir. |

Detay ve formüller: [08 — VAT Rules](08-vat-rules.md).

---

## 10. Veri yönetimi

| ID | Kural |
|---|---|
| BR-DATA-001 | Kullanıcı verisi (veritabanı, görseller, ayarlar) **kurulum dizininde tutulamaz**; kullanıcı veri dizininde tutulur. |
| BR-DATA-002 | Backup **tek dosyadır** ve veritabanı + görseller + metadata (şema versiyonu, uygulama sürümü, oluşturma tarihi) içerir. |
| BR-DATA-003 | Restore öncesi dosya doğrulanır ve mevcut veri ezilmeden önce otomatik güvenlik yedeği alınır. |
| BR-DATA-004 | Schema değişiklikleri yalnızca versiyonlu migration ile yapılır; uygulama güncellemesi kullanıcı verisini silmez. |
| BR-DATA-005 | Import işlemi ya tamamen uygulanır ya da hiç uygulanmaz (all-or-nothing). |
| BR-DATA-006 | Import/export birincil formatı **CSV**'dir; Excel desteği ayrı bir abstraction arkasından sağlanır. |
| **BR-IMEX-001** | **Import sırasında sistemde zaten kayıtlı bir barkodla karşılaşıldığında uygulanacak politika, import başlamadan önce kullanıcı tarafından seçilir:** *(a)* satırları atla, *(b)* mevcut ürünleri güncelle, *(c)* içe aktarmayı iptal et. Varsayılan **(a)**'dır. |
| **BR-IMEX-002** | **Aynı barkodu birden fazla satırda içeren dosyada, o barkoda ait satırların tamamı reddedilir.** Hangi satırın doğru olduğuna sistem karar veremez. |
| BR-IMEX-003 | Satış, satış satırı ve stok hareketi kayıtları içe aktarılamaz; bu veriler yalnızca uygulama içinde oluşur. |

---

## 11. Görsel

| ID | Kural |
|---|---|
| BR-IMG-001 | Ürün görselleri **dosya sisteminde** saklanır; veritabanında yalnızca göreli dosya yolu tutulur. Görsel binary olarak veritabanına gömülmez. |
| BR-IMG-002 | Yüklenen görseller kaydedilmeden önce **optimize edilir** (yeniden boyutlandırma + yeniden kodlama). Sınır değerleri koda sabit yazılmaz, yapılandırılabilir tutulur — bkz. [OD-016](28-open-decisions.md). |
| BR-IMG-003 | Görsel dosyaları anında silinmez; çöp klasörüne taşınır ve gecikmeli olarak temizlenir. |
| BR-IMG-004 | Yedek dosyası yalnızca veritabanında referansı bulunan görselleri içerir. |
| BR-IMG-005 | Görseli bulunamayan ürün hata göstermez; varsayılan ikonla gösterilir. |

---

## 12. Kimlik doğrulama ve dashboard kilidi

| ID | Kural |
|---|---|
| BR-AUTH-001 | Uygulama login ekranı ile başlar. |
| BR-AUTH-002 | Rol/yetki ayrımı yoktur; tüm kullanıcılar aynı yetkilere sahiptir. Birden fazla kullanıcı desteklenir; `userId` izlenebilirlik için kaydedilir. |
| BR-AUTH-003 | Kullanıcı logout yapmadıkça oturum kalıcıdır; uygulama yeniden açıldığında parola sorulmaz. |
| BR-AUTH-004 | Logout yapıldığında oturum verisi tamamen temizlenir ve dashboard kilidi kapanır. |
| BR-AUTH-005 | Logout anında aktif sepet varsa **korunur**; silinmez. |
| BR-AUTH-006 | Sistemde en az bir aktif kullanıcı bulunmak zorundadır; kullanıcı silinemez, pasifleştirilir. |
| BR-AUTH-007 | *(BR-AUTH-013'e taşındı — kilit kapsamı genişledi)* |
| **BR-AUTH-008** | **Dashboard parolası sistem genelinde tektir; kullanıcıya bağlı değildir ve rol anlamı taşımaz.** |
| **BR-AUTH-009** | **Dashboard parolası salt'lı hash olarak saklanır.** |
| **BR-AUTH-010** | **Dashboard parolasını değiştirmek için mevcut dashboard parolası veya recovery code girilmelidir.** |
| **BR-AUTH-011** | **Kullanıcı parolaları, dashboard parolası ve recovery code, kayıt başına rastgele salt ile SHA-256 hash'lenerek saklanır.** |
| **BR-AUTH-012** | **Parola doğrulanmadan finansal ekranların verisi sorgulanmaz ve gösterilmez.** |
| **BR-AUTH-013** | **Finansal erişim kilidi Dashboard ve Raporlar ekranlarını kapsar.** |
| **BR-AUTH-014** | **Satış, ürün, stok, kategori, tedarikçi, satış geçmişi, iade, ayarlar ve yedekleme ekranları kilit kapsamı dışındadır.** |
| **BR-AUTH-015** | **Dashboard parolası unutulduğunda, kurulumda üretilen tek kullanımlık recovery code ile sıfırlanabilir.** |
| **BR-AUTH-016** | **Finansal erişim kilidi oturum kapsamlıdır: bir kez açıldığında logout veya uygulama kapanışına kadar açık kalır.** |
| **BR-AUTH-017** | **Recovery code kullanıldığında otomatik olarak yeni bir kod üretilir ve kullanıcıya bir kez gösterilir.** |

---

## 13. Güvenlik

| ID | Kural |
|---|---|
| **BR-SEC-001** | **Hiçbir parola veya kurtarma kodu sistemde düz metin olarak saklanmaz, yedeklenmez, dışa aktarılmaz veya loglanmaz.** |
| BR-SEC-002 | Arşivden dosya çıkarırken hedef dizin dışına yazma engellenir; aşırı büyüyen arşivler reddedilir. |
| BR-SEC-003 | Uygulama hiçbir veriyi ağ üzerinden dışarı göndermez. |

---

## 14. V1 kapsam dışı — kesinleşmiş

Aşağıdakiler proje sahibi tarafından **V1 kapsamı dışında** bırakılmıştır ve
[30 — Future Scope](30-future-scope.md)'ta kayıtlıdır:

| Konu | Not |
|---|---|
| Kasa açılışı, vardiya, kasa sayımı, kasa kapanışı, beklenen nakit, kasa farkı | V1'in satış sistemini bloklamamalıdır |
| Tartılı / ondalık miktarlı satış | BR-SALE-011 |
| Rol ve yetki sistemi | BR-AUTH-002 |
| Backend, web panel, cloud sync, cloud backup | — |
| Online ödeme, POS terminali, banka entegrasyonu, termal yazıcı | — |
| Mobil uygulama, multi-store senkronizasyonu | — |
| OAuth, JWT, MFA, parola kurtarma | BR-SEC-001 dışındaki güvenlik karmaşıklığı |

---

## 15. v1 dokümantasyonunda tespit edilip çözülen konular

| # | Konu | Çözüm |
|---|---|---|
| 1 | Kısmi iade isteniyordu ama satış durumları yetmiyordu | `partiallyReturned` durumu + `Return`/`ReturnItem` entity'leri (BR-RET-002) — **proje sahibi tarafından onaylandı** |
| 2 | Parola hash'leme kapsam dışıydı; yedek dosyası düz metin parola taşıyacaktı | BR-SEC-001 + BR-AUTH-011 — **karar kapandı** |
| 3 | KDV oranı snapshot'ı belirtilmemişti | BR-VAT-002 |
| 4 | Alış fiyatı snapshot'ı kesin değildi | BR-SALE-001 — **karar kapandı** |
| 5 | Kategori zorunlu ama pasifleştirilebilir; pasif kategorili ürünün durumu tanımsızdı | BR-CAT-003 |
| 6 | Import'ta barkod çakışma politikası tanımsızdı | BR-IMEX-001, BR-IMEX-002 |
| 7 | Gün sınırı ve zaman dilimi tanımsızdı | BR-GEN-004 |
| 8 | KDV dahil/hariç belirsizdi | BR-VAT-003 — **karar kapandı: DAHİL** |
| 9 | Satış miktarının tipi belirsizdi | BR-SALE-011 — **karar kapandı: INTEGER** |
| 10 | İkinci uygulama örneği senaryosu düşünülmemişti | BR-GEN-005 |
| 11 | Görsel boyut/format sınırı yoktu | BR-IMG-002 + [OD-016](28-open-decisions.md) |
| 12 | Kullanıcı yönetimi ekranı tanımlı değildi | [17 §9](17-authentication.md) |
| 13 | İadenin hangi tarihe yazılacağı belirsizdi | BR-RET-008 — **karar kapandı: iade tarihi** |
| 14 | Ürün ve kategori silme koşulları eksikti | BR-PROD-014, BR-CAT-005 |
| 15 | Dashboard'ın ayrıca korunması gereksinimi yoktu | BR-AUTH-008…017 — **yeni gereksinim eklendi** |
| 16 | v1 dokümantasyonu kasa/vardiya kapanışını kapsama eklemeyi öneriyordu | **Reddedildi** — V1 dışı, [30](30-future-scope.md) |
| 17 | v1 dokümantasyonu 800 px görsel sınırını business rule yapmıştı | **Geri alındı** — yapılandırılabilir teknik politika ([OD-016](28-open-decisions.md)) |
| 18 | v2'de dashboard parolası unutulursa kurtarma yolu yoktu | **Recovery code eklendi** — BR-AUTH-015, BR-AUTH-017 |
| 19 | v2'de Raporlar ekranı korumasızdı ve kilidin amacını zayıflatıyordu | **Kilit kapsamı genişletildi** — BR-AUTH-013 |

---

## 16. Açık kalan konular

> ✅ **Açık karar kalmamıştır.** Tüm konular kapanmıştır — [28 — Karar Kaydı](28-open-decisions.md).

Geliştirme, hiçbir karar beklemeden başlayabilir.
