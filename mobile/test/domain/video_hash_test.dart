import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/domain/scan/video_hash.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  setUp(
    () async =>
        directory = await Directory.systemTemp.createTemp('video_hash_'),
  );
  tearDown(() async => directory.delete(recursive: true));

  test('fingerprint matches SHA-256 across chunks and an empty file', () async {
    for (final length in [0, 2 * 1024 * 1024 + 31]) {
      final bytes = Uint8List.fromList(List.generate(length, (i) => i % 251));
      final file = await File('${directory.path}/video').writeAsBytes(bytes);
      final progress = <double>[];
      final digest = await videoFileHash(
        file,
        cancelled: () => false,
        onProgress: progress.add,
      );
      expect(digest, sha256.convert(bytes).toString());
      if (length > 0) expect(progress.last, 1);
    }
  });

  test('cancels during fingerprinting and leaves the source intact', () async {
    final file = await File(
      '${directory.path}/video',
    ).writeAsBytes(Uint8List(16 * 1024 * 1024));
    var cancelled = false;
    final watch = Stopwatch()..start();
    await expectLater(
      videoFileHash(
        file,
        cancelled: () => cancelled,
        onProgress: (_) => cancelled = true,
      ),
      throwsA(isA<VideoHashCancelled>()),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
    expect(await file.length(), 16 * 1024 * 1024);
  });

  test('missing source fails instead of waiting indefinitely', () async {
    await expectLater(
      videoFileHash(
        File('${directory.path}/missing'),
        cancelled: () => false,
        onProgress: (_) {},
      ),
      throwsA(isA<FileSystemException>()),
    );
  });
}
