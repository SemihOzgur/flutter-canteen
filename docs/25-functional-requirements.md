# 25 — Requirement İndeksi ve İzlenebilirlik

> **Doküman sürümü:** v3 — 9 requirement eklendi (recovery code + kilit kapsamı + ölçek).

Bu doküman tüm requirement'ların **merkezi indeksidir.** Tam metin ve acceptance criteria
kaynak dokümanında bulunur; burada özet, öncelik ve faz eşlemesi tutulur.

**Toplam: 285 requirement · 25 modül** (v1: 244 → v2: 276 → v3: 285)

## Öncelik tanımları

| Öncelik | Anlam |
|---|---|
| 🔴 **M** (Must) | Olmadan v1.0.0 yayınlanamaz |
| 🟡 **S** (Should) | v1.0.0'da olmalı; kritik zaman baskısında ertelenebilir |
| 🟢 **C** (Could) | Değer katar; kapsam dışına alınabilir |

Faz numaraları [31 — Roadmap](31-roadmap.md) ile eşleşir.

### v3'te eklenen requirement'lar

| Grup | Yeni ID'ler | Sebep |
|---|---|---|
| AUTH | 022–028 (7) | **Recovery code** üretimi, saklanması, tek kullanımlık kullanımı, yenilenmesi |
| REP | 014 (1) | **Raporlar ekranı finansal erişim kilidi ile korunur** |
| PERF | 008 (1) | 10.000 ürünlük katalog hedefi; yapay üst sınır yok |

### v3'te anlamı genişleyen requirement'lar

| ID | Değişiklik |
|---|---|
| REQ-AUTH-015 | "Dashboard" → **"Dashboard ve Raporlar"** |
| REQ-AUTH-018 | "mevcut parola" → **"mevcut parola veya recovery code"** |
| REQ-AUTH-019 | "dashboard verisi" → **"finansal ekranların verisi"** |
| REQ-AUTH-021 | Kilit her iki ekranı birden kapsar |
| REQ-DASH-011 | Finansal erişim kilidine referans veriyor |

### v2'de eklenen requirement'lar

| Grup | Yeni ID'ler | Sebep |
|---|---|---|
| AUTH | 013–021 (9) | Rol yokluğunun netleştirilmesi, parola hash'leme, **dashboard parolası** |
| DASH | 011–013 (3) | Dashboard kilidi + KDV dahil/hariç ayrımı |
| BKUP | 019–020 (2) | Düz metin parola yasağı, restore sonrası kilit sıfırlama |
| AUDIT | 012–013 (2) | Dashboard olayları, kalıcı silme kayıtları |
| PROD | 013–015 (3) | Koşullu kalıcı silme, KDV dahil etiket, satış birimi/gramaj |
| DB | 009–011 (3) | Tam sayı miktar, düz metin parola yasağı, ürün alanları |
| VAT | 007–009 (3) | KDV dahil fiyatlandırma, KDV çıkarımı, kâr matrahı |
| SALE | 011–012 (2) | Tam sayı miktar, sepet toplamı |
| FIN | 009 (1) | Tam sayı miktar |
| CART | 009 (1) | Barkodsuz ürünün tıklanarak eklenmesi |
| CAT | 006 (1) | Koşullu kalıcı silme |
| SUP | 005 (1) | Marka/birim genişletilebilirliği |
| REP | 013 (1) | KDV hariç matrah üzerinden kâr |

### v2'de değişen requirement'lar

| ID | Eski | Yeni |
|---|---|---|
| REQ-PROD-006 | "Ürün hard-delete edilemez" | "Satılmış veya stok hareketi olan ürün silinemez" (koşullu silme eklendi) |
| REQ-PROD-011 | "Ambalaj miktarı ve birimi" | "Net ağırlık değeri ve birimi" |
| REQ-CAT-001 | "…silinemez" | Silme koşulu REQ-CAT-006'ya taşındı |
| REQ-IMG-003 | "800 pikseli geçmeyecek" | "Yapılandırılmış sınır değerlerine göre" ([OD-016](28-open-decisions.md)) |
| REQ-IMG-004 | "10 MB'tan büyük" | "Yapılandırılmış üst sınırı aşan" |

---

## ARCH — Mimari · [03](03-architecture.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-ARCH-001 | Presentation katmanı DB'ye doğrudan erişmez | 🔴 M | 1 |
| REQ-ARCH-002 | Domain katmanı framework'ten bağımsız ve test edilebilir | 🔴 M | 1 |
| REQ-ARCH-003 | Transaction sınırları yalnızca servis katmanında | 🔴 M | 1 |
| REQ-ARCH-004 | Ürün/satış/stok repository'leri interface arkasında | 🟡 S | 2 |
| REQ-ARCH-005 | Single-instance lock | 🔴 M | 1 |
| REQ-ARCH-006 | Uzun işlemler UI'yi bloklamaz | 🔴 M | 1 |
| REQ-ARCH-007 | Kullanıcı verisi kurulum dizininden ayrı | 🔴 M | 1 |

