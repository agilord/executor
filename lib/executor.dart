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

/// Executes async tasks concurrently with a configurable parallelism [limit].
abstract class Executor {
  /// The maximum number of tasks running concurrently.
  int limit;

  /// Async task executor.
  factory Executor({int limit: 1}) => new _Executor(limit);

  /// Schedules an async task and returns with a future that completes when the
  /// task is finished. Task may not get executed immediately.
  Future<R> scheduleTask<R>(ExecutorTask<R> task);

  /// Schedules an async task and returns its stream. The task is considered
  /// running until the stream is closed.
  Stream<R> scheduleStream<R>(StreamTask<R> task);

  /// Closes the executor and reject new tasks.
  Future close();
}

class _Executor implements Executor {
  int _limit;
  final ListQueue<_Item> _waiting = new ListQueue<_Item>();
  final ListQueue<_Item> _running = new ListQueue<_Item>();
  bool _checkScheduled = false;
  Completer _closeCompleter;

  _Executor(this._limit) {
    assert(_limit > 0);
  }

  bool get isClosing => _closeCompleter != null;

  @override
  int get limit => _limit;

  @override
  set limit(int value) {
    if (_limit == value) return;
    assert(value > 0);
    _limit = value;
    _triggerCheck();
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
  Future close() {
    if (!isClosing) {
      _closeCompleter = new Completer();
    }
    return _closeCompleter.future;
  }

  void _triggerCheck() {
    if (_checkScheduled) return;
    _checkScheduled = true;
    scheduleMicrotask(() {
      _checkScheduled = false;
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
      if (_running.length >= _limit) return;
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
