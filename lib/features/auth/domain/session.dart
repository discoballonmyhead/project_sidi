class Profile {
  const Profile({required this.id, required this.displayName, this.username, this.avatarUrl, this.phone, this.city, this.bio});

  final String id;
  final String displayName;
  final String? username;
  final String? avatarUrl;
  final String? phone;
  final String? city;
  final String? bio;
}

/// An organisation the signed-in user helps run.
class MyOrg {
  const MyOrg({
    required this.id,
    required this.name,
    required this.role,
    required this.status,
    required this.isVerified,
    required this.currency,
    required this.features,
  });

  final String id;
  final String name;
  final String role;
  final String status;
  final bool isVerified;
  final String currency;
  final List<String> features;

  bool get canManage => role == 'owner' || role == 'manager';
  bool has(String feature) => features.contains(feature);
}

/// The signed-in user: profile, platform role and the organisations they run.
class Me {
  const Me({required this.profile, this.email, this.platformRole, this.organizations = const [], this.unreadNotifications = 0});

  final Profile profile;
  final String? email;
  final String? platformRole;
  final List<MyOrg> organizations;
  final int unreadNotifications;

  bool get isStaff => platformRole != null;
  bool get isAdmin => platformRole == 'admin';
}

class AppNotification {
  const AppNotification({required this.id, required this.kind, required this.title, this.body, required this.createdAt, this.readAt});

  final String id;
  final String kind;
  final String title;
  final String? body;
  final DateTime createdAt;
  final DateTime? readAt;
}
