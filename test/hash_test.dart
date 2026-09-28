import 'dart:io';

import 'package:elek/src/hash.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('directiveUris', () {
    test('collects imports, exports, parts and both conditional branches', () {
      const String source = '''
import 'dart:io';
import 'package:app/a.dart';
import "b.dart" show B;
export 'c.dart';
part 'd.g.dart';
import 'stub.dart'
    if (dart.library.io) 'native.dart';
// import 'commented.dart';
''';

      expect(directiveUris(source), <String>[
        'package:app/a.dart',
        'b.dart',
        'c.dart',
        'd.g.dart',
        'stub.dart',
        'native.dart',
      ]);
    });
  });

  group('DartDeps.closure', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('deps_test'));
    tearDown(() => root.deleteSync(recursive: true));

    String write(String rel, String content) {
      final File f = File(p.join(root.path, rel))
        ..createSync(recursive: true)
        ..writeAsStringSync(content);
      return p.normalize(f.path);
    }

    test('follows package, relative and part directives transitively', () {
      final String t = write(
        'app/test/a_test.dart',
        "import 'package:app/x.dart';\nimport 'helper.dart';\n",
      );
      final String helper = write('app/test/helper.dart', '');
      final String x = write('app/lib/x.dart', "part 'x.g.dart';\n");
      final String xg = write('app/lib/x.g.dart', "part of 'x.dart';\n");
      write('app/lib/unrelated.dart', '');

      final DartDeps deps = DartDeps(<String, String>{
        'app': p.join(root.path, 'app/lib'),
      });

      expect(deps.closure(t), <String>{t, helper, x, xg});
    });

    test('follows exports, including conditional ones', () {
      final String t = write('a_test.dart', "import 'a.dart';\n");
      final String a = write(
        'a.dart',
        "export 'src/stub.dart'\n    if (dart.library.io) 'src/io.dart';\n",
      );
      final String stub = write('src/stub.dart', "export 'deep.dart';\n");
      final String io = write('src/io.dart', '');
      final String deep = write('src/deep.dart', '');

      expect(DartDeps(const <String, String>{}).closure(t), <String>{
        t,
        a,
        stub,
        io,
        deep,
      });
    });

    test('skips packages it has no root for and missing files', () {
      final String t = write(
        'a_test.dart',
        "import 'package:hosted/h.dart';\nimport 'gone.dart';\n",
      );

      expect(DartDeps(const <String, String>{}).closure(t), <String>{t});
    });
  });

  group('InputHasher', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('hash_test'));
    tearDown(() => root.deleteSync(recursive: true));

    test('changes when any input changes and ignores input order', () {
      final File a = File(p.join(root.path, 'a.dart'))..writeAsStringSync('a');
      final File b = File(p.join(root.path, 'b.dart'))..writeAsStringSync('b');

      final String first = InputHasher(
        root.path,
      ).digest(<String>[a.path, b.path]);
      final String reordered = InputHasher(
        root.path,
      ).digest(<String>[b.path, a.path]);
      b.writeAsStringSync('b2');
      final String changed = InputHasher(
        root.path,
      ).digest(<String>[a.path, b.path]);

      expect(reordered, first);
      expect(changed, isNot(first));
    });

    test('changes with the extra input', () {
      final File a = File(p.join(root.path, 'a.dart'))..writeAsStringSync('a');
      final InputHasher hasher = InputHasher(root.path);

      expect(
        hasher.digest(<String>[a.path], extra: 'Europe/Istanbul'),
        isNot(hasher.digest(<String>[a.path], extra: 'UTC')),
      );
    });
  });

  group('pathPackages', () {
    test('returns the packages the lockfile resolved from a path', () {
      const String lock = '''
packages:
  args:
    dependency: transitive
    description:
      name: args
      url: "https://pub.dev"
    source: hosted
    version: "2.7.0"
  flutter:
    dependency: "direct main"
    description: flutter
    source: sdk
    version: "0.0.0"
  shared:
    dependency: "direct main"
    description:
      path: "../shared"
      relative: true
    source: path
    version: "0.0.0"
sdks:
  dart: ">=3.8.0 <4.0.0"
''';

      expect(pathPackages(lock), <String>{'shared'});
    });
  });

  group('readPackageRoots', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('roots_test'));
    tearDown(() => root.deleteSync(recursive: true));

    test('keeps workspace packages and named path packages outside it', () {
      final File config =
          File(p.join(root.path, 'ws', '.dart_tool', 'package_config.json'))
            ..createSync(recursive: true)
            ..writeAsStringSync('''
{"configVersion": 2, "packages": [
  {"name": "app", "rootUri": "../app", "packageUri": "lib/"},
  {"name": "shared", "rootUri": "../../shared", "packageUri": "lib/"},
  {"name": "args", "rootUri": "../../cache/args", "packageUri": "lib/"}
]}''');

      expect(
        readPackageRoots(
          config,
          within: p.join(root.path, 'ws'),
          pathPackages: <String>{'shared'},
        ),
        <String, String>{
          'app': p.join(root.path, 'ws', 'app', 'lib'),
          'shared': p.join(root.path, 'shared', 'lib'),
        },
      );
    });
  });
}
