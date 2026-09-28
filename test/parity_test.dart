import 'dart:convert';

import 'package:elek/src/parity.dart';
import 'package:test/test.dart';

const String _testDir = '/repo/app/test';

String _e(Map<String, Object?> event) => jsonEncode(event);

String _suite(int id, String path) => _e(<String, Object?>{
  'type': 'suite',
  'suite': <String, Object?>{'id': id, 'path': path},
});

String _group(int id, String? name) => _e(<String, Object?>{
  'type': 'group',
  'group': <String, Object?>{'id': id, 'name': name},
});

String _start(int id, int suiteId, String name, List<int> groups) =>
    _e(<String, Object?>{
      'type': 'testStart',
      'time': 0,
      'test': <String, Object?>{
        'id': id,
        'suiteID': suiteId,
        'name': name,
        'groupIDs': groups,
      },
    });

String _done(
  int id,
  String result, {
  bool hidden = false,
  bool skipped = false,
}) => _e(<String, Object?>{
  'type': 'testDone',
  'testID': id,
  'result': result,
  'hidden': hidden,
  'skipped': skipped,
  'time': 1,
});

String _error(int id, [String error = 'late']) =>
    _e(<String, Object?>{'type': 'error', 'testID': id, 'error': error});

void main() {
  test('plain and bundled runs of the same tests canonicalize equally', () {
    final List<String> plain = canonicalResults(<String>[
      _suite(0, '$_testDir/core/a_test.dart'),
      _start(1, 0, 'loading a_test.dart', <int>[]),
      _done(1, 'success', hidden: true),
      _group(2, null),
      _group(3, 'inner'),
      _start(4, 0, 'inner works', <int>[2, 3]),
      _done(4, 'success'),
      _start(5, 0, 'skipped one', <int>[2]),
      _done(5, 'success', skipped: true),
      _suite(6, '$_testDir/b_test.dart'),
      _group(7, null),
      _start(8, 6, 'fails', <int>[7]),
      _done(8, 'failure'),
    ], testDir: _testDir);
    final List<String> bundled = canonicalResults(<String>[
      _suite(0, '$_testDir/.bundle/shard_0.dart'),
      _start(1, 0, 'loading shard_0.dart', <int>[]),
      _done(1, 'success', hidden: true),
      _group(2, null),
      _group(3, 'b_test.dart'),
      _start(4, 0, 'b_test.dart fails', <int>[2, 3]),
      _done(4, 'failure'),
      _group(5, 'core/a_test.dart'),
      _group(6, 'core/a_test.dart inner'),
      _start(7, 0, 'core/a_test.dart inner works', <int>[2, 5, 6]),
      _done(7, 'success'),
      _start(8, 0, 'core/a_test.dart skipped one', <int>[2, 5]),
      _done(8, 'success', skipped: true),
    ], testDir: _testDir);

    expect(plain, <String>[
      'b_test.dart :: fails  FAIL',
      'core/a_test.dart :: inner works  PASS',
      'core/a_test.dart :: skipped one  SKIP',
    ]);
    expect(bundled, plain);
  });

  test('a late error fails a test that reported success', () {
    expect(
      canonicalResults(<String>[
        _suite(0, '$_testDir/a_test.dart'),
        _group(1, null),
        _start(2, 0, 'x', <int>[1]),
        _done(2, 'success'),
        _error(2),
      ], testDir: _testDir),
      <String>['a_test.dart :: x  FAIL'],
    );
  });

  test('failed loads and hidden hook failures are kept, passing ones not', () {
    expect(
      canonicalResults(<String>[
        _suite(0, '$_testDir/a_test.dart'),
        _start(1, 0, 'loading a_test.dart', <int>[]),
        _done(1, 'error', hidden: true),
        _suite(2, '$_testDir/b_test.dart'),
        _group(3, null),
        _start(4, 2, '(tearDownAll)', <int>[3]),
        _done(4, 'error', hidden: true),
      ], testDir: _testDir),
      <String>[
        'a_test.dart :: loading a_test.dart  FAIL',
        'b_test.dart :: (tearDownAll)  FAIL',
      ],
    );
  });

  test('repeated names in one file stay distinct', () {
    expect(
      canonicalResults(<String>[
        _suite(0, '$_testDir/a_test.dart'),
        _group(1, null),
        _start(2, 0, 'same', <int>[1]),
        _done(2, 'success'),
        _start(3, 0, 'same', <int>[1]),
        _done(3, 'failure'),
      ], testDir: _testDir),
      <String>['a_test.dart :: same  FAIL', 'a_test.dart :: same  PASS'],
    );
  });

  group('failedTests', () {
    test('keeps each failure with its message, bundled or not', () {
      final List<FailedTest> failures = failedTests(<String>[
        _suite(0, '$_testDir/.bundle/shard_0.dart'),
        _group(1, null),
        _group(2, 'cart/cart_test.dart'),
        _start(3, 0, 'cart/cart_test.dart adds item', <int>[1, 2]),
        _error(3, 'Expected: <4>\n  Actual: <5>'),
        _done(3, 'failure'),
        _start(4, 0, 'cart/cart_test.dart passes', <int>[1, 2]),
        _done(4, 'success'),
      ], testDir: _testDir);

      expect(failures, hasLength(1));
      expect(failures.single.file, 'cart/cart_test.dart');
      expect(failures.single.name, 'adds item');
      expect(failures.single.message, 'Expected: <4>\n  Actual: <5>');
    });

    test('reports a suite that failed to load', () {
      final List<FailedTest> failures = failedTests(<String>[
        _suite(0, '$_testDir/a_test.dart'),
        _start(1, 0, 'loading $_testDir/a_test.dart', <int>[]),
        _error(1, "a_test.dart:3:7: Error: Undefined name 'x'."),
        _done(1, 'error', hidden: true),
      ], testDir: _testDir);

      expect(failures.single.file, 'a_test.dart');
      expect(failures.single.name, 'failed to load');
      expect(failures.single.message, contains("Undefined name 'x'"));
    });
  });

  group('formatFailures', () {
    test('lists file and test, and cuts long messages', () {
      final String out = formatFailures(<FailedTest>[
        (
          file: 'a_test.dart',
          name: 'works',
          message: List<String>.generate(20, (int i) => 'line $i').join('\n'),
        ),
      ]);

      expect(
        out,
        startsWith('elek: 1 failing test\n  test/a_test.dart :: works\n'),
      );
      expect(out, contains('    line 0\n'));
      expect(out, isNot(contains('line 19')));
      expect(out, contains('    ...'));
    });
  });
}
