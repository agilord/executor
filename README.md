# Async task executor for Dart

Executes async tasks with a configurable maximum concurrency and rate.

## Usage

A simple usage example:

    final executor = Executor(concurrency: 10);
    // only 10 of them will be running at a time
    for (var i = 0; i < 20; i++) {
      // ignore: unawaited_futures
      executor.scheduleTask(() async {
        // await longDatabaseTask()
        // await anotherProcessing()
      });
    }
    await executor.join(withWaiting: true);
    await executor.close();

## Links

- [source code][source]
- contributors: [Agilord][agilord]
- Related projects:
  - Alternative: the Dart team's [pool](https://pub.dev/packages/pool) library.
  - PostgreSQL connection pool: [postgres_pool](https://pub.dev/packages/postgres_pool).

[source]: https://github.com/agilord/executor
[agilord]: https://www.agilord.com/
