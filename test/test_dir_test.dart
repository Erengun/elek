import 'dart:io';

import 'package:elek/src/test_dir.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory testDir;

  setUp(() => testDir = Directory.systemTemp.createTempSync('test_dir_test'));
  tearDown(() => testDir.deleteSync(recursive: true));

  String write(String rel) {
    final File f = File(p.join(testDir.path, rel))
      ..createSync(recursive: true)
      ..writeAsStringSync(rel);
    return f.path;
  }

  test('testDataFiles lists visible non-Dart files outside the bundle dir', () {
    final String json = write('fixtures/user.json');
    final String png = write('a/goldens/x.png');
    write('a_test.dart');
    write('.bundle/shard_0.dart');
    write('.bundle/notes.txt');
    write('a/.DS_Store');

    expect(testDataFiles(testDir.path).toSet(), <String>{json, png});
  });

  group('nearestTestConfig', () {
    test('is null without any config', () {
      write('a/b_test.dart');

      expect(nearestTestConfig(testDir.path, 'a/b_test.dart'), isNull);
    });

    test('finds the root config from a nested file', () {
      final String root = write('flutter_test_config.dart');

      expect(nearestTestConfig(testDir.path, 'a/b/c_test.dart'), root);
    });

    test('prefers the closest config', () {
      write('flutter_test_config.dart');
      final String nested = write('a/flutter_test_config.dart');

      expect(nearestTestConfig(testDir.path, 'a/b/c_test.dart'), nested);
      expect(
        nearestTestConfig(testDir.path, 'd_test.dart'),
        p.join(testDir.path, 'flutter_test_config.dart'),
      );
    });
  });
}