## DB — Veritabanı · [05](05-database-architecture.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-DB-001 | WAL + synchronous=FULL + foreign_keys=ON | 🔴 M | 2 |
| REQ-DB-002 | Tüm para alanları tam sayı kuruş | 🔴 M | 2 |
| REQ-DB-003 | Tüm zaman alanları UTC unix-ms | 🔴 M | 2 |
| REQ-DB-004 | Barkod global UNIQUE | 🔴 M | 2 |
| REQ-DB-005 | Tek aktif sepet kısmi unique index | 🔴 M | 2 |
| REQ-DB-006 | Kritik index'ler ilk sürümde mevcut | 🔴 M | 2 |
| REQ-DB-007 | DB dosyası kullanıcı veri dizininde | 🔴 M | 2 |
| REQ-DB-008 | Denormalize alan doğrulama işlevi | 🟡 S | 6 |
| **REQ-DB-009** | **Miktar alanları tam sayı ve pozitif** | 🔴 M | 2 |
| **REQ-DB-010** | **Hiçbir tabloda düz metin parola alanı yok** | 🔴 M | 2 |
| **REQ-DB-011** | **Satış birimi + net ağırlık alanları; ağırlık çifti birlikte** | 🔴 M | 2 |

## MIG — Migration · [06](06-database-migrations.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-MIG-001 | Şema değişiklikleri yalnızca versiyonlu migration ile | 🔴 M | 2 |
| REQ-MIG-002 | Migration öncesi doğrulanmış snapshot | 🔴 M | 2 |
| REQ-MIG-003 | Başarısız migration veriyi geri alır | 🔴 M | 2 |
| REQ-MIG-004 | Migration tek transaction | 🔴 M | 2 |
| REQ-MIG-005 | Daha yeni şema reddedilir | 🔴 M | 2 |
| REQ-MIG-006 | Yarım migration açılışta kurtarılır | 🔴 M | 2 · *kurtarma ekranı v1.0.0* |
| REQ-MIG-007 | Veri kaybettiren migration yasak | 🔴 M | 2 |
| REQ-MIG-008 | Şema versiyonları repoda saklanır | 🟡 S | 2 |

## FIN — Finansal · [07](07-financial-rules.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-FIN-001 | Tam sayı kuruş; floating point yasak | 🔴 M | 1 |
| REQ-FIN-002 | Oranlar basis point | 🔴 M | 1 |
| REQ-FIN-003 | Half-up yuvarlama, satır seviyesinde | 🔴 M | 1 |
| REQ-FIN-004 | Toplam = satır toplamları | 🔴 M | 1 |
| REQ-FIN-005 | `₺#.###,##` tr_TR gösterim | 🔴 M | 1 |
| REQ-FIN-006 | Girişte `,` ve `.` kabul edilir | 🟡 S | 3 |
| REQ-FIN-007 | Yetersiz nakit satışı engeller | 🟡 S | 5 |
| REQ-FIN-008 | Kâr, maliyet snapshot'ı + KDV hariç matrah üzerinden | 🔴 M | 5 |
| **REQ-FIN-009** | **Satış miktarı pozitif tam sayı** | 🔴 M | 5 |

## VAT — KDV · [08](08-vat-rules.md) ✅ *karar kapandı: KDV DAHİL*

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-VAT-001 | KDV oranları yönetilebilir | 🔴 M | 3 |
| REQ-VAT-002 | **Mevzuata bağlı** oran koda gömülmez / seed edilmez; kurulumda yalnızca `%0` (OD-017) | 🔴 M | 3 |
| REQ-VAT-003 | Satır bazında oran snapshot'ı | 🔴 M | 5 |
| REQ-VAT-004 | Oran değişikliği geçmişi bozmaz | 🔴 M | 5 |
| REQ-VAT-005 | Kullanıcı oran tanımlamadıkça KDV'siz çalışır (`%0` varsayılan) | 🟡 S | 3 |
| REQ-VAT-006 | KDV raporu snapshot üzerinden | 🟡 S | 8 |
| **REQ-VAT-007** | **Satış fiyatı KDV dahil; sepet toplamı = girilen fiyatlar** | 🔴 M | 1 |
| **REQ-VAT-008** | **KDV, satır bazında brüt tutardan çıkarılır** | 🔴 M | 1 |
| **REQ-VAT-009** | **Kâr KDV hariç matrah üzerinden** | 🔴 M | 5 |
| **REQ-VAT-010** | **Pasif oran varsayılan yapılamaz** (BR-VAT-006 · OD-019) | 🔴 M | 3 |
| **REQ-VAT-011** | **Pasif oran yeniden aktifleştirilebilir** (OD-020) | 🟡 S | 3 |

