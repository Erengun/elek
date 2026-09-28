import 'dart:io';

import 'package:elek/src/run_lock.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('lock_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  // fcntl locks are per process, so the second holder has to be another one.
  Future<ProcessResult> lockFromChild(String path) {
    final File script = File(p.join(dir.path, 'child.dart'))
      ..writeAsStringSync('''
import 'package:elek/src/run_lock.dart';
void main() => print(tryRunLock(r'$path') == null ? 'busy' : 'locked');
''');
    return Process.run(Platform.resolvedExecutable, <String>[
      '--packages=${p.absolute('.dart_tool', 'package_config.json')}',
      script.path,
    ]);
  }

  test('a second process cannot take a held lock', () async {
    final String path = p.join(dir.path, 'run.lock');
    final RandomAccessFile? held = tryRunLock(path);
    expect(held, isNotNull);

    expect((await lockFromChild(path)).stdout, contains('busy'));

    held!.closeSync();
    expect((await lockFromChild(path)).stdout, contains('locked'));
  });
}
