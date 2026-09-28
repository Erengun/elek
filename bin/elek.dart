// Bundled test runner with a local green-hash cache. Run from a package dir;
// flags in RunnerOptions.parse. A file is skipped when the hash of its import
// closure + salt already passed.
import 'dart:convert';
import 'dart:io';

import 'package:elek/src/bundle.dart';
import 'package:elek/src/hash.dart';
import 'package:elek/src/options.dart';
import 'package:elek/src/pubspec.dart';
import 'package:elek/src/results.dart';
import 'package:elek/src/run_lock.dart';
import 'package:elek/src/test_dir.dart';
import 'package:path/path.dart' as p;

// At or below this many files, bundling saves nothing; run them directly.
const int _directRunMax = 3;

Future<void> main(List<String> args) async {
  final RunnerOptions o = RunnerOptions.parse(
    args,
    environment: Platform.environment,
  );
  final String pkgDir = Directory.current.path;
  final String testDir = p.join(pkgDir, 'test');
  final String bundleDir = p.join(testDir, '.bundle');
  final String workDir = p.join(pkgDir, '.dart_tool', 'elek');
  final String store = o.store ?? p.join(workDir, 'green');
  final bool flutter = usesFlutter(
    File(p.join(pkgDir, 'pubspec.yaml')).readAsStringSync(),
  );

  final List<String> tests = _discover(testDir);
  final Map<String, String> hashes = _hashAll(pkgDir, testDir, tests, flutter);
  final List<String> toRun = o.noCache
      ? tests
      : <String>[
          for (final String t in tests)
            if (!File(p.join(store, hashes[t])).existsSync()) t,
        ];

  stdout.writeln(
    '${toRun.length}/${tests.length} test files to run'
    '${o.noCache ? ' (--no-cache)' : ' (rest unchanged since last green run)'}',
  );
  if (o.dryRun) {
    toRun.forEach(stdout.writeln);
    return;
  }
  if (toRun.isEmpty) return;

  Directory(workDir).createSync(recursive: true);
  // Runs share test/.bundle and the results files; the lock lives until exit.
  if (tryRunLock(p.join(workDir, 'run.lock')) == null) {
    stderr.writeln('Another elek run is already active in this package.');
    exit(1);
  }

  final File durationsFile = File(p.join(store, 'durations.json'));
  final Map<String, int> durations = _readDurations(durationsFile);
  final (
    List<String> targets,
    Map<String, List<String>> shards,
  ) = _prepareTargets(
    toRun,
    testDir: testDir,
    bundleDir: bundleDir,
    shards: o.shards,
    flutter: flutter,
    weight: (String f) => durations[f] ?? File(p.join(testDir, f)).lengthSync(),
  );

  final File resultsFile = File(p.join(workDir, 'results.json'));
  // 79 = "no tests ran": the cache can leave only files without tests to run.
  // Without skipped files it means a filter matched nothing; keep it.
  int code = switch (await _test(flutter, o.testArgs, targets, resultsFile)) {
    79 when toRun.length < tests.length => 0,
    final int c => c,
  };
  if (Directory(bundleDir).existsSync()) {
    Directory(bundleDir).deleteSync(recursive: true);
  }
  final List<String> lines = resultsFile.existsSync()
      ? resultsFile.readAsLinesSync()
      : const <String>[];
  final Map<String, FileResult> results = parseResults(lines, testDir: testDir);
  final Set<String> unloaded = failedLoads(lines, testDir: testDir);
  final List<String> rerun = code == 0
      ? const <String>[]
      : filesToRerun(results, shards: shards, failedLoads: unloaded);
  if (rerun.isNotEmpty) {
    code = await _rerunAlone(
      rerun,
      results,
      code: code,
      failedOutside:
          results.entries.any(
            (MapEntry<String, FileResult> e) =>
                !e.value.passed && !rerun.contains(e.key),
          ) ||
          unloaded.any((String s) => !shards.containsKey(s)),
      flutter: flutter,
      testArgs: o.testArgs,
      testDir: testDir,
      workDir: workDir,
    );
  }

  // Test args can run a subset or a different config, so such a run must not
  // vouch for whole files; RunnerOptions turns the cache off for them.
  if (o.testArgs.isNotEmpty) {
    stdout.writeln('not caching: run used extra test arguments');
  } else if (resultsFile.existsSync()) {
    _persistGreen(
      results,
      toRun: toRun,
      hashes: hashes,
      store: store,
      durations: durations,
      durationsFile: durationsFile,
      loadedAll: code == 0,
    );
  }
  exit(code);
}

