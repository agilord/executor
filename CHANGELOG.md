# Changelog

## 2.1.1

- Improved design on loop and scheduling, preserving caller stacktrace with full details.

## 2.1.0

- Removed `Timer`s to schedule tasks, using a simple loop instead.
- Better distribution for rate-limited executions.

## 2.0.0

- Supporting Dart 2 only.

## 1.0.1

- Dart2 compatibility with `package:dart2_constant`.

## 1.0.0

**Breaking changes**

- Removed deprecated member `limit`.
- Renamed `ExecutorTask` -> `AsyncTask`, return value to `FutureOr`.
- Renamed `Rate.limit` -> `Rate.maximum`.

**New features**

- Added `Executor.onChange`. Clients can use this to monitor the current `scheduledCount` and queue more tasks to ensure `Executor` is running on full capacity.

**Housekeeping**

- Added example.
- Added a few tests.

## 0.1.2

- Expose internal stats: `runningCount`, `waitingCount`, `scheduledCount`.
- Enable sync-points with `join()`, which allows to track the completion of
  the currently running (and optionally the waiting) tasks.

## 0.1.1

- Fix missing heartbeat check on `Executor.close()`, without it the `Future`
  might not have completed.

## 0.1

- start-rate limit support
- renamed `limit` to `concurrency` (leaving old field, marked deprecated)
