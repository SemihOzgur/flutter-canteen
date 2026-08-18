# 18 — Audit Log (Denetim Kaydı)

> **Doküman sürümü:** v3 — recovery code olayları eklendi.

## 1. Amaç

Audit log şu soruya cevap verir:

> **"Bu değer neden böyle? Kim, ne zaman, neyi değiştirdi?"**

Rol sistemi olmadığı için ([17 §1](17-authentication.md)) audit log **tek denetim mekanizmasıdır.**
Yetki kontrolü yoktur; ama izlenebilirlik vardır.

---

## 2. Şema

| Alan | Tip | Açıklama |
|---|---|---|
| `id` | int | PK |
| `created_at` | int (UTC ms) | Ne zaman |
| `user_id` | int? | Kim (sistem işlemlerinde `NULL`) |
| `action` | string | Ne yapıldı (§3) |
| `entity_type` | string | Hangi varlık türü (`product`, `sale`, `category`, ...) |
| `entity_id` | int? | Hangi kayıt |
| `old_value` | JSON? | **Yalnızca değişen alanların** eski değerleri |
| `new_value` | JSON? | **Yalnızca değişen alanların** yeni değerleri |
| `metadata` | JSON? | Ek bağlam (sebep, satır sayısı, dosya adı, süre) |

### Neden yalnızca değişen alanlar?

Tüm kaydı kopyalamak veritabanını hızla şişirir ve okumayı zorlaştırır.

```text
İYİ:
  old_value: {"sale_price_minor": 2500}
  new_value: {"sale_price_minor": 3000}

KÖTÜ:
  old_value: {id, name, description, category_id, brand, ...20 alan}
```

---

## 3. Kaydedilen işlemler

### Ürün
| Action | Ne zaman | metadata |
|---|---|---|
| `productCreated` | Ürün oluşturuldu | oluşturma yolu (hızlı/detaylı/import) |
| `productPriceChanged` | Satış fiyatı değişti | — |
| `productCostChanged` | Alış fiyatı değişti | kaynak (elle / stok girişi) |
| `productDeactivated` / `productActivated` | Pasifleştirme/aktifleştirme | stok miktarı |
| `productDeleted` | Hiç kullanılmamış ürün kalıcı silindi (BR-PROD-014) | ürün adı, barkodlar |
| `categoryDeleted` | Hiç kullanılmamış kategori kalıcı silindi (BR-CAT-005) | kategori adı |
| `productCategoryChanged` | Kategori değişti | — |
| `productSupplierChanged` | Tedarikçi değişti | — |
| `productMinStockChanged` | Minimum stok değişti | — |
| `barcodeAdded` / `barcodeRemoved` | Barkod eklendi/silindi | barkod değeri |
| `productImageChanged` | Görsel değişti | eski/yeni dosya adı |

### Satış
| Action | Ne zaman | metadata |
|---|---|---|
| `saleCompleted` | Satış tamamlandı | fiş no, toplam, satır sayısı |
| `salePriceOverridden` | Satış sırasında fiyat değiştirildi | ürün, liste fiyatı, uygulanan fiyat |
| `saleCancelled` | Satış iptal edildi | fiş no, tutar, **sebep** |
| `saleReturned` | İade yapıldı | fiş no, iade tutarı, satır sayısı, **sebep** |

### Stok
| Action | Ne zaman | metadata |
|---|---|---|
| `stockEntryCreated` | Stok girişi | tedarikçi, satır sayısı, toplam tutar |
| `stockWasteRecorded` | Fire | ürün, miktar, **sebep** |
| `stockAdjusted` | Düzeltme | ürün, eski/yeni stok, **sebep** |

### Kategori / Tedarikçi / KDV
| Action | metadata |
|---|---|
| `categoryCreated` / `categoryRenamed` / `categoryDeactivated` / `categoryActivated` | — |
| `categoryProductsMoved` | kaynak, hedef, ürün sayısı |
| `supplierCreated` / `supplierUpdated` / `supplierDeactivated` / `supplierActivated` | — |
| `vatRateCreated` / `vatRateChanged` / `vatRateDeactivated` / `vatRateActivated` | eski/yeni oran, etkilenen ürün sayısı |

