String slugify(String text) =>
    text.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
