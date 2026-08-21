# Kantin Otomasyonu

Çevrimdışı çalışan kantin satış (POS), stok ve raporlama uygulaması.
**Flutter Desktop** · **Windows üretim** · **macOS geliştirme**.

| | |
|---|---|
| Veritabanı | Drift + SQLite (WAL, `synchronous=FULL`) |
| State | Riverpod |
| Grafik | fl_chart |
| Installer | Inno Setup |
| Dil | Türkçe (V1 tek dil) |
| **Backend** | **Yok** — hiçbir temel işlev internete bağımlı değildir |

Kullanıcı kılavuzu: [`docs/bilgilendirme.md`](docs/bilgilendirme.md)

---

## Kurallar

> Bu proje **doküman öncelikli** geliştirilir. `docs/` iş kurallarının
> source of truth'udur; kod ona uyar, doküman koda uydurulmaz.

Çalışma kuralları [`CLAUDE.md`](CLAUDE.md) ve [`.claude/rules/`](.claude/rules/)
altındadır. Kod yazmadan önce ilgili kural dosyası okunur.

Sessizce değiştirilemeyecek 14 iş kuralı için
[`.claude/rules/00-source-of-truth.md §4`](.claude/rules/00-source-of-truth.md).
En sık gözden kaçanı: **satış fiyatı KDV dahildir** ve **para tam sayı
kuruştur** — domain katmanında `double` kullanılmaz.

---

## Geliştirme

```bash
flutter pub get
flutter test                 # 1468 test
flutter analyze              # uyarısız geçmelidir
dart format lib test
flutter run -d macos
```

### Katmanlar

```text
presentation/  → ekranlar, widget'lar          (DB sorgusu ve hesap YOK)
application/   → servisler, transaction sınırı
domain/        → saf Dart: para, KDV, kâr, stok, satış kuralları
data/          → Drift, repository'ler, dosya sistemi
```

Bağımlılık yönü daima aşağıdır. `drift` importu yalnızca `data/` içinde
bulunur; `presentation/` altında görülürse bu bir bug'dır.

### Testler

Test yatırımı kapsama yüzdesine göre değil, **hatanın maliyetine** göre
yapılır. Para, KDV, kâr, stok defteri, satış atomikliği, iade, yedek/restore,
migration ve kimlik doğrulama 🔴 önceliklidir.

İki test doküman ↔ kod izlenebilirliğini korur:

| Test | Ne yapar |
|---|---|
| `test/docs/requirement_traceability_test.dart` | `docs/25`'teki her 🔴 Must requirement'ın bir testte anıldığını doğrular |
| `test/docs/edge_case_traceability_test.dart` | `docs/26`'daki `EC-*` uç durumları için aynısını yapar |

Kapsanmayan her madde **gerekçesiyle** kayıtlıdır; gerekçesiz boşluk testi
düşürür. Bir madde artık test ediliyorsa kaydının silinmesi de zorunludur.

---

## Windows sürümü

### GitHub Actions ile (macOS'ta geliştirirken)

Geliştirme macOS'ta yapıldığı için Windows çıktısı CI'da üretilir:

**Actions** → **Windows sürümü** → **Run workflow** → çalışma bitince
sayfanın altındaki **Artifacts**:

| Artefakt | İçerik |
|---|---|
| `KantinOtomasyonu-kurulum-<sürüm>` | Kurulum paketi (`.exe`) — asıl dağıtılan dosya |
| `KantinOtomasyonu-tasinabilir-<sürüm>` | Kurulumsuz deneme; klasörü açıp `canteen.exe` çalıştırın |

Aynı çalışma testleri de **Windows üzerinde** yürütür; bu, macOS'ta
görünmeyen yol/kilitleme farklarını yakalayan tek yerdir (rules/05 §6).

### Elle (Windows makinede)

```bat
flutter build windows --release
ISCC.exe installer\canteen.iss
```

Kurulum betiği [`installer/canteen.iss`](installer/canteen.iss).

> ⚠️ Installer `%APPDATA%\CanteenApp\` dizinine **dokunmaz** — kullanıcının
> veritabanı, görselleri ve yedekleri oradadır. Bu kural
> [RSK-002](docs/29-risks.md)'nin tek savunmasıdır ve
> `test/installer/inno_setup_test.dart` tarafından denetlenir.

macOS'ta çalışan bir şeyin Windows'ta çalıştığı **varsayılamaz**. Her sürüm
öncesi yapılması gereken elle testler:
[`docs/32-manual-test-backlog.md`](docs/32-manual-test-backlog.md).

---

## Dokümantasyon

| | |
|---|---|
| [`docs/00-README.md`](docs/00-README.md) | Doküman haritası |
| [`docs/02`](docs/02-product-and-business-requirements.md) | İş kuralları (BR-*) |
| [`docs/25`](docs/25-functional-requirements.md) | Gereksinimler (REQ-*) + kabul kriterleri |
| [`docs/26`](docs/26-edge-cases.md) | Uç durumlar (EC-*) |
| [`docs/28`](docs/28-open-decisions.md) | Karar kaydı (OD-*) |
| [`docs/31`](docs/31-roadmap.md) | Faz planı |
| [`docs/bilgilendirme.md`](docs/bilgilendirme.md) | Kullanıcı kılavuzu |
