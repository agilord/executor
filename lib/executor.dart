// Copyright (c) 2016, Agilord. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

/// Executes async tasks with a configurable maximum concurrency and rate.

library executor;

import 'dart:async';
import 'dart:collection';

import 'package:stack_trace/stack_trace.dart';

part './src/executor_impl.dart';

/// An async task that completes with a Future or a value.
typedef AsyncTask<R> = FutureOr<R> Function();

/// An async task that completes after the Stream is closed.
typedef StreamTask<R> = Stream<R> Function();

/// No more than [maximum] tasks can be started over any given [period].
class Rate {
  /// The maximum number of tasks to start in any given [period].
  final int maximum;

  /// The period of the [Rate], in which [maximum] tasks can be started.
  final Duration period;

  /// Creates a rate limit.
  const Rate(this.maximum, this.period);

  /// Creates a rate limit per second.
  factory Rate.perSecond(int maximum) => Rate(maximum, Duration(seconds: 1));

  /// Creates a rate limit per minute.
  factory Rate.perMinute(int maximum) => Rate(maximum, Duration(minutes: 1));

  /// Creates a rate limit per hour.
  factory Rate.perHour(int maximum) => Rate(maximum, Duration(hours: 1));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Rate &&
          runtimeType == other.runtimeType &&
          maximum == other.maximum &&
          period == other.period;

  @override
  int get hashCode => maximum.hashCode ^ period.hashCode;
}

/// Executes async tasks with a configurable maximum [concurrency] and [rate].
abstract class Executor {
  /// The maximum number of tasks running concurrently.
  int concurrency;

  /// The maximum rate of how frequently tasks can be started.
  Rate rate;

  /// Async task executor.
  factory Executor({
    int concurrency = 1,
    Rate rate,
  }) =>
      _Executor(concurrency, rate);

  /// The number of tasks that are currently running.
  int get runningCount;

  /// The number of tasks that are currently waiting to be started.
  int get waitingCount;

  /// The total number of tasks scheduled ([runningCount] + [waitingCount]).
  int get scheduledCount;

  /// Schedules an async task and returns with a future that completes when the
  /// task is finished. Task may not get executed immediately.
  Future<R> scheduleTask<R>(AsyncTask<R> task);

  /// Schedules an async task and returns its stream. The task is considered
  /// running until the stream is closed.
  Stream<R> scheduleStream<R>(StreamTask<R> task);

  /// Returns a [Future] that completes when all currently running tasks
  /// complete.
  ///
  /// If [withWaiting] is set, it will include the waiting tasks too.
  Future join({bool withWaiting = false});

  /// Notifies the listeners about a state change in [Executor], for example:
  /// - one or more tasks have started
  /// - one or more tasks have completed
  ///
  /// Clients can use this to monitor [scheduledCount] and queue more tasks to
  /// ensure [Executor] is running on full capacity.
  Stream get onChange;

  /// Closes the executor and reject  tasks.
  Future close();
}
