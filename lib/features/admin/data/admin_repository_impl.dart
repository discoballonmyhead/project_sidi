import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import '../../../core/utils/json.dart';
import '../../organization/data/organization_repository_impl.dart';
import '../../organization/domain/organization.dart';
import '../domain/admin.dart';
import '../domain/admin_repository.dart';

class AdminRepositoryImpl implements AdminRepository {
  AdminRepositoryImpl(this._rpc);
  final Rpc _rpc;

  @override
  Future<Result<AdminOverview>> overview() => _rpc.call(
    'admin_overview',
    parse: (json) {
      final map = asJson(json);
      final pending = map.obj('pending');
      final orgs = map.obj('organizations');
      return AdminOverview(
        role: map.str('role'),
        pendingApprovals: pending.integer('org_approval'),
        pendingVerifications: pending.integer('org_verification'),
        pendingFeatures: pending.integer('feature_access'),
        openReports: map.integer('open_reports'),
        orgTotal: orgs.integer('total'),
        orgApproved: orgs.integer('approved'),
        orgSuspended: orgs.integer('suspended'),
        orgVerified: orgs.integer('verified'),
        users: map.integer('users'),
        tournamentsLive: map.integer('tournaments_live'),
        bookings7d: map.integer('bookings_7d'),
      );
    },
  );

  @override
  Future<Result<List<AccessRequest>>> requests({String? status = 'pending', String? kind}) => _rpc.call(
    'admin_requests',
    params: {'p_status': status, 'p_kind': kind},
    parse: (json) => parseList(json, accessRequestFromJson),
  );

  @override
  Future<Result<void>> decideRequest(String requestId, {required bool approve, String? note}) => _rpc.run(
    'admin_request_decide',
    params: {'p_request_id': requestId, 'p_approve': approve, 'p_note': note},
  );

  @override
  Future<Result<List<AdminOrg>>> orgs({String? query, String? status}) => _rpc.call(
    'admin_orgs',
    params: {'p_query': query, 'p_status': status},
    parse: (json) => parseList(
      json,
      (o) => AdminOrg(
        id: o.str('id'),
        name: o.str('name'),
        status: o.str('status'),
        isVerified: o.flag('is_verified'),
        city: o.strOrNull('city'),
        sports: o.strings('sports'),
        ownerName: o.str('owner_name'),
        contactEmail: o.strOrNull('contact_email'),
        features: o.strings('features'),
        openReports: o.integer('open_reports'),
        createdAt: o.date('created_at'),
      ),
    ),
  );

  @override
  Future<Result<void>> moderateOrg(String orgId, String action, {String? note}) =>
      _rpc.run('admin_org_moderate', params: {'p_org_id': orgId, 'p_action': action, 'p_note': note});

  @override
  Future<Result<void>> setOrgFeature(String orgId, String featureKey, {required bool enabled}) => _rpc.run(
    'admin_org_set_feature',
    params: {'p_org_id': orgId, 'p_feature_key': featureKey, 'p_enabled': enabled},
  );

  @override
  Future<Result<List<ContentReport>>> reports({String? status = 'open'}) => _rpc.call(
    'admin_reports',
    params: {'p_status': status},
    parse: (json) => parseList(
      json,
      (r) => ContentReport(
        id: r.str('id'),
        targetType: r.str('target_type'),
        targetId: r.str('target_id'),
        targetName: r.strOrNull('target_name'),
        reason: r.str('reason'),
        status: r.str('status'),
        resolution: r.strOrNull('resolution'),
        reporterName: r.str('reporter_name'),
        createdAt: r.date('created_at'),
      ),
    ),
  );

  @override
  Future<Result<void>> resolveReport(String reportId, {required String status, String? resolution}) => _rpc.run(
    'admin_report_resolve',
    params: {'p_report_id': reportId, 'p_status': status, 'p_resolution': resolution},
  );

  @override
  Future<Result<void>> cancelTournament(String tournamentId, String note) =>
      _rpc.run('admin_tournament_cancel', params: {'p_tournament_id': tournamentId, 'p_note': note});

  @override
  Future<Result<List<AdminUser>>> users({String? query}) => _rpc.call(
    'admin_users',
    params: {'p_query': query},
    parse: (json) => parseList(
      json,
      (u) => AdminUser(
        id: u.str('id'),
        displayName: u.str('display_name'),
        username: u.strOrNull('username'),
        email: u.strOrNull('email'),
        platformRole: u.strOrNull('platform_role'),
        orgCount: u.integer('org_count'),
      ),
    ),
  );

  @override
  Future<Result<void>> setRole(String userId, String? role) =>
      _rpc.run('admin_set_role', params: {'p_user_id': userId, 'p_role': role});

  @override
  Future<Result<List<AuditEntry>>> audit() => _rpc.call(
    'admin_audit',
    parse: (json) => parseList(
      json,
      (a) => AuditEntry(
        action: a.str('action'),
        entity: a.str('entity'),
        actorName: a.strOrNull('actor_name'),
        data: a.obj('data'),
        createdAt: a.date('created_at'),
      ),
    ),
  );
}
