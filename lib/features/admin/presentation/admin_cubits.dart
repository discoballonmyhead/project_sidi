import '../../../core/bloc/async_cubit.dart';
import '../../../core/error/result.dart';
import '../../organization/domain/organization.dart';
import '../domain/admin.dart';
import '../domain/admin_repository.dart';

class AdminOverviewCubit extends AsyncCubit<AdminOverview> {
  AdminOverviewCubit(this._repository);
  final AdminRepository _repository;

  @override
  Future<Result<AdminOverview>> fetch() => _repository.overview();
}

/// The review queue: organisation approvals, verification, feature access.
class AdminRequestsCubit extends AsyncCubit<List<AccessRequest>> {
  AdminRequestsCubit(this._repository);
  final AdminRepository _repository;

  /// `pending`, or null for the decided history.
  String? status = 'pending';
  String? kind;

  @override
  Future<Result<List<AccessRequest>>> fetch() async {
    final result = await _repository.requests(status: status, kind: kind);
    // "History" means everything that has been decided.
    return status == null ? result.map((all) => all.where((r) => r.status != 'pending').toList().reversed.toList()) : result;
  }

  Future<void> filter({String? Function()? status, String? Function()? kind}) {
    if (status != null) this.status = status();
    if (kind != null) this.kind = kind();
    return load();
  }

  Future<bool> decide(AccessRequest request, {required bool approve, String? note}) => act(
    () => _repository.decideRequest(request.id, approve: approve, note: note),
    success: '${request.orgName}: ${approve ? 'approved' : 'rejected'}.',
  );
}

class AdminOrgsCubit extends AsyncCubit<List<AdminOrg>> {
  AdminOrgsCubit(this._repository);
  final AdminRepository _repository;
  String query = '';
  String? status;

  @override
  Future<Result<List<AdminOrg>>> fetch() => _repository.orgs(query: query, status: status);

  Future<void> search({String? query, String? Function()? status}) {
    if (query != null) this.query = query;
    if (status != null) this.status = status();
    return load();
  }

  Future<bool> moderate(AdminOrg org, String action, {String? note}) =>
      act(() => _repository.moderateOrg(org.id, action, note: note), success: '${org.name}: $action done.');

  Future<bool> setFeature(AdminOrg org, String featureKey, {required bool enabled}) =>
      act(() => _repository.setOrgFeature(org.id, featureKey, enabled: enabled));
}

class AdminReportsCubit extends AsyncCubit<List<ContentReport>> {
  AdminReportsCubit(this._repository);
  final AdminRepository _repository;
  String? status = 'open';

  @override
  Future<Result<List<ContentReport>>> fetch() => _repository.reports(status: status);

  Future<void> filter(String? value) {
    status = value;
    return load();
  }

  Future<bool> resolve(ContentReport report, {required bool actioned, String? resolution}) => act(
    () => _repository.resolveReport(report.id, status: actioned ? 'actioned' : 'dismissed', resolution: resolution),
    success: actioned ? 'Report actioned.' : 'Report dismissed.',
  );

  /// Acts on the reported thing, then closes the report.
  Future<bool> takeDown(ContentReport report, String note) => act(() async {
    final result = report.targetType == 'tournament'
        ? await _repository.cancelTournament(report.targetId, note)
        : await _repository.moderateOrg(report.targetId, 'suspend', note: note);
    if (!result.isOk) return result;
    return _repository.resolveReport(report.id, status: 'actioned', resolution: note);
  }, success: report.targetType == 'tournament' ? 'Tournament cancelled.' : 'Organisation suspended.');
}

class AdminUsersCubit extends AsyncCubit<List<AdminUser>> {
  AdminUsersCubit(this._repository);
  final AdminRepository _repository;
  String query = '';

  @override
  Future<Result<List<AdminUser>>> fetch() => _repository.users(query: query);

  Future<void> search(String value) {
    query = value;
    return load();
  }

  Future<bool> setRole(AdminUser user, String? role) => act(
    () => _repository.setRole(user.id, role),
    success: role == null ? '${user.displayName} is no longer staff.' : '${user.displayName} is now ${role == 'admin' ? 'an admin' : 'a moderator'}.',
  );
}

class AdminAuditCubit extends AsyncCubit<List<AuditEntry>> {
  AdminAuditCubit(this._repository);
  final AdminRepository _repository;

  @override
  Future<Result<List<AuditEntry>>> fetch() => _repository.audit();
}
