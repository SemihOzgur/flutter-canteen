# 26 — Edge Case Kataloğu

> **Doküman sürümü:** v3 — recovery code (12 senaryo) ve genişletilmiş kilit kapsamı eklendi.
> Toplam ~168 edge case.

Her edge case: **durum → beklenen davranış**. Bu liste test senaryolarının doğrudan kaynağıdır ([27](27-testing-strategy.md)).

---

## 1. Ürün

| ID | Durum | Beklenen davranış |
|---|---|---|
| EC-PROD-001 | Aynı barkod ikinci ürüne ekleniyor | Reddedilir; sahip ürün gösterilir; "Ürüne git" sunulur |
| EC-PROD-002 | Barkodsuz ürün oluşturuluyor | İzin verilir; ürün favoriler/arama ile satılır |
| EC-PROD-003 | Aynı barkod aynı üründe ikinci kez ekleniyor | Sessizce yok sayılır; hata gösterilmez |
| EC-PROD-004 | Sepette olan ürün pasifleştiriliyor | Sepette kalır; satış tamamlanabilir; satır uyarı rozetiyle gösterilir |
| EC-PROD-005 | Ürünün kategorisi pasifleştirilmiş | Ürün geçerli kalır ve satılabilir; formda "(pasif)" etiketi |
| EC-PROD-006 | Ürünün tedarikçisi pasifleştirilmiş | Ürün geçerli kalır; raporlarda tedarikçi görünür |
| EC-PROD-007 | Satış fiyatı `0` | İzin verilir (ikram ürünü); kâr negatif hesaplanır |
| EC-PROD-008 | Satış fiyatı negatif | Reddedilir |
| EC-PROD-009 | Alış fiyatı > satış fiyatı | İzin verilir; uyarı gösterilir; kâr raporunda negatif kâr |
| EC-PROD-010 | Aynı ad + aynı kategoride ürün var | İzin verilir; uyarı gösterilir |
| EC-PROD-011 | `minimum_stock = 0` | Kritik stok uyarısına girmez |
| EC-PROD-012 | Ürün adı 200 karakter | 120'ye kırpılır (import'ta) / form 120 ile sınırlar |
| EC-PROD-013 | Ürün adı yalnızca boşluk | Reddedilir |
| EC-PROD-014 | Barkod baştaki sıfırla giriliyor (`0123...`) | Sıfır korunur; sayıya çevrilmez |
| EC-PROD-015 | Barkod EAN-13 checksum'ı geçersiz | Uyarı gösterilir; kayda izin verilir |
| EC-PROD-016 | Ürünün tek barkodu siliniyor | İzin verilir; ürün barkodsuz hale gelir; audit'e yazılır |
| EC-PROD-017 | Görsel eklendi, ürün kaydedilmeden çıkıldı | Geçici dosya `temp/`'te kalır; 1 gün sonra temizlenir |
| EC-PROD-018 | Net ağırlık girilmiş, birim boş (veya tersi) | Kayıt reddedilir (BR-PROD-011) |
| EC-PROD-019 | Hiç satılmamış, hiç stok hareketi olmayan ürün siliniyor | Kalıcı silinir; barkodları benzersizlik havuzundan çıkar; audit'e yazılır (BR-PROD-014) |
| EC-PROD-020 | Satılmış ürün siliniyor | Kalıcı silme sunulmaz; yalnızca pasifleştirme (BR-PROD-009) |
| EC-PROD-021 | Stok hareketi olan ama hiç satılmamış ürün siliniyor | Kalıcı silme sunulmaz — stok defteri referansı korunur |
| EC-PROD-022 | Kalıcı silinen ürünün barkodu yeni bir ürüne atanıyor | İzin verilir (barkod artık serbest) |
| EC-PROD-023 | Ürün fiyatı KDV dahil ₺120 giriliyor, KDV oranı yok | `line_vat = 0`, `line_net = line_total = 12000` (BR-VAT-005) |

## 2. Kategori / Tedarikçi

