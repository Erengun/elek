// Inputs under `test/` that no Dart import graph shows.
import 'dart:io';

import 'package:path/path.dart' as p;

/// Fixtures, goldens and other non-Dart files a test may read at runtime.
/// Hashing all of them over-approximates but needs no per-test config.
List<String> testDataFiles(String testDir) => <String>[
  for (final FileSystemEntity e in Directory(testDir).listSync(recursive: true))
    if (e is File &&
        !e.path.endsWith('.dart') &&
        // .DS_Store and friends would rerun everything after a Finder visit.
        !p.basename(e.path).startsWith('.') &&
        // LocalFileComparator writes these on a mismatch: output, not input.
        !p.split(p.relative(e.path, from: testDir)).contains('failures') &&
        !p.isWithin(p.join(testDir, '.bundle'), e.path))
      e.path,
];

/// The `flutter_test_config.dart` Flutter would wrap [file] (relative to
/// [testDir]) in: the closest one walking up to the package root, the
/// directory above [testDir] when it holds a `pubspec.yaml`.
String? nearestTestConfig(String testDir, String file) {
  final String pkg = p.dirname(testDir);
  final String top = File(p.join(pkg, 'pubspec.yaml')).existsSync()
      ? pkg
      : testDir;
  String dir = p.dirname(p.join(testDir, file));
  while (true) {
    final String config = p.join(dir, 'flutter_test_config.dart');
    if (File(config).existsSync()) return config;
    if (p.equals(dir, top) || !p.isWithin(top, dir)) return null;
    dir = p.dirname(dir);
  }
}
