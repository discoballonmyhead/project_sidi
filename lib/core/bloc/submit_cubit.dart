import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../error/failure.dart';
import '../error/result.dart';

enum SubmitStatus { idle, busy, done, failed }

class SubmitState<T> extends Equatable {
  const SubmitState({this.status = SubmitStatus.idle, this.value, this.failure});

  final SubmitStatus status;
  final T? value;
  final Failure? failure;

  bool get isBusy => status == SubmitStatus.busy;

  @override
  List<Object?> get props => [status, value, failure];
}

/// Drives a one-shot form submission: sign in, create an organisation, ...
class SubmitCubit<T> extends Cubit<SubmitState<T>> {
  SubmitCubit() : super(SubmitState<T>());

  Future<void> submit(Future<Result<T>> Function() action) async {
    if (state.isBusy) return;
    emit(SubmitState<T>(status: SubmitStatus.busy));
    final result = await action();
    if (isClosed) return;
    emit(
      result.fold(
        (value) => SubmitState<T>(status: SubmitStatus.done, value: value),
        (failure) => SubmitState<T>(status: SubmitStatus.failed, failure: failure),
      ),
    );
  }
}