| ID | Durum | Beklenen davranış |
|---|---|---|
| EC-CAT-001 | `Genel` kategorisi silinmeye/pasifleştirilmeye çalışılıyor | Engellenir; sebep açıklanır |
| EC-CAT-002 | İçinde 100 ürün olan kategori pasifleştiriliyor | İzin verilir; ürün sayısı gösterilir; taşıma seçeneği sunulur |
| EC-CAT-003 | Pasif kategorinin adı yeni kategoriye veriliyor | Reddedilir (isim benzersizliği pasifleri de kapsar) |
| EC-CAT-004 | Kategori birleştirme sırasında hata | Tam rollback; hiçbir ürünün kategorisi değişmez |
| EC-CAT-005 | Hiç kullanılmamış kategori siliniyor | Kalıcı silinir; audit'e yazılır (BR-CAT-005) |
| EC-CAT-006 | Ürünü olmayan ama geçmiş satış snapshot'ında geçen kategori siliniyor | Kalıcı silme **sunulmaz** — geçmiş kategori raporu bozulur; pasifleştirme önerilir |
| EC-SUP-001 | Tedarikçi pasifleştiriliyor, bağlı ürünler var | İzin verilir; ürünler etkilenmez |
| EC-SUP-002 | Tedarikçisiz stok girişi | İzin verilir; `supplier_id = NULL` |

## 3. Barkod

| ID | Durum | Beklenen davranış |
|---|---|---|
| EC-BARC-001 | Kullanıcı elle hızlı yazıyor, Enter'a basıyor | Barkod sayılmaz; normal arama çalışır |
| EC-BARC-002 | Barkod okundu ama Enter gelmedi | 300 ms sonra buffer temizlenir; işlem yapılmaz |
| EC-BARC-003 | Yarım barkod okundu (kısa hareket) | 4 karakterden kısaysa yok sayılır |
| EC-BARC-004 | 64 karakterden uzun giriş | Buffer temizlenir; uyarı |
| EC-BARC-005 | Dialog açıkken barkod okutuluyor | Yok sayılır (REQ-BARC-011) |
| EC-BARC-006 | Aynı barkod 3 kez arka arkaya çok hızlı okutuluyor | 3 ayrı ekleme; miktar 3 olur; kayıp yaşanmaz |
| EC-BARC-007 | Barkod pasif ürüne ait | "Ürün pasif" sorulur; aktifleştirme seçeneği |
| EC-BARC-008 | Barkod okutulurken sepet DB yazımı sürüyor | Sıraya alınır; kayıp olmaz |
| EC-BARC-009 | Türkçe klavye düzeninde alfanümerik barkod | Yanlış karakter riski; tanılama ekranı ile tespit edilir ([RSK-006](29-risks.md)) |
| EC-BARC-010 | Barkod okutuldu, ürün ekleme dialogu iptal edildi | Ürün oluşmaz; sepete ekleme olmaz; barkod alanı temizlenir |

## 4. Sepet

| ID | Durum | Beklenen davranış |
|---|---|---|
| EC-CART-001 | Uygulama sepet doluyken çöküyor | Yeniden açılışta sepet aynen geri gelir |
| EC-CART-002 | Sepetteki ürünün fiyatı başka ekrandan değiştirildi | Sepetteki fiyat korunur; satır "fiyat güncellendi" rozetiyle işaretlenir |
| EC-CART-003 | Sepette miktar `0`'a düşürülüyor | Satır silinir (onay sorulur) |
| EC-CART-004 | Aynı ürün farklı fiyatlarla sepette | İki ayrı satır olarak durur |
| EC-CART-005 | Sepette 200 satır var | Performans korunur; liste sanallaştırılır |
| EC-CART-006 | Aktif sepet varken farklı kullanıcı giriş yapıyor | 3 seçenek sunulur: devral / sakla / temizle ([17 §6](17-authentication.md)) |
| EC-CART-007 | Backup restore edildi, restore öncesi sepet vardı | Yedekteki sepet geçerli olur; mevcut sepet kaybolur (özet ekranında belirtilir) |
| EC-CART-008 | Migration sonrası sepet | Korunur; şema değişikliği sepet tablolarını etkilerse migration bunu taşır |
| EC-CART-009 | Veritabanında iki `active` sepet oluşmuş (bozulma) | Kısmi unique index engeller; yine de oluşursa en yenisi tutulur, diğeri `abandoned` yapılır, log'a yazılır |
| EC-CART-010 | Sepetteki ürün DB'de bulunamıyor (bozulma) | Satır kaldırılır; kullanıcı bilgilendirilir; sepetin kalanı korunur |

