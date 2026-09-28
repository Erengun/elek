import 'package:elek_example/src/slugify.dart';
import 'package:test/test.dart';

void main() {
  test('collapses separators', () {
    expect(slugify(' Adana  Dürüm '), 'adana-d-r-m');
  });
}
