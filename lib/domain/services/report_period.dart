/// Rapor dönemi — **docs/15 §2 · BR-GEN-004**
///
/// Saf Dart, deterministik (rules/06 §7): "şimdi" **parametredir**.
///
/// ## Gün sınırları YEREL saattedir
///
/// Veriler UTC saklanır (BR-GEN-004) ama kullanıcının "bugün"ü yerel gündür.
/// UTC'ye göre bölmek, UTC+3'te her günün ilk üç saatini bir önceki güne
/// yazardı — kasa mutabakatı tutmazdı.
library;

/// docs/15 §2 — desteklenen dönemler.
enum ReportPeriodKind {
  today,
  yesterday,
  thisWeek,
  thisMonth,
  last7Days,
  last30Days,
  custom,
}

/// Yarı açık aralık: `[fromUtc, toUtc)`.
class ReportPeriod {
  final ReportPeriodKind kind;
  final DateTime fromUtc;
  final DateTime toUtc;

  const ReportPeriod({
    required this.kind,
    required this.fromUtc,
    required this.toUtc,
  });

  /// docs/15 §2 — özel aralık en fazla 5 yıl.
  static const Duration maxCustomRange = Duration(days: 365 * 5);

  Duration get length => toUtc.difference(fromUtc);

  /// docs/15 §2 — karşılaştırma dönemi: **aynı uzunlukta önceki dönem.**
  ReportPeriod get previous => ReportPeriod(
    kind: kind,
    fromUtc: fromUtc.subtract(length),
    toUtc: fromUtc,
  );

  /// docs/15 §3.2 — aralığa göre grafik granülerliği.
  ///
  /// ```text
  /// ≤  2 gün  → saatlik
  /// ≤ 31 gün  → günlük
  /// ≤ 12 ay   → haftalık
  ///  > 12 ay  → aylık
  /// ```
  String get trendFormat {
    final days = length.inDays;
    if (days <= 2) return '%Y-%m-%d %H';
    if (days <= 31) return '%Y-%m-%d';
    if (days <= 366) return '%Y-W%W';
    return '%Y-%m';
  }

  /// docs/15 §3.3 — saatlik yoğunluk yalnızca aralık ≥ 2 gün olduğunda.
  bool get showsHourlyDensity => length.inDays >= 2;

  /// [now] **yerel** saat kabul edilir; sınırlar yerel günden hesaplanıp
  /// UTC'ye çevrilir.
  ///
  /// ## Üst sınır "şu an" değil, GÜNÜN SONUDUR
  ///
  /// docs/15 §2 aralıkları *"… → şu an"* diye tarif eder. Aralık yarı açık
  /// olduğu için (`[from, to)`) üst sınırı tam olarak "şu an" yapmak, **tam o
  /// anda tamamlanan satışı dışarıda bırakır.** Pratikte fark yoktur —
  /// gelecek tarihli kayıt oluşamaz — ama sınır davranışının bir yarış
  /// koşuluna bağlı olması kabul edilemez: "bugünkü ciro" sorgunun hangi
  /// milisaniyede çalıştığına göre değişemez.
  ///
  /// Bu yüzden üst sınır **yerel günün sonudur**. `[bugün 00:00, yarın 00:00)`
  /// ile `[bugün 00:00, şu an]` aynı kümedir.
  static ReportPeriod of(ReportPeriodKind kind, DateTime now) {
    final local = now.toLocal();
    final startOfToday = DateTime(local.year, local.month, local.day);

    // Yarın 00:00 — bugünün tamamını kapsayan yarı açık üst sınır.
    final endOfToday = startOfToday.add(const Duration(days: 1));

    switch (kind) {
      case ReportPeriodKind.today:
      case ReportPeriodKind.custom:
        return _range(kind, startOfToday, endOfToday);
      case ReportPeriodKind.yesterday:
        final start = startOfToday.subtract(const Duration(days: 1));
        return _range(kind, start, startOfToday);
      case ReportPeriodKind.thisWeek:
        // Pazartesi haftanın ilk günüdür (tr_TR).
        final start = startOfToday.subtract(
          Duration(days: local.weekday - DateTime.monday),
        );
        return _range(kind, start, endOfToday);
      case ReportPeriodKind.thisMonth:
        return _range(kind, DateTime(local.year, local.month), endOfToday);
      case ReportPeriodKind.last7Days:
        // "Son 7 gün" bugünü İÇERİR: 6 gün önce 00:00 → bugünün sonu.
        return _range(
          kind,
          startOfToday.subtract(const Duration(days: 6)),
          endOfToday,
        );
      case ReportPeriodKind.last30Days:
        return _range(
          kind,
          startOfToday.subtract(const Duration(days: 29)),
          endOfToday,
        );
    }
  }

  /// Kullanıcının seçtiği özel aralık — **gün sınırlarına genişletilir.**
  ///
  /// Bitiş günü **dâhildir**: kullanıcı 1–5 Ağustos seçtiğinde 5 Ağustos'un
  /// tamamı beklenir, 5 Ağustos 00:00 değil.
  static ReportPeriod customRange(DateTime fromLocal, DateTime toLocal) {
    final start = DateTime(fromLocal.year, fromLocal.month, fromLocal.day);
    final end = DateTime(
      toLocal.year,
      toLocal.month,
      toLocal.day,
    ).add(const Duration(days: 1));
    return _range(ReportPeriodKind.custom, start, end);
  }

  static ReportPeriod _range(
    ReportPeriodKind kind,
    DateTime startLocal,
    DateTime endLocal,
  ) => ReportPeriod(
    kind: kind,
    fromUtc: startLocal.toUtc(),
    toUtc: endLocal.toUtc(),
  );
}
