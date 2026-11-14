import '../../../core/error/result.dart';
import '../../../core/network/rpc.dart';
import 'session.dart';

abstract interface class AuthRepository {
  /// Emits whenever the user signs in or out.
  Stream<bool> get signedInChanges;
  bool get isSignedIn;

  Future<Result<void>> signIn({required String email, required String password});

  /// Returns true when the account still needs e-mail confirmation.
  Future<Result<bool>> signUp({required String email, required String password, required String displayName});
  Future<void> signOut();

  Future<Result<Me>> me();
  Future<Result<Me>> updateProfile(Json patch);
  Future<Result<List<AppNotification>>> notifications();
  Future<Result<void>> markNotificationsRead();
}
