/// Bakım servislerinin provider'ları (OD-002 — Riverpod).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/dao/consistency_dao.dart';
import '../../data/db/providers.dart';
import '../../data/files/providers.dart';
import '../audit/providers.dart';
import '../stock/providers.dart';
import 'consistency_service.dart';

final consistencyDaoProvider = Provider<ConsistencyDao>(
  (ref) => ConsistencyDao(ref.watch(canteenDatabaseProvider)),
);

/// docs/24 §3.3 — Ayarlar → Bakım → Veri Tutarlılığı Kontrolü.
///
/// Görsel dizini `appPathsProvider` üzerinden verilir; yoksa görsel denetimi
/// atlanır (rules/03 §8 — yol **görelidir**, kök çalışma zamanında çözülür).
final consistencyServiceProvider = Provider<ConsistencyService>(
  (ref) => ConsistencyService(
    dao: ref.watch(consistencyDaoProvider),
    stockService: ref.watch(stockServiceProvider),
    audit: ref.watch(auditServiceProvider),
    imagesDirectory: ref.watch(appPathsProvider).imagesDir,
    clock: ref.watch(canteenDatabaseProvider).clock,
  ),
);