### Sistem / Veri
| Action | metadata |
|---|---|
| `backupCreated` | dosya adı, boyut, kayıt sayıları |
| `backupRestored` | kaynak dosya, backup tarihi, şema versiyonu, **restore öncesi kayıt sayıları** |
| `dataImported` | dosya adı, eklenen/güncellenen/atlanan satır sayıları |
| `dataExported` | rapor türü, filtreler, satır sayısı |
| `migrationApplied` | eski/yeni şema versiyonu, süre |
| `consistencyCheckRun` | bulunan sapma sayısı |

### Kullanıcı
| Action | metadata |
|---|---|
| `userLoggedIn` / `userLoggedOut` | — |
| `userCreated` / `userDeactivated` / `userRenamed` | — |
| `passwordChanged` | ⚠️ **Parola, hash ve salt değerleri asla yazılmaz** (BR-SEC-001) |
| **`dashboardUnlocked`** | — |
| **`dashboardUnlockFailed`** | ardışık deneme sayısı |
| **`dashboardPasswordChanged`** | ⚠️ **Parola değeri yazılmaz** |
| **`dashboardRecoveryUsed`** | ⚠️ **Kod değeri yazılmaz** — yalnızca kullanım zamanı |
| **`dashboardRecoveryFailed`** | ardışık deneme sayısı; kod değeri yazılmaz |
| **`dashboardRecoveryRegenerated`** | yeni kod üretildi — ⚠️ **kod değeri yazılmaz** |
| `cartTakenOver` | eski kullanıcı, yeni kullanıcı, sepet tutarı |

---

## 4. Kaydedilmeyenler

| Kaydedilmez | Neden |
|---|---|
| Parola, recovery code, hash, salt değerleri | Güvenlik (BR-SEC-001) |
| Her ekran görüntüleme / sayfa gezinme | Gürültü; denetim değeri yok |
| Aktif sepet işlemleri (ürün ekleme/çıkarma) | Finansal kayıt değil; log'u boğar |
| Rapor görüntüleme | Yalnızca **dışa aktarma** kaydedilir |
| Arama sorguları | Denetim değeri yok, gizlilik gürültüsü |
| Uygulama açılış/kapanış | Log dosyasında var, audit'te gerekmez |

> **İlke:** Audit log'a yalnızca **veriyi değiştiren** veya **veriyi dışarı çıkaran** işlemler yazılır.

---

## 5. Görüntüleme

Ayarlar → Denetim Kaydı:

| Özellik | |
|---|---|
| Filtreler | Tarih aralığı, kullanıcı, işlem türü, varlık türü, varlık ID |
| Gösterim | Zaman çizelgesi; her satır insan-okunur cümle olarak |
| Detay | Satır açılınca eski/yeni değer karşılaştırması |
| Bağlantı | Varlığa git (ürün, satış vb.) |
| Dışa aktarma | CSV |

**İnsan-okunur gösterim örnekleri:**
```text
13.08.2026 14:32  Ahmet    "Coca Cola 330ml" ürününün satış fiyatını ₺25,00 → ₺30,00 yaptı
13.08.2026 14:35  Ahmet    2026-000148 numaralı satışı iptal etti (₺135,00) — Sebep: "yanlış ürün"
13.08.2026 15:02  Ahmet    Yedek oluşturdu (canteen_backup_20260813.canteenbackup, 4,2 MB)
```

Ham JSON gösterimi de bir "Teknik detay" bölümünde bulunur.

---

## 6. Büyüme ve saklama

Tahmin: Günde ~50 audit kaydı → yılda ~18.000 satır → yılda ~5 MB. Yönetilebilir.

