import 'package:elek_example/src/cart.dart';
import 'package:test/test.dart';

void main() {
  test('label formats the total', () {
    final Cart cart = Cart()
      ..add(1000)
      ..add(250);
    expect(cart.label, '12,50 ₺');
  });
}