## 5. Satış

| ID | Durum | Beklenen davranış |
|---|---|---|
| EC-SALE-001 | Boş sepetle F12 | "Sepet boş" uyarısı; işlem yapılmaz |
| EC-SALE-002 | Satış transaction'ı ortasında hata | Tam rollback; sepet korunur; hata gösterilir |
| EC-SALE-003 | Satış sırasında elektrik kesiliyor | Satış ya tam ya hiç; yarım satış oluşmaz |
| EC-SALE-004 | Aynı ürünün birden fazla barkodu ile ekleniyor | Aynı üründür; tek satırda birleşir (fiyat aynıysa) |
| EC-SALE-005 | Satış sırasında ürünün stoğu başka yolla değişti | Satış anındaki değer kullanılır; hareket `resulting_stock` doğru hesaplanır |
| EC-SALE-006 | Fiyat `0`'a düşürülüyor | İzin verilir (ikram); audit'e yazılır |
| EC-SALE-007 | Fiyat negatife düşürülmeye çalışılıyor | Reddedilir |
| EC-SALE-008 | F12'ye 3 kez basılıyor | Tek satış oluşur; buton kilitlenir |
| EC-SALE-009 | Nakit alınan < toplam | Tamamla butonu pasif |
| EC-SALE-010 | Nakit alınan çok büyük (₺100.000) | İzin verilir; para üstü hesaplanır; uyarı gösterilir |
| EC-SALE-011 | Yıl değişiminde satış numarası | Yeni yıl sayacı 1'den başlar |
| EC-SALE-012 | Restore sonrası satış numarası çakışması | Sayaç `MAX(sale_number)`'a göre düzeltilir (REQ-BKUP-015) |
| EC-SALE-013 | 100 satırlık satış tamamlanıyor | Transaction süresi hedefte kalır; UI bloklanmaz |
| EC-SALE-014 | Ondalık miktar girilmeye çalışılıyor | Reddedilir; miktar tam sayıdır (BR-SALE-011) |
| EC-SALE-015 | KDV oranı olan ürün satılıyor | Sepet toplamı = girilen fiyat; KDV **içinden** çıkarılır, üzerine eklenmez (BR-VAT-003) |
| EC-SALE-016 | Satış anında ürünün KDV oranı değiştiriliyor | Satırda satış anındaki oran snapshot'ı kullanılır (BR-VAT-002) |
| EC-SALE-017 | KDV oranı %0 olan ürün | `line_vat = 0`, `line_net = line_total` |
| EC-SALE-018 | Satış anında ürünün alış fiyatı ₺0 | Maliyet snapshot'ı `0` yazılır; kâr = matrahın tamamı |

## 6. Stok

| ID | Durum | Beklenen davranış |
|---|---|---|
| EC-STOCK-001 | Stok 0, satış yapılıyor | Uyarı; kullanıcı devam ederse stok −1 olur |
| EC-STOCK-002 | Stok zaten −5, satış devam ediyor | İzin verilir; −6 olur; raporda görünür |
| EC-STOCK-003 | Negatif stoklu ürün iade ediliyor | Stok artar; −5 → −4 |
| EC-STOCK-004 | `stock_quantity` defterle uyuşmuyor | Tutarlılık kontrolü tespit eder; kullanıcı onayıyla `adjustment` ile düzeltilir |
| EC-STOCK-005 | Stok girişi 0 miktarla | Satır yok sayılır; hareket oluşmaz |
| EC-STOCK-006 | Stok girişi negatif miktarla | Reddedilir (giriş yalnızca pozitif) |
| EC-STOCK-007 | Sayım import'unda fark `0` | Hareket oluşmaz |
| EC-STOCK-008 | Aynı ürün stok girişinde iki satırda | Tek satırda birleştirilir |
| EC-STOCK-009 | Fire miktarı stoktan büyük | İzin verilir; stok negatife düşer; uyarı |
| EC-STOCK-010 | Hareket silinmeye çalışılıyor | UI'da böyle bir seçenek yoktur; "ters kayıt oluştur" sunulur |

## 7. İade / İptal

