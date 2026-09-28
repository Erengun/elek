<p align="center">
  <img src="doc/banner.jpg" alt="elek" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Erengun/elek/actions/workflows/ci.yaml"><img src="https://github.com/Erengun/elek/actions/workflows/ci.yaml/badge.svg" alt="CI"></a>
</p>

**Fast test loops for Flutter developers and coding agents.**
*Elek* is Turkish for sieve.

Stop rerunning tests that already passed. Elek fingerprints each test file's
inputs, skips the ones that are still green, and runs the rest in a few
bundled, duration-balanced shards, so the compiler runs a few times instead of
once per file.

| One edit, then verify (265 files, 2230 tests) | `flutter test` | elek |
|---|---:|---:|
| A test file changed | 192.5 s | 3.9 s |
| A controller changed (17 dependent files) | 192.5 s | 16.1 s |
| Nothing changed | 192.5 s | 1.8 s |

```
fingerprint each test file ─► skip the ones already green ─► bundle the rest
(import closure + test data     (local cache)                 into shards balanced
 + pubspec/lock + SDK)                                        by past durations
```

Status: experimental 0.1.0. Measured on the two projects below; treat anything
else as unverified until you've compared it with plain `flutter test`.

## Install

Not on pub.dev yet. Add it as a dev dependency from git:

```yaml
dev_dependencies:
  elek:
    git: https://github.com/Erengun/elek
```

## Usage

Run from a package directory (the one with `pubspec.yaml` and `test/`):

```sh
dart run elek                 # run what changed since the last green run
dart run elek --no-cache      # run everything (still bundled), refresh cache
dart run elek --dry-run       # list the files that would run
dart run elek --shards 4      # shard count (default: CPU count / 2)
dart run elek --store DIR     # cache directory (default .dart_tool/elek/green)
dart run elek -- --name login # pass arguments to flutter/dart test
```

Flutter packages run `flutter test --no-pub`, others `dart test`.

## For coding agents

Claude Code, Codex, Cursor, Copilot and any other agent that can run a shell
command can use Elek; there is no integration to set up. It prints the usual
`flutter test` / `dart test` output and exits non-zero when a test fails. Put
this in `CLAUDE.md` or `AGENTS.md`:

```markdown
## Tests

After a code change, verify with `dart run elek` instead of `flutter test`:
it runs only the test files whose inputs changed.

Before finishing a large or risky change, run `dart run elek --no-cache`
to run every test.

To run a subset, pass test arguments after `--`, e.g.
`dart run elek -- --name login`. That disables the cache for the run.
```

If the agent's environment sets `CI` (common in cloud and Actions-based
agents), the cache is off; add `--cache` to keep skipping green files.

## How it works

- **Fingerprint.** Per test file: its transitive `import`/`export`/`part`
  closure (both branches of conditional directives), every non-Dart file under
  `test/` (fixtures, goldens), its nearest `flutter_test_config.dart`,
  `pubspec.yaml`, the workspace `pubspec.lock`, declared assets, `l10n.yaml`,
  `dart_test.yaml`, the Dart/Flutter version, locale and time zone.
- **Cache.** A file that passes stores its fingerprint. Same fingerprint next
  time: skipped. Failures, load errors and files run with extra test arguments
  are never stored.
- **Bundling.** Remaining files are grouped into shard entrypoints under
  `test/.bundle/` (deleted after the run), each file inside
  `group('<path>', main)`. Shards are balanced greedily by the last measured
  duration of each file, falling back to file size.
- **Fallback.** Files in one shard share an isolate, so a test that leaks
  global state can break a neighbor. Any bundled file that fails, or whose
  shard fails to load, is rerun as its own suite, and that verdict is the one
  reported and cached. Elek prints which files passed only alone.

## Benchmarks

Apple M3, 8 cores, macOS 15.7.5, Flutter 3.47.4, Dart 3.13.3, default 4
shards. Median of 3 runs. Every "changed" trial starts from the same cached
baseline. Edits are semantic no-ops (`1` → `1 + 0`), not comments. Elek ran
from a kernel snapshot (`dart elek.dill`).

**Private Flutter app**, 265 test files, 2230 tests:

| Scenario | `flutter test` | elek | files run |
|---|---:|---:|---:|
| Full suite | 192.5 s | 44.8 s | 265 |
| No changes | 192.5 s | 1.8 s | 0 |
| One controller changed | 192.5 s | 16.1 s | 17 |
| One test file changed | 192.5 s | 3.9 s | 1 |
| Fixture under `test/` changed | 192.5 s | 49.4 s | 265 |

**[Flame](https://github.com/flame-engine/flame) `packages/flame`**, tag
`flame-v1.38.2` (`03ca247`) with its 9 Linux-generated goldens regenerated
on macOS, 207 test files, 1820 tests:

| Scenario | `flutter test` | elek | files run |
|---|---:|---:|---:|
| Full suite | 61.3 s | 16.1 s | 207 |
| No changes | 61.3 s | 0.7 s | 0 |
| `position_component.dart` changed | 61.3 s | 18.0 s | 203 |
| One test file changed | 61.3 s | 2.4 s | 1 |
| Fixture under `test/` changed | 61.3 s | 17.4 s | 207 |

Flame's `lib/src` is one import cycle behind barrel exports, so 359 of its 385
library files reach 203+ test files. File-level fingerprints can't narrow a
source change there; the wins are no-change and test-only edits. The Flame
numbers include the fallback, which fired in 7 of the 9 bundled runs:
`cache/images_test.dart` 6 times (it shares the global `Flame.images` cache)
and `experimental/linear_layout_component_test.dart` once.

Parity: per-test results (file, full name, pass/fail/skip) were compared
against plain `flutter test` for every full run on both projects and were
identical (`tool/parity.dart`).

## Limitations

- **Isolation.** Files in a shard share one isolate. The fallback catches
  leaks that make a test fail. It can't catch a test that passes only because
  a neighbor left state behind: that gets a green bundled and would fail alone.
- **Cache blind spots.** Files read from outside `test/`, environment
  variables, network and clock-dependent behavior aren't in the fingerprint.
  Use `--no-cache` when those change. The cache is off when `CI` is set
  (unless `--cache`) and whenever arguments follow `--`.
- **Platforms.** Bundling targets Dart VM and Flutter suites. Files that can't
  safely share a shard run as separate suites in the same command. That
  covers a `@TestOn` that isn't a plain OS selector, `@Tags`/`@Skip`/
  `@Timeout`/`@OnPlatform`/`@Retry`, an async `main`, and a nested
  `flutter_test_config.dart`. Browser runs aren't accelerated: they happen only
  if you pass `-p chrome` after `--`, which also turns the cache off.
- **Test config.** A root `flutter_test_config.dart` wraps each shard once, not
  each file. A config above `test/` isn't fingerprinted.
- **Goldens.** Each bundled Flutter file gets a `LocalFileComparator` rooted at
  its own directory. A custom comparator from `flutter_test_config.dart` is
  left alone and resolves against the shard.
- **Selection is file-level.** A change to any file in a test's import
  closure reruns it, even if the test never touches the changed symbol.
- **Exit codes.** Exit 79 ("no tests ran") becomes 0 only when the cache
  skipped files; with nothing skipped it means a filter matched nothing.
