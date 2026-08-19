/// [ProductRepository]'nin Drift implementasyonu.
///
/// Drift bağımlılığı **yalnızca bu katmanda** bulunur (rules/01 §1).
/// Domain katmanı bu dosyayı tanımaz; yalnızca arayüzü bilir.
library;

import 'package:drift/drift.dart';

import '../../core/money/money.dart';
import '../../core/result/result.dart';
import '../../domain/enums/sale_status.dart';
import '../../domain/models/product.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/services/product_rules.dart';
import '../../domain/services/turkish_text.dart';
import '../db/canteen_database.dart' as db;
import '../db/database_opener.dart' show SqliteFunctions;
import 'failures.dart';

class DriftProductRepository implements ProductRepository {
  final db.CanteenDatabase _db;

  DriftProductRepository(this._db);

  static Product _toDomain(db.Product row) => Product(
    id: row.id,
    name: row.name,
    description: row.description,
    categoryId: row.categoryId,
    brand: row.brand,
    salesUnit: row.salesUnit,
    netWeightValue: row.netWeightValue,
    netWeightUnit: row.netWeightUnit,
    purchasePrice: Money(row.purchasePriceMinor),
    salePrice: Money(row.salePriceMinor),
    vatRateId: row.vatRateId,
    stockQuantity: row.stockQuantity,
    minimumStock: row.minimumStock,
    supplierId: row.supplierId,
    shelfLocation: row.shelfLocation,
    imagePath: row.imagePath,
    isFavorite: row.isFavorite,
    isActive: row.isActive,
    createdAt: row.createdAt,
    updatedAt: row.updatedAt,
  );

  @override
  Future<Result<Product>> findById(int id) async {
    final row = await (_db.select(
      _db.products,
    )..where((p) => p.id.equals(id))).getSingleOrNull();

    if (row == null) return const Err(DataFailures.productNotFound);
    return Ok(_toDomain(row));
  }

  @override
  Future<Result<Product>> findByBarcode(String barcode) async {
    // ux_barcode index'i üzerinden — satış hızının bağlı olduğu sorgu.
    final query = _db.select(_db.productBarcodes).join([
      innerJoin(
        _db.products,
        _db.products.id.equalsExp(_db.productBarcodes.productId),
      ),
    ])..where(_db.productBarcodes.barcode.equals(barcode));

    final row = await query.getSingleOrNull();
    if (row == null) return const Err(DataFailures.productNotFound);
    return Ok(_toDomain(row.readTable(_db.products)));
  }

  /// LIKE joker karakterlerini kaçışlar.
  ///
  /// Kullanıcı `%` veya `_` yazarsa bunlar **düz karakter** olarak aranmalıdır;
  /// aksi hâlde tek bir `%` bütün kataloğu döndürürdü.
  static String _escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');

  @override
  Future<List<Product>> search(
    String query, {
    bool includeInactive = false,
    int limit = ProductRules.searchResultLimit,
  }) async {
    final folded = TurkishText.fold(query.trim());
    if (folded.isEmpty) return const [];

    final pattern = '%${_escapeLike(folded)}%';
    const fold = SqliteFunctions.fold;

    // docs/09 §6 — sıralama:
    //   1) ad eşleşmeleri markadan önce ("önce ürün adında, sonra markada")
    //   2) satış adedi (en çok satılan üstte) — kasada isabet oranını artırır
    //   3) ad (deterministik son sıralama)
    //
    // Satış adedi ilişkili alt sorgudan gelir ve `ix_sale_items_product`
    // üzerinden çalışır: yalnızca EŞLEŞEN ürünler için hesaplanır. Tüm
    // `sale_items` tablosunu gruplayan bir JOIN her tuşta tam tarama yapardı.
    //
    // İptal edilmiş satışlar ve iade edilmiş adetler sayılmaz: iptal edilmiş
    // bir satış ürünü listenin başına taşımamalıdır (rules/05 §3 — raporlanan
    // değerler nettir). Bu bir metrik değil, sıralama sezgisidir; ekranda
    // hiçbir rakam olarak gösterilmez.
    final rows = await _db
        .customSelect(
          'SELECT p.* FROM products p '
          // docs/09 §4 — "Ürün arama: varsayılan gizli; 'Pasifleri göster'
          // filtresi ile görünür." Filtre aramayı da kapsamalıdır.
          '${includeInactive ? '' : 'WHERE p.is_active = 1 '}'
          "${includeInactive ? 'WHERE' : 'AND'} ($fold(p.name) LIKE ?1 ESCAPE '\\' "
          "     OR $fold(p.brand) LIKE ?1 ESCAPE '\\') "
          "ORDER BY ($fold(p.name) LIKE ?1 ESCAPE '\\') DESC, "
          '  (SELECT COALESCE(SUM(si.quantity - si.returned_quantity), 0) '
          '     FROM sale_items si '
          '     JOIN sales s ON s.id = si.sale_id '
          '    WHERE si.product_id = p.id AND s.status <> ?2) DESC, '
          '  p.name '
          'LIMIT ?3',
          variables: [
            Variable<String>(pattern),
            Variable<String>(SaleStatus.cancelled.wire),
            Variable<int>(limit),
          ],
          readsFrom: {_db.products, _db.saleItems, _db.sales},
        )
        .get();

    return [for (final row in rows) _toDomain(_db.products.map(row.data))];
  }

