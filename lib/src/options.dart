import 'dart:io';

final class RunnerOptions {
  RunnerOptions({
    required this.noCache,
    required this.dryRun,
    required this.shards,
    required this.store,
    required this.testArgs,
  });

  /// `dart run elek [--no-cache|--cache] [--shards N]
  /// [--dry-run] [--store DIR] [-- <test args>]`. With `CI` set the cache is
  /// off unless `--cache` asks for it: the hash doesn't cover flaky tests.
  /// Test args (--name, --tags, --dart-define...) also turn it off: a cached
  /// file would silently skip the subset the user asked for.
  factory RunnerOptions.parse(
    List<String> args, {
    Map<String, String> environment = const <String, String>{},
  }) {
    final int split = args.indexOf('--');
    final List<String> own = split < 0 ? args : args.sublist(0, split);
    String? valueOf(String flag) {
      final int i = own.indexOf(flag);
      return i < 0 || i + 1 >= own.length ? null : own[i + 1];
    }

    final List<String> testArgs = split < 0
        ? const <String>[]
        : args.sublist(split + 1);
    return RunnerOptions(
      noCache:
          testArgs.isNotEmpty ||
          own.contains('--no-cache') ||
          (environment.containsKey('CI') && !own.contains('--cache')),
      dryRun: own.contains('--dry-run'),
      shards:
          int.tryParse(valueOf('--shards') ?? '') ??
          (Platform.numberOfProcessors ~/ 2).clamp(1, 64),
      store: valueOf('--store'),
      testArgs: testArgs,
    );
  }

  final bool noCache;
  final bool dryRun;
  final int shards;
  final String? store;
  final List<String> testArgs;
}
