// Stays in a shard: elek turns @TestOn into a group skip.
@TestOn('mac-os || linux')
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('temp dir is absolute', () {
    expect(Directory.systemTemp.path, startsWith('/'));
  });
}
