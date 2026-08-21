/// Versiyonlu migration adımları — **REQ-MIG-001 · REQ-MIG-004**
///
/// docs/06 §1–§2.
///
/// ## Faz 2'de plan BOŞTUR — ve bu doğrudur
///
/// Faz 2 yalnızca **v1** şemasını yayınlar. v1, `onCreate` ile oluşturulur;
/// çalıştırılacak bir `vN → vN+1` adımı henüz yoktur. Bu dosya **altyapıdır**:
/// ilk gerçek şema değişikliğinde buraya bir [MigrationStep] eklenir ve tüm
/// koruma mekanizmaları (tek transaction, yıkıcı işlem reddi, snapshot,
/// kurtarma) hazır şekilde devreye girer.
///
/// Altyapı, sentetik adımlarla `test/db/migration_test.dart` içinde
/// **gerçekten çalıştırılarak** doğrulanır.
library;

import 'package:drift/drift.dart';

import 'migration_safety.dart';

/// Tek bir `from → to` şema adımı. Adımlar bitişik olmak zorundadır.
class MigrationStep {
  /// Bu adımın uygulandığı şema versiyonu.
  final int from;

  /// Adım sonrası şema versiyonu — daima `from + 1`.
  final int to;

  final Future<void> Function(Migrator m, GeneratedDatabase db) apply;

  MigrationStep({required this.from, required this.to, required this.apply}) {
    if (to != from + 1) {
      throw ArgumentError(
        'Migration adımları bitişik olmalıdır: $from → $to geçersiz.',
      );
    }
  }

  /// Sabit SQL ifadelerinden adım üretir.
  ///
  /// Her ifade [assertNonDestructive] süzgecinden geçer (REQ-MIG-007).
  /// İfadeler **sabittir**; kullanıcı girdisi içermez (REQ-SEC-006).
  factory MigrationStep.sql({
    required int from,
    required int to,
    required List<String> statements,
  }) {
    for (final statement in statements) {
      assertNonDestructive(statement);
    }
    return MigrationStep(
      from: from,
      to: to,
      apply: (m, db) async {
        for (final statement in statements) {
          await db.customStatement(statement);
        }
      },
    );
  }
}

/// Sıralı migration adımları kümesi.
class MigrationPlan {
  final List<MigrationStep> steps;

  MigrationPlan(List<MigrationStep> steps)
    : steps = List.unmodifiable(
        List.of(steps)..sort((a, b) => a.from - b.from),
      );

  /// Yayınlanmış şema değişikliği yok — testler ve sentetik planlar için.
  static final MigrationPlan empty = MigrationPlan(const []);

  /// Uygulamanın **gerçek** planı — docs/06 §1.
  ///
  /// `kSupportedSchemaVersion` artırıldığında buraya karşılık gelen adım
  /// eklenir; eklenmezse `apply` açıkça `StateError` atar ve sessiz bir
  /// şema uyuşmazlığı oluşmaz.
  static final MigrationPlan released = MigrationPlan([
    // v1 → v2 · OD-029 · REQ-CAT-008
    //
    // Kolon **nullable** eklenir: mevcut kategorilerin hiçbiri ikon
    // kazanmış gibi görünmez ve rules/03 §3'ün "yeni NOT NULL kolon daima
    // varsayılan değerle eklenir" kuralı gereksiz kalır. Veri kaybı yoktur;
    // tek işlem bir ADD COLUMN'dur.
    MigrationStep.sql(
      from: 1,
      to: 2,
      statements: const ['ALTER TABLE categories ADD COLUMN icon_key TEXT'],
    ),
  ]);

  /// [from]'dan [to]'ya kadarki adımları **sırayla** uygular.
  ///
  /// Çağıran (Drift'in `onUpgrade`'i) bu çağrıyı tek bir transaction içinde
  /// yürütür — REQ-MIG-004. Herhangi bir adım hata verirse transaction geri
  /// alınır ve şema versiyonu eski halinde kalır (REQ-MIG-003).
  Future<void> apply(
    Migrator m,
    GeneratedDatabase db, {
    required int from,
    required int to,
  }) async {
    if (to < from) {
      // REQ-MIG-005 normalde bunu bağlantı açılışında yakalar; burası son savunma.
      throw StateError(
        'Şema düşürme desteklenmez ($from → $to). Geri alma yalnızca '
        'pre-migration snapshot ile yapılır (docs/06 §4).',
      );
    }

    for (var version = from; version < to; version++) {
      final step = _stepFrom(version);
      if (step == null) {
        throw StateError(
          'Migration adımı bulunamadı: v$version → v${version + 1}. '
          'kSupportedSchemaVersion artırıldıysa MigrationPlan da güncellenmelidir.',
        );
      }
      await step.apply(m, db);
    }
  }

  MigrationStep? _stepFrom(int version) {
    for (final step in steps) {
      if (step.from == version) return step;
    }
    return null;
  }
}
