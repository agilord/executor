import 'dart:async';

import 'package:test/test.dart';

import 'package:executor/executor.dart';

void main() {
  group('AsyncTask', () {
    test('does not run after closing', () async {
      final executor = Executor();
      final Future<int> resultFuture =
          executor.scheduleTask(() => Future.microtask(() => 12));
      expect(resultFuture, completion(12));

      await executor.close();
      expect(() => executor.scheduleTask(() => 0), throwsException);
    });

    test('concurrency limit', () async {
      final executor = Executor(concurrency: 2);
      final Completer first = Completer();
      final Completer second = Completer();
      final Completer third = Completer();

      expect(executor.runningCount, 0);
      expect(executor.waitingCount, 0);
      expect(executor.scheduledCount, 0);

      // ignore: unawaited_futures
      executor.scheduleTask(() => first.future);
      // ignore: unawaited_futures
      executor.scheduleTask(() => second.future);
      // ignore: unawaited_futures
      executor.scheduleTask(() => third.future);

      expect(executor.runningCount, 0);
      expect(executor.waitingCount, 3);
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

    test('Exceptions do not block further execution.', () async {
      final executor = Executor(concurrency: 2);
      for (int i = 0; i < 10; i++) {
        // ignore: unawaited_futures
        executor.scheduleTask(() async {
          await Future.delayed(Duration(microseconds: i * 10));
          await Future.microtask(() => throw Exception());
        });
      }
      await executor.join(withWaiting: true);
      await executor.close();
    });
  });

  group('StreamTask', () {
    test('completes only after the stream closes', () async {
      final executor = Executor();
      final StreamController controller = StreamController();
      final Stream resultStream =
          executor.scheduleStream(() => controller.stream);
      final Future<List> resultList = resultStream.toList();

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
