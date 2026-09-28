import 'package:elek/src/bundle.dart';
import 'package:test/test.dart';

void main() {
  group('balanceShards', () {
    test('puts the heaviest files in different shards', () {
      final Map<String, int> weights = <String, int>{
        'a_test.dart': 100,
        'b_test.dart': 90,
        'c_test.dart': 10,
        'd_test.dart': 5,
      };

      final List<List<String>> shards = balanceShards(
        weights.keys.toList(),
        2,
        (String f) => weights[f]!,
      );

      expect(shards, <List<String>>[
        <String>['a_test.dart', 'd_test.dart'],
        <String>['b_test.dart', 'c_test.dart'],
      ]);
    });

    test('never returns empty shards', () {
      final List<List<String>> shards = balanceShards(
        <String>['a_test.dart'],
        4,
        (String _) => 1,
      );

      expect(shards, <List<String>>[
        <String>['a_test.dart'],
      ]);
    });
  });

  group('skipExpressionFor', () {
    test('maps OS platform selectors to Platform checks', () {
      expect(
        skipExpressionFor('mac-os || linux'),
        '!(Platform.isMacOS || Platform.isLinux)',
      );
    });

    test('returns null for selectors it cannot express', () {
      expect(skipExpressionFor('browser'), isNull);
    });
  });

  group('bundleEntryFor', () {
    test('plain test file bundles without a skip', () {
      final BundleEntry? entry = bundleEntryFor(
        'core/a_test.dart',
        "import 'package:test/test.dart';\nvoid main() {}\n",
      );

      expect(entry?.path, 'core/a_test.dart');
      expect(entry?.skip, isNull);
    });

    test('@TestOn becomes a Platform skip', () {
      final BundleEntry? entry = bundleEntryFor(
        'core/a_test.dart',
        "@TestOn('mac-os || linux')\nlibrary;\n\nvoid main() {}\n",
      );

      expect(entry?.skip, '!(Platform.isMacOS || Platform.isLinux)');
    });

    test('golden tests are bundled; the shard rebases the comparator', () {
      expect(
        bundleEntryFor(
          'a_test.dart',
          "void main() { expect(x, matchesGoldenFile('g.png')); }",
        ),
        isNotNull,
      );
    });

    test('an async main needs a standalone run: groups must be sync', () {
      for (final String main in <String>[
        'Future<void> main() async {}',
        'void main() async {}',
        'Future<void> main() => setUp();',
        'FutureOr<void> main() {}',
      ]) {
        expect(bundleEntryFor('a_test.dart', main), isNull, reason: main);
      }
      expect(bundleEntryFor('a_test.dart', 'void main() {}'), isNotNull);
    });

    test('other library annotations need a standalone run', () {
      expect(
        bundleEntryFor('a_test.dart', "@Tags(<String>['slow'])\nlibrary;\n"),
        isNull,
      );
      expect(
        bundleEntryFor('a_test.dart', "@TestOn('browser')\nlibrary;\n"),
        isNull,
      );
    });
  });

  test('renderShard imports each file under a prefix and groups by path', () {
    final String source = renderShard(const <BundleEntry>[
      BundleEntry('core/a_test.dart'),
      BundleEntry('features/b_test.dart', skip: '!(Platform.isLinux)'),
    ], flutter: true);

    expect(source, contains("import '../core/a_test.dart' as t0;"));
    expect(source, contains("import '../features/b_test.dart' as t1;"));
    expect(source, contains("group('core/a_test.dart', () {"));
    expect(source, contains('t0.main();'));
    expect(source, contains('  }, skip: !(Platform.isLinux));'));
  });

  test('renderShard points goldens of each Flutter file at its own dir', () {
    final String source = renderShard(const <BundleEntry>[
      BundleEntry('core/a_test.dart'),
    ], flutter: true);

    expect(source, contains("_rebaseGoldens(root, '../core/a_test.dart')"));
    expect(source, contains('LocalFileComparator'));
  });

  test('renderShard uses package:test for pure Dart packages', () {
    final String source = renderShard(const <BundleEntry>[
      BundleEntry('a_test.dart'),
    ], flutter: false);

    expect(source, contains("import 'package:test/test.dart';"));
    expect(source, isNot(contains('flutter_test')));
    expect(source, isNot(contains('Goldens')));
  });
}
