import 'package:flutter_test/flutter_test.dart';
import 'package:sidi/core/utils/json.dart';
import 'package:sidi/features/finance/domain/finance.dart';
import 'package:sidi/features/finance/presentation/finance_cubits.dart';
import 'package:sidi/features/membership/domain/membership.dart';

MetricSeries _metric({required bool higherIsBetter, required double first, required double latest}) => MetricSeries(
  id: 'm', name: 'Metric', unit: '', higherIsBetter: higherIsBetter, first: first, latest: latest, best: latest, points: const [],
);

void main() {
  group('Progress on a metric', () {
    test('a faster smash is an improvement', () {
      final smash = _metric(higherIsBetter: true, first: 200, latest: 220);
      expect(smash.improved, isTrue);
      expect(smash.changePct, 10);
    });

    test('a shorter footwork time is an improvement too', () {
      final footwork = _metric(higherIsBetter: false, first: 20, latest: 18);
      expect(footwork.improved, isTrue);
      expect(footwork.declined, isFalse);
      expect(footwork.changePct, -10);
    });

    test('no change is neither', () {
      final flat = _metric(higherIsBetter: true, first: 50, latest: 50);
      expect(flat.improved, isFalse);
      expect(flat.declined, isFalse);
    });
  });

  test('attendance ignores excused sessions', () {
    const attendance = Attendance(sessions: 10, present: 6, absent: 2, excused: 2);
    expect(attendance.rate, 0.75);
    expect(const Attendance().rate, 0);
  });

  group('Budget', () {
    test('usage is measured against the limit for the period', () {
      const equipment = CategoryTotal(direction: 'expense', category: 'equipment', amount: 15000, monthlyLimit: 10000, periodLimit: 30000);
      expect(equipment.usage, 0.5);
      expect(const CategoryTotal(direction: 'expense', category: 'rent', amount: 1).usage, isNull);
    });

    test('venue times are sent without a zone', () {
      expect(isoLocal(DateTime(2026, 11, 14, 18, 5)), '2026-11-14T18:05:00');
    });

    test('ranges start on the first of the month', () {
      final now = DateTime(2026, 11, 14, 9, 30);
      expect(BudgetRange.thisMonth.window(now), (DateTime(2026, 11), DateTime(2026, 11, 14)));
      expect(BudgetRange.last3Months.window(now).$1, DateTime(2026, 9));
      expect(BudgetRange.thisYear.window(now).$1, DateTime(2026));
    });

    test('a range crossing the new year rolls back correctly', () {
      expect(BudgetRange.last6Months.window(DateTime(2027, 2, 10)).$1, DateTime(2026, 9));
    });
  });
}
