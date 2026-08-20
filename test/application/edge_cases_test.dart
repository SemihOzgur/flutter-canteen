/// Uç durum denetimi — **docs/26 · docs/31 Faz 11**
///
/// Faz 11 çıkış kriteri *"tüm edge case'ler test edilmiş"*tir. Kendi
/// fazlarında doğal bir yeri olmadığı için boşta kalan `EC-*` maddeleri
/// burada toplanır. `edge_case_traceability_test.dart` hangi maddelerin
/// hâlâ açık olduğunu sayar; bu dosya o listeyi **kapatır**.
///
/// ## Kapsanan uç durumlar (docs/26 · Faz 11 izlenebilirliği)
///
/// - **EC-RET-005** — iade edilen ürün pasifleştirilmiş
/// - **EC-STOCK-003** — negatif stoklu ürün iade ediliyor
/// - **EC-SALE-004** — aynı ürünün birden fazla barkodu ile ekleniyor
/// - **EC-SALE-005** — satış sırasında stok başka yolla değişti
/// - **EC-SUP-002** — tedarikçisiz stok girişi
/// - **EC-PROD-005** — ürünün kategorisi pasifleştirilmiş
/// - **EC-PROD-006** — ürünün tedarikçisi pasifleştirilmiş
/// - **EC-RET-008** — satış ve iade farklı aylarda
/// - **EC-SYS-006** — sistem saati geriye alınmış
/// - **EC-REC-007** — hem parola hem recovery code kaybedilmiş
library;

import 'package:canteen/application/audit/audit_service.dart';
import 'package:canteen/application/auth/financial_access_service.dart';
import 'package:canteen/application/sales/cart_service.dart';
import 'package:canteen/application/sales/return_service.dart';
import 'package:canteen/application/sales/sale_service.dart';
import 'package:canteen/application/stock/stock_service.dart';
import 'package:canteen/data/dao/daos.dart';
import 'package:canteen/data/dao/reporting_dao.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Cart, CartItem, Product, Sale, SaleItem, StockMovement;
import 'package:canteen/data/repositories/drift_product_repository.dart';
import 'package:canteen/data/repositories/drift_sale_repository.dart';
import 'package:canteen/data/repositories/drift_stock_repository.dart';
import 'package:canteen/domain/models/sale_return.dart';
import 'package:canteen/domain/enums/stock_movement_type.dart';
import 'package:canteen/domain/models/sale.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import '../support/test_database.dart';

