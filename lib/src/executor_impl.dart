part of executor;

class _Executor implements Executor {
  int _concurrency;
  Rate _rate;
  final ListQueue<_Item> _waiting = new ListQueue<_Item>();
  final ListQueue<_Item> _running = new ListQueue<_Item>();
  final ListQueue<DateTime> _started = new ListQueue<DateTime>();
  final StreamController _onChangeController = new StreamController.broadcast();
  Future _runFuture;
  bool _closing = false;
  Completer _notifyCompleter;
  Timer _notifyTimer;

  _Executor(this._concurrency, this._rate) {
    assert(_concurrency > 0);
    _runFuture = _run();
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
    _doNotify();
  }

  @override
  Rate get rate => _rate;

  @override
  set rate(Rate value) {
    if (_rate == value) return;
    _rate = value;
    _doNotify();
  }

  @override
  Future<R> scheduleTask<R>(AsyncTask<R> task) async {
    if (isClosing) throw new Exception('Executor doesn\'t accept new tasks.');
    final item = new _Item();
    _waiting.add(item);
    _doNotify();
    await item.trigger.future;
    final completer = Completer<R>();
    try {
      final r = await task();
      completer.complete(r);
    } catch (e, st) {
      final chain = new Chain([new Trace.from(st), new Trace.current(1)]);
      completer.completeError(e, chain);
    }
    item.finalizer.complete();
    _doNotify();
    return completer.future;
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
      futures.add(item.finalizer.future.whenComplete(() => null));
    }
    if (withWaiting) {
      for (_Item item in _waiting) {
        futures.add(item.finalizer.future.whenComplete(() => null));
      }
    }
    if (futures.isEmpty) return new Future.value();
    return Future.wait(futures);
  }

  @override
  Stream get onChange => _onChangeController.stream;

  @override
  Future close() async {
    _closing = true;
    _doNotify();
    await _runFuture;
    await _onChangeController.close();
  }

  Future _run() async {
    for (;;) {
      if (isClosing && _waiting.isEmpty && _running.isEmpty) {
        return;
      }
      if (_waiting.isEmpty || _running.length >= _concurrency) {
        await _waitForNotify();
        continue;
      }
      if (_rate != null) {
        final DateTime now = new DateTime.now();
        final DateTime limitStart = now.subtract(_rate.period);
        while (_started.isNotEmpty && _started.first.isBefore(limitStart)) {
          _started.removeFirst();
        }
        if (_started.isNotEmpty) {
          final gap = _rate.period ~/ _rate.maximum;
          final last = now.difference(_started.last);
          if (gap > last) {
            final diff = gap - last;
            _notifyTimer ??= new Timer(diff, _doNotify);
            await _waitForNotify();
            continue;
          }
        }
        _started.add(now);
      }
      final _Item item = _waiting.removeFirst();
      _running.add(item);
      // ignore: unawaited_futures
      item.finalizer.future.whenComplete(() {
        _running.remove(item);
        _doNotify();
        if (!_closing &&
            _onChangeController.hasListener &&
            !_onChangeController.isClosed) {
          _onChangeController.add(null);
        }
      });
      item.trigger.complete();
      _doNotify();
    }
  }

  void _doNotify() {
    _notifyCompleter?.complete();
    _notifyCompleter = null;
    _notifyTimer?.cancel();
    _notifyTimer = null;
  }

  Future _waitForNotify() async {
    _notifyCompleter = new Completer();
    await _notifyCompleter.future;
    _notifyCompleter = null;
    _notifyTimer?.cancel();
    _notifyTimer = null;
  }
}

class _Item {
  final Completer trigger = new Completer();
  final Completer finalizer = new Completer();
}
