import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import '../../../core/utils/json.dart';
import '../../catalog/data/catalog_repository_impl.dart';
import '../domain/membership.dart';
import '../domain/membership_repository.dart';

Plan planFromJson(Json p) => Plan(
  id: p.str('id'),
  orgId: p.str('org_id'),
  name: p.str('name'),
  description: p.strOrNull('description'),
  tier: p.str('tier', 'member'),
  sportCode: p.strOrNull('sport_code'),
  price: p.number('price'),
  billingPeriod: p.str('billing_period', 'monthly'),
  bookingDiscountPct: p.number('booking_discount_pct'),
  tracksPerformance: p.flag('tracks_performance'),
  isActive: p.flag('is_active', true),
  memberCount: p.integer('member_count'),
);

Membership membershipFromJson(Json m) => Membership(
  id: m.str('id'),
  orgId: m.str('org_id'),
  planId: m.str('plan_id'),
  status: m.str('status'),
  orgName: m.str('org_name'),
  currency: m.str('currency', 'INR'),
  planName: m.str('plan_name'),
  tier: m.str('tier', 'member'),
  sportCode: m.strOrNull('sport_code'),
  price: m.number('price'),
  billingPeriod: m.str('billing_period', 'monthly'),
  tracksPerformance: m.flag('tracks_performance'),
  memberName: m.str('member_name'),
  coachId: m.strOrNull('coach_id'),
  coachName: m.strOrNull('coach_name'),
  note: m.strOrNull('note'),
  startsOn: m.dayOrNull('starts_on'),
  endsOn: m.dayOrNull('ends_on'),
  reportCount: m.integer('report_count'),
  sessionCount: m.integer('session_count'),
  lastSessionOn: m.dayOrNull('last_session_on'),
  paymentStatus: m.objOrNull('payment')?.strOrNull('status'),
);

Journey journeyFromJson(dynamic json) {
  final map = asJson(json);
  final attendance = map.obj('attendance');
  return Journey(
    membership: membershipFromJson(map.obj('membership')),
    attendance: Attendance(
      sessions: attendance.integer('sessions'),
      present: attendance.integer('present'),
      absent: attendance.integer('absent'),
      excused: attendance.integer('excused'),
      minutes: attendance.integer('minutes'),
      last30Days: attendance.integer('last_30_days'),
    ),
    metrics: map.list(
      'metrics',
      (m) => MetricSeries(
        id: m.str('id'),
        name: m.str('name'),
        unit: m.str('unit'),
        higherIsBetter: m.flag('higher_is_better', true),
        first: m.number('first'),
        latest: m.number('latest'),
        best: m.number('best'),
        points: m.list(
          'points',
          (p) => MetricPoint(on: p.dayOrNull('on') ?? DateTime.now(), value: p.number('value'), note: p.strOrNull('note')),
        ),
      ),
    ),
    reports: map.list(
      'reports',
      (r) => ProgressReport(
        id: r.str('id'),
        periodStart: r.dayOrNull('period_start') ?? DateTime.now(),
        periodEnd: r.dayOrNull('period_end') ?? DateTime.now(),
        rating: r.intOrNull('rating'),
        summary: r.str('summary'),
        strengths: r.strOrNull('strengths'),
        focusAreas: r.strOrNull('focus_areas'),
        publishedAt: r.date('published_at'),
        coachName: r.strOrNull('coach_name'),
      ),
    ),
    sessions: map.list(
      'sessions',
      (s) => TrainingSession(
        id: s.str('id'),
        heldOn: s.dayOrNull('held_on') ?? DateTime.now(),
        minutes: s.integer('minutes'),
        attendance: s.str('attendance'),
        focus: s.strOrNull('focus'),
        notes: s.strOrNull('notes'),
      ),
    ),
    availableMetrics: map.list('available_metrics', metricFromJson),
  );
}

class MembershipRepositoryImpl implements MembershipRepository {
  MembershipRepositoryImpl(this._rpc);
  final Rpc _rpc;

  @override
  Future<Result<void>> join(String planId, {String? note}) =>
      _rpc.run('membership_join', params: {'p_plan_id': planId, 'p_note': note});

  @override
  Future<Result<void>> cancel(String membershipId) =>
      _rpc.run('membership_cancel', params: {'p_membership_id': membershipId});

  @override
  Future<Result<List<Membership>>> myMemberships() =>
      _rpc.call('my_memberships', parse: (json) => parseList(json, membershipFromJson));

  @override
  Future<Result<Journey>> myJourney(String membershipId) =>
      _rpc.call('my_journey', params: {'p_membership_id': membershipId}, parse: journeyFromJson);

  @override
  Future<Result<List<Plan>>> plans(String orgId) =>
      _rpc.call('org_plans', params: {'p_org_id': orgId}, parse: (json) => parseList(json, planFromJson));

  @override
  Future<Result<void>> savePlan(String orgId, Json plan) =>
      _rpc.run('org_plan_save', params: {'p_org_id': orgId, 'p_plan': plan});

  @override
  Future<Result<List<Membership>>> orgMemberships(String orgId) =>
      _rpc.call('org_memberships', params: {'p_org_id': orgId}, parse: (json) => parseList(json, membershipFromJson));

  @override
  Future<Result<void>> decide(String membershipId, {required bool approve, String? coachId}) => _rpc.run(
    'org_membership_decide',
    params: {'p_membership_id': membershipId, 'p_approve': approve, 'p_coach_id': coachId},
  );

  @override
  Future<Result<void>> update(String membershipId, Json patch) =>
      _rpc.run('org_membership_update', params: {'p_membership_id': membershipId, 'p_patch': patch});

  @override
  Future<Result<Journey>> memberJourney(String membershipId) =>
      _rpc.call('org_member_journey', params: {'p_membership_id': membershipId}, parse: journeyFromJson);

  @override
  Future<Result<void>> logSession(String membershipId, Json session) =>
      _rpc.run('org_session_log', params: {'p_membership_id': membershipId, 'p_session': session});

  @override
  Future<Result<void>> recordMetrics(String membershipId, List<Json> entries, {DateTime? on}) => _rpc.run(
    'org_performance_record',
    params: {'p_membership_id': membershipId, 'p_entries': entries, 'p_recorded_on': on == null ? null : isoDay(on)},
  );

  @override
  Future<Result<void>> publishReport(String membershipId, Json report) =>
      _rpc.run('org_report_publish', params: {'p_membership_id': membershipId, 'p_report': report});

  @override
  Future<Result<void>> defineMetric(String orgId, Json metric) =>
      _rpc.run('org_metric_save', params: {'p_org_id': orgId, 'p_metric': metric});
}
