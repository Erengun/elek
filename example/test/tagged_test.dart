// @Tags can't be expressed by group(), so elek runs this file on its own.
@Tags(<String>['slow'])
library;

import 'package:elek_example/src/greeting.dart';
import 'package:test/test.dart';

void main() {
  test('greeting ends with an exclamation mark', () {
    expect(greet('Mehmet'), endsWith('!'));
  });
}
