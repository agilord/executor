part of executor;

class _Executor implements Executor {
  int _concurrency;
  Rate _rate;
  final ListQueue<_Item> _waiting = ListQueue<_Item>();
  final ListQueue<_Item> _running = ListQueue<_Item>();
  final ListQueue<DateTime> _started = ListQueue<DateTime>();
  final StreamController _onChangeController = StreamController.broadcast();
  bool _closing = false;
  Timer _triggerTimer;

  _Executor(this._concurrency, this._rate) {
    assert(_concurrency > 0);
  }

  @override
  int get runningCount => _running.length;

  @override
  int get waitingCount => _waiting.length;

  @override
  int get scheduledCount => runningCount + waitingCount;

  bool get isClosing => _closing;

  @override
  int get concurrency => _concurrency;

  @override
  set concurrency(int value) {
    if (_concurrency == value) return;
    assert(value > 0);
    _concurrency = value;
    _trigger();
  }

  @override
  Rate get rate => _rate;

  @override
  set rate(Rate value) {
    if (_rate == value) return;
    _rate = value;
    _trigger();
  }

  @override
  Future<R> scheduleTask<R>(AsyncTask<R> task) async {
    if (isClosing) throw Exception('Executor doesn\'t accept  tasks.');
    final item = _Item<R>();
    _waiting.add(item);
    _trigger();
    await item.trigger.future;
    if (isClosing) {
      item.result.completeError(
          TimeoutException('Executor is closing'), Trace.current(1));
    } else {
      try {
        final r = await task();
        item.result.complete(r);
      } catch (e, st) {
        final chain = Chain([Trace.from(st), Trace.current(1)]);
        item.result.completeError(e, chain);
      }
    }
    _trigger();
    item.done.complete();
    return item.result.future;
  }

  @override
  Stream<R> scheduleStream<R>(StreamTask<R> task) {
    StreamController<R> streamController;
    StreamSubscription<R> streamSubscription;
    final Completer resourceCompleter = Completer();
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
        streamController.addError(e, st as StackTrace);
      }
      complete();
    };
    streamController = StreamController<R>(
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
  Future join({bool withWaiting = false}) {
    final List<Future> futures = [];
    for (_Item item in _running) {
      futures.add(item.result.future.catchError((_) async => null));
    }
    if (withWaiting) {
      for (_Item item in _waiting) {
        futures.add(item.result.future.catchError((_) async => null));
      }
    }
    if (futures.isEmpty) return Future.value();
    return Future.wait(futures);
  }

  @override
  Stream get onChange => _onChangeController.stream;

  @override
  Future close() async {
    _closing = true;
    _trigger();
    await join(withWaiting: true);
    _triggerTimer?.cancel();
    await _onChangeController.close();
  }

  void _trigger() {
    _triggerTimer?.cancel();
    _triggerTimer = null;

    while (_running.length < _concurrency && _waiting.isNotEmpty) {
      if (_rate != null) {
        final now = DateTime.now();
        final limitStart = now.subtract(_rate.period);
        while (_started.isNotEmpty && _started.first.isBefore(limitStart)) {
          _started.removeFirst();
        }
        if (_started.isNotEmpty) {
          final gap = _rate.period ~/ _rate.maximum;
          final last = now.difference(_started.last);
          if (gap > last) {
            final diff = gap - last;
            _triggerTimer ??= Timer(diff, _trigger);
            return;
          }
        }
        _started.add(now);
      }

      final item = _waiting.removeFirst();
      _running.add(item);
      item.done.future.whenComplete(() {
        _running.remove(item);
        _trigger();
        if (!_closing &&
            _onChangeController.hasListener &&
            !_onChangeController.isClosed) {
          _onChangeController.add(null);
        }
      });
      item.trigger.complete();
    }
  }
}

class _Item<R> {
  final trigger = Completer();
  final result = Completer<R>();
  final done = Completer();
}
