---
name: elek
description: Use when changing code in a Dart or Flutter package that has elek as a dev dependency. Explains how to verify changes with elek instead of flutter test or dart test, and what to do when elek's Stop hook reports failures.
---

# Verifying changes with elek

elek runs only the test files whose inputs changed since their last green
run, in a few bundled shards. Run it from the package directory, the one with
`pubspec.yaml` and `test/`.

| Situation | Command |
|---|---|
| After a code change | `dart run elek` |
| A few tests by name | `dart run elek -- --name <pattern>` (runs without the cache) |
| Large refactor, or a change elek can't see: env variables, files outside `test/`, network or clock-dependent behavior | `dart run elek --no-cache` |
| See what would run | `dart run elek --dry-run` |

Before saying a substantial task is done, make sure an elek run passed after
your last edit. With the elek plugin's Stop hook this happens by itself after
edits made with the file-editing tools. Edits made through the shell (`sed`,
code generation, `dart fix`) don't trigger the hook, so run `dart run elek`
yourself after those.

When the Stop hook blocks with `Elek verification failed`, read the failing
tests it lists and fix them. If they are unrelated to your change (they were
already failing), tell the user instead of looping. The hook gives up after 3
attempts.

When elek prints `note: <file> failed bundled but passes alone`, report it to
the user as a likely shared-state problem between test files. Don't treat it
as your failure.

If elek prints `Another elek run is already active in this package.`, wait for
the other run to finish and try again. Don't run elek in parallel in the same
package.
