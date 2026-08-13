# 16 — Raporlama

> **Doküman sürümü:** v3 — Raporlar artık **finansal erişim kilidi** ile korunuyor.

## 0. Erişim — finansal erişim kilidi

> 🔒 **BR-AUTH-013 — Raporlar ekranı, Dashboard ile aynı kilit tarafından korunur.**

```text
F7 (Raporlar) → finansal erişim açık mı?
                  ├── Evet → raporlar yüklenir
                  └── Hayır → dashboard parolası sorulur
```

- Kilit **oturum kapsamlıdır**: Dashboard için bir kez açıldıysa Raporlar için tekrar sorulmaz
  ve tersi de geçerlidir (BR-AUTH-016).
- Parola doğrulanmadan **hiçbir rapor sorgusu çalıştırılmaz** (BR-AUTH-012).
- Parola unutulursa recovery code ile sıfırlanabilir ([17 §8](17-authentication.md)).

Bu, v2'deki bilinçli boşluğu kapatır: Raporlar ekranı Dashboard ile aynı finansal bilgiyi
(ciro, kâr, maliyet, stok değeri) daha ayrıntılı içerdiği için aynı korumayı gerektirir.
Tam kural seti: [17 §7](17-authentication.md).

## 1. Dashboard ile fark

| | Dashboard | Raporlar |
|---|---|---|
| Amaç | Anlık durum, hızlı bakış | Detaylı inceleme, dışa aktarma |
| Detay | Özet, ilk 10 | Tam liste, sayfalı |
| Filtre | Yalnızca tarih | Tarih + kategori + tedarikçi + ürün + durum + kullanıcı |
| Çıktı | Ekran | Ekran + CSV/Excel |
| Kullanım sıklığı | Günlük | Haftalık/aylık |

---

## 2. Ortak rapor altyapısı

Tüm raporlar aynı iskeleti paylaşır:

```text
┌────────────────────────────────────────────────────────────┐
│ [Rapor seçici ▾]   Tarih: [___] – [___]  [Hızlı aralıklar] │
│ Filtreler: [Kategori ▾][Tedarikçi ▾][Durum ▾][Kullanıcı ▾] │
├────────────────────────────────────────────────────────────┤
│ ÖZET ŞERİDİ: toplam satır · toplam tutar · toplam adet ...  │
├────────────────────────────────────────────────────────────┤
│ Sıralanabilir tablo (sütun başlığına tıkla)                 │
│ ...                                                        │
├────────────────────────────────────────────────────────────┤
│ 1–50 / 1.284      [< >]        [CSV] [Excel]               │
└────────────────────────────────────────────────────────────┘
```

Ortak özellikler:
- Sunucu tarafı (SQL) sıralama ve sayfalama — bellekte tüm veri tutulmaz.
- Dışa aktarma **filtrelenmiş tüm sonucu** kapsar, yalnızca görünen sayfayı değil.
- Boş sonuç: "Seçilen kriterlere uygun kayıt bulunamadı" + filtreleri temizleme kısayolu.
- Uzun süren rapor (> 2 sn) isolate'te çalışır, iptal edilebilir.

---

## 3. Rapor kataloğu

### R1 — Satış Raporu
**Soru:** Hangi satışlar yapıldı?

| | |
|---|---|
| Satır birimi | Satış (fiş) |
| Sütunlar | Fiş no, tarih/saat, satır sayısı, adet, matrah (KDV hariç), KDV, toplam (KDV dahil), maliyet, kâr, durum, kullanıcı, nakit alınan/para üstü |
| Filtreler | Tarih, durum, kullanıcı, tutar aralığı |
| Özet | Fiş sayısı, brüt ciro, iptal, iade, net ciro, net kâr, ortalama fiş |
| Detay | Satıra tıklayınca satış detayı |

### R2 — Ürün Satış Raporu
**Soru:** Hangi ürün ne kadar sattı?

| | |
|---|---|
| Satır birimi | Ürün |
| Sütunlar | Ürün, kategori, satılan adet, iade adet, net adet, net ciro, maliyet, kâr, kâr marjı %, ortalama satış fiyatı |
| Filtreler | Tarih, kategori, tedarikçi, ürün |
| Sıralama | Varsayılan: net ciro azalan |
| Özet | Ürün çeşidi, toplam adet, toplam ciro, toplam kâr |

### R3 — Stok Durum Raporu
**Soru:** Elimde ne var, değeri ne?

