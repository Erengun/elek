import 'price.dart';

final class Cart {
  final List<int> _items = <int>[];

  void add(int kurus) => _items.add(kurus);

  int get total => _items.fold(0, (int sum, int item) => sum + item);

  String get label => formatPrice(total);
}