| Politika | Karar |
|---|---|
| Otomatik silme | ❌ Yapılmaz — denetim kaydı silinmemelidir (BR-GEN-002) |
| Arşivleme | ✅ 2 yıldan eski kayıtlar, kullanıcı onayıyla CSV'ye aktarılıp tablodan çıkarılabilir |
| Backup'a dahil | ✅ Evet |
| Uyarı | Tablo 500.000 satırı geçerse kullanıcı arşivlemeye yönlendirilir |

---

## 7. Yazma garantisi

> **Audit log yazımı, kaydettiği işlemle aynı transaction içinde yapılır.**

Gerekçe: İşlem başarılı olup audit kaydı yazılmazsa denetim izi kopar. Tersi de doğrudur —
işlem geri alınırsa audit kaydı da geri alınmalıdır.

**İstisna:** `userLoggedIn`, `backupCreated` gibi tek başına duran işlemler kendi transaction'ındadır.

Audit yazımı **hiçbir zaman ana işlemi bloklamamalı veya başarısız kılmamalıdır** —
audit yazımında beklenmedik bir hata olursa (örn. JSON serileştirme hatası), hata log dosyasına
yazılır ve ana işlem devam eder. Bu, "denetim uğruna satış kaybetme" durumunu engeller.

---

## 8. Requirement'lar

| ID | Requirement |
|---|---|
| REQ-AUDIT-001 | §3'te listelenen tüm işlemler audit log'a yazılır. |
| REQ-AUDIT-002 | Audit kaydı zaman, kullanıcı, işlem, varlık türü ve varlık kimliği içerir. |
| REQ-AUDIT-003 | Değer değişikliklerinde yalnızca değişen alanların eski ve yeni değerleri saklanır. |
| REQ-AUDIT-004 | Parola, recovery code, hash veya salt değerleri audit log'a asla yazılmaz. |
| REQ-AUDIT-005 | Audit kayıtları düzenlenemez ve silinemez. |
| REQ-AUDIT-006 | Audit kaydı, ilgili işlemle aynı transaction içinde yazılır. |
| REQ-AUDIT-007 | Audit yazımındaki bir hata ana işlemi başarısız kılmaz. |
| REQ-AUDIT-008 | Audit kayıtları tarih, kullanıcı, işlem ve varlık türüne göre filtrelenebilir. |
| REQ-AUDIT-009 | Audit kayıtları insan-okunur cümleler halinde gösterilir. |
| REQ-AUDIT-010 | Audit kayıtları CSV olarak dışa aktarılabilir. |
| REQ-AUDIT-011 | 2 yıldan eski kayıtlar kullanıcı onayıyla arşivlenebilir. |
| REQ-AUDIT-012 | Finansal erişim kilidi açılışları, başarısız denemeler, parola değişiklikleri ve recovery code kullanımı/yenilenmesi audit log'a yazılır; parola ve kod değerleri yazılmaz. |
| REQ-AUDIT-013 | Kalıcı ürün ve kategori silme işlemleri audit log'a yazılır. |

---

## 9. Acceptance criteria

**REQ-AUDIT-006**
```text
Given: Satış tamamlanıyor
When:  Transaction içinde stok güncellemesi hata veriyor
Then:  Satış kaydı oluşmaz
And:   saleCompleted audit kaydı da oluşmaz
```

**REQ-AUDIT-003**
```text
Given: Bir ürünün yalnızca satış fiyatı değiştiriliyor
When:  Değişiklik kaydediliyor
Then:  old_value = {"sale_price_minor": 2500}
And:   new_value = {"sale_price_minor": 3000}
And:   Diğer alanlar JSON'da bulunmaz
```

**REQ-AUDIT-007**
```text
Given: Audit kaydının metadata alanı serileştirilemiyor
When:  Satış tamamlanıyor
Then:  Satış başarıyla kaydedilir
And:   Hata log dosyasına yazılır
And:   Kullanıcı satışa devam edebilir
```
