import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import 'organization.dart';

abstract interface class OrganizationRepository {
  Future<Result<String>> create(Json org);
  Future<Result<void>> update(String orgId, Json patch);
  Future<Result<OrgOverview>> overview(String orgId);

  Future<Result<OrgAccess>> access(String orgId);
  Future<Result<void>> requestVerification(String orgId, {required String message, List<String> documents = const []});
  Future<Result<void>> requestFeature(String orgId, String featureKey, {String? message});
  Future<Result<void>> withdrawRequest(String requestId);

  Future<Result<List<TeamMember>>> team(String orgId);
  Future<Result<void>> setTeamMember(String orgId, {required String handle, required String role});
  Future<Result<void>> removeTeamMember(String orgId, String userId);
}
