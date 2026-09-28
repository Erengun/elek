// dart run tool/parity.dart <plain.json> <elek.json> <test dir>
//     [--strip RE] [--rerun results_rerun.json]
// Exits 1 when the two JSON reporter files disagree on any test outcome.
// --strip drops per-run noise from names, e.g. ' \[seed=\d+\]'.
// --rerun: elek's standalone reruns, whose files replace the bundled lines.
import 'dart:io';

import 'package:elek/src/parity.dart';

void main(List<String> args) {
  String? option(String name) {
    final int i = args.indexOf(name);
    return i < 0 || i + 1 >= args.length ? null : args[i + 1];
  }

  final String? stripRe = option('--strip');
  final RegExp? strip = stripRe == null ? null : RegExp(stripRe);
  final String? rerun = option('--rerun');
  final List<String> files = <String>[
    for (int i = 0; i < args.length; i++)
      if (!args[i].startsWith('--') &&
          (i == 0 || !args[i - 1].startsWith('--')))
        args[i],
  ];
  if (files.length != 3) {
    stderr.writeln(
      'usage: parity.dart <plain.json> <elek.json> <test dir> [--strip RE]',
    );
    exit(64);
  }
  final String testDir = Directory(files[2]).absolute.path;
  List<String> read(String path) => <String>[
    for (final String l in canonicalResults(
      File(path).readAsLinesSync(),
      testDir: testDir,
    ))
      strip == null ? l : l.replaceAll(strip, ''),
  ]..sort();
  final List<String> plain = read(files[0]);
  final List<String> elek = _replaceFiles(
    read(files[1]),
    rerun == null ? const <String>[] : read(rerun),
  );

  String summary(List<String> r) {
    int count(String s) => r.where((String l) => l.endsWith('  $s')).length;
    return '${r.length} tests, ${count('PASS')} pass, ${count('FAIL')} fail, '
        '${count('SKIP')} skip';
  }

  stdout
    ..writeln('plain: ${summary(plain)}')
    ..writeln('elek:  ${summary(elek)}');
  final List<String> onlyPlain = _minus(plain, elek);
  final List<String> onlyElek = _minus(elek, plain);
  for (final String l in onlyPlain) {
    stdout.writeln('- $l');
  }
  for (final String l in onlyElek) {
    stdout.writeln('+ $l');
  }
  if (onlyPlain.isEmpty && onlyElek.isEmpty) {
    stdout.writeln('identical');
    return;
  }
  exit(1);
}

String _file(String line) => line.substring(0, line.indexOf(' :: '));

List<String> _replaceFiles(List<String> base, List<String> rerun) {
  final Set<String> rerunFiles = rerun.map(_file).toSet();
  return <String>[
    for (final String l in base)
      if (!rerunFiles.contains(_file(l))) l,
    ...rerun,
  ]..sort();
}

// Multiset difference: repeated test names count separately.
List<String> _minus(List<String> a, List<String> b) {
  final Map<String, int> left = <String, int>{};
  for (final String l in b) {
    left[l] = (left[l] ?? 0) + 1;
  }
  return <String>[
    for (final String l in a)
      if ((left[l] = (left[l] ?? 0) - 1) < 0) l,
  ];
}