## PROD — Ürün · [09](09-product-management.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-PROD-001 | Ad/satış fiyatı/alış fiyatı/kategori zorunlu | 🔴 M | 3 |
| REQ-PROD-002 | Boş alış fiyatı = 0 | 🔴 M | 3 |
| REQ-PROD-003 | Kategori seçilmezse `Genel` | 🔴 M | 3 |
| REQ-PROD-004 | Çoklu barkod | 🔴 M | 3 |
| REQ-PROD-005 | Duplicate barkod reddedilir + sahip ürün gösterilir | 🔴 M | 3 |
| REQ-PROD-006 | *(değişti)* Satılmış/hareketi olan ürün silinemez, pasifleştirilir | 🔴 M | 3 |
| REQ-PROD-007 | Başlangıç stoğu hareket oluşturur | 🔴 M | 3 |
| REQ-PROD-008 | Fiyat değişiklikleri audit'e | 🟡 S | 3 |
| REQ-PROD-009 | Favori ekleme/çıkarma | 🟡 S | 3 |
| REQ-PROD-010 | Türkçe duyarsız arama | 🔴 M | 3 |
| REQ-PROD-011 | *(değişti)* Net ağırlık değeri ve birimi birlikte | 🟢 C | 3 |
| REQ-PROD-012 | %50+ fiyat değişikliğinde onay | 🟢 C | 3 |
| **REQ-PROD-013** | **Hiç kullanılmamış ürün kalıcı silinebilir** | 🟡 S | 3 |
| **REQ-PROD-014** | **Fiyat alanı "KDV Dahil" olarak etiketlenir** | 🔴 M | 3 |
| **REQ-PROD-015** | **Satış birimi ve net ağırlık ayrı, açıklayıcı alanlar** | 🟡 S | 3 |

## CAT / SUP — Kategori, Tedarikçi, Marka, Birim · [10](10-category-brand-supplier.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-CAT-001 | *(değişti)* Kategori oluşturma/düzenleme/pasifleştirme | 🔴 M | 3 |
| REQ-CAT-002 | `Genel` korumalı | 🔴 M | 3 |
| REQ-CAT-003 | Pasif kategori ürünleri etkilemez | 🔴 M | 3 |
| REQ-CAT-004 | Ürünleri başka kategoriye taşıma | 🟢 C | 3 |
| REQ-CAT-005 | Kategori adı benzersiz | 🟡 S | 3 |
| **REQ-CAT-006** | **Hiç kullanılmamış kategori kalıcı silinebilir** | 🟡 S | 3 |
| **REQ-CAT-007** | **Pasif kategori yeniden aktifleştirilebilir** (OD-020) | 🟡 S | 3 |
| **REQ-CAT-008** | **Kategoriye sabit katalogdan ikon seçilebilir** (OD-029) | 🟡 S | v1.1 |
| REQ-SUP-001 | Yalnızca ad ile tedarikçi | 🔴 M | 3 |
| REQ-SUP-002 | Tedarikçi silinemez | 🔴 M | 3 |
| REQ-SUP-003 | Tedarikçi detayında ürün ve girişler | 🟡 S | 6 |
| REQ-SUP-004 | Tedarikçi opsiyonel | 🔴 M | 3 |
| **REQ-SUP-005** | **Marka/birim serbest metin; entity'ye dönüştürülebilir** | 🟡 S | 3 |
| **REQ-SUP-006** | **Pasif tedarikçi yeniden aktifleştirilebilir** (OD-020) | 🟡 S | 3 |

## BARC — Barkod · [11](11-barcode-system.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-BARC-001 | HID klavye girişi; SDK yok | 🔴 M | 4 |
| REQ-BARC-002 | Süre eşiği + Enter ile ayırt etme | 🔴 M | 4 |
| REQ-BARC-003 | Satış ekranında global yakalama | 🔴 M | 4 |
| REQ-BARC-004 | Bulunan ürün onaysız sepete | 🔴 M | 5 |
| REQ-BARC-005 | Tekrar okutma miktarı artırır | 🔴 M | 5 |
| REQ-BARC-006 | Bulunamayan barkod → hızlı ürün ekleme (barkod dolu) | 🔴 M | 5 |
| REQ-BARC-007 | Yeni ürün otomatik sepete | 🔴 M | 5 |
| REQ-BARC-008 | Barkod metin; baştaki sıfır korunur | 🔴 M | 4 |
| REQ-BARC-009 | Lookup < 100 ms | 🔴 M | 4 |
| REQ-BARC-010 | Barkod tanılama ekranı | 🟡 S | 4 |
| REQ-BARC-011 | Dialog açıkken dinleme kapalı | 🟡 S | 4 |
| REQ-BARC-012 | Barkodsuz ürün satılabilir | 🔴 M | 5 |

