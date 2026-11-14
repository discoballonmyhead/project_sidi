import 'dart:async';
import 'dart:io' show SocketException;

import 'package:supabase_flutter/supabase_flutter.dart';

import '../error/failure.dart';
import '../error/result.dart';

typedef Json = Map<String, dynamic>;

/// The app's only door to the backend: a named public RPC with JSON in and
/// JSON out. Repositories depend on this interface, so tests swap in a fake.
abstract interface class Rpc {
  /// Calls [function] and parses its JSON result.
  Future<Result<T>> call<T>(
    String function, {
    Json params = const {},
    required T Function(dynamic json) parse,
  });

  /// Calls a [function] whose result does not matter.
  Future<Result<void>> run(String function, {Json params = const {}});
}

class SupabaseRpc implements Rpc {
  SupabaseRpc(this._client);

  final SupabaseClient _client;

  @override
  Future<Result<T>> call<T>(
    String function, {
    Json params = const {},
    required T Function(dynamic json) parse,
  }) async {
    try {
      final json = await _client.rpc(function, params: params);
      return Ok(parse(json));
    } catch (error) {
      return Err(mapError(error));
    }
  }

  @override
  Future<Result<void>> run(String function, {Json params = const {}}) =>
      call<void>(function, params: params, parse: (_) {});

  /// Backend errors arrive as `PTxxx` (HTTP status xxx) with a slug in
  /// `message` and the readable text in `details`.
  static Failure mapError(Object error) {
    if (error is PostgrestException) {
      final code = error.code ?? '';
      final status = code.startsWith('PT') ? int.tryParse(code.substring(2)) : null;
      final details = error.details?.toString();
      if (status != null) {
        return Failure(error.message, (details == null || details.isEmpty) ? error.message : details, status: status);
      }
      if (code == '42501') {
        return const Failure('forbidden', 'You are not allowed to do that.', status: 403);
      }
      return Failure.unexpected(error.message);
    }
    if (error is AuthException) {
      return Failure('auth', error.message, status: int.tryParse(error.statusCode ?? ''));
    }
    if (error is SocketException || error is TimeoutException) {
      return const Failure.network();
    }
    final text = error.toString();
    if (text.contains('ClientException') || text.contains('Failed host lookup') || text.contains('XMLHttpRequest')) {
      return const Failure.network();
    }
    return const Failure.unexpected();
  }
}
