/// Referans veri provider wiring testleri — **rules/01 §1 · OD-002**
///
/// Servis testleri bağımlılıkları elle enjekte eder; yanlış kurulmuş bir
/// provider grafiği onlardan geçer. Bu dosya yalnızca **kurulumu** doğrular:
/// servisler çözülüyor mu, aynı veritabanına bağlanıyor mu, liste
/// provider'ları gerçekten servis üzerinden okuyor mu.
///
/// Desen: `test/application/auth/providers_test.dart`.
library;

import 'package:canteen/application/reference/category_service.dart';
import 'package:canteen/application/reference/providers.dart';
import 'package:canteen/application/reference/supplier_service.dart';
import 'package:canteen/application/reference/vat_rate_service.dart';
import 'package:canteen/core/result/result.dart';
import 'package:canteen/data/db/canteen_database.dart'
    hide Category, Product, Sale, SaleItem, StockMovement, Supplier, VatRate;
import 'package:canteen/data/db/providers.dart';
import 'package:canteen/data/db/seed.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/test_database.dart';

void main() {
  late CanteenDatabase db;

  ProviderContainer newContainer() {
    final container = ProviderContainer(
      overrides: [canteenDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() => db = memoryDatabase());
  tearDown(() => db.close());

  test('üç servis de çözülür ve tek örnektir', () {
    final container = newContainer();

    expect(container.read(categoryServiceProvider), isA<CategoryService>());
    expect(container.read(supplierServiceProvider), isA<SupplierService>());
    expect(container.read(vatRateServiceProvider), isA<VatRateService>());

    expect(
      identical(
        container.read(categoryServiceProvider),
        container.read(categoryServiceProvider),
      ),
      isTrue,
    );
  });

  test(
    'categoryListProvider seed edilmiş `Genel` kategorisini döner',
    () async {
      final container = newContainer();

      final categories = await container.read(categoryListProvider.future);
      expect(categories.single.name, Seed.generalCategoryName);
      expect(categories.single.isSystem, isTrue);
    },
  );

  test('mutasyon sonrası invalidate ile liste tazelenir', () async {
    final container = newContainer();

    expect(await container.read(categoryListProvider.future), hasLength(1));

    final created = await container
        .read(categoryServiceProvider)
        .create(name: 'İçecek');
    expect(created.isOk, isTrue);

    container.invalidate(categoryListProvider);
    final refreshed = await container.read(categoryListProvider.future);
    expect(refreshed.map((c) => c.name), contains('İçecek'));
  });

  test('aktif kategori listesi pasifleri eler', () async {
    final container = newContainer();
    final service = container.read(categoryServiceProvider);

    final id = (await service.create(name: 'İçecek') as Ok<int>).value;
    await service.deactivate(id);

    final all = await container.read(categoryListProvider.future);
    final active = await container.read(activeCategoryListProvider.future);

    expect(all.map((c) => c.id), contains(id));
    expect(active.map((c) => c.id), isNot(contains(id)));
  });

  test('supplierListProvider boş başlar ve oluşturulanı gösterir', () async {
    final container = newContainer();

    expect(await container.read(supplierListProvider.future), isEmpty);

    await container.read(supplierServiceProvider).create(name: 'Toptancı');
    container.invalidate(supplierListProvider);

    expect(
      (await container.read(supplierListProvider.future)).single.name,
      'Toptancı',
    );
  });

  test('OD-017: vatRateListProvider nötr %0 oranıyla başlar', () async {
    final container = newContainer();

    final initial = await container.read(vatRateListProvider.future);
    expect(initial.single.rateBasisPoints, 0, reason: 'Yalnızca nötr oran.');
    expect(
      await container.read(vatDisabledProvider.future),
      isTrue,
      reason: 'BR-VAT-005: tek oran %0 ise KDV alanları gizlenir.',
    );

    await container
        .read(vatRateServiceProvider)
        .create(name: 'Standart', rateBasisPoints: 2000);
    container
      ..invalidate(vatRateListProvider)
      ..invalidate(vatDisabledProvider);

    final after = await container.read(vatRateListProvider.future);
    expect(after, hasLength(2), reason: 'Nötr oran + kullanıcının oranı.');
    expect(after.map((r) => r.rateBasisPoints), containsAll(<int>[0, 2000]));
    expect(
      await container.read(vatDisabledProvider.future),
      isFalse,
      reason: 'Gerçek bir oran tanımlanınca KDV açılır.',
    );
  });
}
