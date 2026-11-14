import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sidi/core/bloc/async_cubit.dart';
import 'package:sidi/core/error/failure.dart';
import 'package:sidi/core/error/result.dart';

/// A cubit whose next fetch result is set by the test.
class _CounterCubit extends AsyncCubit<int> {
  Result<int> next = const Ok(1);
  int fetches = 0;

  @override
  Future<Result<int>> fetch() async {
    fetches++;
    return next;
  }
}

void main() {
  group('AsyncCubit.load', () {
    blocTest<_CounterCubit, AsyncState<int>>(
      'shows a spinner, then the value',
      build: _CounterCubit.new,
      act: (cubit) => cubit.load(),
      expect: () => [
        isA<AsyncState<int>>().having((s) => s.status, 'status', AsyncStatus.loading),
        isA<AsyncState<int>>().having((s) => s.data, 'data', 1).having((s) => s.status, 'status', AsyncStatus.success),
      ],
    );

    blocTest<_CounterCubit, AsyncState<int>>(
      'a first load that fails becomes a failure state',
      build: () => _CounterCubit()..next = const Err(Failure.network()),
      act: (cubit) => cubit.load(),
      skip: 1,
      expect: () => [
        isA<AsyncState<int>>()
            .having((s) => s.status, 'status', AsyncStatus.failure)
            .having((s) => s.failure?.code, 'failure', 'network')
            .having((s) => s.data, 'data', isNull),
      ],
    );

    test('a refresh that fails keeps the content and reports the problem', () async {
      final cubit = _CounterCubit();
      await cubit.load();
      cubit.next = const Err(Failure('boom', 'Server unavailable'));
      await cubit.load();

      expect(cubit.state.status, AsyncStatus.success);
      expect(cubit.state.data, 1);
      expect(cubit.state.notice?.text, 'Server unavailable');
      expect(cubit.state.notice?.isError, isTrue);
    });
  });

  group('AsyncCubit.act', () {
    test('success shows the message and reloads', () async {
      final cubit = _CounterCubit();
      await cubit.load();
      cubit.next = const Ok(2);

      final ok = await cubit.act(() async => const Ok(null), success: 'Saved.');

      expect(ok, isTrue);
      expect(cubit.fetches, 2);
      expect(cubit.state.data, 2);
      expect(cubit.state.notice?.text, 'Saved.');
      expect(cubit.state.busy, isFalse);
    });

    test('failure reports the reason and leaves the content alone', () async {
      final cubit = _CounterCubit();
      await cubit.load();

      final ok = await cubit.act(() async => const Err<void>(Failure('slot_taken', 'That time has just been taken.', status: 409)));

      expect(ok, isFalse);
      expect(cubit.fetches, 1, reason: 'nothing changed, so nothing is reloaded');
      expect(cubit.state.data, 1);
      expect(cubit.state.notice?.text, 'That time has just been taken.');
    });

    test('two identical notices are still two notices', () async {
      final cubit = _CounterCubit();
      cubit.say('Same text');
      final first = cubit.state.notice;
      cubit.say('Same text');
      expect(cubit.state.notice, isNot(equals(first)));
    });

    test('a second action is ignored while one is running', () async {
      final cubit = _CounterCubit();
      await cubit.load();
      var runs = 0;
      Future<Result<void>> slow() async {
        runs++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return const Ok(null);
      }

      final results = await Future.wait([cubit.act(slow), cubit.act(slow)]);

      expect(runs, 1);
      expect(results, [true, false]);
    });
  });
}
