import 'package:elek/src/options.dart';
import 'package:test/test.dart';

void main() {
  test('cache is on locally and off under CI', () {
    expect(RunnerOptions.parse(const <String>[]).noCache, isFalse);
    expect(
      RunnerOptions.parse(
        const <String>[],
        environment: const <String, String>{'CI': 'true'},
      ).noCache,
      isTrue,
    );
  });

  test('--cache opts back in under CI', () {
    expect(
      RunnerOptions.parse(
        const <String>['--cache'],
        environment: const <String, String>{'CI': 'true'},
      ).noCache,
      isFalse,
    );
  });

  test('arguments after -- go to the test command', () {
    final RunnerOptions o = RunnerOptions.parse(const <String>[
      '--shards',
      '3',
      '--',
      '--name',
      'x',
    ]);

    expect(o.shards, 3);
    expect(o.testArgs, <String>['--name', 'x']);
  });

  test('test arguments turn the cache off so a filtered file still runs', () {
    expect(
      RunnerOptions.parse(const <String>[
        '--cache',
        '--',
        '--name',
        'x',
      ]).noCache,
      isTrue,
    );
  });
}