| | |
|---|---|
| Satır birimi | Ürün (anlık durum — tarih filtresi yok) |
| Sütunlar | Ürün, kategori, tedarikçi, stok, minimum stok, durum (normal/kritik/negatif), alış fiyatı, **stok değeri** (`stok × alış fiyatı`), satış fiyatı, potansiyel ciro, raf konumu |
| Filtreler | Kategori, tedarikçi, durum, aktif/pasif |
| Özet | **Toplam stok değeri (maliyet)** ve potansiyel ciro |

> Toplam stok değeri, kantin işletmecisi için en önemli tek sayılardan biridir — bağlı sermaye.

### R4 — Stok Hareket Raporu
**Soru:** Stok neden değişti?

| | |
|---|---|
| Satır birimi | Stok hareketi |
| Sütunlar | Tarih/saat, ürün, tip, miktar (±), sonuç stok, birim maliyet, tedarikçi, referans (tıklanabilir), not, kullanıcı |
| Filtreler | Tarih, ürün, tip, tedarikçi, kullanıcı |
| Özet | Tip bazında toplam giriş/çıkış |

### R5 — Kâr Raporu
**Soru:** Ne kadar kazandım?

| | |
|---|---|
| Gruplama | Gün / Hafta / Ay / Kategori / Ürün (seçilebilir) |
| Sütunlar | Grup, ciro (KDV dahil), **matrah (KDV hariç)**, toplam maliyet, brüt kâr, kâr marjı %, fire maliyeti, **net kâr (fire düşülmüş)** |
| Filtreler | Tarih, kategori, tedarikçi |

> Fire maliyetinin kâr raporuna dahil edilmesi kritiktir; aksi halde kâr olduğundan yüksek görünür.

> **KDV ve kâr (BR-VAT-003 gereği kesin):** Fiyatlar KDV dahil olduğu için KDV işletmenin geliri
> değildir. **Kâr daima KDV hariç matrah üzerinden hesaplanır** (REQ-VAT-009, REQ-REP-013).
> Rapor hem KDV dahil ciroyu hem matrahı gösterir, ancak **kâr sütunu tek anlamlıdır.**
>
> ```text
> Brüt kâr = matrah (KDV hariç ciro) − maliyet
> Net kâr  = brüt kâr − fire maliyeti
> ```

### R6 — Kategori Raporu
**Soru:** Hangi kategori işimi taşıyor?

| | |
|---|---|
| Satır birimi | Kategori |
| Sütunlar | Kategori, ürün çeşidi, satılan adet, net ciro, ciro payı %, maliyet, kâr, kâr marjı %, mevcut stok değeri |
| Kaynak | `sale_items.category_id_snapshot` (geçmiş doğruluğu için) |

### R7 — Tedarikçi Raporu
**Soru:** Hangi tedarikçiden ne kadar alıyorum, ne kadar kazandırıyor?

| | |
|---|---|
| Satır birimi | Tedarikçi |
| Sütunlar | Tedarikçi, ürün çeşidi, dönem içi stok girişi (adet), alış tutarı, son giriş tarihi, bu tedarikçinin ürünlerinden net ciro ve kâr, mevcut stok değeri |
| Not | Ciro/kâr, ürünün **güncel** tedarikçisine göredir ([10 §2.2](10-category-brand-supplier.md) uyarısı) |

### R8 — Kritik Stok Raporu / Sipariş Listesi
**Soru:** Ne sipariş etmeliyim?

| | |
|---|---|
| Satır birimi | Ürün (`minimum_stock > 0 AND stock <= minimum_stock`) |
| Sütunlar | Ürün, stok, minimum stok, **önerilen sipariş miktarı**, tedarikçi, son alış fiyatı, tahmini tutar, son 30 gün satış adedi |
| Gruplama | Tedarikçiye göre |
| Çıktı | Tedarikçi bazlı sipariş listesi CSV |

> Önerilen sipariş miktarı = `max(minimum_stock × 2 − stock, son 30 gün satışı)` — basit bir
> sezgisel formül. Kullanıcı düzenleyebilir.

### R9 — Negatif Stok Raporu
**Soru:** Nerede veri hatası var?

| | |
|---|---|
| Satır birimi | Ürün (`stock < 0`) |
| Sütunlar | Ürün, stok, negatife düştüğü tarih (ilk negatif hareket), o günden beri satış adedi, son stok girişi tarihi |
| Aksiyon | Satırdan doğrudan düzeltme (`adjustment`) oluşturma |

### R10 — Fire Raporu
**Soru:** Ne kadar zarar ettim?

| | |
|---|---|
| Satır birimi | Fire hareketi veya ürün (gruplanabilir) |
| Sütunlar | Ürün, fire adedi, birim maliyet, toplam maliyet kaybı, sebep, tarih |
| Özet | Sebep bazında dağılım, toplam kayıp |

