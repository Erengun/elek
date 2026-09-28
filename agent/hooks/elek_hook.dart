// Agent hook for Claude Code and Codex. `mark` (PostToolUse) records that the
// session edited files; `verify` (Stop) then runs elek once and blocks the
// stop with the failures (`decision: block`, which both tools accept). Only dart: imports, so it runs without pub get.
import 'dart:convert';
import 'dart:io';

const int maxAttempts = 3;
const int maxReason = 4000;

Future<void> main(List<String> args) async {
  final Map<String, Object?> input =
      jsonDecode(await stdin.transform(utf8.decoder).join())
          as Map<String, Object?>;
  final File state = stateFile(
    input['session_id'] as String? ?? 'default',
    Platform.environment,
  );
  final HookResult r = switch (args.firstOrNull) {
    'mark' => mark(input, state),
    'verify' => await verify(input, state),
    _ => (code: 0, stdout: null, stderr: 'usage: elek_hook.dart mark|verify'),
  };
  if (r.stdout case final String out) stdout.write(out);
  if (r.stderr case final String err) stderr.write(err);
  exit(r.code);
}

typedef HookResult = ({int code, String? stdout, String? stderr});
typedef ElekRun = ({int code, String output});
typedef ElekRunner = Future<ElekRun> Function(String packageDir);

File stateFile(String sessionId, Map<String, String> env) {
  final String base =
      env['CLAUDE_PLUGIN_DATA'] ??
      env['PLUGIN_DATA'] ??
      '${Directory.systemTemp.path}/elek-agent';
  final String id = sessionId.replaceAll(RegExp(r'[^\w-]'), '_');
  return File('$base/sessions/$id.json');
}

({bool dirty, int attempts}) readState(File f) {
  if (!f.existsSync()) return (dirty: false, attempts: 0);
  final Map<String, Object?> j =
      jsonDecode(f.readAsStringSync()) as Map<String, Object?>;
  return (dirty: j['dirty'] == true, attempts: j['attempts'] as int? ?? 0);
}

void writeState(File f, {required bool dirty, required int attempts}) {
  f
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode({'dirty': dirty, 'attempts': attempts}));
}

/// Paths a tool call wrote: Claude's `file_path`/`notebook_path`, or the file
/// headers of a Codex `apply_patch`.
List<String> editedPaths(Map<String, Object?> input) {
  final Object? toolInput = input['tool_input'];
  if (toolInput is! Map<String, Object?>) return const <String>[];
  return <String>[
    for (final String key in const <String>['file_path', 'notebook_path'])
      if (toolInput[key] case final String path) path,
    if (toolInput['command'] case final String patch
        when input['tool_name'] == 'apply_patch')
      ...patchPaths(patch),
  ];
}

final RegExp _patchHeader = RegExp(
  r'^\*\*\* (?:Add File|Update File|Delete File|Move to): (.+)$',
  multiLine: true,
);

List<String> patchPaths(String patch) => <String>[
  for (final RegExpMatch m in _patchHeader.allMatches(patch)) m[1]!.trim(),
];

/// Edits under build output or hidden directories can't affect tests.
bool isSourceEdit(String path) => !path
    .split(RegExp(r'[/\\]'))
    .any(
      (String s) =>
          s == 'build' || (s.startsWith('.') && s.length > 1 && s != '..'),
    );

HookResult mark(Map<String, Object?> input, File state) {
  if (editedPaths(input).any(isSourceEdit)) {
    writeState(state, dirty: true, attempts: readState(state).attempts);
  }
  return (code: 0, stdout: null, stderr: null);
}

/// Whether [pubspec] lists elek under `dev_dependencies`.
bool usesElek(String pubspec) {
  bool inDevDeps = false;
  for (final String line in const LineSplitter().convert(pubspec)) {
    if (RegExp(r'^\S').hasMatch(line)) {
      inDevDeps = line.startsWith('dev_dependencies:');
    } else if (inDevDeps && RegExp(r'^\s+elek\s*:').hasMatch(line)) {
      return true;
    }
  }
  return false;
}

