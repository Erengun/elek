import 'package:elek/src/pubspec.dart';
import 'package:test/test.dart';

void main() {
  group('usesFlutter', () {
    test('true when a dependency is the Flutter SDK', () {
      expect(
        usesFlutter('dependencies:\n  flutter:\n    sdk: flutter\n'),
        isTrue,
      );
    });

    test('true for quoted and flow-style SDK dependencies', () {
      for (final String pubspec in <String>[
        'dependencies:\n  flutter:\n    sdk: "flutter"\n',
        "dev_dependencies:\n  flutter_test:\n    sdk: 'flutter'\n",
        'dependencies:\n  flutter: {sdk: flutter}\n',
      ]) {
        expect(usesFlutter(pubspec), isTrue, reason: pubspec);
      }
    });

    test('false for pure Dart packages and SDK constraints', () {
      expect(
        usesFlutter(
          "environment:\n  sdk: ^3.6.0\n  flutter: '>=3.0.0'\n"
          'dependencies:\n  path: ^1.9.1\n',
        ),
        isFalse,
      );
    });
  });

  test('declaredAssets reads assets and fonts under flutter: only', () {
    const String pubspec = '''
name: x
assets:
  - not/flutter.png
flutter:
  uses-material-design: true
  assets:
    - assets/icon.png # trailing comment
    - "assets/img/"
    - path: assets/flavored/
      flavors:
        - dev
  # assets:
  #   - commented.png
  fonts:
    - family: Nunito
      fonts:
        - asset: assets/fonts/Nunito-Bold.ttf
          weight: 700
  generate: true
sentry:
  project: x
''';

    expect(declaredAssets(pubspec), <String>[
      'assets/icon.png',
      'assets/img/',
      'assets/flavored/',
      'assets/fonts/Nunito-Bold.ttf',
    ]);
  });
}