### R11 — KDV Raporu *(yalnızca KDV tanımlıysa)*
**Soru:** Ne kadar KDV topladım?

| | |
|---|---|
| Gruplama | KDV oranı (`vat_rate_snapshot_bp`) ve dönem |
| Sütunlar | Oran, matrah (net), KDV tutarı, KDV dahil toplam |

### R12 — Audit Log Raporu
Bkz. [18 §5](18-audit-log.md).

---

## 4. Dışa aktarma

| Format | Kullanım | Not |
|---|---|---|
| **CSV** | 🔴 **Birincil** — her rapor | UTF-8 **BOM ile** — Excel Türkçe karakterleri doğru açsın diye. Ayırıcı: `;` (Türkçe Excel varsayılanı) |
| **Excel (.xlsx)** | 🟡 İkincil — biçimlendirilmiş çıktı | Ayrı bir abstraction arkasından ([OD-009](28-open-decisions.md)); CSV yolunu karmaşıklaştırmaz |

Dosya adı: `<rapor>_<baslangic>_<bitis>.csv` → `satis_raporu_2026-08-01_2026-08-13.csv`

Dışa aktarma audit log'a yazılır (hangi rapor, hangi filtreler, kaç satır).

---

## 5. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-REP-001 | §3'teki 12 rapor uygulanır. |
| REQ-REP-002 | Tüm raporlar tarih aralığı filtresi destekler (anlık durum raporları hariç). |
| REQ-REP-003 | Raporlar CSV olarak dışa aktarılabilir. |
| REQ-REP-004 | Dışa aktarma, görünen sayfayı değil filtrelenmiş tüm sonucu kapsar. |
| REQ-REP-005 | CSV çıktıları Türkçe karakterleri Excel'de doğru gösterecek şekilde kodlanır. |
| REQ-REP-006 | Rapor sıralama ve sayfalama veritabanı seviyesinde yapılır. |
| REQ-REP-007 | Kâr raporu fire maliyetini ayrı bir kalem olarak içerir. |
| REQ-REP-008 | Ürün ve kategori raporları geçmiş doğruluğu için snapshot alanlarını kullanır. |
| REQ-REP-009 | Stok durum raporu toplam stok değerini maliyet üzerinden gösterir. |
| REQ-REP-010 | Kritik stok raporu tedarikçi bazlı sipariş listesi olarak dışa aktarılabilir. |
| REQ-REP-011 | 2 saniyeden uzun süren raporlar iptal edilebilir ve UI'yi bloklamaz. |
| REQ-REP-012 | Rapor dışa aktarma işlemleri audit log'a yazılır. |
| REQ-REP-013 | Kâr metrikleri KDV hariç matrah üzerinden hesaplanır; ciro hem KDV dahil hem KDV hariç gösterilir. |
| REQ-REP-014 | Raporlar ekranı finansal erişim kilidi ile korunur; parola doğrulanmadan hiçbir rapor sorgusu çalıştırılmaz. |

---

## 6. Acceptance criteria

**REQ-REP-014**
```text
Given: Kullanıcı giriş yapmış, finansal erişim kilidi kapalı
When:  F7 ile Raporlar açılmak isteniyor
Then:  Dashboard parolası sorulur
And:   Hiçbir rapor sorgusu çalıştırılmaz
When:  Doğru parola giriliyor
Then:  Raporlar yüklenir
When:  Dashboard'a geçilip tekrar Raporlar'a dönülüyor
Then:  Parola tekrar sorulmaz (oturum kapsamlı kilit)
```

**REQ-REP-008**
```text
Given: Bir ürün "İçecek" kategorisindeyken 50 adet satılmış
When:  Ürün "Atıştırmalık" kategorisine taşınıyor
And:   Geçmiş tarihli kategori raporu çalıştırılıyor
Then:  50 adet "İçecek" kategorisi altında raporlanır
And:   Sonraki satışlar "Atıştırmalık" altında raporlanır
```

**REQ-REP-004**
```text
Given: Rapor 1.284 satır sonuç veriyor, ekranda 50 satır görünüyor
When:  CSV dışa aktarma yapılıyor
Then:  Dosyada 1.284 veri satırı + 1 başlık satırı bulunur
```

**REQ-REP-005**
```text
Given: Raporda "Çikolatalı Gofret" adlı ürün var
When:  CSV dışa aktarılıp Türkçe Excel ile açılıyor
Then:  Ürün adı "Çikolatalı Gofret" olarak doğru görünür
And:   Sütunlar ayrı hücrelerdedir
```