/// Package dirs under [cwd] that use elek, found through git so ignored and
/// generated trees aren't walked. Outside git, only [cwd] itself is checked.
List<String> elekPackages(String cwd) {
  List<String> pubspecs;
  try {
    final ProcessResult r = Process.runSync('git', <String>[
      'ls-files',
      '--cached',
      '--others',
      '--exclude-standard',
      '--',
      '*pubspec.yaml',
    ], workingDirectory: cwd);
    pubspecs = r.exitCode == 0
        ? const LineSplitter().convert(r.stdout as String)
        : <String>['pubspec.yaml'];
  } on ProcessException {
    pubspecs = <String>['pubspec.yaml'];
  }
  return <String>[
    for (final String rel in pubspecs.toSet())
      if (File('$cwd/$rel') case final File f
          when (rel == 'pubspec.yaml' || rel.endsWith('/pubspec.yaml')) &&
              f.existsSync() &&
              usesElek(f.readAsStringSync()))
        rel.contains('/') ? rel.substring(0, rel.lastIndexOf('/')) : '.',
  ]..sort();
}

Future<ElekRun> runElek(String packageDir) async {
  // --cache: agent sandboxes often set CI, and the local cache is the point.
  final ProcessResult r = await Process.run(
    'dart',
    <String>['run', 'elek', '--cache'],
    workingDirectory: packageDir,
    runInShell: Platform.isWindows,
  );
  return (code: r.exitCode, output: '${r.stdout}${r.stderr}');
}

Future<HookResult> verify(
  Map<String, Object?> input,
  File state, {
  ElekRunner run = runElek,
  List<String> Function(String cwd) packages = elekPackages,
}) async {
  final ({bool dirty, int attempts}) s = readState(state);
  if (!s.dirty) return (code: 0, stdout: null, stderr: null);
  final String cwd = input['cwd'] as String? ?? Directory.current.path;

  final List<String> passed = <String>[];
  for (final String rel in packages(cwd)) {
    final String dir = rel == '.' ? cwd : '$cwd/$rel';
    final String pkg = dir
        .split(RegExp(r'[/\\]'))
        .lastWhere((String s) => s.isNotEmpty);
    final ElekRun r = await run(dir);
    final String first = r.output.split('\n').first.split(' (').first.trim();
    if (r.output.contains('Another elek run is already active')) {
      return _message(
        'elek: skipped verification in $pkg, another elek run is active.',
      );
    }
    if (r.code == 0) {
      passed.add('$pkg ($first)');
      continue;
    }
    if (s.attempts + 1 >= maxAttempts) {
      writeState(state, dirty: true, attempts: 0);
      return _message(
        'elek: $pkg still fails after $maxAttempts attempts; letting the '
        'agent stop. Run `dart run elek` in $pkg to see the failures.',
      );
    }
    writeState(state, dirty: true, attempts: s.attempts + 1);
    return (
      code: 0,
      stderr: null,
      stdout: _json(<String, Object?>{
        'decision': 'block',
        'reason': truncate(
          'Elek verification failed in $pkg.\n$first\n\n'
          '${_failures(r.output)}\n'
          'Fix the failures before stopping. If they are unrelated to your '
          'change, tell the user instead of trying again.',
        ),
      }),
    );
  }
  writeState(state, dirty: false, attempts: 0);
  if (passed.isEmpty) return (code: 0, stdout: null, stderr: null);
  return _message('elek: passed in ${passed.join(', ')}');
}

/// elek's `elek: N failing tests` block, or the output tail without one.
String _failures(String output) {
  final int i = output.lastIndexOf(
    RegExp(r'^elek: \d+ failing', multiLine: true),
  );
  if (i >= 0) return output.substring(i).trim();
  final List<String> lines = output.trimRight().split('\n');
  return lines.skip(lines.length > 40 ? lines.length - 40 : 0).join('\n');
}

String truncate(String s, [int max = maxReason]) =>
    s.length <= max ? s : '${s.substring(0, max)}\n... (truncated)';

HookResult _message(String text) => (
  code: 0,
  stdout: _json(<String, Object?>{'systemMessage': text}),
  stderr: null,
);

// Codex rejects plain text on stdout for Stop, so everything goes out as JSON.
String _json(Map<String, Object?> body) => jsonEncode(body);
