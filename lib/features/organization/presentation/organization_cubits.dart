import '../../../core/bloc/async_cubit.dart';
import '../../../core/bloc/submit_cubit.dart';
import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import '../domain/organization.dart';
import '../domain/organization_repository.dart';

/// Files an application for a new organisation; the value is its id.
class OrgCreateCubit extends SubmitCubit<String> {
  OrgCreateCubit(this._repository);
  final OrganizationRepository _repository;

  Future<void> create(Json org) => submit(() => _repository.create(org));
}

class OrgOverviewCubit extends AsyncCubit<OrgOverview> {
  OrgOverviewCubit(this._repository, this.orgId);
  final OrganizationRepository _repository;
  final String orgId;

  @override
  Future<Result<OrgOverview>> fetch() => _repository.overview(orgId);

  Future<bool> update(Json patch) => act(() => _repository.update(orgId, patch), success: 'Details saved.');
}

class OrgAccessCubit extends AsyncCubit<OrgAccess> {
  OrgAccessCubit(this._repository, this.orgId);
  final OrganizationRepository _repository;
  final String orgId;

  @override
  Future<Result<OrgAccess>> fetch() => _repository.access(orgId);

  Future<bool> requestVerification(String message, List<String> documents) => act(
    () => _repository.requestVerification(orgId, message: message, documents: documents),
    success: 'Verification request sent.',
  );

  Future<bool> requestFeature(FeatureState feature, String? message) => act(
    () => _repository.requestFeature(orgId, feature.key, message: message),
    success: 'Request for ${feature.name} sent.',
  );

  Future<bool> withdraw(AccessRequest request) =>
      act(() => _repository.withdrawRequest(request.id), success: 'Request withdrawn.');
}

class TeamCubit extends AsyncCubit<List<TeamMember>> {
  TeamCubit(this._repository, this.orgId);
  final OrganizationRepository _repository;
  final String orgId;

  @override
  Future<Result<List<TeamMember>>> fetch() => _repository.team(orgId);

  Future<bool> setMember(String handle, String role) =>
      act(() => _repository.setTeamMember(orgId, handle: handle, role: role), success: 'Team updated.');

  Future<bool> remove(TeamMember member) =>
      act(() => _repository.removeTeamMember(orgId, member.userId), success: '${member.displayName} removed.');
}
