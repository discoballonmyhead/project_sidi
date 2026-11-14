import 'package:equatable/equatable.dart';

/// The one error type that crosses the data → presentation boundary.
///
/// [code] is the machine-readable slug raised by the backend
/// (`slot_taken`, `forbidden`, ...); [message] is already fit to show.
class Failure extends Equatable {
  const Failure(this.code, this.message, {this.status});

  const Failure.network()
    : code = 'network',
      message = 'Could not reach the server. Check your connection and try again.',
      status = null;

  const Failure.unexpected([String? detail])
    : code = 'unexpected',
      message = detail ?? 'Something went wrong. Please try again.',
      status = null;

  final String code;
  final String message;
  final int? status;

  bool get isAuth => status == 401 || code == 'not_authenticated';
  bool get isNotFound => status == 404;

  @override
  List<Object?> get props => [code, message, status];

  @override
  String toString() => 'Failure($code, $message)';
}