| ID | Durum | Beklenen davranış |
|---|---|---|
| EC-RET-001 | İptal edilmiş satış tekrar iptal ediliyor | Engellenir; sebep açıklanır |
| EC-RET-002 | İade edilmiş satış iptal edilmeye çalışılıyor | Engellenir; "iade yapılmış satış iptal edilemez" |
| EC-RET-003 | Satılandan fazla iade giriliyor | Alan maksimum değerle sınırlanır; kayıt reddedilir |
| EC-RET-004 | Tüm satırlar tek tek iade edildi | Durum otomatik `returned` olur |
| EC-RET-005 | İade edilen ürün pasifleştirilmiş | İade yapılabilir; stok artar |
| EC-RET-006 | İade transaction'ı ortasında hata | Tam rollback; `returned_quantity` değişmez |
| EC-RET-007 | İade edilen ürünün fiyatı değişmiş | Orijinal snapshot fiyat kullanılır |
| EC-RET-008 | Satış ve iade farklı aylarda | Satış satış ayına, iade iade ayına yazılır ([14 §5](14-returns-and-cancellation.md)) |
| EC-RET-009 | `0` miktarla iade kaydediliyor | Reddedilir ("en az bir ürün seçin") |

## 8. Yedekleme / Geri yükleme

| ID | Durum | Beklenen davranış |
|---|---|---|
| EC-BKUP-001 | Yedek dosyası bozuk (checksum uyuşmuyor) | Reddedilir; mevcut veriye dokunulmaz |
| EC-BKUP-002 | Yedek geçerli ZIP değil | Reddedilir |
| EC-BKUP-003 | `metadata.json` eksik/bozuk | Reddedilir |
| EC-BKUP-004 | Yedek daha yeni şema versiyonlu | Reddedilir; sürüm güncelleme önerilir |
| EC-BKUP-005 | Yedek daha eski şema versiyonlu | Kabul; restore sonrası migration çalışır |
| EC-BKUP-006 | Yedekte görsel eksik | Uyarı; restore devam eder; ürünler varsayılan ikonla |
| EC-BKUP-007 | Yedekte bozuk görsel dosyası | Checksum yakalar; uyarı; o görsel atlanır |
| EC-BKUP-008 | Yedek alırken uygulama kapanıyor | `.tmp` dosya kalır; geçerli yedek olarak listelenmez |
| EC-BKUP-009 | Restore sırasında elektrik kesiliyor | Açılışta tespit; `.old_<ts>` geri konur |
| EC-BKUP-010 | Restore sırasında disk doluyor | Restore durur; eski veri geri konur; hata gösterilir |
| EC-BKUP-011 | Yedekteki veri mevcut veriden az | Karşılaştırmalı özette vurgulanır; yazarak onay istenir |
| EC-BKUP-012 | Restore edilen DB'de kullanıcı yok | Restore sonrası kurulum sihirbazı açılır |
| EC-BKUP-013 | Yedek dosyası zip-slip yolu içeriyor | Reddedilir (REQ-SEC-003) |
| EC-BKUP-014 | Yedek açıldığında 50 GB'a genişliyor | Reddedilir (REQ-SEC-004) |
| EC-BKUP-015 | Yedek başka bilgisayarda restore ediliyor | Çalışır; mutlak yol saklanmadığı için görseller bulunur |

## 9. Import / Export

