import '../../../core/error/result.dart';
import '../../organization/domain/organization.dart';
import 'admin.dart';

abstract interface class AdminRepository {
  Future<Result<AdminOverview>> overview();
  Future<Result<List<AccessRequest>>> requests({String? status = 'pending', String? kind});
  Future<Result<void>> decideRequest(String requestId, {required bool approve, String? note});

  Future<Result<List<AdminOrg>>> orgs({String? query, String? status});

  /// [action] is `suspend`, `reinstate`, `verify` or `unverify`.
  Future<Result<void>> moderateOrg(String orgId, String action, {String? note});
  Future<Result<void>> setOrgFeature(String orgId, String featureKey, {required bool enabled});

  Future<Result<List<ContentReport>>> reports({String? status = 'open'});
  Future<Result<void>> resolveReport(String reportId, {required String status, String? resolution});
  Future<Result<void>> cancelTournament(String tournamentId, String note);

  Future<Result<List<AdminUser>>> users({String? query});
  Future<Result<void>> setRole(String userId, String? role);
  Future<Result<List<AuditEntry>>> audit();
}
