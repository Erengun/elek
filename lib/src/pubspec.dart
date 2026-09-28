// Line-based pubspec reads, enough for the two facts the runner needs;
// avoids a yaml dependency.
import 'dart:convert';

// Block (`sdk: flutter`), quoted, or flow style (`{sdk: flutter}`).
final RegExp _flutterSdk = RegExp(
  r'''\bsdk:\s*(['"]?)flutter\1\s*(?:[},#]|$)''',
  multiLine: true,
);
final RegExp _listItem = RegExp(r'^-\s+(?:path:\s*)?(.+)$');
final RegExp _fontAsset = RegExp(r'^(?:-\s+)?asset:\s*(.+)$');

/// Whether the package depends on the Flutter SDK, so needs `flutter test`.
bool usesFlutter(String pubspec) => _flutterSdk.hasMatch(pubspec);

/// Asset and font paths under the top-level `flutter:` key, as written.
List<String> declaredAssets(String pubspec) {
  final List<String> out = <String>[];
  bool inFlutter = false;
  int? assetsIndent;
  // Indent of the first `- ` under `assets:`; deeper items (flavors) aren't paths.
  int? itemIndent;
  for (final String raw in LineSplitter.split(pubspec)) {
    final String line = raw.replaceFirst(RegExp(r'\s+#.*$'), '');
    final String t = line.trim();
    if (t.isEmpty || t.startsWith('#')) continue;
    final int indent = line.length - line.trimLeft().length;
    if (indent == 0) {
      inFlutter = line.startsWith('flutter:');
      assetsIndent = null;
      continue;
    }
    if (!inFlutter) continue;
    if (assetsIndent != null &&
        (indent < assetsIndent ||
            (indent == assetsIndent && !t.startsWith('-')))) {
      assetsIndent = null;
    }
    if (t == 'assets:') {
      assetsIndent = indent;
      itemIndent = null;
      continue;
    }
    if (assetsIndent != null && t.startsWith('-')) itemIndent ??= indent;
    final RegExpMatch? item = assetsIndent == null || indent != itemIndent
        ? null
        : _listItem.firstMatch(t);
    final RegExpMatch? font = _fontAsset.firstMatch(t);
    final String? path = (font ?? item)?[1];
    if (path != null) out.add(_unquote(path.trim()));
  }
  return out;
}

String _unquote(String s) =>
    s.length > 1 && (s[0] == "'" || s[0] == '"') && s.endsWith(s[0])
    ? s.substring(1, s.length - 1)
    : s;
