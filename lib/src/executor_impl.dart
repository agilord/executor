part of executor;

class _Executor implements Executor {
  int _concurrency;
  Rate _rate;
  final ListQueue<_Item> _waiting = new ListQueue<_Item>();
  final ListQueue<_Item> _running = new ListQueue<_Item>();
  final ListQueue<DateTime> _started = new ListQueue<DateTime>();
  final StreamController _onChangeController = new StreamController.broadcast();
  Timer _changeTimer;
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
  Future<R> scheduleTask<R>(AsyncTask<R> task) {
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
  Stream get onChange => _onChangeController.stream;

  @override
  Future close() {
    if (!isClosing) {
      _closeCompleter = new Completer();
    }
    _triggerCheck();
    _onChangeController.close();
    return _closeCompleter.future;
  }

  void _triggerCheck({Duration sleep, bool force: false}) {
    if (force && _checkTimer != null) {
      _checkTimer.cancel();
      _checkTimer = null;
    }
    if (_checkTimer != null) return;
    _checkTimer = new Timer(sleep ?? core.Duration.zero, () {
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
        if (_started.length >= _rate.maximum) {
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
        _notifyChange();
        _triggerCheck();
      });
      try {
        item.completer.complete(item.task());
      } catch (e, st) {
        item.completer.completeError(e, st);
      }
      _notifyChange();
    }
  }

  void _notifyChange() {
    if (_changeTimer != null) return;
    _changeTimer = new Timer(core.Duration.zero, () {
      _changeTimer = null;
      if (isClosing) return;
      if (!_onChangeController.isClosed) {
        _onChangeController.add(null);
      }
    });
  }
}

class _Item<R> {
  final AsyncTask<R> task;
  final Completer<R> completer = new Completer<R>();
  _Item(this.task);
}
