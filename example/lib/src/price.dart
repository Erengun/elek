String formatPrice(int kurus) =>
    '${kurus ~/ 100},${(kurus % 100).toString().padLeft(2, '0')} ₺';