## CART / SALE — Sepet & Satış · [12](12-sales-system.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-CART-001 | Tek aktif sepet | 🔴 M | 5 |
| REQ-CART-002 | Her değişiklik anında kalıcı | 🔴 M | 5 |
| REQ-CART-003 | Çökme sonrası sepet restore | 🔴 M | 5 |
| REQ-CART-004 | Sepet stok/ciroya etki etmez | 🔴 M | 5 |
| REQ-CART-005 | Satır fiyatı değiştirilebilir; ürün fiyatı değişmez | 🔴 M | 5 |
| REQ-CART-006 | Aynı ürün aynı fiyatla birleşir | 🔴 M | 5 |
| REQ-CART-007 | Restore'da sepet fiyatı korunur, kullanıcı bilgilendirilir | 🟡 S | 5 |
| REQ-CART-008 | Boş sepetle satış yok | 🔴 M | 5 |
| **REQ-CART-009** | **Barkodsuz ürün arama/kategori/favoriden tıklanarak eklenir** | 🔴 M | 5 |
| REQ-SALE-001 | Satış atomik transaction | 🔴 M | 5 |
| REQ-SALE-002 | 5 snapshot alanı (ad, fiyat, maliyet, KDV oranı, kategori) | 🔴 M | 5 |
| REQ-SALE-003 | Geçmiş satışlar değişmez | 🔴 M | 5 |
| REQ-SALE-004 | Fiyat override audit'e | 🟡 S | 5 |
| REQ-SALE-005 | Benzersiz satış numarası | 🔴 M | 5 |
| REQ-SALE-006 | Tamamlama sonrası yeni sepet + odak | 🟡 S | 5 |
| REQ-SALE-007 | Nakit hesaplama opsiyonel | 🟡 S | 5 |
| REQ-SALE-008 | Çift gönderim engellenir | 🔴 M | 5 |
| REQ-SALE-009 | Tamamlama < 50 ms | 🟡 S | 5 |
| REQ-SALE-010 | Satış geçmişi filtrelenebilir | 🟡 S | 7 |
| **REQ-SALE-011** | **Miktarlar pozitif tam sayı** | 🔴 M | 5 |
| **REQ-SALE-012** | **Sepet toplamı = KDV dahil fiyatların toplamı** | 🔴 M | 5 |

## STOCK — Stok · [13](13-stock-system.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-STOCK-001 | Her stok değişimi hareket kaydı | 🔴 M | 6 |
| REQ-STOCK-002 | `stock_quantity` = hareket toplamı | 🔴 M | 6 |
| REQ-STOCK-003 | Hareketler değiştirilemez/silinemez | 🔴 M | 6 |
| REQ-STOCK-004 | `resulting_stock` saklanır | 🔴 M | 6 |
| REQ-STOCK-005 | Negatif stok satışı engellemez; uyarı + Devam Et | 🔴 M | 5 |
| REQ-STOCK-006 | Negatif stok ayrıca listelenir | 🟡 S | 7 |
| REQ-STOCK-007 | Stok girişi tek transaction | 🔴 M | 6 |
| REQ-STOCK-008 | Alış fiyatı güncelleme onayı | 🟡 S | 6 |
| REQ-STOCK-009 | Fire sebep zorunlu + maliyet raporu | 🟡 S | 6 |
| REQ-STOCK-010 | Stok geçmişi referans/sebepleriyle görünür | 🔴 M | 6 |
| REQ-STOCK-011 | `minimum_stock=0` kritik sayılmaz | 🟡 S | 6 |
| REQ-STOCK-012 | Tutarlılık kontrol işlevi | 🟡 S | 6 |

## RET — İade & İptal · [14](14-returns-and-cancellation.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-RET-001 | Satış silinemez | 🔴 M | 7 |
| REQ-RET-002 | İptal tüm stoğu geri ekler | 🔴 M | 7 |
| REQ-RET-003 | Kısmi iade (`Return`/`ReturnItem`) | 🔴 M | 7 |
| REQ-RET-004 | İade satılanı aşamaz | 🔴 M | 7 |
| REQ-RET-005 | İade snapshot fiyatla | 🔴 M | 7 |
| REQ-RET-006 | İade/iptal ayrı stok hareketi | 🔴 M | 7 |
| REQ-RET-007 | Durum otomatik hesaplanır | 🔴 M | 7 |
| REQ-RET-008 | İptal edilmiş satış tekrar iptal/iade edilemez | 🔴 M | 7 |
| REQ-RET-009 | Raporlar net değer gösterir | 🟡 S | 8 |
| REQ-RET-010 | İptal/iade atomik | 🔴 M | 7 |
| REQ-RET-011 | İade, iade tarihine yazılır | 🟡 S | 8 |
| REQ-RET-012 | Sebep bilgisiyle audit'e | 🟡 S | 7 |

