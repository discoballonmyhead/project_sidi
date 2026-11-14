import '../../discover/domain/discover.dart';

/// Header of the manage section: the organisation, what the caller may do in
/// it, which features it holds and the numbers for the dashboard tiles.
class OrgOverview {
  const OrgOverview({required this.org, required this.myRole, required this.features, required this.stats});

  final Org org;
  final String myRole;
  final List<String> features;
  final Map<String, double> stats;

  bool get canManage => myRole == 'owner' || myRole == 'manager';
  bool get canCoach => canManage || myRole == 'coach';
  bool get canDesk => canManage || myRole == 'staff';
  bool get isApproved => org.status == 'approved';
  bool has(String feature) => features.contains(feature);
  int stat(String key) => (stats[key] ?? 0).round();
  double amount(String key) => stats[key] ?? 0;
}

class FeatureState {
  const FeatureState({
    required this.key,
    required this.name,
    required this.description,
    required this.autoGrant,
    required this.requiresVerified,
    required this.enabled,
    required this.pending,
  });

  final String key;
  final String name;
  final String description;
  final bool autoGrant;
  final bool requiresVerified;
  final bool enabled;
  final bool pending;
}

/// A request waiting for (or decided by) platform staff.
class AccessRequest {
  const AccessRequest({
    required this.id,
    required this.kind,
    required this.status,
    this.message,
    this.documents = const [],
    this.featureKey,
    this.featureName,
    required this.createdAt,
    this.decidedAt,
    this.decisionNote,
    required this.orgId,
    required this.orgName,
    required this.orgStatus,
    required this.orgIsVerified,
    this.orgCity,
    this.orgSports = const [],
    required this.requesterName,
    this.decidedByName,
  });

  final String id;

  /// `org_approval`, `org_verification` or `feature_access`.
  final String kind;
  final String status;
  final String? message;
  final List<String> documents;
  final String? featureKey;
  final String? featureName;
  final DateTime createdAt;
  final DateTime? decidedAt;
  final String? decisionNote;
  final String orgId;
  final String orgName;
  final String orgStatus;
  final bool orgIsVerified;
  final String? orgCity;
  final List<String> orgSports;
  final String requesterName;
  final String? decidedByName;

  String get title => switch (kind) {
    'org_approval' => 'New organisation',
    'org_verification' => 'Verification',
    _ => 'Feature: ${featureName ?? featureKey ?? ''}',
  };
}

class OrgAccess {
  const OrgAccess({required this.status, required this.isVerified, required this.features, required this.requests});
  final String status;
  final bool isVerified;
  final List<FeatureState> features;
  final List<AccessRequest> requests;

  bool get verificationPending => requests.any((r) => r.kind == 'org_verification' && r.status == 'pending');
}

class TeamMember {
  const TeamMember({required this.userId, required this.role, required this.displayName, this.username});
  final String userId;
  final String role;
  final String displayName;
  final String? username;
}
