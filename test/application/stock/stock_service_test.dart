/// Stok defteri testleri — **BR-STOCK-001…004/008 · REQ-PROD-007 · docs/13 §2**
///
/// docs/27 §4: gerçek in-memory SQLite üzerinde çalışır; mock veritabanı yoktur.
///
/// Test önceliği rules/06 §2: **Stock — defter tutarlılığı** 🔴.
library;

import 'package:canteen/application/stock/stock_service.dart';
import 'package:canteen/core/money/money.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Product, StockMovement;
import 'package:canteen/data/repositories/drift_stock_repository.dart';
import 'package:canteen/domain/enums/stock_movement_type.dart';
import 'package:canteen/domain/enums/stock_reference_type.dart';
import 'package:canteen/domain/models/stock_movement.dart';
import 'package:canteen/domain/repositories/stock_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late StockRepository stock;
  late StockService service;
  late int userId;
  late int productId;

  setUp(() async {
    db = memoryDatabase();
    stock = DriftStockRepository(db);
    service = StockService(db: db, stock: stock, clock: () => testEpochUtc);
    userId = await insertTestUser(db);
    productId = await insertTestProduct(db);
  });

  tearDown(() async => db.close());

  Future<int> cachedStock() async {
    final row = await (db.select(
      db.products,
    )..where((p) => p.id.equals(productId))).getSingle();
    return row.stockQuantity;
  }

  /// BR-STOCK-003 invariant'ı: `stock_quantity == Σ quantity_delta`.
  Future<void> expectLedgerConsistency() async {
    expect(
      await cachedStock(),
      await stock.sumQuantityDelta(productId),
      reason: 'BR-STOCK-002/003 — önbellek defterle aynı olmalıdır.',
    );
  }

  test('REQ-PROD-007 — başlangıç stoğu `initial` hareketi oluşturur', () async {
    final result = await service.recordInitialStock(
      productId: productId,
      quantity: 50,
      userId: userId,
      unitCost: const Money(8000),
    );

    expect(result.isOk, isTrue);
    expect((result as Ok<int>).value, 50);

    final movements = await stock.movementsOf(productId);
    expect(movements, hasLength(1));

    final movement = movements.single;
    expect(movement.type, StockMovementType.initial);
    expect(movement.quantityDelta, 50);
    // BR-STOCK-008 — hareket sonrası stok her harekette yazılır.
    expect(movement.resultingStock, 50);
    expect(movement.userId, userId);
    expect(movement.unitCost, const Money(8000));

    // Acceptance criteria (docs/09 §8): products.stock_quantity = 50.
    expect(await cachedStock(), 50);
    await expectLedgerConsistency();
  });

  test('BR-STOCK-004 — miktar 0 ise HAREKET YAZILMAZ', () async {
    final result = await service.recordInitialStock(
      productId: productId,
      quantity: 0,
      userId: userId,
    );

    expect(result.isOk, isTrue);
    expect((result as Ok<int>).value, 0);
    expect(await stock.movementsOf(productId), isEmpty);
    expect(await cachedStock(), 0);
    await expectLedgerConsistency();
  });

  test('docs/13 §2 — `initial` yönü artıdır; negatif reddedilir', () async {
    final result = await service.recordInitialStock(
      productId: productId,
      quantity: -5,
      userId: userId,
    );

    expect(result.isErr, isTrue);
    expect(result.failureOrNull!.code, 'stock_initial_negative');
    expect(await stock.movementsOf(productId), isEmpty);
    expect(await cachedStock(), 0);
  });

  test('docs/13 §2 — ürün başına en fazla bir `initial`', () async {
    await service.recordInitialStock(
      productId: productId,
      quantity: 10,
      userId: userId,
    );

    final second = await service.recordInitialStock(
      productId: productId,
      quantity: 7,
      userId: userId,
    );

    expect(second.isErr, isTrue);
    expect(second.failureOrNull!.code, 'stock_already_initialized');
    expect(await stock.movementsOf(productId), hasLength(1));
    expect(await cachedStock(), 10);
    await expectLedgerConsistency();
  });

  test(
    'BR-STOCK-002 — hareket ve önbellek AYNI transaction içindedir',
    () async {
      // Hata ENJEKSİYONU (rules/06 §2): önbellek yazımı patlarsa deftere
      // yazılmış hareket de geri alınmalıdır. Aksi hâlde
      // `stock_quantity != Σ quantity_delta` olur — RSK-008.
      final failing = _FailingCacheStockRepository(stock);
      final service = StockService(
        db: db,
        stock: failing,
        clock: () => testEpochUtc,
      );

      await expectLater(
        service.recordInitialStock(
          productId: productId,
          quantity: 12,
          userId: userId,
        ),
        throwsA(isA<StateError>()),
      );

      expect(
        await stock.movementsOf(productId),
        isEmpty,
        reason: 'Hareket geri alınmalıdır.',
      );
      expect(await cachedStock(), 0);
      await expectLedgerConsistency();
    },
  );

  test('var olmayan kullanıcı → FK hatası, defter değişmez', () async {
    await expectLater(
      service.recordInitialStock(
        productId: productId,
        quantity: 5,
        userId: 9999,
      ),
      throwsA(anything),
    );

    expect(await stock.movementsOf(productId), isEmpty);
    expect(await cachedStock(), 0);
  });
}

/// Önbellek yazımında patlayan sarmalayıcı — atomiklik testi için.
///
/// Diğer tüm çağrılar gerçek repository'ye devredilir; yalnızca
/// [writeStockQuantity] patlar.
class _FailingCacheStockRepository implements StockRepository {
  final StockRepository _inner;

  _FailingCacheStockRepository(this._inner);

  @override
  Future<int> writeStockQuantity(int productId, int quantity) =>
      throw StateError('önbellek yazımı başarısız');

  @override
  Future<int> appendMovement({
    required int productId,
    required StockMovementType type,
    required int quantityDelta,
    required int resultingStock,
    required int userId,
    required DateTime createdAtUtc,
    Money? unitCost,
    StockReferenceType? referenceType,
    int? referenceId,
    int? supplierId,
    String? note,
  }) => _inner.appendMovement(
    productId: productId,
    type: type,
    quantityDelta: quantityDelta,
    resultingStock: resultingStock,
    userId: userId,
    createdAtUtc: createdAtUtc,
    unitCost: unitCost,
    referenceType: referenceType,
    referenceId: referenceId,
    supplierId: supplierId,
    note: note,
  );

  @override
  Future<int> readStockQuantity(int productId) =>
      _inner.readStockQuantity(productId);

  @override
  Future<int> countMovements(int productId) => _inner.countMovements(productId);

  @override
  Future<Result<StockMovement>> findById(int id) => _inner.findById(id);

  @override
  Future<List<StockMovement>> findByReference({
    required StockReferenceType referenceType,
    required int referenceId,
  }) => _inner.findByReference(
    referenceType: referenceType,
    referenceId: referenceId,
  );

  @override
  Future<List<StockMovement>> movementsOf(
    int productId, {
    int limit = 100,
    int offset = 0,
  }) => _inner.movementsOf(productId, limit: limit, offset: offset);

  @override
  Future<int> sumQuantityDelta(int productId) =>
      _inner.sumQuantityDelta(productId);
}
