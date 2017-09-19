// Copyright (c) 2017, Agilord. All rights reserved. Use of this source code
// is governed by a BSD-style license that can be found in the LICENSE file.

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
