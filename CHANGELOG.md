## 0.1.0

- Initial release: incremental test runner for Dart and Flutter packages.
- Skips test files whose import closure, test data and toolchain fingerprint
  already passed; runs the rest in duration-balanced bundled shards. The
  import closure follows `path:` dependencies outside the workspace.
- A second concurrent run in the same package exits instead of clobbering the
  first run's shards and results.
- Suites that can't share a shard (non-OS `@TestOn`, other library
  annotations, async `main`, nested `flutter_test_config.dart`) run alone.
- Cache is off under `CI` and whenever test arguments follow `--`.
- When a run fails, prints an `elek: N failing tests` block with each failing
  test and the start of its message, including compile errors.
- Agent plugin for Claude Code and Codex (`agent/`): a skill plus hooks that
  run elek when the agent tries to finish after editing files, and send the
  failures back to it.
