import 'dart:async';

import 'package:test/test.dart';

import 'package:executor/executor.dart';

void main() {
  group('AsyncTask', () {
    test('does not run after closing', () async {
      final executor = Executor();
      final resultFuture =
          executor.scheduleTask(() => Future.microtask(() => 12));

      await Future.delayed(Duration.zero);
      await executor.close();
      expect(await resultFuture, 12);

      expect(() => executor.scheduleTask(() => 0), throwsException);
    });

    test('concurrency limit', () async {
      final executor = Executor(concurrency: 2);
      final first = Completer();
      final second = Completer();
      final third = Completer();

      expect(executor.runningCount, 0);
      expect(executor.waitingCount, 0);
      expect(executor.scheduledCount, 0);

      // ignore: unawaited_futures
      executor.scheduleTask(() => first.future);
      // ignore: unawaited_futures
      executor.scheduleTask(() => second.future);
      // ignore: unawaited_futures
      executor.scheduleTask(() => third.future);

      expect(executor.runningCount, 2);
      expect(executor.waitingCount, 1);
      expect(executor.scheduledCount, 3);

      await Future.delayed(Duration(milliseconds: 100));
      expect(executor.runningCount, 2);
      expect(executor.waitingCount, 1);
      expect(executor.scheduledCount, 3);

      first.complete();
      await Future.delayed(Duration(milliseconds: 100));
      expect(executor.runningCount, 2);
      expect(executor.waitingCount, 0);
      expect(executor.scheduledCount, 2);

      second.complete();
      await Future.delayed(Duration(milliseconds: 100));
      expect(executor.runningCount, 1);
      expect(executor.waitingCount, 0);
      expect(executor.scheduledCount, 1);

      third.complete();
      await Future.delayed(Duration(milliseconds: 100));
      expect(executor.runningCount, 0);
      expect(executor.waitingCount, 0);
      expect(executor.scheduledCount, 0);
    });

    group('Exceptions do not block further execution', () {
      Future<void> testForType<T>({required T defaultValue}) async {
        final executor = Executor(concurrency: 2);
        for (var i = 0; i < 10; i++) {
          executor.scheduleTask<T>(() async {
            await Future.delayed(Duration(microseconds: i * 10));
            await Future<Null>.microtask(() => throw Exception());

            // Some arbitrary value to match the task type
            return defaultValue;
          }) //
              // We don't want the failed tasks to leak into the dart test
              .ignore();
        }
        final taskResults = await executor.join(withWaiting: true);

        // All the tasks throw, so the output is null
        expect(taskResults.length, 10);
        expect(taskResults, everyElement(null));

        await executor.close();
      }

      test('Nullable return type', () async {
        await testForType<int?>(defaultValue: 1);
      });

      test('Non-nullable return type', () async {
        await testForType<int>(defaultValue: 1);
      });
    });

    test('Rate limiting', () async {
      final executor = Executor(concurrency: 2, rate: Rate.perSecond(3));
      final sw = Stopwatch()..start();
      final running = <int>[];
      final times = <int>[];
      for (var i = 0; i < 10; i++) {
        // ignore: unawaited_futures
        executor.scheduleTask(() async {
          running.add(executor.runningCount);
          times.add(sw.elapsedMilliseconds);
          await Future.delayed(Duration(seconds: 1));
        });
      }
      await executor.join(withWaiting: true);
      expect(running, [1, 2, 2, 2, 2, 2, 2, 2, 2, 2]);
      for (var i = 0; i < 10; i += 2) {
        expect(times[i + 1] - times[i], greaterThan(320));
        expect(times[i + 1] - times[i], lessThan(360));
      }
      for (var i = 0; i < 8; i += 2) {
        expect(times[i + 2] - times[i], greaterThan(950));
        expect(times[i + 2] - times[i], lessThan(1050));
      }
    });
  });

  group('StreamTask', () {
    test('completes only after the stream closes', () async {
      final executor = Executor();
      final controller = StreamController();
      final resultStream = executor.scheduleStream(() => controller.stream);
      final resultList = resultStream.toList();

      await Future.delayed(Duration(milliseconds: 100));
      expect(executor.runningCount, 1);

      controller.add(1);
      await Future.delayed(Duration(milliseconds: 100));
      expect(executor.runningCount, 1);

      controller.add(2);
      await Future.delayed(Duration(milliseconds: 100));
      expect(executor.runningCount, 1);

      await controller.close();
      await Future.delayed(Duration(milliseconds: 100));
      expect(executor.runningCount, 0);

      expect(resultList, completion([1, 2]));
    });
  });
}
