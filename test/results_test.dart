import 'dart:convert';

import 'package:elek/src/results.dart';
import 'package:test/test.dart';

const String _testDir = '/repo/app/test';

String _e(Map<String, Object?> event) => jsonEncode(event);

String _suite(int id, String path) => _e(<String, Object?>{
  'type': 'suite',
  'suite': <String, Object?>{'id': id, 'path': path},
});

String _group(int id, int suiteId, String? name) => _e(<String, Object?>{
  'type': 'group',
  'group': <String, Object?>{'id': id, 'suiteID': suiteId, 'name': name},
});

String _start(int id, int suiteId, String name, List<int> groups, int time) =>
    _e(<String, Object?>{
      'type': 'testStart',
      'time': time,
      'test': <String, Object?>{
        'id': id,
        'suiteID': suiteId,
        'name': name,
        'groupIDs': groups,
      },
    });

String _done(int id, String result, int time, {bool hidden = false}) =>
    _e(<String, Object?>{
      'type': 'testDone',
      'testID': id,
      'result': result,
      'hidden': hidden,
      'time': time,
    });

void main() {
  test('maps bundled tests to their file through the top-level group', () {
    final Map<String, FileResult> results = parseResults(<String>[
      _suite(0, '$_testDir/.bundle/shard_0.dart'),
      _start(1, 0, 'loading shard_0.dart', <int>[], 0),
      _done(1, 'success', 900, hidden: true),
      _group(2, 0, null),
      _group(3, 0, 'core/a_test.dart'),
      _group(4, 0, 'core/a_test.dart inner'),
      _group(5, 0, 'core/b_test.dart'),
      _start(6, 0, 'core/a_test.dart inner works', <int>[2, 3, 4], 1000),
      _done(6, 'success', 1300),
      _start(7, 0, 'core/b_test.dart fails', <int>[2, 5], 1300),
      _done(7, 'failure', 1400),
    ], testDir: _testDir);

    expect(
      results.keys,
      unorderedEquals(<String>['core/a_test.dart', 'core/b_test.dart']),
    );
    expect(results['core/a_test.dart']!.passed, isTrue);
    expect(results['core/a_test.dart']!.millis, 300);
    expect(results['core/b_test.dart']!.passed, isFalse);
  });

  test('a failing hidden setUpAll fails the file', () {
    final Map<String, FileResult> results = parseResults(<String>[
      _suite(0, '$_testDir/.bundle/shard_0.dart'),
      _group(1, 0, null),
      _group(2, 0, 'a_test.dart'),
      _start(3, 0, 'a_test.dart (setUpAll)', <int>[1, 2], 0),
      _done(3, 'error', 5, hidden: true),
      _start(4, 0, 'a_test.dart ok', <int>[1, 2], 5),
      _done(4, 'success', 6),
    ], testDir: _testDir);

    expect(results['a_test.dart']!.passed, isFalse);
  });

  test('maps unbundled suites to their path relative to test/', () {
    final Map<String, FileResult> results = parseResults(<String>[
      _suite(0, '$_testDir/features/c_test.dart'),
      _start(1, 0, 'loading features/c_test.dart', <int>[], 0),
      _done(1, 'success', 10, hidden: true),
      _group(2, 0, null),
      _start(3, 0, 'works', <int>[2], 10),
      _done(3, 'success', 20),
    ], testDir: _testDir);

    expect(results.keys, <String>['features/c_test.dart']);
    expect(results['features/c_test.dart']!.passed, isTrue);
  });

  test('an async error reported after testDone fails the file', () {
    final Map<String, FileResult> results = parseResults(<String>[
      _suite(0, '$_testDir/.bundle/shard_0.dart'),
      _group(1, 0, null),
      _group(2, 0, 'a_test.dart'),
      _start(3, 0, 'a_test.dart leaks', <int>[1, 2], 0),
      _done(3, 'success', 5),
      _e(<String, Object?>{'type': 'error', 'testID': 3, 'time': 6}),
    ], testDir: _testDir);

    expect(results['a_test.dart']!.passed, isFalse);
  });

  test('a suite that fails to load leaves its files out', () {
    final Map<String, FileResult> results = parseResults(<String>[
      _suite(0, '$_testDir/.bundle/shard_0.dart'),
      _start(1, 0, 'loading shard_0.dart', <int>[], 0),
      _done(1, 'error', 10),
    ], testDir: _testDir);

    expect(results, isEmpty);
  });

  test('failedLoads names suites whose loading test errored', () {
    expect(
      failedLoads(<String>[
        _suite(0, '$_testDir/.bundle/shard_0.dart'),
        _start(1, 0, 'loading shard_0.dart', <int>[], 0),
        _done(1, 'error', 10, hidden: true),
        _suite(2, '$_testDir/.bundle/shard_1.dart'),
        _start(3, 2, 'loading shard_1.dart', <int>[], 0),
        _done(3, 'success', 10, hidden: true),
      ], testDir: _testDir),
      <String>{'.bundle/shard_0.dart'},
    );
  });

  test('filesToRerun takes failed bundled files and whole unloaded shards', () {
    final Map<String, FileResult> results = <String, FileResult>{
      'a_test.dart': FileResult(),
      'b_test.dart': FileResult()..passed = false,
      'solo_test.dart': FileResult()..passed = false,
    };

    expect(
      filesToRerun(
        results,
        shards: const <String, List<String>>{
          '.bundle/shard_0.dart': <String>['a_test.dart', 'b_test.dart'],
          '.bundle/shard_1.dart': <String>['c_test.dart', 'd_test.dart'],
        },
        failedLoads: const <String>{'.bundle/shard_1.dart'},
      ),
      <String>['b_test.dart', 'c_test.dart', 'd_test.dart'],
    );
  });
}
