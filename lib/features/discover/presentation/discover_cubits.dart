import '../../../core/bloc/async_cubit.dart';
import '../../../core/error/result.dart';
import '../../membership/domain/membership.dart';
import '../../membership/domain/membership_repository.dart';
import '../domain/discover.dart';
import '../domain/discover_repository.dart';

class OrgSearchCubit extends AsyncCubit<List<OrgCard>> {
  OrgSearchCubit(this._repository);
  final DiscoverRepository _repository;

  String query = '';
  String? sport;

  @override
  Future<Result<List<OrgCard>>> fetch() => _repository.searchOrgs(query: query, sport: sport);

  Future<void> search({String? query, String? Function()? sport}) {
    if (query != null) this.query = query;
    if (sport != null) this.sport = sport();
    return load();
  }
}

class OrgProfileCubit extends AsyncCubit<OrgProfile> {
  OrgProfileCubit(this._repository, this._memberships, this.orgId);

  final DiscoverRepository _repository;
  final MembershipRepository _memberships;
  final String orgId;

  @override
  Future<Result<OrgProfile>> fetch() => _repository.orgProfile(orgId);

  Future<bool> join(Plan plan, {String? note}) =>
      act(() => _memberships.join(plan.id, note: note), success: 'Request sent. ${plan.name} will confirm shortly.');

  Future<bool> report(String reason) => act(
    () => _repository.report(targetType: 'organization', targetId: orgId, reason: reason),
    success: 'Thanks. Our moderators will take a look.',
    reload: false,
  );
}
