// Per-file outcome from `flutter test --file-reporter json:...` output.
import 'dart:convert';

import 'package:path/path.dart' as p;

final class FileResult {
  bool passed = true;
  int millis = 0;
}

/// Keys are test file paths relative to [testDir]. Bundled tests map to their
/// file through the top-level group; files that never ran a test are absent.
Map<String, FileResult> parseResults(
  Iterable<String> lines, {
  required String testDir,
}) {
  final Map<int, String> suites = <int, String>{};
  final Map<int, String?> groups = <int, String?>{};
  final Map<int, (String?, int)> starts = <int, (String?, int)>{};
  final Map<String, FileResult> results = <String, FileResult>{};

  for (final String line in lines) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (decoded is! Map<String, Object?>) continue;
    final Map<String, Object?> e = decoded;
    switch (e['type']) {
      case 'suite':
        final Map<String, Object?> s = e['suite']! as Map<String, Object?>;
        suites[s['id']! as int] = s['path'] as String? ?? '';
      case 'group':
        final Map<String, Object?> g = e['group']! as Map<String, Object?>;
        groups[g['id']! as int] = g['name'] as String?;
      case 'testStart':
        final Map<String, Object?> t = e['test']! as Map<String, Object?>;
        starts[t['id']! as int] = (
          _fileOf(t, suites, groups, testDir),
          e['time']! as int,
        );
      case 'testDone':
        final (String? file, int start) = starts[e['testID']! as int]!;
        if (file == null) continue;
        final FileResult r = results.putIfAbsent(file, FileResult.new);
        if (e['result'] != 'success') r.passed = false;
        r.millis += (e['time']! as int) - start;
      // Uncaught async errors can arrive after a `testDone` that said success.
      case 'error':
        final (String? file, _) = starts[e['testID']! as int]!;
        if (file == null) continue;
        results.putIfAbsent(file, FileResult.new).passed = false;
    }
  }
  return results;
}

String? _fileOf(
  Map<String, Object?> test,
  Map<int, String> suites,
  Map<int, String?> groups,
  String testDir,
) {
  final List<Object?> groupIds = test['groupIDs']! as List<Object?>;
  // `loading <suite>` has no groups; a failed load simply never reports tests.
  if (groupIds.isEmpty) return null;
  final String suite = p.relative(
    p.absolute(suites[test['suiteID']! as int]!),
    from: testDir,
  );
  if (!p.isWithin('.bundle', suite)) return p.split(suite).join('/');
  for (final Object? id in groupIds) {
    final String? name = groups[id! as int];
    if (name != null && name.isNotEmpty) return name;
  }
  return null;
}

/// Suites (relative to [testDir]) whose `loading` test didn't succeed.
Set<String> failedLoads(Iterable<String> lines, {required String testDir}) {
  final Map<int, String> suites = <int, String>{};
  final Map<int, int> loading = <int, int>{};
  final Set<String> failed = <String>{};
  for (final String line in lines) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (decoded is! Map<String, Object?>) continue;
    final Map<String, Object?> e = decoded;
    switch (e['type']) {
      case 'suite':
        final Map<String, Object?> s = e['suite']! as Map<String, Object?>;
        suites[s['id']! as int] = p
            .split(
              p.relative(p.absolute(s['path'] as String? ?? ''), from: testDir),
            )
            .join('/');
      case 'testStart':
        final Map<String, Object?> t = e['test']! as Map<String, Object?>;
        if ((t['groupIDs']! as List<Object?>).isEmpty) {
          loading[t['id']! as int] = t['suiteID']! as int;
        }
      case 'testDone' when e['result'] != 'success':
        final int? suite = loading[e['testID']! as int];
        if (suite != null) failed.add(suites[suite]!);
    }
  }
  return failed;
}

/// Of [suites] (relative to [testDir]), those that never reported or finished
/// fewer tests than their root group declared: `--fail-fast` stopped them, or
/// the test process died partway.
Set<String> unfinishedSuites(
  Iterable<String> lines, {
  required String testDir,
  required Iterable<String> suites,
}) {
  final Map<int, String> paths = <int, String>{};
  final Map<int, int> declared = <int, int>{};
  final Map<int, int> finished = <int, int>{};
  final Map<int, int> suiteOf = <int, int>{};
  for (final String line in lines) {
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      continue;
    }
    if (decoded is! Map<String, Object?>) continue;
    final Map<String, Object?> e = decoded;
    switch (e['type']) {
      case 'suite':
        final Map<String, Object?> s = e['suite']! as Map<String, Object?>;
        paths[s['id']! as int] = p
            .split(
              p.relative(p.absolute(s['path'] as String? ?? ''), from: testDir),
            )
            .join('/');
      case 'group':
        final Map<String, Object?> g = e['group']! as Map<String, Object?>;
        if (g['parentID'] == null) {
          declared[g['suiteID']! as int] = g['testCount']! as int;
        }
      case 'testStart':
        final Map<String, Object?> t = e['test']! as Map<String, Object?>;
        suiteOf[t['id']! as int] = t['suiteID']! as int;
      case 'testDone' when e['hidden'] != true:
        if (suiteOf[e['testID']! as int] case final int suite) {
          finished.update(suite, (int n) => n + 1, ifAbsent: () => 1);
        }
    }
  }
  final Set<String> complete = <String>{
    for (final MapEntry<int, int> d in declared.entries)
      if ((finished[d.key] ?? 0) >= d.value) paths[d.key]!,
  };
  return <String>{
    for (final String s in suites)
      if (!complete.contains(s)) s,
  };
}

/// Bundled files whose shard verdict can't be trusted: they failed, or their
/// shard never loaded. A neighbor's leaked global state can cause either, so
/// they get a standalone rerun whose verdict wins.
List<String> filesToRerun(
  Map<String, FileResult> results, {
  required Map<String, List<String>> shards,
  required Set<String> failedLoads,
}) => <String>[
  for (final MapEntry<String, List<String>> shard in shards.entries)
    for (final String f in shard.value)
      if (failedLoads.contains(shard.key) || results[f]?.passed == false) f,
]..sort();
