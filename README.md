# Async task executor for Dart

Executes async tasks concurrently with a configurable parallelism limit.

This is an alternative implementation of the Dart team's
[pool](https://github.com/dart-lang/pool) library with fewer tests,
but with streaming support.

It will get deprecated in favor of `pool` once it reaches feature parity.

## Usage

A simple usage example:

    import 'dart:async';
    
    import 'package:executor/executor.dart';
    
    Future main() async {
      Executor executor = new Executor(limit: 10);
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

[source]: https://github.com/agilord/db_executor
[agilord]: https://www.agilord.com/
