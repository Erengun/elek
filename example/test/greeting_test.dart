import 'package:elek_example/src/greeting.dart';
import 'package:test/test.dart';

void main() {
  test('greets by name', () {
    expect(greet('Ayşe'), 'Merhaba, Ayşe!');
  });
}