## DASH — Dashboard · [15](15-dashboard.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-DASH-001 | 7 tarih aralığı seçeneği | 🔴 M | 8 |
| REQ-DASH-002 | Aralık değişince yeniden hesaplama | 🔴 M | 8 |
| REQ-DASH-003 | Önceki dönemle karşılaştırma | 🟡 S | 8 |
| REQ-DASH-004 | Stok kartları anlık | 🔴 M | 8 |
| REQ-DASH-005 | Otomatik zaman granülerliği | 🟡 S | 8 |
| REQ-DASH-006 | Sipariş listesi dışa aktarma | 🟢 C | 8 |
| REQ-DASH-007 | Net (iade/iptal düşülmüş) metrikler | 🔴 M | 8 |
| REQ-DASH-008 | < 1 sn yükleme | 🟡 S | 8 |
| REQ-DASH-009 | Bağımsız kart yüklemesi | 🟡 S | 8 |
| REQ-DASH-010 | Karttan düzeltme ekranına geçiş | 🟢 C | 8 |
| **REQ-DASH-011** | **Finansal erişim kilidi açılmadan erişilemez** | 🔴 M | 3 |
| **REQ-DASH-012** | **Parola doğrulanmadan veri sorgulanmaz/görünmez** | 🔴 M | 3 |
| **REQ-DASH-013** | **Kâr KDV hariç, ciro KDV dahil; ayrım ekranda belirtilir** | 🔴 M | 8 |

## REP — Raporlar · [16](16-reporting.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-REP-001 | 12 rapor | 🟡 S | 8 |
| REQ-REP-002 | Tarih filtresi | 🔴 M | 8 |
| REQ-REP-003 | CSV dışa aktarma | 🔴 M | 8 |
| REQ-REP-004 | Export filtrelenmiş tümünü kapsar | 🔴 M | 8 |
| REQ-REP-005 | Türkçe karakter uyumlu CSV | 🔴 M | 8 |
| REQ-REP-006 | DB seviyesinde sıralama/sayfalama | 🟡 S | 8 |
| REQ-REP-007 | Kâr raporunda fire | 🟡 S | 8 |
| REQ-REP-008 | Snapshot alanları kullanılır | 🔴 M | 8 |
| REQ-REP-009 | Stok değeri maliyet üzerinden | 🟡 S | 8 |
| REQ-REP-010 | Tedarikçi bazlı sipariş listesi | 🟢 C | 8 |
| REQ-REP-011 | Uzun raporlar iptal edilebilir | 🟢 C | 8 |
| REQ-REP-012 | Export audit'e | 🟡 S | 8 |
| **REQ-REP-013** | **Kâr KDV hariç matrahtan; ciro her iki biçimde gösterilir** | 🔴 M | 8 |
| **REQ-REP-014** | **Raporlar finansal erişim kilidi ile korunur** | 🔴 M | 3 |

