import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'api_exception.dart';

const _bufferBytes = 256 * 1024;

// Dio's Uint8List request path copies it into 1 KiB pieces. Stream views keep
// the existing resumable 4 MiB request bounded and avoid those copies/events.
Stream<Uint8List> binaryUploadBody(Uint8List bytes) =>
    Stream.fromIterable(_uploadViews(bytes));

Iterable<Uint8List> _uploadViews(Uint8List bytes) sync* {
  for (var start = 0; start < bytes.length; start += _bufferBytes) {
    yield Uint8List.sublistView(
      bytes,
      start,
      min(start + _bufferBytes, bytes.length),
    );
  }
}

// TLS can deliver many small records. Batch disk writes without buffering the
// whole result; an interrupted request may retransmit at most one pending batch.
Stream<Uint8List> _diskBlocks(Stream<Uint8List> source) async* {
  final pending = BytesBuilder(copy: false);
  await for (final bytes in source) {
    pending.add(bytes);
    if (pending.length >= _bufferBytes) yield pending.takeBytes();
  }
  if (pending.isNotEmpty) yield pending.takeBytes();
}

/// Results are immutable within a job. Keep partial bytes on a broken connection
/// and use HTTP Range on the next attempt. The caller still checks the complete
/// manifest size and SHA-256 before committing or acknowledging anything.
Future<void> downloadResumableFile(
  Dio dio,
  String path,
  File target, {
  void Function(int received)? onProgress,
}) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    final offset = await target.exists() ? await target.length() : 0;
    final response = await dio.get<ResponseBody>(
      path,
      options: Options(
        responseType: ResponseType.stream,
        receiveTimeout: const Duration(minutes: 10),
        headers: {
          'Accept-Encoding': 'identity',
          if (offset > 0) 'Range': 'bytes=$offset-',
        },
        validateStatus: (status) =>
            status != null && status >= 200 && status < 600,
      ),
    );
    final body = response.data!;
    if (!const [200, 206, 416].contains(response.statusCode)) {
      // Streaming requests must still preserve the normal JSON error envelope
      // (especially expired device tokens), without writing it into the result.
      final bytes = BytesBuilder(copy: false);
      await for (final block in body.stream) {
        if (bytes.length + block.length > 64 * 1024) break;
        bytes.add(block);
      }
      Object? envelope;
      try {
        envelope = jsonDecode(utf8.decode(bytes.takeBytes()));
      } on FormatException {
        // Fall back to the HTTP status if the server/proxy returned other data.
      }
      final retry = int.tryParse(response.headers.value('retry-after') ?? '');
      throw ApiException.fromEnvelope(
        response.statusCode!,
        envelope,
        retryAfter: retry == null ? null : Duration(seconds: retry),
      );
    }
    final range = response.headers.value('content-range') ?? '';
    if (response.statusCode == 416) {
      await body.stream.listen(null).cancel();
      final total = RegExp(r'^bytes \*/(\d+)$').firstMatch(range);
      if (offset > 0 && total != null && int.parse(total[1]!) == offset) return;
      if (attempt == 0 && await target.exists()) {
        await target.delete();
        continue;
      }
      throw const FormatException('The PC rejected the result download range.');
    }
    final append = response.statusCode == 206;
    int? expectedLength;
    if (append) {
      final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+)$').firstMatch(range);
      if (match == null ||
          int.parse(match[1]!) != offset ||
          int.parse(match[2]!) != int.parse(match[3]!) - 1) {
        await body.stream.listen(null).cancel();
        throw const FormatException('The PC returned an invalid result range.');
      }
      expectedLength = int.parse(match[3]!);
    } else {
      expectedLength = int.tryParse(
        response.headers.value('content-length') ?? '',
      );
    }
    await target.parent.create(recursive: true);
    final sink = target.openWrite(
      mode: append ? FileMode.append : FileMode.write,
    );
    // Attach before asynchronous IO: disk errors must reach the awaiting call.
    sink.done.ignore();
    var received = append ? offset : 0;
    Stream<Uint8List> measured() async* {
      await for (final block in _diskBlocks(body.stream)) {
        received += block.length;
        onProgress?.call(received);
        yield block;
      }
    }

    try {
      await sink.addStream(measured());
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (expectedLength != null && await target.length() != expectedLength) {
      throw const FormatException('The result download was interrupted.');
    }
    return;
  }
}