  /// [list] ve [count] için ortak filtre.
  Expression<bool> _listFilter(
    db.$ProductsTable p, {
    required bool includeInactive,
    required int? categoryId,
  }) {
    var filter = includeInactive
        ? const Constant(true)
        : p.isActive.equals(true);
    if (categoryId != null) {
      filter = filter & p.categoryId.equals(categoryId);
    }
    return filter;
  }

  @override
  Future<List<Product>> list({
    bool includeInactive = false,
    int? categoryId,
    int limit = ProductRules.searchResultLimit,
    int offset = 0,
  }) async {
    final rows =
        await (_db.select(_db.products)
              ..where(
                (p) => _listFilter(
                  p,
                  includeInactive: includeInactive,
                  categoryId: categoryId,
                ),
              )
              ..orderBy([(p) => OrderingTerm(expression: p.name)])
              ..limit(limit, offset: offset))
            .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<int> count({bool includeInactive = false, int? categoryId}) async {
    final total = _db.products.id.count();
    final row =
        await (_db.selectOnly(_db.products)
              ..addColumns([total])
              ..where(
                _listFilter(
                  _db.products,
                  includeInactive: includeInactive,
                  categoryId: categoryId,
                ),
              ))
            .getSingle();
    return row.read(total) ?? 0;
  }

  @override
  Future<bool> existsWithName({
    required String name,
    required int categoryId,
    int? excludeProductId,
  }) async {
    const fold = SqliteFunctions.fold;
    final row = await _db
        .customSelect(
          'SELECT 1 FROM products '
          'WHERE category_id = ?1 AND $fold(name) = ?2 AND id <> ?3 LIMIT 1',
          variables: [
            Variable<int>(categoryId),
            Variable<String>(TurkishText.fold(name)),
            // `id <> -1` hiçbir satırı elemez: id'ler daima pozitiftir.
            Variable<int>(excludeProductId ?? -1),
          ],
          readsFrom: {_db.products},
        )
        .getSingleOrNull();
    return row != null;
  }

  @override
  Future<Result<int>> create(NewProduct product) async {
    final now = _db.clock().toUtc();
    try {
      final id = await _db
          .into(_db.products)
          .insert(
            db.ProductsCompanion.insert(
              name: product.name,
              description: Value(product.description),
              categoryId: product.categoryId,
              brand: Value(product.brand),
              salesUnit: Value(product.salesUnit),
              netWeightValue: Value(product.netWeightValue),
              netWeightUnit: Value(product.netWeightUnit),
              purchasePriceMinor: Value(product.purchasePrice.minor),
              salePriceMinor: product.salePrice.minor,
              vatRateId: Value(product.vatRateId),
              minimumStock: Value(product.minimumStock),
              supplierId: Value(product.supplierId),
              shelfLocation: Value(product.shelfLocation),
              imagePath: Value(product.imagePath),
              isFavorite: Value(product.isFavorite),
              createdAt: now,
              updatedAt: now,
            ),
          );
      return Ok(id);
    } on Object catch (error) {
      final failure = mapConstraintFailure(error);
      if (failure == null) rethrow;
      return Err(failure);
    }
  }

  @override
  Future<Result<void>> update(Product product) async {
    final affected =
        await (_db.update(
          _db.products,
        )..where((p) => p.id.equals(product.id))).write(
          db.ProductsCompanion(
            name: Value(product.name),
            description: Value(product.description),
            categoryId: Value(product.categoryId),
            brand: Value(product.brand),
            salesUnit: Value(product.salesUnit),
            netWeightValue: Value(product.netWeightValue),
            netWeightUnit: Value(product.netWeightUnit),
            purchasePriceMinor: Value(product.purchasePrice.minor),
            salePriceMinor: Value(product.salePrice.minor),
            vatRateId: Value(product.vatRateId),
            minimumStock: Value(product.minimumStock),
            supplierId: Value(product.supplierId),
            shelfLocation: Value(product.shelfLocation),
            imagePath: Value(product.imagePath),
            isFavorite: Value(product.isFavorite),
            isActive: Value(product.isActive),
            updatedAt: Value(_db.clock().toUtc()),
            // stock_quantity BİLİNÇLİ olarak yazılmaz — tek yazım noktası
            // StockService'tir (rules/02 §4, Faz 6).
          ),
        );

    if (affected == 0) return const Err(DataFailures.productNotFound);
    return const Ok(null);
  }

  @override
  Future<Result<int>> addBarcode({
    required int productId,
    required String barcode,
    bool isPrimary = false,
  }) async {
    try {
      final id = await _db
          .into(_db.productBarcodes)
          .insert(
            db.ProductBarcodesCompanion.insert(
              productId: productId,
              barcode: barcode,
              isPrimary: Value(isPrimary),
              createdAt: _db.clock().toUtc(),
            ),
          );
      return Ok(id);
    } on Object catch (error) {
      final failure = mapConstraintFailure(error);
      if (failure == null) rethrow;
      return Err(failure);
    }
  }

  @override
  Future<int> setActive(int id, bool isActive) {
    // Yalnızca bu iki kolon yazılır: pasifleştirme başka hiçbir alana
    // dokunmaz (docs/09 §4).
    return (_db.update(_db.products)..where((p) => p.id.equals(id))).write(
      db.ProductsCompanion(
        isActive: Value(isActive),
        updatedAt: Value(_db.clock().toUtc()),
      ),
    );
  }

  @override
  Future<int> setFavorite(int id, bool isFavorite) {
    // REQ-PROD-009 — yalnızca bu iki kolon yazılır; favori işareti fiyat,
    // stok veya aktiflik gibi hiçbir alana dokunmaz.
    return (_db.update(_db.products)..where((p) => p.id.equals(id))).write(
      db.ProductsCompanion(
        isFavorite: Value(isFavorite),
        updatedAt: Value(_db.clock().toUtc()),
      ),
    );
  }

  @override
  Future<int> countFavorites() async {
    final count = _db.products.id.count();
    final row =
        await (_db.selectOnly(_db.products)
              ..addColumns([count])
              ..where(_db.products.isFavorite & _db.products.isActive))
            .getSingle();
    return row.read(count) ?? 0;
  }

  @override
  Future<int> deleteById(int id) =>
      (_db.delete(_db.products)..where((p) => p.id.equals(id))).go();

  @override
  Future<int> removeBarcode({required int productId, required String barcode}) {
    return (_db.delete(_db.productBarcodes)..where(
          (b) => b.productId.equals(productId) & b.barcode.equals(barcode),
        ))
        .go();
  }

  @override
  Future<int> removeAllBarcodesOf(int productId) => (_db.delete(
    _db.productBarcodes,
  )..where((b) => b.productId.equals(productId))).go();

  @override
  Future<int> clearPrimaryBarcodes(int productId) {
    return (_db.update(_db.productBarcodes)..where(
          (b) => b.productId.equals(productId) & b.isPrimary.equals(true),
        ))
        .write(const db.ProductBarcodesCompanion(isPrimary: Value(false)));
  }

  @override
  Future<List<String>> barcodesOf(int productId) async {
    // Sıra deterministiktir ve **birincil barkod başta gelir**: satış anında
    // `sale_items.barcode_snapshot`'a yazılacak değer listenin ilkidir
    // (docs/04 §3.9). Sırasız bir sonuç, aynı ürünün satışlarında rastgele
    // barkod snapshot'ı üretirdi.
    final rows =
        await (_db.select(_db.productBarcodes)
              ..where((b) => b.productId.equals(productId))
              ..orderBy([
                (b) => OrderingTerm(
                  expression: b.isPrimary,
                  mode: OrderingMode.desc,
                ),
                (b) => OrderingTerm(expression: b.id),
              ]))
            .get();
    return rows.map((r) => r.barcode).toList();
  }
}
