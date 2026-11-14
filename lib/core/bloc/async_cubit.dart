import 'package:flutter_bloc/flutter_bloc.dart';

import '../error/result.dart';
import 'async_state.dart';

export 'async_state.dart';

/// Base for the feature cubits: load one value, run actions against it.
///
/// Subclasses implement [fetch] and expose intent methods that call [act].
/// Keeping the load / act / notice mechanics here means every screen behaves
/// the same way: content stays visible while refreshing, a failed action
/// reports itself without replacing the content, and success reloads.
abstract class AsyncCubit<T> extends Cubit<AsyncState<T>> {
  AsyncCubit() : super(AsyncState<T>());

  int _noticeId = 0;

  /// Reads the value this cubit owns.
  Future<Result<T>> fetch();

  /// Loads (or reloads) the value. With content on screen the reload is
  /// silent: no spinner, and a failure keeps the old content.
  Future<void> load() async {
    final hadData = state.hasData;
    if (!hadData) {
      emit(state.copyWith(status: AsyncStatus.loading, clearFailure: true));
    }
    final result = await fetch();
    if (isClosed) return;
    result.fold(
      (value) => emit(AsyncState<T>(status: AsyncStatus.success, data: value, busy: state.busy, notice: state.notice)),
      (failure) => hadData
          ? emit(state.copyWith(notice: _notice(failure.message, isError: true)))
          : emit(state.copyWith(status: AsyncStatus.failure, failure: failure)),
    );
  }

  /// Runs a mutation. On success shows [success] (if given) and reloads;
  /// on failure shows the reason. Returns whether it succeeded.
  Future<bool> act(
    Future<Result<Object?>> Function() action, {
    String? success,
    bool reload = true,
  }) async {
    if (state.busy) return false;
    emit(state.copyWith(busy: true));
    final result = await action();
    if (isClosed) return false;
    final failure = result.failureOrNull;
    if (failure != null) {
      emit(state.copyWith(busy: false, notice: _notice(failure.message, isError: true)));
      return false;
    }
    emit(state.copyWith(busy: false, notice: success == null ? null : _notice(success)));
    if (reload) await load();
    return true;
  }

  void say(String text, {bool isError = false}) => emit(state.copyWith(notice: _notice(text, isError: isError)));

  Notice _notice(String text, {bool isError = false}) => Notice(text, isError: isError, id: ++_noticeId);
}
