import '../../catalog/domain/catalog.dart';

class Plan {
  const Plan({
    required this.id,
    required this.orgId,
    required this.name,
    this.description,
    required this.tier,
    this.sportCode,
    required this.price,
    required this.billingPeriod,
    required this.bookingDiscountPct,
    required this.tracksPerformance,
    required this.isActive,
    this.memberCount = 0,
  });

  final String id;
  final String orgId;
  final String name;
  final String? description;

  /// `pass`, `member`, `club` or `mentee`.
  final String tier;
  final String? sportCode;
  final double price;
  final String billingPeriod;
  final double bookingDiscountPct;
  final bool tracksPerformance;
  final bool isActive;
  final int memberCount;
}

class Membership {
  const Membership({
    required this.id,
    required this.orgId,
    required this.planId,
    required this.status,
    required this.orgName,
    required this.currency,
    required this.planName,
    required this.tier,
    this.sportCode,
    required this.price,
    required this.billingPeriod,
    required this.tracksPerformance,
    required this.memberName,
    this.coachId,
    this.coachName,
    this.note,
    this.startsOn,
    this.endsOn,
    this.reportCount = 0,
    this.sessionCount = 0,
    this.lastSessionOn,
    this.paymentStatus,
  });

  final String id;
  final String orgId;
  final String planId;
  final String status;
  final String orgName;
  final String currency;
  final String planName;
  final String tier;
  final String? sportCode;
  final double price;
  final String billingPeriod;
  final bool tracksPerformance;
  final String memberName;
  final String? coachId;
  final String? coachName;
  final String? note;
  final DateTime? startsOn;
  final DateTime? endsOn;
  final int reportCount;
  final int sessionCount;
  final DateTime? lastSessionOn;
  final String? paymentStatus;
}

class Attendance {
  const Attendance({this.sessions = 0, this.present = 0, this.absent = 0, this.excused = 0, this.minutes = 0, this.last30Days = 0});
  final int sessions;
  final int present;
  final int absent;
  final int excused;
  final int minutes;
  final int last30Days;

  /// Share of non-excused sessions attended, 0..1.
  double get rate => present + absent == 0 ? 0 : present / (present + absent);
}

class MetricPoint {
  const MetricPoint({required this.on, required this.value, this.note});
  final DateTime on;
  final double value;
  final String? note;
}

/// One measured metric over time.
class MetricSeries {
  const MetricSeries({
    required this.id,
    required this.name,
    required this.unit,
    required this.higherIsBetter,
    required this.first,
    required this.latest,
    required this.best,
    required this.points,
  });

  final String id;
  final String name;
  final String unit;
  final bool higherIsBetter;
  final double first;
  final double latest;
  final double best;
  final List<MetricPoint> points;

  double get change => latest - first;

  /// Percent change since the first measurement, signed.
  double get changePct => first == 0 ? 0 : change / first.abs() * 100;

  /// Whether the change is in the direction the athlete wants.
  bool get improved => higherIsBetter ? change > 0 : change < 0;
  bool get declined => higherIsBetter ? change < 0 : change > 0;
}

class ProgressReport {
  const ProgressReport({
    required this.id,
    required this.periodStart,
    required this.periodEnd,
    this.rating,
    required this.summary,
    this.strengths,
    this.focusAreas,
    required this.publishedAt,
    this.coachName,
  });

  final String id;
  final DateTime periodStart;
  final DateTime periodEnd;
  final int? rating;
  final String summary;
  final String? strengths;
  final String? focusAreas;
  final DateTime publishedAt;
  final String? coachName;
}

class TrainingSession {
  const TrainingSession({required this.id, required this.heldOn, required this.minutes, required this.attendance, this.focus, this.notes});
  final String id;
  final DateTime heldOn;
  final int minutes;
  final String attendance;
  final String? focus;
  final String? notes;
}

/// The continuous performance report of one membership.
class Journey {
  const Journey({
    required this.membership,
    required this.attendance,
    required this.metrics,
    required this.reports,
    required this.sessions,
    this.availableMetrics = const [],
  });

  final Membership membership;
  final Attendance attendance;
  final List<MetricSeries> metrics;
  final List<ProgressReport> reports;
  final List<TrainingSession> sessions;

  /// Metrics a coach can record (coach view only).
  final List<MetricDef> availableMetrics;
}
