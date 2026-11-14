import '../../../core/network/rpc.dart';

class AdminOverview {
  const AdminOverview({
    required this.role,
    required this.pendingApprovals,
    required this.pendingVerifications,
    required this.pendingFeatures,
    required this.openReports,
    required this.orgTotal,
    required this.orgApproved,
    required this.orgSuspended,
    required this.orgVerified,
    required this.users,
    required this.tournamentsLive,
    required this.bookings7d,
  });

  final String role;
  final int pendingApprovals;
  final int pendingVerifications;
  final int pendingFeatures;
  final int openReports;
  final int orgTotal;
  final int orgApproved;
  final int orgSuspended;
  final int orgVerified;
  final int users;
  final int tournamentsLive;
  final int bookings7d;

  int get pendingTotal => pendingApprovals + pendingVerifications + pendingFeatures;
  bool get isAdmin => role == 'admin';
}

class AdminOrg {
  const AdminOrg({
    required this.id,
    required this.name,
    required this.status,
    required this.isVerified,
    this.city,
    required this.sports,
    required this.ownerName,
    this.contactEmail,
    required this.features,
    required this.openReports,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String status;
  final bool isVerified;
  final String? city;
  final List<String> sports;
  final String ownerName;
  final String? contactEmail;
  final List<String> features;
  final int openReports;
  final DateTime createdAt;
}

class ContentReport {
  const ContentReport({
    required this.id,
    required this.targetType,
    required this.targetId,
    this.targetName,
    required this.reason,
    required this.status,
    this.resolution,
    required this.reporterName,
    required this.createdAt,
  });

  final String id;
  final String targetType;
  final String targetId;
  final String? targetName;
  final String reason;
  final String status;
  final String? resolution;
  final String reporterName;
  final DateTime createdAt;
}

class AdminUser {
  const AdminUser({required this.id, required this.displayName, this.username, this.email, this.platformRole, required this.orgCount});
  final String id;
  final String displayName;
  final String? username;
  final String? email;
  final String? platformRole;
  final int orgCount;
}

class AuditEntry {
  const AuditEntry({required this.action, required this.entity, this.actorName, required this.data, required this.createdAt});
  final String action;
  final String entity;
  final String? actorName;
  final Json data;
  final DateTime createdAt;
}
