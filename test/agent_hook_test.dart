import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../agent/hooks/elek_hook.dart';

void main() {
  late Directory dir;
  late File state;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('hook_test');
    state = File(p.join(dir.path, 'state.json'));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  group('editedPaths', () {
    test('reads Claude file paths', () {
      expect(
        editedPaths(<String, Object?>{
          'tool_name': 'Edit',
          'tool_input': <String, Object?>{'file_path': '/repo/lib/a.dart'},
        }),
        <String>['/repo/lib/a.dart'],
      );
    });

    test('reads every file header of a Codex apply_patch', () {
      const String patch = '''
*** Begin Patch
*** Update File: lib/a.dart
@@
-old
+new
*** Add File: test/b_test.dart
+void main() {}
*** Delete File: lib/c.dart
*** Update File: lib/d.dart
*** Move to: lib/e.dart
*** End Patch''';

      expect(
        editedPaths(<String, Object?>{
          'tool_name': 'apply_patch',
          'tool_input': <String, Object?>{'command': patch},
        }),
        <String>[
          'lib/a.dart',
          'test/b_test.dart',
          'lib/c.dart',
          'lib/d.dart',
          'lib/e.dart',
        ],
      );
    });
  });

  test('isSourceEdit ignores build output and hidden directories', () {
    expect(isSourceEdit('/repo/lib/a.dart'), isTrue);
    expect(isSourceEdit('../shared/lib/a.dart'), isTrue);
    expect(isSourceEdit('/repo/build/app.js'), isFalse);
    expect(isSourceEdit('/repo/.dart_tool/x.json'), isFalse);
    expect(isSourceEdit(r'C:\repo\.git\config'), isFalse);
  });

  group('mark', () {
    test('marks the session dirty only for source edits', () {
      mark(<String, Object?>{
        'tool_name': 'Write',
        'tool_input': <String, Object?>{'file_path': '/repo/.idea/x.xml'},
      }, state);
      expect(readState(state).dirty, isFalse);

      final HookResult r = mark(<String, Object?>{
        'tool_name': 'Write',
        'tool_input': <String, Object?>{'file_path': '/repo/lib/a.dart'},
      }, state);
      expect(readState(state).dirty, isTrue);
      expect(r.stdout, isNull);
      expect(r.code, 0);
    });
  });

  test('usesElek looks only at dev_dependencies', () {
    expect(
      usesElek('dev_dependencies:\n  test: any\n  elek:\n    git: x\n'),
      isTrue,
    );
    expect(
      usesElek('dependencies:\n  elek: any\ndev_dependencies:\n  test: any\n'),
      isFalse,
    );
  });

  test('elekPackages finds packages that use elek', () {
    void pubspec(String rel, String content) =>
        File(p.join(dir.path, rel, 'pubspec.yaml'))
          ..createSync(recursive: true)
          ..writeAsStringSync(content);
    pubspec('app', 'name: app\ndev_dependencies:\n  elek: any\n');
    pubspec('core', 'name: core\ndev_dependencies:\n  test: any\n');
    Process.runSync('git', <String>['init', '-q'], workingDirectory: dir.path);

    expect(elekPackages(dir.path), <String>['app']);
  });

  group('verify', () {
    final Map<String, Object?> input = <String, Object?>{'cwd': '/repo'};
    List<String> onePackage(String _) => <String>['app'];
    ElekRunner returning(int code, String output) =>
        (String _) async => (code: code, output: output);

    test('does nothing when the session edited nothing', () async {
      final HookResult r = await verify(
        input,
        state,
        run: (String _) => fail('ran elek'),
        packages: onePackage,
      );
      expect(r, (code: 0, stdout: null, stderr: null));
    });

    test('passes, clears the flag and tells the user', () async {
      writeState(state, dirty: true, attempts: 1);
      final HookResult r = await verify(
        input,
        state,
        run: returning(0, '2/6 test files to run\nok\n'),
        packages: onePackage,
      );
      expect(r.code, 0);
      expect(
        (jsonDecode(r.stdout!) as Map<String, Object?>)['systemMessage'],
        'elek: passed in app (2/6 test files to run)',
      );
      expect(readState(state), (dirty: false, attempts: 0));
    });

    test(
      'blocks with the failure block, then gives up after 3 tries',
      () async {
        writeState(state, dirty: true, attempts: 0);
        final ElekRunner failing = returning(
          1,
          '1/6 test files to run\nnoise\n\nelek: 1 failing test\n'
          '  test/a_test.dart :: works\n    Expected: <4>\n',
        );

        for (int attempt = 1; attempt < maxAttempts; attempt++) {
          final HookResult r = await verify(
            input,
            state,
            run: failing,
            packages: onePackage,
          );
          expect(r.code, 0);
          final Map<String, Object?> out =
              jsonDecode(r.stdout!) as Map<String, Object?>;
          expect(out['decision'], 'block');
          final String reason = out['reason']! as String;
          expect(reason, contains('Elek verification failed in app.'));
          expect(reason, contains('test/a_test.dart :: works'));
          expect(reason, isNot(contains('noise')));
        }

        final HookResult last = await verify(
          input,
          state,
          run: failing,
          packages: onePackage,
        );
        expect(last.code, 0);
        expect(
          (jsonDecode(last.stdout!) as Map<String, Object?>)['systemMessage'],
          contains('still fails'),
        );
        expect(readState(state), (dirty: false, attempts: 0));
      },
    );

    test('does not block when another elek run holds the lock', () async {
      writeState(state, dirty: true, attempts: 0);
      final HookResult r = await verify(
        input,
        state,
        run: returning(
          1,
          'Another elek run is already active in this package.',
        ),
        packages: onePackage,
      );
      expect(r.code, 0);
      expect(readState(state).dirty, isTrue);
    });
  });

  test('truncate caps long reasons', () {
    expect(truncate('x' * 10, 4), 'xxxx\n... (truncated)');
    expect(truncate('short'), 'short');
  });
}
