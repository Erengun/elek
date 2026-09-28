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
        !p.isWithin(p.join(testDir, '.bundle'), e.path))
      e.path,
];

/// The `flutter_test_config.dart` Flutter would wrap [file] (relative to
/// [testDir]) in: the closest one walking up to [testDir]. Flutter keeps
/// walking to the package root; a config there isn't seen or hashed.
String? nearestTestConfig(String testDir, String file) {
  String dir = p.dirname(p.join(testDir, file));
  while (true) {
    final String config = p.join(dir, 'flutter_test_config.dart');
    if (File(config).existsSync()) return config;
    if (p.equals(dir, testDir) || !p.isWithin(testDir, dir)) return null;
    dir = p.dirname(dir);
  }
}
