import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/api/mobile_api.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/repositories/studio_repository.dart';
import 'package:antigravity_mobile/domain/jobs/job_tracker.dart';
import 'package:antigravity_mobile/domain/scan/scan_state.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart' show debugPrint;

final _fixturePng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAWElEQVRIDbXBAQEAAAABIF433wpV5KnIU5GnIk9Fnoo8FXkq8lTkqchTkaciT0WeijwVeSryVOSpyFORpyJPRZ6KPBV5KvJU5KnIU5GnIk9Fnoo8FXkq8jThJy0h7YJJqAAAAABJRU5ErkJggg==',
);

void main() {
  final liveGpu = Platform.environment['REFACE_LIVE_GPU'] == '1';
  test(
    'fresh phone and empty server: upload, process, commit, ACK, erase server inputs and output',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'mobile_stateless_https_',
      );
      final app = Directory('../the app').absolute;
      final python = Platform.isWindows
          ? '${app.path}/venv/Scripts/python.exe'
          : '${app.path}/venv/bin/python';
      final ready = File('${root.path}/ready.json');
      Process? server;
      HttpMobileApi? api;
      JobTracker? tracker;
      AppDatabase? db;
      final output = StringBuffer();
      try {
        server = await Process.start(python, [
          File('tools/stateless_studio_fixture.py').absolute.path,
          '--root',
          '${root.path}/server',
          '--ready',
          ready.path,
          if (liveGpu) '--gpu',
        ], workingDirectory: root.path);
        server.stdout.transform(utf8.decoder).listen(output.write);
        server.stderr.transform(utf8.decoder).listen(output.write);
        final readyDeadline = DateTime.now().add(const Duration(seconds: 30));
        while (!await ready.exists() &&
            DateTime.now().isBefore(readyDeadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          await ready.exists(),
          isTrue,
          reason: 'Isolated HTTPS server did not start: $output',
        );
        final connection =
            jsonDecode(await ready.readAsString()) as Map<String, dynamic>;
        api = HttpMobileApi(
          ServerSession(
            serverId: connection['server_id'] as String,
            name: 'Empty test server',
            host: connection['host'] as String,
            port: connection['port'] as int,
            fingerprint: connection['fingerprint'] as String,
            token: connection['token'] as String,
          ),
        );
        final startDeadline = DateTime.now().add(const Duration(seconds: 15));
        while (true) {
          try {
            await api.health();
            break;
          } on Object {
            if (DateTime.now().isAfter(startDeadline)) rethrow;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        final workspace = Directory(connection['workspace'] as String);
        List<File> payloadFiles() => workspace
            .listSync(recursive: true)
            .whereType<File>()
            .where(
              (file) =>
                  !file.path.contains(
                    '${Platform.pathSeparator}tls${Platform.pathSeparator}',
                  ) &&
                  !file.path.endsWith('devices.json') &&
                  !file.path.endsWith('.antigravity-mobile-workspace'),
            )
            .toList();
        expect(payloadFiles(), isEmpty);
        final database = AppDatabase(NativeDatabase.memory());
        db = database;
        expect(await database.select(database.persons).get(), isEmpty);
        expect(await database.select(database.faces).get(), isEmpty);
        final files = FileStore(Directory('${root.path}/phone'));
        final repository = StudioRepository(database, files);
        final source = liveGpu
            ? await File('build/reface-acceptance/source.png').readAsBytes()
            : _fixturePng;
        final targetBytes = liveGpu
            ? await File('build/reface-acceptance/target.png').readAsBytes()
            : _fixturePng;
        final analysis = await api.analyzeImage(
          Uint8List.fromList(source),
          options: const AnalyzeOptions(minQuality: 0, detectBodies: false),
        );
        expect(analysis.faces, isNotEmpty);
        expect(
          payloadFiles(),
          isEmpty,
          reason: 'Photo analysis must leave no input file',
        );
        final target = File('${root.path}/phone-target.png');
        await target.writeAsBytes(targetBytes);
        final identity = analysis.faces.first;
        final id = await repository.enqueue(
          serverId: api.serverId,
          type: 'reface_image_v3',
          params: {
            'source_faces': [
              {
                'embedding': encodeEmbedding(identity.embedding),
                'quality': identity.quality.score,
              },
            ],
          },
          target: target,
          video: false,
        );
        var committedBeforeAck = false;
        tracker = JobTracker(
          repository: repository,
          api: () => api,
          keepAlive: const NoKeepAlive(),
          onCompleted: (localId) async {
            final result =
                (await database.select(database.results).get()).single;
            final bytes = await files.resolve(result.path).readAsBytes();
            expect(sha256.convert(bytes).toString(), result.sha256);
            expect(
              payloadFiles(),
              isNotEmpty,
              reason: 'The result must exist until the phone commits',
            );
            committedBeforeAck = true;
          },
        );
        final deadline = DateTime.now().add(const Duration(minutes: 4));
        while (DateTime.now().isBefore(deadline)) {
          await tracker.synchronizeOnce();
          final job = (await repository.job(id))!;
          if (job.status == 'failed' || job.status == 'lost') {
            fail('Round trip failed: ${job.error}\n$output');
          }
          if (job.acknowledged) break;
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        final job = (await repository.job(id))!;
        expect(job.status, 'completed');
        expect(job.acknowledged, isTrue);
        expect(committedBeforeAck, isTrue);
        final result = (await database.select(database.results).get()).single;
        expect(await files.resolve(result.path).exists(), isTrue);
        expect(
          await files.resolve(result.originalPath).readAsBytes(),
          targetBytes,
        );
        expect(
          payloadFiles(),
          isEmpty,
          reason:
              'No input, cache blob, intermediate or output may remain after ACK',
        );
        expect((await api.blobOffset(job.targetSha)).exists, isFalse);
        expect(Directory('${root.path}/data').existsSync(), isFalse);
        debugPrint(
          'PASS: real Flutter HTTPS client, ${liveGpu ? 'real GPU' : 'fixture compute'}, verified phone commit and zero remaining server payload files.',
        );
      } finally {
        tracker?.dispose();
        api?.close();
        await db?.close();
        if (server != null) {
          await File('${root.path}/ready.stop').writeAsString('stop');
          try {
            await server.exitCode.timeout(const Duration(seconds: 30));
          } on TimeoutException {
            server.kill();
            await server.exitCode;
            rethrow;
          }
        }
        await root.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