## AUTH — Kimlik, Oturum, **Finansal Erişim Kilidi**, **Recovery Code** · [17](17-authentication.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-AUTH-001 | Login ekranı | 🔴 M | 3 |
| REQ-AUTH-002 | Kurulum sihirbazı | 🔴 M | 3 |
| REQ-AUTH-003 | Kalıcı oturum | 🔴 M | 3 |
| REQ-AUTH-004 | Logout temizler + dashboard kilidini kapatır | 🔴 M | 3 |
| REQ-AUTH-005 | Logout sepeti silmez | 🟡 S | 5 |
| REQ-AUTH-006 | Geçersiz kullanıcı → oturum iptal | 🟡 S | 3 |
| REQ-AUTH-007 | Bozuk oturum çökertmez | 🔴 M | 3 |
| REQ-AUTH-008 | Kullanıcı yönetimi (silme hariç) | 🟡 S | 3 |
| REQ-AUTH-009 | En az bir aktif kullanıcı | 🟡 S | 3 |
| REQ-AUTH-010 | Farklı kullanıcı → sepet seçeneği | 🟢 C | 5 |
| REQ-AUTH-011 | 5 hatalı denemede bekleme | 🟢 C | 3 |
| REQ-AUTH-012 | Kullanıcı adı harf duyarsız | 🟡 S | 3 |
| **REQ-AUTH-013** | **Rol/yetki ayrımı yok; tüm kullanıcılar eşit** | 🔴 M | 3 |
| **REQ-AUTH-014** | **Parolalar salt'lı SHA-256; düz metin yok** | 🔴 M | 3 |
| **REQ-AUTH-015** | **Dashboard VE Raporlar ayrı parola gerektirir** | 🔴 M | 3 |
| **REQ-AUTH-016** | **Dashboard parolası kurulumda zorunlu belirlenir** | 🔴 M | 3 |
| **REQ-AUTH-017** | **Dashboard parolası salt'lı hash olarak saklanır** | 🔴 M | 3 |
| **REQ-AUTH-018** | **Değiştirmek için mevcut parola veya recovery code gerekir** | 🔴 M | 3 |
| **REQ-AUTH-019** | **Doğrulanmadan finansal ekran verisi sorgulanmaz** | 🔴 M | 3 |
| **REQ-AUTH-020** | **Kilit olayları audit'e; parola/kod değeri yazılmaz** | 🟡 S | 3 |
| **REQ-AUTH-021** | **Kilit logout/kapanışta sıfırlanır** | 🟡 S | 3 |
| **REQ-AUTH-022** | **Kurulumda recovery code üretilir ve bir kez gösterilir** | 🔴 M | 3 |
| **REQ-AUTH-023** | **Recovery code hash olarak saklanır; düz metin yok** | 🔴 M | 3 |
| **REQ-AUTH-024** | **"Kodu kaydettim" onayı olmadan kurulum ilerlemez** | 🟡 S | 3 |
| **REQ-AUTH-025** | **Recovery code ile dashboard parolası sıfırlanabilir** | 🔴 M | 3 |
| **REQ-AUTH-026** | **Recovery code tek kullanımlıktır** | 🔴 M | 3 |
| **REQ-AUTH-027** | **Kullanım sonrası yeni kod üretilir ve gösterilir** | 🔴 M | 3 |
| **REQ-AUTH-028** | **Kullanıcı parolasıyla yeni kod üretebilir** | 🟢 C | 3 |

## AUDIT — Denetim · [18](18-audit-log.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-AUDIT-001 | Listelenen işlemler kaydedilir | 🔴 M | 6 |
| REQ-AUDIT-002 | Zaman/kullanıcı/işlem/varlık | 🔴 M | 6 |
| REQ-AUDIT-003 | Yalnızca değişen alanlar | 🟡 S | 6 |
| REQ-AUDIT-004 | Parola/hash/salt asla yazılmaz | 🔴 M | 6 |
| REQ-AUDIT-005 | Düzenlenemez/silinemez | 🔴 M | 6 |
| REQ-AUDIT-006 | Aynı transaction'da | 🔴 M | 6 |
| REQ-AUDIT-007 | Audit hatası ana işlemi bozmaz | 🔴 M | 6 |
| REQ-AUDIT-008 | Filtrelenebilir | 🟡 S | 8 |
| REQ-AUDIT-009 | İnsan-okunur gösterim | 🟢 C | 8 |
| REQ-AUDIT-010 | CSV dışa aktarma | 🟢 C | 8 |
| REQ-AUDIT-011 | 2 yıl+ arşivleme | 🟢 C | 11 |
| **REQ-AUDIT-012** | **Dashboard kilit olayları kaydedilir** | 🔴 M | 6 |
| **REQ-AUDIT-013** | **Kalıcı ürün/kategori silme kaydedilir** | 🟡 S | 6 |

## BKUP — Yedekleme · [19](19-backup-restore.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-BKUP-001 | Tek dosyalık yedek | 🔴 M | 9 |
| REQ-BKUP-002 | DB + görsel + metadata + checksum | 🔴 M | 9 |
| REQ-BKUP-003 | Durdurmadan tutarlı snapshot | 🔴 M | 9 |
| REQ-BKUP-004 | Atomik dosya adlandırma | 🔴 M | 9 |
| REQ-BKUP-005 | Yedek sonrası doğrulama | 🔴 M | 9 |
| REQ-BKUP-006 | Restore öncesi tam doğrulama | 🔴 M | 9 |
| REQ-BKUP-007 | Karşılaştırmalı özet | 🔴 M | 9 |
| REQ-BKUP-008 | Kasıtlı onay | 🔴 M | 9 |
| REQ-BKUP-009 | Restore öncesi güvenlik yedeği | 🔴 M | 9 |
| REQ-BKUP-010 | Eski veri silinmez, adı değişir | 🔴 M | 9 |
| REQ-BKUP-011 | Başarısız restore geri alınır | 🔴 M | 9 |
| REQ-BKUP-012 | Yarım restore kurtarılır | 🔴 M | 9 |
| REQ-BKUP-013 | Yeni sürümlü yedek reddedilir | 🔴 M | 9 |
| REQ-BKUP-014 | Eski şema migration ile güncellenir | 🟡 S | 9 |
| REQ-BKUP-015 | Oturum sonlandırma + sayaç düzeltme | 🔴 M | 9 |
| REQ-BKUP-016 | 7 gün yedek hatırlatması | 🟡 S | 9 |
| REQ-BKUP-017 | Audit'e yazılır | 🟡 S | 9 |
| REQ-BKUP-018 | Eksik görsel engellemez | 🟡 S | 9 |
| **REQ-BKUP-019** | **Yedekte düz metin parola bulunmaz** | 🔴 M | 9 |
| **REQ-BKUP-020** | **Restore sonrası dashboard kilidi kapanır + parola uyarısı** | 🔴 M | 9 |

