# Async task executor for Dart

Executes async tasks with a configurable maximum concurrency and rate.

## Usage

A simple usage example:

    import 'dart:async';
    
    import 'package:executor/executor.dart';
    
    Future main() async {
      Executor executor = new Executor(concurrency: 10);
      // only 10 of them will be running at a time
      for (int i = 0; i < 20; i++) {
         executor.scheduleTask(() async {
           // await longDatabaseTask()
           // await anotherProcessing()
         });
      }
    }

## Links

- [source code][source]
- contributors: [Agilord][agilord]
- Related projects:
  - Alternative: the Dart team's [pool](https://pub.dartlang.org/packages/pool) library.
  - Database executor: [db_executor](https://pub.dartlang.org/packages/db_executor) (from the same authors as this projects)

[source]: https://github.com/agilord/db_executor
[agilord]: https://www.agilord.com/
