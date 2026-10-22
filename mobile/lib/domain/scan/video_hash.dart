import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';

class VideoHashCancelled implements Exception {
  const VideoHashCancelled();
}

/// Read-only work in its own isolate. Cancelling cannot leave a partial upload
/// or database write, and memory stays bounded even for multi-gigabyte videos.
Future<String> videoFileHash(
  File file, {
  required bool Function() cancelled,
  required void Function(double) onProgress,
}) async {
  if (cancelled()) throw const VideoHashCancelled();
  final port = ReceivePort();
  final result = Completer<String>();
  // A worker can fail before Isolate.spawn has returned its handle.
  result.future.ignore();
  Isolate? worker;
  SendPort? control;
  Timer? timer;
  final subscription = port.listen((message) {
    if (result.isCompleted) return;
    if (message is SendPort) {
      control = message;
      if (cancelled()) control!.send(null);
    } else if (message is double) {
      onProgress(message);
      if (cancelled()) control?.send(null);
    } else if (message is List && message.length == 1) {
      if (message.single == null || cancelled()) {
        result.completeError(const VideoHashCancelled());
      } else {
        result.complete(message.single as String);
      }
    } else {
      result.completeError(
        const FileSystemException('Could not calculate the video fingerprint.'),
      );
    }
  });
  try {
    worker = await Isolate.spawn(
      _hashWorker,
      (file.path, port.sendPort),
      onError: port.sendPort,
      onExit: port.sendPort,
      errorsAreFatal: true,
    );
    timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!result.isCompleted && cancelled()) {
        control?.send(null);
      }
    });
    return await result.future;
  } finally {
    timer?.cancel();
    worker?.kill(priority: Isolate.immediate);
    await subscription.cancel();
    port.close();
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest digest;
  @override
  void add(Digest data) => digest = data;
  @override
  void close() {}
}

void _hashWorker((String, SendPort) request) async {
  final (path, port) = request;
  final control = ReceivePort();
  var cancelled = false;
  control.listen((_) => cancelled = true);
  port.send(control.sendPort);
  final file = File(path).openSync();
  final output = _DigestSink();
  final sink = sha256.startChunkedConversion(output);
  try {
    final total = file.lengthSync();
    var read = 0;
    final updates = Stopwatch()..start();
    while (true) {
      final bytes = await file.read(1024 * 1024);
      if (cancelled) break;
      if (bytes.isEmpty) break;
      sink.add(bytes);
      read += bytes.length;
      if (updates.elapsedMilliseconds >= 200 || read == total) {
        port.send(total == 0 ? 1.0 : read / total);
        updates.reset();
      }
    }
    sink.close();
  } finally {
    file.closeSync();
    control.close();
  }
  Isolate.exit(port, [cancelled ? null : output.digest.toString()]);
}
