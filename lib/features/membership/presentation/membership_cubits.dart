import '../../../core/bloc/async_cubit.dart';
import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import '../../organization/domain/organization.dart';
import '../../organization/domain/organization_repository.dart';
import '../domain/membership.dart';
import '../domain/membership_repository.dart';

class MyMembershipsCubit extends AsyncCubit<List<Membership>> {
  MyMembershipsCubit(this._repository);
  final MembershipRepository _repository;

  @override
  Future<Result<List<Membership>>> fetch() => _repository.myMemberships();

  Future<bool> cancel(Membership membership) =>
      act(() => _repository.cancel(membership.id), success: 'Membership cancelled.');
}

/// One membership's continuous performance report. The same cubit serves the
/// member (read only) and the coach, who also records into it.
class JourneyCubit extends AsyncCubit<Journey> {
  JourneyCubit(this._repository, this.membershipId, {required this.coachView});

  final MembershipRepository _repository;
  final String membershipId;
  final bool coachView;

  @override
  Future<Result<Journey>> fetch() =>
      coachView ? _repository.memberJourney(membershipId) : _repository.myJourney(membershipId);

  Future<bool> logSession(Json session) =>
      act(() => _repository.logSession(membershipId, session), success: 'Session logged.');

  Future<bool> recordMetrics(Map<String, num> values, {DateTime? on}) => act(
    () => _repository.recordMetrics(membershipId, [
      for (final entry in values.entries) {'metric_id': entry.key, 'value': entry.value},
    ], on: on),
    success: 'Measurements recorded.',
  );

  Future<bool> publishReport(Json report) =>
      act(() => _repository.publishReport(membershipId, report), success: 'Report published to the member.');

  Future<bool> defineMetric(Json metric) {
    final orgId = state.data?.membership.orgId;
    if (orgId == null) return Future.value(false);
    return act(() => _repository.defineMetric(orgId, metric), success: 'Metric added.');
  }
}

class PlansCubit extends AsyncCubit<List<Plan>> {
  PlansCubit(this._repository, this.orgId);
  final MembershipRepository _repository;
  final String orgId;

  @override
  Future<Result<List<Plan>>> fetch() => _repository.plans(orgId);

  Future<bool> save(Json plan) => act(() => _repository.savePlan(orgId, plan), success: 'Plan saved.');
}

typedef MembersData = ({List<Membership> memberships, List<TeamMember> team});

/// Members and mentees of an organisation, with the team for coach picking.
class MembersCubit extends AsyncCubit<MembersData> {
  MembersCubit(this._repository, this._organizations, this.orgId);

  final MembershipRepository _repository;
  final OrganizationRepository _organizations;
  final String orgId;

  @override
  Future<Result<MembersData>> fetch() async {
    final memberships = await _repository.orgMemberships(orgId);
    if (memberships case Err(:final failure)) return Err(failure);
    final team = await _organizations.team(orgId);
    if (team case Err(:final failure)) return Err(failure);
    return Ok((memberships: memberships.valueOrNull!, team: team.valueOrNull!));
  }

  Future<bool> decide(Membership membership, {required bool approve, String? coachId}) => act(
    () => _repository.decide(membership.id, approve: approve, coachId: coachId),
    success: approve ? '${membership.memberName} is now a member.' : 'Request declined.',
  );

  Future<bool> update(Membership membership, Json patch) =>
      act(() => _repository.update(membership.id, patch), success: 'Membership updated.');
}