/// Runs the test command on [targets], writing JSON results to [results].
Future<int> _test(
  bool flutter,
  List<String> testArgs,
  List<String> targets,
  File results,
) async {
  // A stale file would be read as this run's results if flutter dies early.
  if (results.existsSync()) results.deleteSync();
  final Process runner = await Process.start(
    flutter ? 'flutter' : 'dart',
    <String>[
      'test',
      if (flutter) '--no-pub',
      '--file-reporter',
      'json:${results.path}',
      ...testArgs,
      ...targets,
    ],
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  return runner.exitCode;
}

/// Reruns [files] one suite each; their standalone verdicts replace the
/// bundled ones in [results]. Returns the run's exit code: the rerun's, unless
/// something outside [files] also failed.
Future<int> _rerunAlone(
  List<String> files,
  Map<String, FileResult> results, {
  required int code,
  required bool failedOutside,
  required bool flutter,
  required List<String> testArgs,
  required String testDir,
  required String workDir,
}) async {
  stdout.writeln(
    '${files.length} bundled test files failed; rerunning them alone, since '
    'state leaked from a shard neighbor can fail a file only when bundled.',
  );
  final File rerunFile = File(p.join(workDir, 'results_rerun.json'));
  final int rerunCode = await _test(flutter, testArgs, <String>[
    for (final String f in files) p.join(testDir, f),
  ], rerunFile);
  final Map<String, FileResult> alone = rerunFile.existsSync()
      ? parseResults(rerunFile.readAsLinesSync(), testDir: testDir)
      : <String, FileResult>{};
  for (final String f in files) {
    if (results[f]?.passed == false && alone[f]?.passed == true) {
      stdout.writeln(
        'note: $f failed bundled but passes alone; it likely shares global '
        'state with another test file.',
      );
    }
    results.remove(f);
    if (alone[f] case final FileResult r) results[f] = r;
  }
  if (failedOutside) return code;
  return rerunCode == 79 ? 0 : rerunCode;
}

/// `*_test.dart` paths relative to [testDir], excluding generated bundles.
List<String> _discover(String testDir) =>
    <String>[
        for (final FileSystemEntity e in Directory(
          testDir,
        ).listSync(recursive: true))
          if (e is File && e.path.endsWith('_test.dart'))
            // `/` everywhere: these become Dart import URIs and group names.
            p.split(p.relative(e.path, from: testDir)).join('/'),
      ]
      ..removeWhere((String f) => p.isWithin('.bundle', f))
      ..sort();

Map<String, String> _hashAll(
  String pkgDir,
  String testDir,
  List<String> tests,
  bool flutter,
) {
  final File config = _findPackageConfig(pkgDir);
  final String workspace = p.dirname(p.dirname(config.path));
  final File lock = File(p.join(workspace, 'pubspec.lock'));
  final Map<String, String> roots = readPackageRoots(
    config,
    within: workspace,
    pathPackages: lock.existsSync()
        ? pathPackages(lock.readAsStringSync())
        : const <String>{},
  );
  final DartDeps deps = DartDeps(roots);
  final InputHasher hasher = InputHasher(workspace);
  // Salt .dart files (test config, this runner) bring their imports along.
  final Set<String> salt = <String>{
    for (final String f in _salt(pkgDir, workspace, roots, flutter))
      ...(f.endsWith('.dart') ? deps.closure(f) : <String>{f}),
  };
  final String env = _environment(flutter);
  return <String, String>{
    for (final String t in tests)
      t: hasher.digest(<String>{
        ...deps.closure(p.join(testDir, t)),
        if (nearestTestConfig(testDir, t) case final String config)
          ...deps.closure(config),
        ...salt,
      }, extra: env),
  };
}

File _findPackageConfig(String from) {
  String dir = from;
  while (true) {
    final File f = File(p.join(dir, '.dart_tool', 'package_config.json'));
    if (f.existsSync()) return f;
    final String parent = p.dirname(dir);
    if (parent == dir) {
      throw StateError('No .dart_tool/package_config.json; run pub get.');
    }
    dir = parent;
  }
}

/// Inputs every test depends on but no import shows: dependency versions,
/// the Flutter SDK, declared assets, test data files and this runner itself.
List<String> _salt(
  String pkgDir,
  String workspace,
  Map<String, String> roots,
  bool flutter,
) {
  final String pubspec = p.join(pkgDir, 'pubspec.yaml');
  final String? runnerLib = roots['elek'];
  final List<String> candidates = <String>[
    pubspec,
    p.join(workspace, 'pubspec.yaml'),
    p.join(workspace, 'pubspec.lock'),
    p.join(pkgDir, 'l10n.yaml'),
    p.join(pkgDir, 'dart_test.yaml'),
    ...testDataFiles(p.join(pkgDir, 'test')),
    if (flutter) ?_flutterVersionFile(),
    if (runnerLib != null) p.join(p.dirname(runnerLib), 'bin', 'elek.dart'),
    for (final String asset in declaredAssets(File(pubspec).readAsStringSync()))
      ..._filesAt(p.join(pkgDir, asset)),
  ];
  return <String>[
    for (final String f in candidates)
      if (File(f).existsSync()) f,
  ];
}

List<String> _filesAt(String path) => Directory(path).existsSync()
    ? <String>[
        for (final FileSystemEntity e in Directory(
          path,
        ).listSync(recursive: true))
          if (e is File) e.path,
      ]
    : <String>[path];

// `dart run` executes <flutter>/bin/cache/dart-sdk/bin/dart.
String? _flutterVersionFile() {
  final String cache = p.dirname(
    p.dirname(p.dirname(Platform.resolvedExecutable)),
  );
  final File f = File(p.join(cache, 'flutter.version.json'));
  return f.existsSync() ? f.path : null;
}

/// Host facts tests can observe without importing them. The time zone offset
/// flips with DST, which is the point: date tests break exactly then.
String _environment(bool flutter) {
  final DateTime now = DateTime.now();
  return <String>[
    Platform.version,
    Platform.localeName,
    now.timeZoneName,
    '${now.timeZoneOffset}',
    if (flutter && _flutterVersionFile() == null) _flutterRevision(),
  ].join('\n');
}

String _flutterRevision() {
  final ProcessResult r = Process.runSync('flutter', <String>[
    '--version',
    '--machine',
  ], runInShell: Platform.isWindows);
  if (r.exitCode == 0) {
    try {
      final Object? v =
          (jsonDecode(r.stdout as String)
              as Map<String, Object?>)['frameworkRevision'];
      if (v is String) return v;
    } on FormatException {
      // Falls through to the warning.
    }
  }
  stderr.writeln(
    'warning: Flutter version unknown; SDK upgrades will not invalidate the '
    'test cache. Use --no-cache after upgrading Flutter.',
  );
  return '';
}

/// Writes shard entrypoints. Returns the paths to hand to the test command and
/// each shard's files, keyed by shard path relative to [testDir].
(List<String>, Map<String, List<String>>) _prepareTargets(
  List<String> toRun, {
  required String testDir,
  required String bundleDir,
  required int shards,
  required bool flutter,
  required int Function(String file) weight,
}) {
  if (toRun.length <= _directRunMax) {
    return (
      <String>[for (final String f in toRun) p.join(testDir, f)],
      const <String, List<String>>{},
    );
  }
  final Map<String, BundleEntry> bundled = <String, BundleEntry>{};
  final List<String> standalone = <String>[];
  // A shard in `.bundle/` resolves to the root config, not a nested one.
  final String? shardConfig = nearestTestConfig(testDir, '.bundle/shard.dart');
  for (final String f in toRun) {
    if (nearestTestConfig(testDir, f) != shardConfig) {
      stderr.writeln(
        'note: $f has its own flutter_test_config; running it alone.',
      );
      standalone.add(p.join(testDir, f));
      continue;
    }
    final BundleEntry? entry = bundleEntryFor(
      f,
      File(p.join(testDir, f)).readAsStringSync(),
    );
    if (entry == null) {
      stderr.writeln(
        'note: $f has library annotations or an async main; running it alone.',
      );
      standalone.add(p.join(testDir, f));
    } else {
      bundled[f] = entry;
    }
  }

  final Directory dir = Directory(bundleDir);
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  final List<List<String>> groups = balanceShards(
    bundled.keys.toList(),
    shards,
    weight,
  );
  final List<String> targets = <String>[];
  final Map<String, List<String>> shardFiles = <String, List<String>>{};
  for (int i = 0; i < groups.length; i++) {
    shardFiles['.bundle/shard_$i.dart'] = groups[i];
    final File shard = File(p.join(bundleDir, 'shard_$i.dart'))
      ..writeAsStringSync(
        renderShard(<BundleEntry>[
          for (final String f in groups[i]) bundled[f]!,
        ], flutter: flutter),
      );
    targets.add(shard.path);
  }
  return (<String>[...targets, ...standalone], shardFiles);
}

Map<String, int> _readDurations(File file) {
  if (!file.existsSync()) return <String, int>{};
  try {
    return (jsonDecode(file.readAsStringSync()) as Map<String, Object?>).map(
      (String k, Object? v) => MapEntry<String, int>(k, v! as int),
    );
    // Only a shard-balancing hint: a corrupt or reshaped file must not block runs.
  } on Object {
    return <String, int>{};
  }
}

void _persistGreen(
  Map<String, FileResult> results, {
  required List<String> toRun,
  required Map<String, String> hashes,
  required String store,
  required Map<String, int> durations,
  required File durationsFile,
  required bool loadedAll,
}) {
  Directory(store).createSync(recursive: true);
  int green = 0;
  for (final String f in toRun) {
    final FileResult? r = results[f];
    // No results: either the file has no tests or it failed to load. Only a
    // clean exit rules out the load failure.
    if (r == null && !loadedAll) continue;
    if (r != null) durations[f] = r.millis;
    if (r != null && !r.passed) continue;
    File(p.join(store, hashes[f])).writeAsStringSync('');
    green++;
  }
  durationsFile.writeAsStringSync(jsonEncode(durations));
  stdout.writeln('cached $green/${toRun.length} green test files');
}