## IMEX — Import/Export · [20](20-import-export.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-IMEX-001 | CSV/Excel ürün import | 🟡 S | 10 |
| REQ-IMEX-002 | Şablon indirme | 🟡 S | 10 |
| REQ-IMEX-003 | Sütun eşleştirme | 🟡 S | 10 |
| REQ-IMEX-004 | Satır bazlı validasyon + önizleme | 🔴 M | 10 |
| REQ-IMEX-005 | Hatalı satırlar sebebiyle listelenir | 🔴 M | 10 |
| REQ-IMEX-006 | Hata listesi CSV | 🟢 C | 10 |
| REQ-IMEX-007 | Onaysız import yok | 🔴 M | 10 |
| REQ-IMEX-008 | Tek transaction, tam rollback | 🔴 M | 10 |
| REQ-IMEX-009 | Barkod çakışma politikası seçilir (BR-IMEX-001) | 🔴 M | 10 |
| REQ-IMEX-010 | Dosya içi duplicate reddedilir (BR-IMEX-002) | 🔴 M | 10 |
| REQ-IMEX-011 | Stok değişimi hareket oluşturur | 🔴 M | 10 |
| REQ-IMEX-012 | Satış/hareket import edilemez | 🔴 M | 10 |
| REQ-IMEX-013 | Export ↔ import uyumlu | 🟡 S | 10 |
| REQ-IMEX-014 | UTF-8 BOM CSV | 🔴 M | 8 |
| REQ-IMEX-015 | Büyük import bloklamaz/iptal edilebilir | 🟡 S | 10 |
| REQ-IMEX-016 | Audit'e yazılır | 🟡 S | 10 |

## IMG — Görseller · [21](21-image-storage.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-IMG-001 | Dosya sisteminde + göreli yol | 🟡 S | 3 |
| REQ-IMG-002 | UUID adlandırma | 🟡 S | 3 |
| REQ-IMG-003 | *(değişti)* Yapılandırılmış sınırlara göre optimizasyon | 🟡 S | 3 |
| REQ-IMG-004 | *(değişti)* Sınırı aşan/bozuk dosya reddi | 🟡 S | 3 |
| REQ-IMG-005 | İçerikten format doğrulama | 🟡 S | 3 |
| REQ-IMG-006 | Gecikmeli silme (.trash) | 🟡 S | 3 |
| REQ-IMG-007 | Açılışta orphan/kırık tarama | 🟡 S | 9 |
| REQ-IMG-008 | Kırık referans temizlenir | 🟡 S | 9 |
| REQ-IMG-009 | Görselsiz ürün hata göstermez | 🔴 M | 3 |
| REQ-IMG-010 | Yedek yalnızca kullanılan görseller | 🟡 S | 9 |
| REQ-IMG-011 | Ürün başına 1 görsel | 🔴 M | 3 |
| REQ-IMG-012 | Elle bakım işlevi | 🟢 C | 9 |
| **REQ-IMG-013** | **Görselsiz ürün: kategori ikonu → addan türetme → nötr ikon** (OD-029) | 🟡 S | v1.1 |

## UX · [23](23-ux-requirements.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-UX-001 | Faresiz satış akışı | 🔴 M | 5 |
| REQ-UX-002 | Odak daima barkod girişinde | 🔴 M | 5 |
| REQ-UX-003 | Yazınca odak otomatik döner | 🔴 M | 5 |
| REQ-UX-004 | 1366×768 tam işlevsel | 🔴 M | 5 |
| REQ-UX-005 | Sepet paneli gizlenmez | 🔴 M | 5 |
| REQ-UX-006 | Pencere durumu saklanır | 🟢 C | 1 |
| REQ-UX-007 | Türkçe, eyleme dönük hatalar | 🔴 M | 11 |
| REQ-UX-008 | Teknik detay gizli | 🔴 M | 11 |
| REQ-UX-009 | Onay yalnızca geri alınamazda | 🟡 S | 11 |
| REQ-UX-010 | F1 kısayol listesi | 🟡 S | 5 |
| REQ-UX-011 | Anlamlı boş durumlar | 🟡 S | 11 |
| REQ-UX-012 | Renk tek başına anlam taşımaz | 🟡 S | 11 |
| REQ-UX-013 | 300 ms+ işlemde gösterge | 🟡 S | 11 |
| REQ-UX-014 | Büyük toplam gösterimi | 🟡 S | 5 |

