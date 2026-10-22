import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/index/embedding_index.dart';

/// Host benchmark only: phone startup, frame timings and battery need device
/// acceptance. Run with the cached Dart SDK and --packages=.dart_tool/package_config.json.
Future<void> main(List<String> args) async {
  final count = args.isEmpty ? 100000 : int.parse(args.single);
  if (count < 1 || count > 1000000) throw ArgumentError('Use 1–1000000 faces.');
  final startRss = ProcessInfo.currentRss;
  final random = Random(42);
  final index = await IsolateEmbeddingIndex.spawn();
  final watch = Stopwatch()..start();
  late Float32List known;
  try {
    for (var offset = 0; offset < count; offset += 500) {
      final batch = <(int, Float32List)>[];
      for (var i = offset; i < min(offset + 500, count); i++) {
        final vector = Float32List.fromList(
          List.generate(512, (_) => random.nextDouble() * 2 - 1),
        );
        if (i == 0) known = vector;
        batch.add((i + 1, vector));
      }
      await index.addAll(batch);
    }
    final loadMs = watch.elapsedMilliseconds;
    final times = <int>[];
    for (var i = 0; i < 12; i++) {
      watch
        ..reset()
        ..start();
      final hit = (await index.nearest([known])).single;
      if (hit?.id != 1 || hit!.cosine < .999) {
        throw StateError('Nearest identity mismatch');
      }
      times.add(watch.elapsedMicroseconds);
    }
    times.sort();
    stdout.writeln(
      jsonEncode({
        'environment': 'host Dart VM; not Android acceptance',
        'faces': await index.size(),
        'dimensions': 512,
        'load_ms': loadMs,
        'query_median_ms': times[times.length ~/ 2] / 1000,
        'query_max_ms': times.last / 1000,
        'rss_increase_mib': (ProcessInfo.currentRss - startRss) / 1048576,
        'process_peak_rss_mib': ProcessInfo.maxRss / 1048576,
      }),
    );
  } finally {
    await index.dispose();
  }
}
