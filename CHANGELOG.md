## 0.1.0

- Initial release: incremental test runner for Dart and Flutter packages.
- Skips test files whose import closure, test data and toolchain fingerprint
  already passed; runs the rest in duration-balanced bundled shards.
- Suites that can't share a shard (non-OS `@TestOn`, other library
  annotations, async `main`, nested `flutter_test_config.dart`) run alone.
- Cache is off under `CI` and whenever test arguments follow `--`.
