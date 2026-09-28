# elek example

Six tiny test files to watch elek bundle, cache and pick tests. Run every
command from this folder.

| Test | Imports | Shows |
|---|---|---|
| `price_test.dart` | `price.dart` | plain file, bundled |
| `cart_test.dart` | `cart.dart` → `price.dart` | transitive import |
| `greeting_test.dart` | `greeting.dart` | plain file, bundled |
| `slugify_test.dart` | `slugify.dart` | plain file, bundled |
| `posix_path_test.dart` | — | `@TestOn` becomes a group skip, stays bundled |
| `tagged_test.dart` | `greeting.dart` | `@Tags` can't be bundled, runs alone |

## 1. First run: everything runs, bundled

```sh
dart run elek --shards 2
```

```
6/6 test files to run (rest unchanged since last green run)
note: tagged_test.dart has library annotations or an async main; running it alone.
... test/.bundle/shard_0.dart: posix_path_test.dart temp dir is absolute
... test/.bundle/shard_1.dart: cart_test.dart label formats the total
...
00:00 +6: All tests passed!
cached 6/6 green test files
```

Five files are compiled as two shards instead of five suites. The shards
are generated in `test/.bundle/` and deleted after the run.

## 2. Run again: nothing to do

```sh
dart run elek
```

```
0/6 test files to run (rest unchanged since last green run)
```

## 3. Change one file: only its dependents run

Add a comment to `lib/src/price.dart`, then:

```sh
dart run elek --dry-run
```

```
2/6 test files to run (rest unchanged since last green run)
cart_test.dart
price_test.dart
```

`cart_test.dart` never mentions `price.dart`, but `cart.dart` imports it.
Edit `lib/src/greeting.dart` too and `greeting_test.dart` and
`tagged_test.dart` join the list. Undo the edits and it's back to `0/6`:
the cache is keyed by content, not timestamps.

## 4. Make a test fail

Break `formatPrice` and run `dart run elek`. The failing file isn't cached,
so it runs again next time until it passes.

## Flags

| Flag | Effect |
|---|---|
| `--dry-run` | list the files that would run, run nothing |
| `--no-cache` | run every file (default when `CI` is set) |
| `--cache` | use the cache even under `CI` |
| `--shards N` | shard count (default: half the CPU cores) |
| `--store DIR` | where green hashes live (default `.dart_tool/elek/green`) |
| `-- <args>` | passed to `dart test`; such runs don't write the cache |