void main() {
  late CanteenDatabase db;
  late DateTime now;
  late CartService cartService;
  late SaleService saleService;
  late ReturnService returnService;
  late StockService stockService;
  late DriftProductRepository products;
  late DriftStockRepository stockRepo;
  late DriftSaleRepository saleRepo;
  late int userId;

  setUp(() async {
    now = testEpochUtc;
    db = memoryDatabase(clock: () => now);
    products = DriftProductRepository(db);
    stockRepo = DriftStockRepository(db);
    saleRepo = DriftSaleRepository(db);
    final audit = AuditService(auditLogs: AuditLogsDao(db), clock: () => now);
    stockService = StockService(
      db: db,
      stock: stockRepo,
      products: products,
      audit: audit,
      clock: () => now,
    );
    cartService = CartService(
      db: db,
      carts: CartsDao(db),
      cartItems: CartItemsDao(db),
      vatRates: VatRatesDao(db),
      products: products,
      clock: () => now,
    );
    saleService = SaleService(
      db: db,
      cartService: cartService,
      carts: CartsDao(db),
      vatRates: VatRatesDao(db),
      appSettings: AppSettingsDao(db),
      auditLogs: AuditLogsDao(db),
      products: products,
      sales: saleRepo,
      stockService: stockService,
      clock: () => now,
    );
    returnService = ReturnService(
      db: db,
      sales: saleRepo,
      stockService: stockService,
      audit: audit,
      clock: () => now,
    );
    userId = await insertTestUser(db);
  });

  tearDown(() => db.close());

  Future<int> product({
    String name = 'Kola',
    int salePriceMinor = 2500,
    int stockQuantity = 10,
    int? categoryId,
  }) async {
    final id = await insertTestProduct(
      db,
      name: name,
      salePriceMinor: salePriceMinor,
      categoryId: categoryId,
    );
    await (db.update(db.products)..where((p) => p.id.equals(id))).write(
      ProductsCompanion(stockQuantity: Value(stockQuantity)),
    );
    return id;
  }

  Future<({int saleId, List<SaleItem> items})> sell(
    Map<int, int> quantities,
  ) async {
    final cart = await cartService.ensureActive(userId);
    for (final entry in quantities.entries) {
      final added = await cartService.addProduct(
        cartId: cart.id,
        productId: entry.key,
        quantity: entry.value,
      );
      expect(added.isErr, isFalse, reason: '${added.failureOrNull}');
    }
    final receipt = await saleService.complete(cartId: cart.id, userId: userId);
    expect(receipt.isErr, isFalse, reason: '${receipt.failureOrNull}');
    final saleId = receipt.valueOrNull!.saleId;
    return (saleId: saleId, items: await saleRepo.itemsOf(saleId));
  }

  Future<int> stockOf(int id) async => (await (db.select(
    db.products,
  )..where((p) => p.id.equals(id))).getSingle()).stockQuantity;

  // ---------------------------------------------------------------------
  // İADE — docs/26 §7
  // ---------------------------------------------------------------------

  group('iade uç durumları', () {
    test('EC-RET-005 — ürün PASİFLEŞSE de iade yapılabilir', () async {
      // "İade yapılabilir; stok hareketi yazılır." Aksi hâlde pasifleştirme
      // müşterinin parasını geri alamamasına yol açardı.
      final id = await product(stockQuantity: 10);
      final sale = await sell({id: 2});
      await products.setActive(id, false);

      final result = await returnService.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [
          ReturnLineRequest(saleItemId: sale.items.single.id, quantity: 1),
        ],
        reason: 'Müşteri beğenmedi',
      );

      expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
      expect(await stockOf(id), 9, reason: '8 satılmıştı, 1 geri geldi.');
      final movements = await stockRepo.movementsOf(id);
      expect(
        movements.where((m) => m.type == StockMovementType.returnedToStock),
        hasLength(1),
      );
    });

    test('EC-STOCK-003 — negatif stoklu ürünün iadesi stoğu ARTIRIR', () async {
      // "−5 → −4". İade negatif stoğu sıfırlamaz, yalnızca bir artırır;
      // defter mutlak değer değil, delta tutar.
      final id = await product(stockQuantity: 0);
      final sale = await sell({id: 5}); // BR-STOCK-006: negatife düşer
      expect(await stockOf(id), -5);

      final result = await returnService.createReturn(
        saleId: sale.saleId,
        userId: userId,
        lines: [
          ReturnLineRequest(saleItemId: sale.items.single.id, quantity: 1),
        ],
        reason: 'Bozuk çıktı',
      );

      expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
      expect(await stockOf(id), -4);
      final movement = (await stockRepo.movementsOf(
        id,
      )).firstWhere((m) => m.type == StockMovementType.returnedToStock);
      expect(movement.resultingStock, -4);
    });

    test(
      'EC-RET-008 — iade İADE ayında, satış SATIŞ ayında raporlanır',
      () async {
        // BR-RET-008: orijinal satışın tarihi ve tutarı DEĞİŞMEZ. Ocak'ta
        // satılıp Şubat'ta iade edilen mal, Ocak cirosunu geriye dönük
        // düşürmez — aksi hâlde kapanmış bir ay sonradan değişirdi.
        now = DateTime.utc(2026, 1, 15, 10);
        final id = await product(stockQuantity: 10);
        final sale = await sell({id: 2}); // 2 × ₺25,00 = ₺50,00

        now = DateTime.utc(2026, 2, 10, 10);
        final result = await returnService.createReturn(
          saleId: sale.saleId,
          userId: userId,
          lines: [
            ReturnLineRequest(saleItemId: sale.items.single.id, quantity: 1),
          ],
          reason: 'Geç iade',
        );
        expect(result.isErr, isFalse, reason: '${result.failureOrNull}');

        final dao = ReportingDao(db);
        final january = await dao.periodTotals(
          fromMillis: DateTime.utc(2026, 1).millisecondsSinceEpoch,
          toMillis: DateTime.utc(2026, 2).millisecondsSinceEpoch,
        );
        final february = await dao.periodTotals(
          fromMillis: DateTime.utc(2026, 2).millisecondsSinceEpoch,
          toMillis: DateTime.utc(2026, 3).millisecondsSinceEpoch,
        );

        expect(january.grossRevenueMinor, 5000);
        expect(
          january.returnedMinor,
          0,
          reason: 'İade ŞUBAT\'ta yapıldı; Ocak brütü geriye dönük değişmez.',
        );
        expect(february.grossRevenueMinor, 0);
        expect(february.returnedMinor, 2500, reason: 'İade kendi ayına düşer.');
      },
    );
  });

  // ---------------------------------------------------------------------
  // SATIŞ — docs/26 §4-5
  // ---------------------------------------------------------------------

  group('satış uç durumları', () {
    test(
      'EC-SALE-004 — aynı ürünün İKİ BARKODU tek satırda birleşir',
      () async {
        // Çoklu barkod (BR-PROD-012) aynı ürüne işaret eder; barkodun kendisi
        // satır kimliği değildir. İki farklı barkodun iki satır açması, kasada
        // "aynı ürün iki kez göründü" hatasını üretirdi.
        final id = await product(stockQuantity: 10);
        await products.addBarcode(productId: id, barcode: '8690000000001');
        await products.addBarcode(productId: id, barcode: '8690000000002');

        final first = await products.findByBarcode('8690000000001');
        final second = await products.findByBarcode('8690000000002');
        expect(first.valueOrNull!.id, second.valueOrNull!.id);

        final cart = await cartService.ensureActive(userId);
        await cartService.addProduct(
          cartId: cart.id,
          productId: first.valueOrNull!.id,
          quantity: 1,
        );
        await cartService.addProduct(
          cartId: cart.id,
          productId: second.valueOrNull!.id,
          quantity: 1,
        );

        final lines = (await cartService.load(cart.id, userId)).lines;
        expect(lines, hasLength(1), reason: 'Aynı üründür — tek satır.');
        expect(lines.single.quantity, 2);
      },
    );

    test('EC-SALE-005 — satış SIRASINDA değişen stok zinciri bozmaz', () async {
      // Sepet stok rezerve etmez (REQ-CART-004). Sepete eklendikten sonra
      // stok başka bir yoldan değişirse satış hareketi SATIŞ ANINDAKİ
      // değerden zincirlenmelidir; sepetteki eski değerden değil.
      final id = await product(stockQuantity: 10);
      final cart = await cartService.ensureActive(userId);
      await cartService.addProduct(cartId: cart.id, productId: id, quantity: 2);

      // Sepet açıkken fire kaydediliyor: 10 → 7.
      final waste = await stockService.recordWaste(
        productId: id,
        quantity: 3,
        reason: 'Kırıldı',
        userId: userId,
      );
      expect(waste.isErr, isFalse, reason: '${waste.failureOrNull}');
      expect(await stockOf(id), 7);

      final receipt = await saleService.complete(
        cartId: cart.id,
        userId: userId,
      );
      expect(receipt.isErr, isFalse, reason: '${receipt.failureOrNull}');

      expect(await stockOf(id), 5, reason: '7 − 2; 10 − 2 DEĞİL.');
      final saleMovement = (await stockRepo.movementsOf(
        id,
      )).firstWhere((m) => m.type == StockMovementType.sale);
      expect(
        saleMovement.resultingStock,
        5,
        reason: 'resulting_stock defterin o anki ucundan hesaplanır.',
      );
    });
  });

  // ---------------------------------------------------------------------
  // ÜRÜN / TEDARİKÇİ — docs/26 §1-2
  // ---------------------------------------------------------------------

  group('referans verisi uç durumları', () {
    test('EC-SUP-002 — tedarikçisiz stok girişi KABUL EDİLİR', () async {
      // "İzin verilir; supplier_id = NULL." Kantinde peşin/fişsiz alım
      // olağandır; tedarikçiyi zorunlu kılmak girişi bloklardı.
      final id = await product(stockQuantity: 0);

      final result = await stockService.recordEntry(
        lines: [StockEntryLine(productId: id, quantity: 5)],
        userId: userId,
      );

      expect(result.isErr, isFalse, reason: '${result.failureOrNull}');
      final movement = (await stockRepo.movementsOf(
        id,
      )).firstWhere((m) => m.type == StockMovementType.stockEntry);
      expect(movement.supplierId, isNull);
      expect(await stockOf(id), 5);
    });

    test('EC-PROD-005 — kategorisi PASİF ürün satılmaya devam eder', () async {
      // Kategori pasifleştirmek ürünü satıştan düşürmez (BR-CAT-005);
      // yalnızca yeni ürün eklenirken listelenmez. Aksi hâlde tek bir
      // kategori kapatma işlemi kasayı durdururdu.
      final categoryId = await db
          .into(db.categories)
          .insert(
            CategoriesCompanion.insert(
              name: 'Atıştırmalık',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final id = await product(categoryId: categoryId, stockQuantity: 10);

      await (db.update(db.categories)..where((c) => c.id.equals(categoryId)))
          .write(const CategoriesCompanion(isActive: Value(false)));

      final sale = await sell({id: 1});
      expect(sale.items, hasLength(1));
      expect(
        sale.items.single.categoryIdSnapshot,
        categoryId,
        reason: 'Snapshot pasiflikten etkilenmez — geçmiş satış değişmez.',
      );
    });

    test('EC-PROD-006 — tedarikçisi PASİF ürün satılmaya devam eder', () async {
      final supplierId = await db
          .into(db.suppliers)
          .insert(
            SuppliersCompanion.insert(
              name: 'Dağıtım A.Ş.',
              createdAt: now,
              updatedAt: now,
            ),
          );
      final id = await product(stockQuantity: 10);
      await (db.update(db.products)..where((p) => p.id.equals(id))).write(
        ProductsCompanion(supplierId: Value(supplierId)),
      );

      await (db.update(db.suppliers)..where((s) => s.id.equals(supplierId)))
          .write(const SuppliersCompanion(isActive: Value(false)));

      final sale = await sell({id: 1});
      expect(sale.items, hasLength(1));
      expect(await stockOf(id), 9);
    });
  });

  // ---------------------------------------------------------------------
  // SİSTEM — docs/26 §11
  // ---------------------------------------------------------------------

  group('sistem uç durumları', () {
    test(
      'EC-REC-007 — finansal erişim kurtarılamasa da KASA ÇALIŞIR',
      () async {
        // RSK-016 kabul edilmiş bir risktir: dashboard parolası ve recovery
        // code birlikte kaybedilirse finansal ekranlar kalıcı olarak kapalı
        // kalır. Kritik olan, bunun **satışı durdurmamasıdır** — kantin
        // rapor göremeden de çalışmaya devam etmelidir.
        final access = FinancialAccessService(
          db: db,
          settings: AppSettingsDao(db),
          auditLogs: AuditLogsDao(db),
          clock: () => now,
        );
        await access.setPassword('UNUTULDU');

        final wrong = await access.unlock('HATIRLAMIYORUM');
        expect(wrong.isErr, isTrue);
        expect(access.isUnlocked, isFalse);

        // Kilit kapalıyken satış, stok ve ürün işlemleri ETKİLENMEZ.
        final id = await product(stockQuantity: 10);
        final sale = await sell({id: 2});
        expect(sale.items, hasLength(1));
        expect(await stockOf(id), 8);

        final entry = await stockService.recordEntry(
          lines: [StockEntryLine(productId: id, quantity: 5)],
          userId: userId,
        );
        expect(entry.isErr, isFalse, reason: '${entry.failureOrNull}');
        expect(await stockOf(id), 13);

        expect(
          access.isUnlocked,
          isFalse,
          reason: 'Satış yapmak finansal kilidi AÇMAZ.',
        );
      },
    );

    test('EC-SYS-006 — saat GERİYE alınsa da kayıtlar yazılır', () async {
      // "Kayıtlar yazılır; raporlarda tutarsız sıralama olabilir."
      // Uygulama saatin monotonluğuna GÜVENMEZ: bir satışın zaman damgası
      // öncekinden küçük olabilir ve bu bir hata değildir.
      final id = await product(stockQuantity: 10);

      now = DateTime.utc(2026, 3, 10, 12);
      final later = await sell({id: 1});

      now = DateTime.utc(2026, 3, 10, 9); // kullanıcı saati 3 saat geri aldı
      final earlier = await sell({id: 1});

      final first = (await saleRepo.findById(later.saleId)).valueOrNull!;
      final second = (await saleRepo.findById(earlier.saleId)).valueOrNull!;

      expect(
        second.completedAt.isBefore(first.completedAt),
        isTrue,
        reason: 'Sonraki satışın damgası daha erken — kabul edilen durum.',
      );
      expect(
        second.saleNumber.compareTo(first.saleNumber),
        greaterThan(0),
        reason:
            'Fiş numarası SAYAÇTAN gelir, saatten değil; saat geri alınsa '
            'bile numara artmaya devam eder ve benzersizliği korur.',
      );
      expect(await stockOf(id), 8);
    });
  });
}
