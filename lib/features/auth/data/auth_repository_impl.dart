import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import '../../../core/utils/json.dart';
import '../domain/auth_repository.dart';
import '../domain/session.dart';

Me meFromJson(dynamic json) {
  final map = asJson(json);
  final profile = map.obj('profile');
  return Me(
    profile: Profile(
      id: profile.str('id'),
      displayName: profile.str('display_name', 'Player'),
      username: profile.strOrNull('username'),
      avatarUrl: profile.strOrNull('avatar_url'),
      phone: profile.strOrNull('phone'),
      city: profile.strOrNull('city'),
      bio: profile.strOrNull('bio'),
    ),
    email: map.strOrNull('email'),
    platformRole: map.strOrNull('platform_role'),
    organizations: map.list(
      'organizations',
      (o) => MyOrg(
        id: o.str('id'),
        name: o.str('name'),
        role: o.str('role'),
        status: o.str('status'),
        isVerified: o.flag('is_verified'),
        currency: o.str('currency', 'INR'),
        features: o.strings('features'),
      ),
    ),
    unreadNotifications: map.integer('unread_notifications'),
  );
}

class AuthRepositoryImpl implements AuthRepository {
  AuthRepositoryImpl(this._client, this._rpc);

  final SupabaseClient _client;
  final Rpc _rpc;

  @override
  Stream<bool> get signedInChanges => _client.auth.onAuthStateChange.map((state) => state.session != null).distinct();

  @override
  bool get isSignedIn => _client.auth.currentSession != null;

  @override
  Future<Result<void>> signIn({required String email, required String password}) async {
    try {
      await _client.auth.signInWithPassword(email: email.trim(), password: password);
      return const Ok(null);
    } catch (error) {
      return Err(SupabaseRpc.mapError(error));
    }
  }

  @override
  Future<Result<bool>> signUp({required String email, required String password, required String displayName}) async {
    try {
      final response = await _client.auth.signUp(
        email: email.trim(),
        password: password,
        data: {'display_name': displayName.trim()},
      );
      return Ok(response.session == null);
    } catch (error) {
      return Err(SupabaseRpc.mapError(error));
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Signing out locally is enough; the session is gone either way.
    }
  }

  @override
  Future<Result<Me>> me() => _rpc.call('me', parse: meFromJson);

  @override
  Future<Result<Me>> updateProfile(Json patch) => _rpc.call('profile_update', params: {'p_patch': patch}, parse: meFromJson);

  @override
  Future<Result<List<AppNotification>>> notifications() => _rpc.call(
    'notifications_list',
    parse: (json) => parseList(
      json,
      (n) => AppNotification(
        id: n.str('id'),
        kind: n.str('kind'),
        title: n.str('title'),
        body: n.strOrNull('body'),
        createdAt: n.date('created_at'),
        readAt: n.dateOrNull('read_at'),
      ),
    ),
  );

  @override
  Future<Result<void>> markNotificationsRead() => _rpc.run('notifications_mark_read');
}
