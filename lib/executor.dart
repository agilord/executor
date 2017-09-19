// Copyright (c) 2016, Agilord. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

/// This is an alternative implementation of package:pool with fewer tests but
/// with streaming support. It will get deprecated in favor of `pool` once it
/// reaches feature parity.

import 'dart:async';
import 'dart:collection';

/// An async task that completes with a Future.
typedef Future<R> ExecutorTask<R>();

/// An async task that completes after the Stream is closed.
typedef Stream<R> StreamTask<R>();

/// No more than [limit] number of tasks can be started over any given [period].
class Rate {
  /// The maximum number of tasks to start in any given [period].
  final int limit;

  /// The period of the rate limit.
  final Duration period;

  /// Creates a rate limit.
  const Rate(this.limit, this.period);

  /// Creates a rate limit per second.
  factory Rate.perSecond(int limit) =>
      new Rate(limit, new Duration(seconds: 1));

  /// Creates a rate limit per minute.
  factory Rate.perMinute(int limit) =>
      new Rate(limit, new Duration(minutes: 1));

  /// Creates a rate limit per hour.
  factory Rate.perHour(int limit) => new Rate(limit, new Duration(hours: 1));

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is Rate &&
        this.limit == other.limit &&
        this.period == other.period;
  }

  @override
  int get hashCode {
    return limit.hashCode ^ period.hashCode;
  }
}

/// Executes async tasks with a configurable maximum [concurrency] and [rate].
abstract class Executor {
  /// The maximum number of tasks running concurrently.
  int concurrency;

  /// The maximum rate of how frequently tasks can be started.
  Rate rate;

  /// Async task executor.
  factory Executor({
    int concurrency: 1,
    Rate rate,
  }) =>
      new _Executor(concurrency, rate);

  /// The number of tasks that are currently running.
  int get runningCount;

  /// The number of tasks that are currently waiting to be started.
  int get waitingCount;

  /// The total number of tasks scheduled (running + waiting).
  int get scheduledCount;

  /// Schedules an async task and returns with a future that completes when the
  /// task is finished. Task may not get executed immediately.
  Future<R> scheduleTask<R>(ExecutorTask<R> task);

  /// Schedules an async task and returns its stream. The task is considered
  /// running until the stream is closed.
  Stream<R> scheduleStream<R>(StreamTask<R> task);

  /// Returns a [Future] that completes when all currently running tasks
  /// complete.
  ///
  /// If [withWaiting] is set, it will include the waiting tasks too.
  Future join({bool withWaiting: false});

  /// Closes the executor and reject new tasks.
  Future close();
}

class _Executor implements Executor {
  int _concurrency;
  Rate _rate;
  final ListQueue<_Item> _waiting = new ListQueue<_Item>();
  final ListQueue<_Item> _running = new ListQueue<_Item>();
  final ListQueue<DateTime> _started = new ListQueue<DateTime>();
  Timer _checkTimer;
  Completer _closeCompleter;

  _Executor(this._concurrency, this._rate) {
    assert(_concurrency > 0);
  }

  @override
  int get runningCount => _running.length;

  @override
  int get waitingCount => _waiting.length;

  @override
  int get scheduledCount => runningCount + waitingCount;

  bool get isClosing => _closeCompleter != null;

  @override
  int get concurrency => _concurrency;

  @override
  set concurrency(int value) {
    if (_concurrency == value) return;
    assert(value > 0);
    _concurrency = value;
    _triggerCheck();
  }

  @override
  Rate get rate => _rate;

  @override
  set rate(Rate value) {
    if (_rate == value) return;
    _rate = value;
    _triggerCheck(force: true);
  }

  @override
  Future<R> scheduleTask<R>(ExecutorTask<R> task) {
    if (isClosing) throw new Exception('Executor doesn\'t accept new tasks.');
    final _Item<R> item = new _Item(task);
    _waiting.add(item);
    item.completer.future.whenComplete(() => _triggerCheck());
    _triggerCheck();
    return item.completer.future;
  }

  @override
  Stream<R> scheduleStream<R>(StreamTask<R> task) {
    StreamController<R> streamController;
    StreamSubscription<R> streamSubscription;
    final Completer resourceCompleter = new Completer();
    final complete = () {
      if (streamSubscription != null) {
        streamSubscription.cancel();
        streamSubscription = null;
      }
      if (!resourceCompleter.isCompleted) {
        resourceCompleter.complete();
      }
      if (!streamController.isClosed) {
        streamController.close();
      }
    };
    final completeWithError = (e, st) {
      if (!streamController.isClosed) {
        streamController.addError(e, st);
      }
      complete();
    };
    streamController = new StreamController<R>(
        onCancel: complete,
        onPause: () => streamSubscription?.pause(),
        onResume: () => streamSubscription?.resume());
    scheduleTask(() {
      if (resourceCompleter.isCompleted) return null;
      try {
        final Stream<R> stream = task();
        if (stream == null) {
          complete();
          return null;
        }
        streamSubscription = stream.listen(streamController.add,
            onError: streamController.addError,
            onDone: complete,
            cancelOnError: true);
      } catch (e, st) {
        completeWithError(e, st);
      }
      return resourceCompleter.future;
    }).catchError(completeWithError);
    return streamController.stream;
  }

  @override
  Future join({bool withWaiting: false}) {
    final List<Future> futures = [];
    for (_Item item in _running) {
      futures.add(item.completer.future.whenComplete(() => null));
    }
    if (withWaiting) {
      for (_Item item in _waiting) {
        futures.add(item.completer.future.whenComplete(() => null));
      }
    }
    if (futures.isEmpty) return new Future.value();
    return Future.wait(futures);
  }

  @override
  Future close() {
    if (!isClosing) {
      _closeCompleter = new Completer();
    }
    _triggerCheck();
    return _closeCompleter.future;
  }

  void _triggerCheck({Duration sleep, bool force: false}) {
    if (force && _checkTimer != null) {
      _checkTimer.cancel();
      _checkTimer = null;
    }
    if (_checkTimer != null) return;
    _checkTimer = new Timer(sleep ?? Duration.ZERO, () {
      _checkTimer = null;
      _check();
    });
  }

  void _check() {
    for (;;) {
      if (isClosing && _waiting.isEmpty && _running.isEmpty) {
        _closeCompleter.complete();
        return;
      }
      if (_waiting.isEmpty) return;
      if (_running.length >= _concurrency) return;
      final DateTime now = new DateTime.now();
      if (_rate != null) {
        final DateTime limitStart = now.subtract(_rate.period);
        while (_started.isNotEmpty && _started.first.isBefore(limitStart)) {
          _started.removeFirst();
        }
        if (_started.length >= _rate.limit) {
          final diff = _rate.period - now.difference(_started.first);
          _triggerCheck(sleep: diff);
          return;
        }
        _started.add(now);
      }
      final _Item item = _waiting.removeFirst();
      _running.add(item);
      item.completer.future.whenComplete(() {
        _running.remove(item);
        _triggerCheck();
      });
      try {
        item.completer.complete(item.task());
      } catch (e, st) {
        item.completer.completeError(e, st);
      }
    }
  }
}

class _Item<R> {
  final ExecutorTask<R> task;
  final Completer<R> completer = new Completer<R>();
  _Item(this.task);
}
