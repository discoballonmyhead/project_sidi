import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import '../../../core/utils/json.dart';
import '../../discover/data/discover_repository_impl.dart';
import '../domain/organization.dart';
import '../domain/organization_repository.dart';

AccessRequest accessRequestFromJson(Json r) => AccessRequest(
  id: r.str('id'),
  kind: r.str('kind'),
  status: r.str('status'),
  message: r.strOrNull('message'),
  documents: r.strings('documents'),
  featureKey: r.strOrNull('feature_key'),
  featureName: r.strOrNull('feature_name'),
  createdAt: r.date('created_at'),
  decidedAt: r.dateOrNull('decided_at'),
  decisionNote: r.strOrNull('decision_note'),
  orgId: r.str('org_id'),
  orgName: r.str('org_name'),
  orgStatus: r.str('org_status'),
  orgIsVerified: r.flag('org_is_verified'),
  orgCity: r.strOrNull('org_city'),
  orgSports: r.strings('org_sports'),
  requesterName: r.str('requester_name'),
  decidedByName: r.strOrNull('decided_by_name'),
);

class OrganizationRepositoryImpl implements OrganizationRepository {
  OrganizationRepositoryImpl(this._rpc);
  final Rpc _rpc;

  @override
  Future<Result<String>> create(Json org) =>
      _rpc.call('org_create', params: {'p_org': org}, parse: (json) => asJson(json).str('id'));

  @override
  Future<Result<void>> update(String orgId, Json patch) =>
      _rpc.run('org_update', params: {'p_org_id': orgId, 'p_patch': patch});

  @override
  Future<Result<OrgOverview>> overview(String orgId) => _rpc.call(
    'org_overview',
    params: {'p_org_id': orgId},
    parse: (json) {
      final map = asJson(json);
      return OrgOverview(
        org: orgFromJson(map.obj('organization')),
        myRole: map.str('my_role'),
        features: map.strings('features'),
        stats: {
          for (final entry in map.obj('stats').entries)
            if (entry.value is num) entry.key: (entry.value as num).toDouble(),
        },
      );
    },
  );

  @override
  Future<Result<OrgAccess>> access(String orgId) => _rpc.call(
    'org_access',
    params: {'p_org_id': orgId},
    parse: (json) {
      final map = asJson(json);
      return OrgAccess(
        status: map.str('status'),
        isVerified: map.flag('is_verified'),
        features: map.list(
          'features',
          (f) => FeatureState(
            key: f.str('key'),
            name: f.str('name'),
            description: f.str('description'),
            autoGrant: f.flag('auto_grant'),
            requiresVerified: f.flag('requires_verified'),
            enabled: f.flag('enabled'),
            pending: f.flag('pending'),
          ),
        ),
        requests: map.list('requests', accessRequestFromJson),
      );
    },
  );

  @override
  Future<Result<void>> requestVerification(String orgId, {required String message, List<String> documents = const []}) =>
      _rpc.run(
        'org_request_verification',
        params: {'p_org_id': orgId, 'p_message': message, 'p_documents': documents},
      );

  @override
  Future<Result<void>> requestFeature(String orgId, String featureKey, {String? message}) => _rpc.run(
    'org_request_feature',
    params: {'p_org_id': orgId, 'p_feature_key': featureKey, 'p_message': message},
  );

  @override
  Future<Result<void>> withdrawRequest(String requestId) =>
      _rpc.run('org_request_withdraw', params: {'p_request_id': requestId});

  @override
  Future<Result<List<TeamMember>>> team(String orgId) => _rpc.call(
    'org_team',
    params: {'p_org_id': orgId},
    parse: (json) => parseList(
      json,
      (m) => TeamMember(
        userId: m.str('user_id'),
        role: m.str('role'),
        displayName: m.str('display_name'),
        username: m.strOrNull('username'),
      ),
    ),
  );

  @override
  Future<Result<void>> setTeamMember(String orgId, {required String handle, required String role}) =>
      _rpc.run('org_team_set', params: {'p_org_id': orgId, 'p_handle': handle, 'p_role': role});

  @override
  Future<Result<void>> removeTeamMember(String orgId, String userId) =>
      _rpc.run('org_team_remove', params: {'p_org_id': orgId, 'p_user_id': userId});
}
