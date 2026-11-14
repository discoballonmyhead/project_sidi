import 'package:equatable/equatable.dart';

import '../error/failure.dart';

enum AsyncStatus { initial, loading, success, failure }

/// A one-off message for the UI (snack bar). [id] makes two identical texts
/// distinct so the second one is still shown.
class Notice extends Equatable {
  const Notice(this.text, {this.isError = false, required this.id});

  final String text;
  final bool isError;
  final int id;

  @override
  List<Object?> get props => [id];
}

/// State of a screen that loads one thing, [data], and runs actions on it.
class AsyncState<T> extends Equatable {
  const AsyncState({
    this.status = AsyncStatus.initial,
    this.data,
    this.failure,
    this.busy = false,
    this.notice,
  });

  final AsyncStatus status;
  final T? data;

  /// Why loading failed. Kept separate from [notice]: a failed action must
  /// not wipe the content that is already on screen.
  final Failure? failure;

  /// An action (save, delete, ...) is in flight.
  final bool busy;
  final Notice? notice;

  bool get hasData => data != null;
  bool get isLoading => status == AsyncStatus.loading || status == AsyncStatus.initial;

  AsyncState<T> copyWith({
    AsyncStatus? status,
    T? data,
    Failure? failure,
    bool clearFailure = false,
    bool? busy,
    Notice? notice,
  }) => AsyncState<T>(
    status: status ?? this.status,
    data: data ?? this.data,
    failure: clearFailure ? null : failure ?? this.failure,
    busy: busy ?? this.busy,
    notice: notice ?? this.notice,
  );

  @override
  List<Object?> get props => [status, data, failure, busy, notice];
}
