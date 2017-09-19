import 'dart:async';

import 'package:test/test.dart';

import 'package:executor/executor.dart';

void main() {
  group('AsyncTask', () {

    test('does not run after closing', () async {
      final executor = new Executor();
      final Future<int> resultFuture =
          executor.scheduleTask(() => new Future.microtask(() => 12));
      expect(resultFuture, completion(12));

      await executor.close();
      expect(() => executor.scheduleTask(() => 0), throwsException);
    });

    test('concurrency limit', () async {
      final executor = new Executor(concurrency: 2);
      final Completer first = new Completer();
      final Completer second = new Completer();
      final Completer third = new Completer();

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

      await new Future.delayed(new Duration(milliseconds: 100));
      expect(executor.runningCount, 2);
      expect(executor.waitingCount, 1);
      expect(executor.scheduledCount, 3);

      first.complete();
      await new Future.delayed(new Duration(milliseconds: 100));
      expect(executor.runningCount, 2);
      expect(executor.waitingCount, 0);
      expect(executor.scheduledCount, 2);

      second.complete();
      await new Future.delayed(new Duration(milliseconds: 100));
      expect(executor.runningCount, 1);
      expect(executor.waitingCount, 0);
      expect(executor.scheduledCount, 1);

      third.complete();
      await new Future.delayed(new Duration(milliseconds: 100));
      expect(executor.runningCount, 0);
      expect(executor.waitingCount, 0);
      expect(executor.scheduledCount, 0);
    });
  });

  group('StreamTask', () {
    test('completes only after the stream closes', () async {
      final executor = new Executor();
      final StreamController controller = new StreamController();
      final Stream resultStream = executor.scheduleStream(() => controller.stream);
      final Future<List> resultList = resultStream.toList();

      await new Future.delayed(new Duration(milliseconds: 100));
      expect(executor.runningCount, 1);

      controller.add(1);
      await new Future.delayed(new Duration(milliseconds: 100));
      expect(executor.runningCount, 1);

      controller.add(2);
      await new Future.delayed(new Duration(milliseconds: 100));
      expect(executor.runningCount, 1);

      await controller.close();
      await new Future.delayed(new Duration(milliseconds: 100));
      expect(executor.runningCount, 0);

      expect(resultList, completion([1,2]));
    });
  });
}
