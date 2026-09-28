<p align="center">
  <img src="doc/banner.jpg" alt="elek" width="100%">
</p>

<p align="center">
  <a href="https://github.com/Erengun/elek/actions/workflows/ci.yaml"><img src="https://github.com/Erengun/elek/actions/workflows/ci.yaml/badge.svg" alt="CI"></a>
</p>

**Your coding agent is fast. Your test suite isn't.**

Elek is an incremental test runner for Dart and Flutter. *Elek* means sieve
in Turkish: it sifts out the tests that are already green and runs only what
may have changed. With the agent plugin, Elek checks your agent's changes
before it says it's done.

Elek fingerprints the inputs of each test file and skips the files that
passed last time with the same inputs. Whatever is left runs in a few bundled
shards, balanced by how long each file took before, so the compiler starts a
handful of times instead of once per file.

| Local verification loop (265 files, 2230 tests) | `flutter test` | elek | speedup |
|---|---:|---:|---:|
| A test file changed | 192.5 s | 3.9 s | 49× |
| A controller changed (17 dependent files) | 192.5 s | 16.1 s | 12× |
| Nothing changed | 192.5 s | 1.8 s | 107× |

```
fingerprint each test file ─► skip the ones already green ─► bundle the rest
(import closure + test data     (local cache)                 into shards balanced
 + pubspec/lock + SDK)                                        by past durations
```

Elek is at 0.1 and experimental. It has been measured on the two projects
below. On any other project, compare its results with plain `flutter test`
before you rely on it.

## Install

Add Elek as a dev dependency:

```sh
dart pub add dev:elek
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

In a Flutter package Elek calls `flutter test --no-pub`; anywhere else it
calls `dart test`.

## For coding agents

Any agent that can run a shell command can use Elek, including Claude Code,
Codex, Cursor and Copilot. No agent-specific integration is required. Elek
prints the usual `flutter test` or `dart test` output and exits non-zero when
a test fails. Put something like this in `CLAUDE.md` or `AGENTS.md`:

```markdown
## Tests

After a code change, verify with `dart run elek` instead of `flutter test`:
it runs only the test files whose inputs changed.

Before finishing a large or risky change, run `dart run elek --no-cache`
to run every test.

