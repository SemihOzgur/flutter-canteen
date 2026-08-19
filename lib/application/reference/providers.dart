/// Referans veri servislerinin provider'ları (OD-002 — Riverpod).
///
/// Desen `application/auth/providers.dart` ile aynıdır: servisler
/// **application** katmanına aittir, bu yüzden kurulum bilgisi de buradadır;
/// `data/db/providers.dart` yalnızca bağlantı, repository ve DAO'ları verir
/// (rules/01 §1 — bağımlılık yönü daima aşağı).
///
/// ## Neden `autoDispose` yok
///
/// Bu üç servis durumsuzdur (kilit gibi bellekte yaşayan bir değer tutmazlar);
/// yine de `Provider` kullanılır, çünkü tekrar tekrar kurmanın faydası yoktur.
/// Liste provider'ları ise mutasyondan sonra `ref.invalidate` ile tazelenir —
/// `userListProvider` ile aynı desen.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/providers.dart';
import '../../domain/models/category.dart';
import '../../domain/models/supplier.dart';
import '../../domain/models/vat_rate.dart';
import '../auth/providers.dart' show appLoggerProvider;
import 'category_service.dart';
import 'supplier_service.dart';
import 'vat_rate_service.dart';

// --- Servisler ---------------------------------------------------------------

/// Kategori yönetimi (docs/10 §1).
final categoryServiceProvider = Provider<CategoryService>(
  (ref) => CategoryService(
    db: ref.watch(canteenDatabaseProvider),
    categories: ref.watch(categoriesDaoProvider),
    auditLogs: ref.watch(auditLogsDaoProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

/// Tedarikçi yönetimi (docs/10 §2).
final supplierServiceProvider = Provider<SupplierService>(
  (ref) => SupplierService(
    db: ref.watch(canteenDatabaseProvider),
    suppliers: ref.watch(suppliersDaoProvider),
    auditLogs: ref.watch(auditLogsDaoProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

/// KDV oranı yönetimi (docs/08 §4).
final vatRateServiceProvider = Provider<VatRateService>(
  (ref) => VatRateService(
    db: ref.watch(canteenDatabaseProvider),
    vatRates: ref.watch(vatRatesDaoProvider),
    auditLogs: ref.watch(auditLogsDaoProvider),
    logger: ref.watch(appLoggerProvider),
  ),
);

// --- Listeler ----------------------------------------------------------------

/// Kategori listesi — **pasifler dâhil** (yönetim ekranı için).
final categoryListProvider = FutureProvider<List<Category>>(
  (ref) => ref.watch(categoryServiceProvider).list(),
);

/// Yalnızca aktif kategoriler — ürün formu ve satış ekranı filtresi
/// (docs/10 §1.3: pasif kategori yeni ürün atamasında görünmez).
final activeCategoryListProvider = FutureProvider<List<Category>>(
  (ref) => ref.watch(categoryServiceProvider).list(onlyActive: true),
);

/// Tedarikçi listesi — **pasifler dâhil** (tedarikçi silinmez).
final supplierListProvider = FutureProvider<List<Supplier>>(
  (ref) => ref.watch(supplierServiceProvider).list(),
);

/// KDV oranı listesi — **pasifler dâhil** (oran silinmez).
final vatRateListProvider = FutureProvider<List<VatRate>>(
  (ref) => ref.watch(vatRateServiceProvider).list(),
);

/// Sistemde hiç KDV oranı yoksa `true` — BR-VAT-005.
///
/// KDV alanlarının ve rapor sütunlarının gizlenmesi buna bakar (docs/08 §3).
/// Bu provider bir oran **üretmez**; yalnızca durumu bildirir (REQ-VAT-002 —
/// seed yok).
final vatDisabledProvider = FutureProvider<bool>(
  (ref) => ref.watch(vatRateServiceProvider).isVatDisabled(),
);
