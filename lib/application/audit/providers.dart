/// Denetim kaydı servisinin provider'ı (OD-002 — Riverpod).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/providers.dart';
import '../auth/providers.dart' show appLoggerProvider;
import 'audit_service.dart';

/// docs/18 §7 — denetim kaydının tek yazım noktası.
final auditServiceProvider = Provider<AuditService>(
  (ref) => AuditService(
    auditLogs: ref.watch(auditLogsDaoProvider),
    clock: ref.watch(canteenDatabaseProvider).clock,
    logger: ref.watch(appLoggerProvider),
  ),
);
