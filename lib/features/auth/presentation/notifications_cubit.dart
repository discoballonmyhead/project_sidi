import '../../../core/bloc/async_cubit.dart';
import '../../../core/error/result.dart';
import '../domain/auth_repository.dart';
import '../domain/session.dart';

class NotificationsCubit extends AsyncCubit<List<AppNotification>> {
  NotificationsCubit(this._auth);
  final AuthRepository _auth;

  @override
  Future<Result<List<AppNotification>>> fetch() => _auth.notifications();

  Future<void> markAllRead() => act(_auth.markNotificationsRead);
}
