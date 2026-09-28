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

typedef FailedTest = ({String file, String name, String message});

/// Failed tests with their error messages, in reporting order. A suite that
/// never loaded (usually a compile error) is named `failed to load`.
List<FailedTest> failedTests(
  Iterable<String> lines, {
  required String testDir,
}) {
  final Map<int, String> suites = <int, String>{};
  final Map<int, String?> groups = <int, String?>{};
  final Map<int, (String, String)> tests = <int, (String, String)>{};
  final Map<int, List<String>> errors = <int, List<String>>{};
  final Set<int> failed = <int>{};

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
        final (String file, String name) = _identify(t, suites, groups);
        tests[t['id']! as int] = (
          file,
          (t['groupIDs']! as List<Object?>).isEmpty ? 'failed to load' : name,
        );
      case 'testDone' when e['result'] != 'success':
        failed.add(e['testID']! as int);
      case 'error':
        final int id = e['testID']! as int;
        failed.add(id);
        errors.putIfAbsent(id, () => <String>[]).add(e['error']! as String);
    }
  }
  return <FailedTest>[
    for (final int id in failed)
      if (tests[id] case (final String file, final String name))
        (
          file: file,
          name: name,
          message: (errors[id] ?? const <String>[]).join('\n').trim(),
        ),
  ];
}

const int _messageLines = 10;

/// `elek: N failing tests` followed by each test (paths from the package root) and the head of its message.
String formatFailures(List<FailedTest> failures) {
  final StringBuffer out = StringBuffer(
    'elek: ${failures.length} failing test${failures.length == 1 ? '' : 's'}\n',
  );
  for (final FailedTest f in failures) {
    out.writeln('  test/${f.file} :: ${f.name}');
    final List<String> lines = f.message.split('\n');
    for (final String l in lines.take(_messageLines)) {
      out.writeln('    $l');
    }
    if (lines.length > _messageLines) out.writeln('    ...');
  }
  return out.toString();
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