## PERF / DATA / SEC / COMP · [24](24-non-functional-requirements.md)

| ID | Özet | Ö | Faz |
|---|---|---|---|
| REQ-PERF-001 | Barkod → sepet < 100 ms | 🔴 M | 5 |
| REQ-PERF-002 | Satış transaction < 50 ms | 🟡 S | 5 |
| REQ-PERF-003 | Soğuk açılış < 3 sn | 🟡 S | 11 |
| REQ-PERF-004 | Dashboard < 1 sn | 🟡 S | 8 |
| REQ-PERF-005 | UI 100 ms+ bloklanmaz | 🔴 M | 11 |
| REQ-PERF-006 | Liste sayfalama | 🔴 M | 3 |
| REQ-PERF-007 | SQL aggregation | 🔴 M | 8 |
| **REQ-PERF-008** | **10.000 ürünlük katalogda arama/listeleme hedefleri; yapay üst sınır yok** | 🟡 S | 11 |
| REQ-DATA-001 | Atomik işlem listesi | 🔴 M | 5 |
| REQ-DATA-002 | WAL + FULL | 🔴 M | 2 |
| REQ-DATA-003 | Kesinti sonrası tutarlılık | 🔴 M | 5 |
| REQ-DATA-004 | Yarım işlem kurtarma | 🔴 M | 9 |
| REQ-DATA-005 | Single-instance | 🔴 M | 1 |
| REQ-DATA-006 | Tutarlılık kontrolü | 🟡 S | 6 |
| REQ-DATA-007 | Onaylı, hareketli düzeltme | 🟡 S | 6 |
| REQ-DATA-008 | Veri kurulum dizininde değil | 🔴 M | 1 |
| REQ-SEC-001 | Salt'lı parola hash | 🟡 S | 3 |
| REQ-SEC-002 | Parola hiçbir çıktıda yok | 🔴 M | 3 |
| REQ-SEC-003 | Zip-slip koruması | 🔴 M | 9 |
| REQ-SEC-004 | Aşırı büyük arşiv koruması | 🟡 S | 9 |
| REQ-SEC-005 | CSV formül kaçışı | 🟡 S | 8 |
| REQ-SEC-006 | Parametreli sorgular | 🔴 M | 2 |
| REQ-SEC-007 | Teknik hata log'a | 🔴 M | 1 |
| REQ-SEC-008 | Ağ trafiği yok | 🔴 M | 11 |
| REQ-COMP-001 | Windows 10/11 x64 | 🔴 M | 12 |
| REQ-COMP-002 | DPI ölçekleme | 🟡 S | 12 |
| REQ-COMP-003 | macOS geliştirme desteği | 🔴 M | 1 |
| REQ-COMP-004 | Güncelleme veri korur | 🔴 M | 12 |

---

## Özet dağılım

| Öncelik | Adet | Oran |
|---|---|---|
| 🔴 Must | 185 | %65 |
| 🟡 Should | 84 | %29 |
| 🟢 Could | 16 | %6 |
| **Toplam** | **285** | |

| Faz | Requirement | Not |
|---|---|---|
| 1 — Temel | 18 | |
| 2 — Veritabanı | 21 | Blokajsız |
| 3 — Ürün, Auth, Finansal erişim + Recovery | **69** | **En yüklü — bölünmeli** |
| 4 — Barkod | 7 | |
| 5 — Satış | **45** | En kritik |
| 6 — Stok & Audit | 23 | |
| 7 — İade/İptal | 12 | |
| 8 — Dashboard & Rapor | 34 | |
| 9 — Yedekleme | 27 | |
| 10 — Import/Export | 15 | |
| 11 — Test & Sağlamlaştırma | 11 | Çapraz kesen UX/PERF/SEC |
| 12 — Windows Sürüm | 3 | |
| **Toplam** | **285** | |

> Faz 3'ün yükü v1'e göre 45'ten **69**'a çıkmıştır (finansal erişim kilidi + recovery code + koşullu silme + ürün alanları).
> [31 §3](31-roadmap.md)'te önerildiği gibi 3a–3d alt fazlarına bölünmesi tavsiye edilir.
