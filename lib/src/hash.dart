// Content hash of a test file's inputs: its transitive Dart import closure
// plus a global salt. Same idea as Tuist selective testing, per file.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

// Whole directive up to `;`, so both branches of a conditional import count.
final RegExp _directive = RegExp(
  r'^\s*(?:import|export|part)\b(?!\s+of\b)[^;]*;',
  multiLine: true,
);
final RegExp _uri = RegExp(r"""(['"])([^'"]+\.dart)\1""");

/// Non-`dart:` URIs referenced by import/export/part directives in [source].
List<String> directiveUris(String source) => <String>[
  for (final RegExpMatch d in _directive.allMatches(source))
    for (final RegExpMatch u in _uri.allMatches(d[0]!))
      if (!u[2]!.startsWith('dart:')) u[2]!,
];

final class DartDeps {
  /// [packageRoots]: package name -> absolute `lib/` dir. Packages not listed
  /// (hosted/git) are left out; the lockfile in the salt covers them.
  DartDeps(this.packageRoots);

  final Map<String, String> packageRoots;
  final Map<String, List<String>> _edges = <String, List<String>>{};

  List<String> _depsOf(String file) => _edges.putIfAbsent(file, () {
    final List<String> out = <String>[];
    for (final String uri in directiveUris(File(file).readAsStringSync())) {
      final String? resolved = _resolve(file, uri);
      if (resolved != null && File(resolved).existsSync()) out.add(resolved);
    }
    return out;
  });

  String? _resolve(String from, String uri) {
    if (uri.startsWith('package:')) {
      final String rest = uri.substring('package:'.length);
      final int slash = rest.indexOf('/');
      final String? root = packageRoots[rest.substring(0, slash)];
      // `package:a/src/b.dart` keeps its `/` otherwise; on Windows the same file
      // would then be a different closure entry than its relative import.
      return root == null
          ? null
          : p.normalize(p.join(root, rest.substring(slash + 1)));
    }
    return p.normalize(p.join(p.dirname(from), uri));
  }

  Set<String> closure(String file) {
    final Set<String> seen = <String>{file};
    final List<String> stack = <String>[file];
    while (stack.isNotEmpty) {
      for (final String dep in _depsOf(stack.removeLast())) {
        if (seen.add(dep)) stack.add(dep);
      }
    }
    return seen;
  }
}

/// Names of packages that [lockfile] resolved from a `path:` source. Their
/// sources can change without the lockfile changing, unlike hosted or git ones.
Set<String> pathPackages(String lockfile) {
  final Set<String> names = <String>{};
  String? current;
  for (final String line in const LineSplitter().convert(lockfile)) {
    if (RegExp(r'^  (\S+):\s*$').firstMatch(line) case final RegExpMatch m) {
      current = m[1];
    } else if (current != null && line.trim() == 'source: path') {
      names.add(current);
    }
  }
  return names;
}

/// Reads `.dart_tool/package_config.json`, keeping packages whose sources live
/// under [within] (the workspace) plus [pathPackages] wherever they live.
Map<String, String> readPackageRoots(
  File config, {
  required String within,
  Set<String> pathPackages = const <String>{},
}) {
  final Map<String, Object?> json =
      jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
  final Uri base = config.absolute.uri;
  final Map<String, String> roots = <String, String>{};
  for (final Object? entry in json['packages']! as List<Object?>) {
    final Map<String, Object?> pkg = entry! as Map<String, Object?>;
    final Uri root = base.resolve('${pkg['rootUri']}/');
    final String lib = p.normalize(
      root.resolve(pkg['packageUri'] as String? ?? 'lib/').toFilePath(),
    );
    final String name = pkg['name']! as String;
    if (p.isWithin(within, lib) || pathPackages.contains(name)) {
      roots[name] = lib;
    }
  }
  return roots;
}

/// sha256 over [extra] and sorted (relative path, file digest) pairs. File
/// digests are memoized, so hashing hundreds of overlapping closures stays cheap.
final class InputHasher {
  InputHasher(this.root);

  final String root;
  final Map<String, String> _fileDigests = <String, String>{};

  String digest(Iterable<String> files, {String extra = ''}) {
    final List<String> rels = <String>[
      for (final String f in files) p.relative(f, from: root),
    ]..sort();
    final StringBuffer buf = StringBuffer()..writeln(extra);
    for (final String rel in rels) {
      final String digest = _fileDigests.putIfAbsent(
        rel,
        () => sha256
            .convert(File(p.join(root, rel)).readAsBytesSync())
            .toString(),
      );
      buf.writeln('$rel $digest');
    }
    return sha256.convert(utf8.encode(buf.toString())).toString();
  }
}