To run a subset, pass test arguments after `--`, e.g.
`dart run elek -- --name login`. That disables the cache for the run.
```

Cloud agents and agents running in GitHub Actions often have `CI` set, and
Elek turns its cache off when it sees `CI`. Add `--cache` there if you still
want green files skipped.

Only one Elek run at a time can work in a package, because runs share
`test/.bundle/` and the results files. A second run exits with
`Another elek run is already active in this package.`, so agents that run
shell commands in parallel should wait and retry.

### Agent plugin

The repo also ships a plugin for Claude Code and Codex. It adds a skill that
tells the agent how to verify with Elek, and two hooks:

- After each file edit, a hook records that the session changed something.
  It doesn't run any tests.
- When the agent tries to finish, a hook runs `dart run elek --cache` once in
  every package of the project that has Elek as a dev dependency. If a test
  fails, the agent gets the failing tests and their messages and keeps working.
  If it passes, you see a one-line `elek: passed` message.

Turns without edits cost nothing. The hook stops the agent from finishing at
most 3 times in a row. After that it stays quiet until the agent edits a file
again, so a test that was already failing can't trap it in a loop. Edits made through the shell (`sed`, code generation) don't mark the
session as changed; the skill tells the agent to run Elek itself after those.
The hook needs `dart` on your `PATH`.

Claude Code:

```sh
/plugin marketplace add Erengun/elek
/plugin install elek@elek
```

Codex:

```sh
codex plugin marketplace add Erengun/elek
codex plugin add elek@elek
```

Codex doesn't run plugin hooks until you trust them in `/hooks`. Claude Code
runs them once the plugin is enabled and lists them in `/hooks`. The hook
source is `agent/hooks/elek_hook.dart`, if you want to read what it does
first.

## How it works

A test file's fingerprint covers its transitive `import`, `export` and `part`
closure (both branches of a conditional directive count), including `path:`
dependencies that live outside the workspace, every non-Dart file
under `test/` such as fixtures and goldens (except the `failures/` images a
golden mismatch leaves behind), its nearest `flutter_test_config.dart` up to
the package root, `pubspec.yaml`, the workspace `pubspec.lock`,
declared assets, `l10n.yaml`, `dart_test.yaml`, the Dart and Flutter versions,
the locale and the time zone. Hosted and git dependencies aren't walked:
the lockfile pins them, so a new version changes `pubspec.lock` instead.

When a file passes, Elek stores its fingerprint. If the fingerprint is the same
on the next run, Elek skips the file. It never stores failures, load errors, or
runs that had extra test arguments.

The files that still need to run go into generated shard entrypoints under
`test/.bundle/`, one `group('<path>', main)` per file. Elek deletes the
directory after the run. It fills the shards greedily using each file's last
measured duration, or its size when there is no history yet.

Files in the same shard share an isolate, so a test that leaks global state can
break its neighbor. When a bundled file fails, or its shard fails to load, Elek
reruns that file as its own suite and reports and caches that result instead.
It also prints the files that only passed when run alone. If the bundled run
stopped early (`--fail-fast`, or a crashed test process), a passing rerun
doesn't turn it green: the tests that never ran keep the run red.

## Benchmarks

All numbers come from an Apple M3 with 8 cores on macOS 15.7.5, with Flutter
3.47.4, Dart 3.13.3 and the default 4 shards. Each is the median of 3 runs.
Every "changed" trial started from the same cached baseline, and the edits
changed code without changing behavior (`1` to `1 + 0`) rather than touching a
comment. Elek ran from a kernel snapshot (`dart elek.dill`).

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

Flame's `lib/src` is one big import cycle behind barrel exports, so 359 of
its 385 library files reach at least 203 test files. File-level fingerprints
can't narrow a source change in a graph like that. On Flame, Elek helps when
nothing changed or when only a test file changed. The Flame numbers include
the fallback, which fired in 7 of the 9 bundled runs:
`cache/images_test.dart` six times (it shares the global `Flame.images` cache)
and `experimental/linear_layout_component_test.dart` once.

For every full run on both projects, `tool/parity.dart` compared each test's
file, full name and result (pass, fail or skip) with a plain `flutter test`
run. They matched every time.

## Limitations

- Files in a shard share one isolate. The fallback catches leaks that make a
  test fail, but not a test that passes only because a neighbor left state
  behind. That test is green when bundled and would fail on its own.
- The fingerprint doesn't include files read from outside `test/`, environment
  variables, the network, or anything that depends on the clock. Run
  `--no-cache` when one of those changes. The cache is also off when `CI` is
  set (unless you pass `--cache`) and whenever you pass arguments after `--`.
- Bundling works for Dart VM and Flutter suites. A file that can't share a
  shard runs as its own suite in the same command: a `@TestOn` that isn't a
  plain OS selector, `@Tags`, `@Skip`, `@Timeout`, `@OnPlatform` or `@Retry`,
  a `main` that is async or has an arrow body (`void main() => ...`, which
  can return a helper's Future), or a nested `flutter_test_config.dart`.
  Elek doesn't speed
  up browser runs. Those only happen if you pass `-p chrome` after `--`, which
  also turns the cache off.
- A `flutter_test_config.dart` in `test/` or at the package root wraps each
  shard once rather than each file.
- Each bundled Flutter file gets a `LocalFileComparator` rooted at its own
  directory, but only when the comparator is still flutter_test's default. A
  comparator that `flutter_test_config.dart` set up (a subclass, or one with
  its own base directory) is left alone. If that comparator resolves paths
  relative to the test file, it resolves them against the shard in
  `test/.bundle/`, and `--update-goldens` writes the new images there, where
  Elek deletes them after the run. Use plain `flutter test` to update goldens
  in that setup.
- Bundled test names start with the file path (`cart_test.dart adds item`),
  so a `--name` or `--plain-name` pattern anchored with `^` after `--`
  matches nothing in a shard. Leave the pattern unanchored.
- Selection works per file. Changing any file in a test's import closure
  reruns that test, even if the test never uses the changed code.
- Exit code 79 ("no tests ran") becomes 0 only when the cache skipped files.
  When nothing was skipped, it means a filter matched nothing, and Elek keeps
  the 79.
