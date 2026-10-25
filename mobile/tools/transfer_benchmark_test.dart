// Run explicitly with flutter test tools/transfer_benchmark_test.dart --no-pub.
// Real pinned HTTPS and production blob/result routes; disposable synthetic data.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:antigravity_mobile/data/api/mobile_api.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    '32 MiB transfer benchmark over real local HTTPS',
    () async {
      final root = await Directory.systemTemp.createTemp('studio_transfer_');
      final ready = File('${root.path}/ready.json');
      Process? server;
      HttpMobileApi? api;
      final output = StringBuffer();
      try {
        server = await Process.start(
          File('../the app/venv/Scripts/python.exe').absolute.path,
          [
            File('tools/stateless_studio_fixture.py').absolute.path,
            '--root',
            '${root.path}/server',
            '--ready',
            ready.path,
            '--transfer-mib',
            '32',
          ],
          workingDirectory: root.path,
        );
        server.stdout.transform(utf8.decoder).listen(output.write);
        server.stderr.transform(utf8.decoder).listen(output.write);
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (!await ready.exists()) {
          if (DateTime.now().isAfter(deadline)) fail('Server startup: $output');
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        final connection = jsonDecode(await ready.readAsString()) as Map;
        final client = HttpMobileApi(
          ServerSession(
            serverId: connection['server_id'] as String,
            name: 'Disposable transfer benchmark',
            host: connection['host'] as String,
            port: connection['port'] as int,
            fingerprint: connection['fingerprint'] as String,
            token: connection['token'] as String,
          ),
        );
        api = client;
        while (true) {
          try {
            await client.health();
            break;
          } on Object {
            if (DateTime.now().isAfter(deadline)) rethrow;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }
        final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAWElEQVRIDbXBAQEAAAABIF433wpV5KnIU5GnIk9Fnoo8FXkq8lTkqchTkaciT0WeijwVeSryVOSpyFORpyJPRZ6KPBV5KvJU5KnIU5GnIk9Fnoo8FXkq8jThJy0h7YJJqAAAAABJRU5ErkJggg==',
        );
        final bytes = Uint8List(32 * 1024 * 1024)..setRange(0, png.length, png);
        final embedding = base64Encode(
          (Float32List(512)..[0] = 1).buffer.asUint8List(),
        );
        final uploads = <double>[], downloads = <double>[];
        for (var run = 0; run < 3; run++) {
          bytes[bytes.length - 1] = run;
          final hash = sha256.convert(bytes).toString();
          final watch = Stopwatch()..start();
          var offset = (await client.blobOffset(hash)).offset;
          while (offset < bytes.length) {
            offset = await client.uploadChunk(
              hash,
              Uint8List.sublistView(
                bytes,
                offset,
                min(offset + 4 * 1024 * 1024, bytes.length),
              ),
              offset,
              bytes.length,
            );
          }
          uploads.add(watch.elapsedMicroseconds / 1000000);
          final job = await client.createStudioJob({
            'client_job_id': 'transfer-$run',
            'type': 'reface_image_v3',
            'inputs': {'target': hash},
            'params': {
              'source_faces': [
                {'embedding': embedding, 'quality': .8},
              ],
            },
          });
          while (true) {
            final status = await client.studioJob(job.id);
            if (status.status == 'failed') {
              fail('Fixture failed: ${status.error}');
            }
            if (status.status == 'completed') break;
            await Future<void>.delayed(const Duration(milliseconds: 50));
          }
          final manifest = await client.studioResult(job.id);
          final target = File('${root.path}/result-$run.png');
          watch.reset();
          await client.downloadStudioResult(job.id, manifest.name, target);
          downloads.add(watch.elapsedMicroseconds / 1000000);
          expect(await target.length(), manifest.size);
          expect(
            (await sha256.bind(target.openRead()).first).toString(),
            manifest.sha256,
          );
          await client.deleteVideoJob(job.id);
          expect((await client.blobOffset(hash)).exists, isFalse);
        }
        uploads.sort();
        downloads.sort();
        debugPrint(
          'TRANSFER_BENCH ${jsonEncode({'transport': 'pinned HTTPS loopback; desktop Flutter test; synthetic data', 'mib_each_direction': 32, 'runs': 3, 'upload_seconds': uploads, 'download_seconds': downloads, 'median_upload_mib_s': 32 / uploads[1], 'median_download_mib_s': 32 / downloads[1]})}',
        );
      } finally {
        api?.close();
        if (server != null) {
          await File('${root.path}/ready.stop').writeAsString('stop');
          try {
            await server.exitCode.timeout(const Duration(seconds: 30));
          } on TimeoutException {
            server.kill();
            await server.exitCode;
          }
        }
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