| ID | Durum | Beklenen davranış |
|---|---|---|
| EC-IMEX-001 | Dosyada aynı barkod iki satırda | Her iki satır da reddedilir; satır numaraları gösterilir |
| EC-IMEX-002 | Sistemde var olan barkod dosyada | Seçilen çakışma politikası uygulanır |
| EC-IMEX-003 | CSV bozuk / ayırıcı tutarsız | Parse hatası; satır numarasıyla gösterilir |
| EC-IMEX-004 | Excel dosyası şifre korumalı | Açılamaz; anlaşılır hata |
| EC-IMEX-005 | Zorunlu sütun eşleştirilmemiş | Import başlatılamaz |
| EC-IMEX-006 | Fiyat "on lira" gibi metin | Satır hatalı işaretlenir |
| EC-IMEX-007 | Fiyat `1.234,56` formatında | `tr_TR` kuralına göre doğru yorumlanır |
| EC-IMEX-008 | Boş dosya / yalnızca başlık | "İçe aktarılacak satır bulunamadı" |
| EC-IMEX-009 | 50.000 satırlık dosya | Isolate'te işlenir; ilerleme gösterilir; iptal edilebilir |
| EC-IMEX-010 | Import ortasında hata | Tam rollback |
| EC-IMEX-011 | Import ortasında kullanıcı iptal ediyor | Tam rollback; hiçbir kayıt oluşmaz |
| EC-IMEX-012 | Export sırasında disk doluyor | Yarım dosya bırakılmaz; hata gösterilir |
| EC-IMEX-013 | Export'ta ürün adı `=CMD()` ile başlıyor | `'` ile kaçışlanır (REQ-SEC-005) |
| EC-IMEX-014 | Import'ta tanımsız KDV oranı | Varsayılan oran kullanılır; uyarı |

## 10. Kimlik / Oturum

| ID | Durum | Beklenen davranış |
|---|---|---|
| EC-AUTH-001 | Hatalı parola | Genel hata mesajı; hangi alanın yanlış olduğu söylenmez |
| EC-AUTH-002 | 5 hatalı deneme | 30 sn bekleme |
| EC-AUTH-003 | Oturumdaki kullanıcı pasifleştirilmiş | Oturum geçersiz; login ekranı |
| EC-AUTH-004 | Oturum verisi bozuk JSON | Sessizce temizlenir; login ekranı; uygulama çökmez |
| EC-AUTH-005 | Son aktif kullanıcı pasifleştirilmeye çalışılıyor | Engellenir |
| EC-AUTH-006 | Kullanıcı adı büyük harfle giriliyor | Küçük harfe normalize edilerek eşleşir |
| EC-AUTH-007 | Restore sonrası oturum | Sonlandırılır; login ekranı |
| EC-AUTH-008 | Hiç kullanıcı yok (yeni kurulum) | Kurulum sihirbazı |

## 10b. Finansal erişim kilidi

| ID | Durum | Beklenen davranış |
|---|---|---|
| EC-DASH-001 | Kilit kapalıyken Dashboard açılmak isteniyor | Parola sorulur; **hiçbir sorgu çalıştırılmaz**, hiçbir rakam görünmez |
| EC-DASH-002 | Yanlış dashboard parolası | Hata; 5 denemede 30 sn bekleme; audit'e yazılır |
| EC-DASH-003 | Parola ekranında "Vazgeç" | Önceki ekrana dönülür; kilit kapalı kalır |
| EC-DASH-004 | Kilit açıkken başka ekrana gidip Dashboard'a dönülüyor | Parola tekrar sorulmaz (oturum kapsamlı) |
| EC-DASH-005 | Logout sonrası tekrar giriş yapılıyor | Dashboard parolası **tekrar sorulur** |
| EC-DASH-006 | Uygulama kapatılıp açılıyor | Dashboard kilidi kapalı başlar |
| EC-DASH-007 | Dashboard parolası unutuldu | **Recovery code ile sıfırlanabilir** ([17 §8](17-authentication.md)) |
| EC-DASH-008 | Parola değiştirilirken mevcut parola yanlış | Değişiklik reddedilir |
| EC-DASH-009 | Dashboard parolası kullanıcı parolasıyla aynı giriliyor | İzin verilir; uyarı gösterilir |
| EC-DASH-010 | Restore sonrası dashboard parolası | Yedekteki parola geçerli olur; kilit kapatılır; kullanıcı uyarılır (REQ-BKUP-020) |
| EC-DASH-011 | Kurulum sihirbazında dashboard parolası boş bırakılıyor | Kurulum ilerlemez — zorunlu alan (REQ-AUTH-016) |
| EC-DASH-012 | Kilit kapalıyken **Raporlar** açılmak isteniyor | Parola sorulur; hiçbir rapor sorgusu çalışmaz (BR-AUTH-013) |
| EC-DASH-013 | Dashboard için kilit açıldı, sonra Raporlar açılıyor | Parola tekrar sorulmaz — tek kilit her ikisini kapsar |
| EC-DASH-014 | Kilit kapalıyken satış / ürün / stok ekranı açılıyor | Parola sorulmaz (BR-AUTH-014) |

## 10c. Recovery code

| ID | Durum | Beklenen davranış |
|---|---|---|
| EC-REC-001 | Doğru recovery code giriliyor | Yeni parola belirleme ekranı açılır |
| EC-REC-002 | **Kullanılmış** recovery code tekrar giriliyor | "Bu kurtarma kodu daha önce kullanılmış" — reddedilir |
| EC-REC-003 | Yanlış recovery code 5 kez giriliyor | 30 sn bekleme; audit log'a yazılır |
| EC-REC-004 | Recovery başarılı | Parola güncellenir + eski kod geçersizleşir + **yeni kod üretilir**, tek transaction |
| EC-REC-005 | Yeni parola kaydedilirken hata oluşuyor | Tam rollback; eski parola ve eski kod geçerli kalır |
| EC-REC-006 | Recovery sonrası yeni kod ekranı kapatılıyor (kaydetmeden) | "Kodu kaydettim" onayı olmadan ekran kapanmaz |
| EC-REC-007 | Kullanıcı hem parolayı hem kodu kaybetmiş | Finansal erişim kurtarılamaz; **diğer tüm işlevler çalışır** ([RSK-016](29-risks.md)) |
| EC-REC-008 | Ayarlar'dan yeni kod üretiliyor, mevcut parola yanlış | Reddedilir; eski kod geçerli kalır |
| EC-REC-009 | Ayarlar'dan yeni kod üretiliyor, parola doğru | Yeni kod üretilir, eski geçersizleşir, bir kez gösterilir |
| EC-REC-010 | Restore sonrası recovery code | Yedekteki kod geçerli olur; mevcut kod geçersizleşir; kullanıcı uyarılır |
| EC-REC-011 | Kod büyük/küçük harf veya tire farkıyla giriliyor | Normalize edilerek karşılaştırılır (tireler ve harf durumu esnek) |
| EC-REC-012 | Veritabanında recovery kaydı hiç yok (eski kurulum) | "Şifremi unuttum" seçeneği gösterilmez; parola değiştirme yolu açık kalır |

## 11. Sistem / Altyapı

| ID | Durum | Beklenen davranış |
|---|---|---|
| EC-SYS-001 | İkinci uygulama örneği açılıyor | Engellenir; mevcut pencere öne getirilir |
| EC-SYS-002 | Veri dizini yazılamıyor (izin) | Anlaşılır hata + çözüm önerisi; uygulama açılmaz |
| EC-SYS-003 | Disk dolu, satış tamamlanıyor | Transaction başarısız; sepet korunur; anlaşılır hata |
| EC-SYS-004 | DB dosyası bozuk (`integrity_check` fail) | Bozuk dosya yeniden adlandırılır; son otomatik yedek önerilir |
| EC-SYS-005 | Migration yarım kalmış | Açılışta tespit; snapshot'tan kurtarma |
| EC-SYS-006 | Sistem saati geriye alınmış | Kayıtlar yazılır; raporlarda tutarsız sıralama olabilir; uyarı gösterilir |
| EC-SYS-007 | Yaz saati geçişi | Zamanlar UTC saklandığı için etkilenmez; gün sınırları yerel saate göre hesaplanır |
| EC-SYS-008 | Ekran çözünürlüğü 1366×768'in altında | Uyarı gösterilir; uygulama açılır ama düzen bozulabilir |
| EC-SYS-009 | Uygulama uzun süre açık (7 gün) | Bellek sızıntısı olmamalı; görsel önbelleği sınırlı kalmalı |
| EC-SYS-010 | Antivirüs `.canteenbackup` dosyasını karantinaya alıyor | Kullanıcı bilgilendirilir; standart ZIP olduğu belirtilir |

---

## Edge case → test eşlemesi

| Grup | Öncelikli test türü |
|---|---|
| EC-PROD-*, EC-CAT-* | Unit + repository testi |
| EC-DASH-*, EC-REC-* | Integration testi (kilit servisi + sorgu çalıştırılmadığının doğrulanması + recovery transaction'ı) |
| EC-BARC-* | Widget testi (input handler) + manuel donanım testi |
| EC-CART-*, EC-SALE-* | **Integration testi (en kritik)** |
| EC-STOCK-*, EC-RET-* | **Business logic unit testi (en kritik)** |
| EC-BKUP-* | Integration testi + bozuk dosya fixture'ları |
| EC-IMEX-* | Fixture dosyalarıyla integration testi |
| EC-AUTH-* | Unit + integration |
| EC-SYS-* | Manuel test + kaos senaryoları |

Detay: [27 — Test Stratejisi](27-testing-strategy.md).
