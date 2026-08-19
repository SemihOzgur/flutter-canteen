/// Ürün repository sözleşmesi — **REQ-ARCH-004**
///
/// docs/03-architecture.md §4 · rules/01 §4: interface yalnızca Product, Sale ve
/// Stock için yazılır. Diğer tablolar doğrudan DAO ile kullanılır.
///
/// Bu dosya `domain/` içindedir ve **hiçbir Drift/Flutter/dart:io bağımlılığı
/// taşımaz** (rules/01 §1).
///
/// ## Kapsam sınırı
///
/// Burada **kalıcılık** işlemleri vardır; iş akışı orkestrasyonu yoktur.
/// Doğrulama, varsayılan kategori, uyarı üretimi, audit ve transaction
/// sınırları `ProductService`'e aittir (rules/01 §1, §5).
///
/// `stock_quantity` bu arayüzden **yazılamaz** — tek yazım noktası
/// `StockService`'tir (rules/02 §4). `create` bile başlangıç stoğu almaz:
/// stok yalnızca `stock_movements` üzerinden oluşur (BR-STOCK-001).
library;

import '../../core/money/money.dart';
import '../../core/result/result.dart';
import '../models/product.dart';

abstract interface class ProductRepository {
  Future<Result<Product>> findById(int id);

  /// Barkod lookup — satış hızının tamamı buna bağlıdır (docs/05 §3, 🔴).
  ///
  /// Bulunamazsa `Failure('product_not_found')` döner; bu **beklenen** bir
  /// sonuçtur (bilinmeyen barkod akışı, rules/02 §10) ve exception fırlatmaz.
  Future<Result<Product>> findByBarcode(String barcode);

  /// Ürün araması — **REQ-PROD-010 · docs/09 §6**
  ///
  /// | Kural | |
  /// |---|---|
  /// | Kapsam | Önce ürün adı, sonra marka (`contains`) |
  /// | Duyarlılık | Büyük/küçük harf **ve** Türkçe karakter duyarsız |
  /// | Görünürlük | Yalnızca **aktif** ürünler (docs/09 §4) |
  /// | Sıralama | Ad eşleşmeleri önce, sonra **satış adedi**, sonra ad |
  /// | Sınır | Varsayılan 50 sonuç |
  ///
  /// [query] **ham kullanıcı metnidir**; katlama ve LIKE kaçışlaması
  /// implementasyonun işidir. (Kullanıcı adı eşleşmesinden farkı budur:
  /// orada hangi kuralın uygulanacağı bir iş kararıdır ve çağıran normalize
  /// eder; burada kural tektir ve `TurkishText.fold`'dur.)
  /// [includeInactive] "Pasifleri göster" filtresidir — docs/09 §4 tablosu
  /// aramanın da bu filtreye uymasını ister ("varsayılan gizli; filtre ile
  /// görünür"). Aksi hâlde kullanıcı filtreyi açıp arama yazdığında pasif
  /// ürünler sessizce kaybolurdu.
  Future<List<Product>> search(String query, {bool includeInactive, int limit});

  /// Ürün listesi — **REQ-PERF-006**: sayfalıdır, tüm kayıtlar belleğe alınmaz
  /// (rules/01 §8).
  ///
  /// [includeInactive] yönetim ekranının "Pasifleri göster" filtresidir
  /// (docs/09 §4); varsayılan olarak pasif ürünler **gizlidir**.
  /// [onlyFavorites] satış ekranının favori şeridi içindir (docs/12 §1 ·
  /// BR-PROD-008). Favoriler ayrı bir entity değildir (rules/02 §11.5), bu
  /// yüzden ayrı bir sorgu değil, aynı listenin bir filtresidir.
  Future<List<Product>> list({
    bool includeInactive,
    int? categoryId,
    bool onlyFavorites,
    int limit,
    int offset,
  });

  /// [list] ile aynı filtrelerin toplam kayıt sayısı — sayfalama göstergesi
  /// için. Sayım **SQL tarafında** yapılır (rules/01 §8).
  Future<int> count({bool includeInactive, int? categoryId});

