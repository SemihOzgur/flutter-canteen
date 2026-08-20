/// Rapor dönemleri — **docs/15 §2 · BR-GEN-004**
///
/// Gün sınırları **yerel saattedir**; veriler UTC saklanır. Bu ayrımın
/// sınırları burada, veritabanı olmadan sınanır.
///
/// ## Kapsanan requirement'lar (Faz 11 izlenebilirliği)
///
/// - **REQ-DASH-001** — 7 tarih aralığı seçeneği
/// ## Kapsanan uç durumlar (docs/26 · Faz 11 izlenebilirliği)
///
/// - **EC-SYS-007** — yaz saati geçişi — UTC saklanır, gün sınırı yereldir
///
library;

import 'package:canteen/domain/services/report_period.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Yerel saatte 14 Ağustos 2026, saat 15:30.
  final now = DateTime(2026, 8, 14, 15, 30);

  ReportPeriod period(ReportPeriodKind kind) => ReportPeriod.of(kind, now);

  DateTime localStartOf(ReportPeriodKind kind) =>
      period(kind).fromUtc.toLocal();

  DateTime localEndOf(ReportPeriodKind kind) => period(kind).toUtc.toLocal();

  group('docs/15 §2 — dönem sınırları', () {
    test('Bugün: yerel 00:00 → yarın 00:00', () {
      expect(localStartOf(ReportPeriodKind.today), DateTime(2026, 8, 14));
      expect(localEndOf(ReportPeriodKind.today), DateTime(2026, 8, 15));
    });

    test('SINIR — üst sınır "şu an" DEĞİLDİR', () {
      // Yarı açık aralıkta üst sınır "şu an" olsaydı, tam o anda tamamlanan
      // satış dışarıda kalırdı ve "bugünkü ciro" sorgunun çalıştığı
      // milisaniyeye göre değişirdi.
      expect(period(ReportPeriodKind.today).toUtc, isNot(now.toUtc()));
      expect(period(ReportPeriodKind.today).toUtc.isAfter(now.toUtc()), isTrue);
    });

    test('Dün: önceki gün 00:00 → bugün 00:00', () {
      expect(localStartOf(ReportPeriodKind.yesterday), DateTime(2026, 8, 13));
      expect(localEndOf(ReportPeriodKind.yesterday), DateTime(2026, 8, 14));
    });

    test('Dün ile Bugün ÇAKIŞMAZ ve boşluk BIRAKMAZ', () {
      expect(
        period(ReportPeriodKind.yesterday).toUtc,
        period(ReportPeriodKind.today).fromUtc,
      );
    });

    test('Bu Hafta pazartesiden başlar (tr_TR)', () {
      // 14 Ağustos 2026 bir Cuma; o haftanın pazartesisi 10 Ağustos.
      expect(now.weekday, DateTime.friday);
      expect(localStartOf(ReportPeriodKind.thisWeek), DateTime(2026, 8, 10));
    });

    test('Bu Ay ayın 1\'inden başlar', () {
      expect(localStartOf(ReportPeriodKind.thisMonth), DateTime(2026, 8));
    });

    test('Son 7 Gün bugünü İÇERİR — 6 gün önceden başlar', () {
      expect(localStartOf(ReportPeriodKind.last7Days), DateTime(2026, 8, 8));
      expect(period(ReportPeriodKind.last7Days).length.inDays, 7);
    });

    test('Son 30 Gün 30 gündür', () {
      expect(localStartOf(ReportPeriodKind.last30Days), DateTime(2026, 7, 16));
      expect(period(ReportPeriodKind.last30Days).length.inDays, 30);
    });

    test('YEREL gün sınırı günün HER saatinde korunur', () {
      // UTC'ye göre bölünseydi, saat farkı olan bir makinede gece yarısına
      // yakın saatlerde gün BİR ÖNCEKİNE (veya sonrakine) kayardı ve
      // kullanıcının "bugün"ü yanlış olurdu (BR-GEN-004).
      //
      // ⚠️ Makinenin saat dilimi UTC ise (CI'da olabilir) bu testin ayırt
      // edici gücü yoktur: kayma diye bir şey oluşmaz. Bu bir test kusuru
      // değil, ortamın sınırıdır — docs/32 §8'de kayıtlıdır.
      for (final hour in [0, 1, 12, 22, 23]) {
        final at = DateTime(2026, 8, 14, hour, 30);
        final today = ReportPeriod.of(ReportPeriodKind.today, at);

        expect(
          today.fromUtc.toLocal(),
          DateTime(2026, 8, 14),
          reason: 'Saat $hour:30 — gün başlangıcı YEREL 00:00 olmalıdır.',
        );
        expect(today.toUtc.toLocal(), DateTime(2026, 8, 15));
      }
    });

    test('sınırlar UTC\'ye çevrilir ama YEREL günden hesaplanır', () {
      // UTC'ye göre bölünseydi UTC+3'te her günün ilk üç saati bir önceki
      // güne yazılır ve kasa mutabakatı tutmazdı (BR-GEN-004).
      final start = period(ReportPeriodKind.today).fromUtc;
      expect(start.isUtc, isTrue);
      expect(start.toLocal().hour, 0);
      expect(start.toLocal().minute, 0);
    });
  });

  group('docs/15 §2 — karşılaştırma dönemi', () {
    test('aynı uzunlukta ÖNCEKİ dönemdir', () {
      final current = period(ReportPeriodKind.last7Days);
      final previous = current.previous;

      expect(previous.length, current.length);
      expect(previous.toUtc, current.fromUtc);
      expect(previous.fromUtc.toLocal(), DateTime(2026, 8, 1));
    });

    test('dün için karşılaştırma önceki gündür', () {
      final previous = period(ReportPeriodKind.yesterday).previous;

      expect(previous.fromUtc.toLocal(), DateTime(2026, 8, 12));
      expect(previous.toUtc.toLocal(), DateTime(2026, 8, 13));
    });
  });

  group('docs/15 §3.2 — grafik granülerliği', () {
    String formatFor(int days) => ReportPeriod(
      kind: ReportPeriodKind.custom,
      fromUtc: now.toUtc(),
      toUtc: now.toUtc().add(Duration(days: days)),
    ).trendFormat;

    test('≤ 2 gün saatlik', () {
      expect(formatFor(1), '%Y-%m-%d %H');
      expect(formatFor(2), '%Y-%m-%d %H');
    });

    test('SINIR — 3 gün günlüğe geçer', () {
      expect(formatFor(3), '%Y-%m-%d');
    });

    test('SINIR — 31 gün günlük, 32 gün haftalık', () {
      expect(formatFor(31), '%Y-%m-%d');
      expect(formatFor(32), '%Y-W%W');
    });

    test('SINIR — 366 gün haftalık, 367 gün aylık', () {
      expect(formatFor(366), '%Y-W%W');
      expect(formatFor(367), '%Y-%m');
    });
  });

  group('docs/15 §3.3 — saatlik yoğunluk koşulu', () {
    bool showsFor(int days) => ReportPeriod(
      kind: ReportPeriodKind.custom,
      fromUtc: now.toUtc(),
      toUtc: now.toUtc().add(Duration(days: days)),
    ).showsHourlyDensity;

    test('SINIR — 1 gün gösterilmez, 2 gün gösterilir', () {
      expect(showsFor(1), isFalse);
      expect(showsFor(2), isTrue);
    });

    test('Bugün seçiliyken gösterilmez', () {
      expect(period(ReportPeriodKind.today).showsHourlyDensity, isFalse);
    });

    test('Son 7 Gün seçiliyken gösterilir', () {
      expect(period(ReportPeriodKind.last7Days).showsHourlyDensity, isTrue);
    });
  });

  group('özel aralık', () {
    test('bitiş günü DÂHİLDİR — gün sonuna genişletilir', () {
      // Kullanıcı 1–5 Ağustos seçtiğinde 5 Ağustos'un TAMAMI beklenir.
      final custom = ReportPeriod.customRange(
        DateTime(2026, 8, 1, 14),
        DateTime(2026, 8, 5, 9),
      );

      expect(custom.fromUtc.toLocal(), DateTime(2026, 8, 1));
      expect(custom.toUtc.toLocal(), DateTime(2026, 8, 6));
      expect(custom.length.inDays, 5);
    });

    test('tek günlük özel aralık o günün tamamıdır', () {
      final custom = ReportPeriod.customRange(
        DateTime(2026, 8, 3),
        DateTime(2026, 8, 3),
      );

      expect(custom.length.inDays, 1);
      expect(custom.showsHourlyDensity, isFalse);
    });
  });
}
