import 'package:elek_example/src/price.dart';
import 'package:test/test.dart';

void main() {
  test('pads kurus to two digits', () {
    expect(formatPrice(1205), '12,05 ₺');
  });
}
