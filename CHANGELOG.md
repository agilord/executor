# Changelog

## 2.2.5

- `isOpen` method to indicate if the `Executor` is still accepting tasks.

## 2.2.4

- Updated lints.

## 2.2.3

- Fix tasks with non-nullable return types when an error is thrown. ([#4](https://github.com/agilord/executor/pull/4) by [davidmartos96](https://github.com/davidmartos96))

## 2.2.2

- Migrated to null safety (by [swdyh](https://github.com/swdyh))

## 2.2.1

- Updated code to Dart 2.7.0 and latest lints.
- Fix: task completion updates the running count immediately.

## 2.2.0

- Removed `new` keyword, and updated to follow `package:pedantic` rules.
- `Executor.join` will register `Future.catchError` on task futures, preventing
  uncaught exceptions from blocking further execution.
- Simplified execution and trigger mechanism.

## 2.1.2

- Using `package:stack_trace` to chain async stacktraces when task fails.

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
