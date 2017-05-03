# Changelog

## 0.1.1

- Fix missing heartbeat check on `Executor.close()`, without it the `Future`
  might not have completed.

## 0.1

- start-rate limit support
- renamed `limit` to `concurrency` (leaving old field, marked deprecated)
