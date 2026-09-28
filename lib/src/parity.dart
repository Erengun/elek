// Canonical per-test outcomes from a JSON reporter stream, so a plain
// `flutter test` run and a bundled elek run can be diffed line by line.
import 'dart:convert';

import 'package:path/path.dart' as p;

/// Sorted `file :: name  PASS|FAIL|SKIP` lines. Bundled names lose their
/// file-group prefix. Hidden tests (loading, setUpAll...) only show up
/// when they fail, since shards change how many of them exist.
List<String> canonicalResults(
  Iterable<String> lines, {
  required String testDir,
}) {
  final Map<int, String> suites = <int, String>{};
  final Map<int, String?> groups = <int, String?>{};
  final Map<int, (String, String)> tests = <int, (String, String)>{};
  final Map<int, String> status = <int, String>{};
  final Set<int> hidden = <int>{};

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
      case 'group':
        final Map<String, Object?> g = e['group']! as Map<String, Object?>;
        groups[g['id']! as int] = g['name'] as String?;
      case 'testStart':
        final Map<String, Object?> t = e['test']! as Map<String, Object?>;
        tests[t['id']! as int] = _identify(t, suites, groups);
      case 'testDone':
        final int id = e['testID']! as int;
        if (e['hidden'] == true) hidden.add(id);
        status.update(
          id,
          (String s) => s,
          ifAbsent: () => e['result'] != 'success'
              ? 'FAIL'
              : e['skipped'] == true
              ? 'SKIP'
              : 'PASS',
        );
      case 'error':
        status[e['testID']! as int] = 'FAIL';
    }
  }
  return <String>[
    for (final MapEntry<int, (String, String)> t in tests.entries)
      if (status[t.key] case final String s
          when !hidden.contains(t.key) || s == 'FAIL')
        '${t.value.$1} :: ${t.value.$2}  $s',
  ]..sort();
}

(String, String) _identify(
  Map<String, Object?> test,
  Map<int, String> suites,
  Map<int, String?> groups,
) {
  final String suite = suites[test['suiteID']! as int]!;
  final String name = test['name']! as String;
  if (!p.isWithin('.bundle', suite)) return (suite, name);
  for (final Object? id in test['groupIDs']! as List<Object?>) {
    final String? file = groups[id! as int];
    if (file != null && file.isNotEmpty) {
      return (
        file,
        name.startsWith('$file ') ? name.substring(file.length + 1) : name,
      );
    }
  }
  return (suite, name);
}
