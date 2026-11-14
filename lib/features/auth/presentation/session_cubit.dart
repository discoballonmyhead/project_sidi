import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/error/failure.dart';
import '../../../core/network/rpc.dart';
import '../domain/auth_repository.dart';
import '../domain/session.dart';

enum SessionStatus { unknown, signedOut, signedIn }

class SessionState extends Equatable {
  const SessionState({this.status = SessionStatus.unknown, this.me, this.failure});

  final SessionStatus status;
  final Me? me;

  /// Set when the session exists but the profile could not be loaded.
  final Failure? failure;

  @override
  List<Object?> get props => [status, me, failure];
}

/// Who is using the app. Lives for the whole app lifetime; the router
/// redirects on its status and screens read [SessionState.me] for roles.
class SessionCubit extends Cubit<SessionState> {
  SessionCubit(this._auth) : super(const SessionState()) {
    _subscription = _auth.signedInChanges.listen(_onAuthChanged);
  }

  final AuthRepository _auth;
  late final StreamSubscription<bool> _subscription;

  Future<void> start() => _onAuthChanged(_auth.isSignedIn);

  Future<void> _onAuthChanged(bool signedIn) async {
    if (!signedIn) {
      emit(const SessionState(status: SessionStatus.signedOut));
      return;
    }
    if (state.status == SessionStatus.signedIn && state.me != null) return;
    await refresh();
  }

  /// Reloads the profile, roles and organisations.
  Future<void> refresh() async {
    final result = await _auth.me();
    if (isClosed) return;
    result.fold(
      (me) => emit(SessionState(status: SessionStatus.signedIn, me: me)),
      (failure) => failure.isAuth
          ? signOut()
          : emit(SessionState(status: SessionStatus.signedIn, me: state.me, failure: failure)),
    );
  }

  Future<Failure?> updateProfile(Json patch) async {
    final result = await _auth.updateProfile(patch);
    if (isClosed) return null;
    return result.fold((me) {
      emit(SessionState(status: SessionStatus.signedIn, me: me));
      return null;
    }, (failure) => failure);
  }

  Future<void> signOut() async {
    await _auth.signOut();
    if (!isClosed) emit(const SessionState(status: SessionStatus.signedOut));
  }

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}