  /// BR-PROD-013 · EC-PROD-010 — aynı ad + aynı kategori kombinasyonu var mı?
  ///
  /// Sonuç bir **uyarıdır**, kısıt değil: ürün adı benzersiz olmak zorunda
  /// değildir. Karşılaştırma arama ile aynı katlamayı kullanır
  /// (`TurkishText.fold`) — "Ayran" ile "AYRAN" aynı üründür.
  ///
  /// [excludeProductId] düzenleme sırasında ürünün **kendisini** dışarıda
  /// bırakır; aksi hâlde her kayıt kendi kopyası sanılırdı.
  Future<bool> existsWithName({
    required String name,
    required int categoryId,
    int? excludeProductId,
  });

  /// Ürünü kaydeder ve yeni `id`'yi döner.
  Future<Result<int>> create(NewProduct product);

  Future<Result<void>> update(Product product);

  /// BR-PROD-009 — kullanılmış ürün silinmez, yalnızca pasifleşir.
  ///
  /// Yalnızca `is_active` (ve `updated_at`) yazılır; başka hiçbir alan
  /// değişmez. Etkilenen satır sayısını döner.
  Future<int> setActive(int id, bool isActive);

  /// BR-PROD-008 · REQ-PROD-009 — favori bayrağını değiştirir.
  ///
  /// `Product.isFavorite` **boolean bir alandır**; ayrı bir `Favorite`
  /// entity'si veya tablosu yoktur (rules/02 §11.5 · docs/04 §1). Yalnızca
  /// `is_favorite` (ve `updated_at`) yazılır; başka hiçbir alan değişmez.
  /// Etkilenen satır sayısını döner.
  Future<int> setFavorite(int id, bool isFavorite);

  /// Yalnızca alış fiyatını günceller — **BR-STOCK-009 · REQ-STOCK-008.**
  ///
  /// Stok girişinde kullanıcı farklı bir alış fiyatı girdiğinde ürünün fiyatı
  /// da güncellenebilir; bu güncelleme girişle **aynı transaction** içinde
  /// olmak zorundadır. Tüm ürünü yeniden yazan [update] bunun için fazla
  /// geniştir: aradaki başka bir değişikliği sessizce geri alabilirdi.
  Future<int> updatePurchasePrice(int id, Money purchasePrice);

  /// docs/09 §5 — "30'dan fazla favori eklenirse kullanıcı uyarılır."
  ///
  /// Sayım **SQL tarafında** yapılır (rules/01 §8) ve `ix_products_favorite`
  /// kısmi index'ini kullanır. Yalnızca **aktif** ürünler sayılır: pasif ürün
  /// satış ekranındaki favoriler bölümünde görünmez, dolayısıyla ekran
  /// karmaşasına da katkı vermez.
  Future<int> countFavorites();

  /// BR-PROD-014 — **koşulsuz** siler.
  ///
  /// "Hiç satılmamış ve hiç stok hareketi yok" koşulunun kontrolü çağırana
  /// aittir ve silmeyle **aynı transaction** içinde yapılmalıdır
  /// (`ProductService.delete`).
  Future<int> deleteById(int id);

  /// BR-PROD-005 — barkod global benzersizdir.
  /// Çakışma → `Failure('barcode_exists')`.
  Future<Result<int>> addBarcode({
    required int productId,
    required String barcode,
    bool isPrimary = false,
  });

  /// EC-PROD-016 — barkod silinebilir; ürün barkodsuz kalabilir.
  ///
  /// Silinen barkod global benzersizlik havuzundan **çıkar** (docs/09 §3).
  /// Etkilenen satır sayısını döner.
  Future<int> removeBarcode({required int productId, required String barcode});

  /// Kalıcı silmenin parçası — ürünün tüm barkodları serbest kalır
  /// (EC-PROD-022).
  Future<int> removeAllBarcodesOf(int productId);

  /// docs/04 §3.6 — ürün başına en fazla bir `is_primary = true`.
  Future<int> clearPrimaryBarcodes(int productId);

  /// Ürünün barkodları — **birincil barkod başta**, sonra ekleniş sırasında.
  ///
  /// Sıra sözleşmenin parçasıdır: `sale_items.barcode_snapshot` listenin
  /// ilkinden yazılır (docs/04 §3.9).
  Future<List<String>> barcodesOf(int productId);
}
