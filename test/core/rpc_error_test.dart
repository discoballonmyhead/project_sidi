import 'package:flutter_test/flutter_test.dart';
import 'package:sidi/core/network/rpc.dart';
import 'package:sidi/core/utils/json.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('SupabaseRpc.mapError', () {
    test('backend errors keep their slug, readable text and HTTP status', () {
      final failure = SupabaseRpc.mapError(
        const PostgrestException(message: 'slot_taken', code: 'PT409', details: 'That time has just been taken.'),
      );
      expect(failure.code, 'slot_taken');
      expect(failure.message, 'That time has just been taken.');
      expect(failure.status, 409);
    });

    test('an unauthenticated call is recognised as an auth failure', () {
      final failure = SupabaseRpc.mapError(const PostgrestException(message: 'not_authenticated', code: 'PT401', details: 'Sign in to continue.'));
      expect(failure.isAuth, isTrue);
    });

    test('a privilege error from Postgres becomes a plain forbidden', () {
      final failure = SupabaseRpc.mapError(const PostgrestException(message: 'permission denied for schema app', code: '42501'));
      expect(failure.code, 'forbidden');
      expect(failure.message, isNot(contains('schema')), reason: 'internals are not shown to the user');
    });

    test('auth errors pass their message through', () {
      final failure = SupabaseRpc.mapError(const AuthException('Invalid login credentials', statusCode: '400'));
      expect(failure.message, 'Invalid login credentials');
    });

    test('anything else is a generic failure', () {
      expect(SupabaseRpc.mapError(StateError('x')).code, 'unexpected');
    });
  });

  group('JSON readers', () {
    const json = <String, dynamic>{'n': 4.5, 's': '7', 'day': '2026-11-14', 'at': '2026-11-14T10:30:00+00:00', 'list': ['a', 1]};

    test('numbers arrive as numbers or strings', () {
      expect(json.number('n'), 4.5);
      expect(json.integer('s'), 7);
      expect(json.integer('missing', 3), 3);
    });

    test('calendar dates are not shifted by the time zone', () {
      expect(json.dayOrNull('day'), DateTime(2026, 11, 14));
      expect(isoDay(DateTime(2026, 3, 5, 23, 59)), '2026-03-05');
    });

    test('timestamps are converted to local time', () {
      expect(json.date('at').toUtc(), DateTime.utc(2026, 11, 14, 10, 30));
    });

    test('lists tolerate mixed content', () {
      expect(json.strings('list'), ['a', '1']);
      expect(parseList('not a list', (item) => item), isEmpty);
    });
  });
}
