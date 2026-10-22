import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';

import '../../data/api/api_exception.dart';
import '../../data/api/studio_api.dart';
import '../../data/api/dtos/jobs.dart';
import '../../data/db/app_database.dart';
import '../../data/repositories/studio_repository.dart';
import '../scan/scan_state.dart';
import '../scan/video_scan.dart';
import 'artifact_store.dart';

class _Paused implements Exception {}

/// The DB is authoritative. A lost POST response, network outage, or app kill is recoverable.
/// The PC is ACKed only after a size/hash-verified output and its result row are on the phone.
class JobTracker {
  JobTracker({
    required this.repository,
    required this.api,
    required this.keepAlive,
    this.interval = const Duration(seconds: 3),
    this.onCompleted,
  });
  final StudioRepository repository;
  final StudioApi? Function() api;
  final ScanKeepAlive keepAlive;
  final Duration interval;
  final Future<void> Function(String id)? onCompleted;
  final _paused = <String>{};
  final _events = <String, StreamSubscription<Object?>>{};
  final _eventWrites = <Future<void>>{};
  Timer? _timer;
  var _working = false;
  var _disposed = false;
  var _suspended = false;
  Completer<void>? _idle;

  void start() {
    if (_disposed || _suspended) return;
    _timer?.cancel();
    _tick();
  }

  Future<void> _tick() async {
    try {
      await synchronizeOnce();
    } finally {
      if (!_disposed && !_suspended) _timer = Timer(interval, _tick);
    }
  }

  Future<void> synchronizeOnce() async {
    if (_working || _disposed || _suspended) return;
    _working = true;
    _idle = Completer<void>();
    try {
      final client = api();
      if (client == null) return;
      final jobs = await repository.db.select(repository.db.jobs).get();
      final active = jobs
          .where(
            (j) =>
                j.serverId == client.serverId &&
                (!const [
                      'paused',
                      'failed',
                      'lost',
                      'completed',
                    ].contains(j.status) ||
                    (j.status == 'completed' && !j.acknowledged)),
          )
          .toList();
      if (active.isNotEmpty) {
        await keepAlive.start(
          title: 'Your Gallery Studio',
          text: '${active.length} active jobs',
        );
      }
      for (final job in active) {
        if (_disposed) break;
        try {
          if (job.status == 'completed') {
            await _ack(job, client);
          } else {
            await _sync(job, client);
          }
        } on _Paused {
          // The pause is durable; the next run excludes this row.
        } catch (error) {
          final lost = error is ApiException && error.statusCode == 404;
          final refused =
              error is ApiException &&
              !error.retryable &&
              error.code != 'missing_blobs';
          await repository.update(
            job.id,
            JobsCompanion(
              error: Value('$error'),
              status: lost
                  ? const Value('lost')
                  : refused
                  ? const Value('failed')
                  : const Value.absent(),
            ),
          );
        }
      }
      final remaining = await repository.db.select(repository.db.jobs).get();
      if (!remaining.any(
        (j) =>
            !const ['completed', 'failed', 'paused', 'lost'].contains(j.status),
      )) {
        await keepAlive.stop();
      }
    } finally {
      _working = false;
      _idle?.complete();
    }
  }

  void _check(String id) {
    if (_disposed || _suspended || _paused.contains(id)) throw _Paused();
  }

  Future<void> _sync(JobRow initial, StudioApi client) async {
    var job = (await repository.job(initial.id))!;
    _check(job.id);
    if (job.remoteId == null) {
      final inputs = Map<String, dynamic>.from(
        jsonDecode(job.inputFiles) as Map,
      );
      if (inputs.isEmpty) inputs[job.targetSha] = job.targetPath;
      var index = 0;
      for (final input in inputs.entries) {
        final file = repository.files.resolve(input.value as String);
        if (!await file.exists()) {
          throw const FormatException(
            'A private input is missing. Choose it again.',
          );
        }
        await _upload(job.id, client, file, input.key, (fraction) async {
          await repository.update(
            job.id,
            JobsCompanion(progress: Value((index + fraction) / inputs.length)),
          );
        });
        index++;
      }
      _check(job.id);
      final remote = await client.createStudioJob(
        jsonDecode(job.requestJson) as Map<String, dynamic>,
      );
      await repository.update(
        job.id,
        JobsCompanion(
          remoteId: Value(remote.id),
          status: Value(remote.status),
          progress: Value(remote.progress),
        ),
      );
      job = (await repository.job(job.id))!;
      // A pause during POST must also stop the accepted remote job.
      if (_paused.contains(job.id)) {
        await client.controlStudioJob(remote.id, resume: false);
        await repository.update(
          job.id,
          const JobsCompanion(status: Value('paused')),
        );
        throw _Paused();
      }
    }
    final remote = await client.studioJob(job.remoteId!);
    if (remote.status == 'completed') {
      await repository.update(
        job.id,
        const JobsCompanion(
          status: Value('downloading'),
          progress: Value(1),
          error: Value(null),
        ),
      );
      await _download(job, client);
    } else {
      await repository.update(
        job.id,
        JobsCompanion(
          status: Value(remote.status),
          progress: Value(remote.progress),
          message: Value(remote.message),
          detailsJson: Value(jsonEncode(remote.details)),
          error: Value(remote.error),
          updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
        ),
      );
      if (const ['queued', 'running'].contains(remote.status) &&
          !_events.containsKey(job.id)) {
        final localId = job.id;
        _events[localId] = client
            .studioEvents(job.remoteId!)
            .listen(
              (event) {
                final write = _writeEvent(localId, event);
                _eventWrites.add(write);
                write.whenComplete(() => _eventWrites.remove(write));
              },
              onError: (Object _) {
                _events.remove(localId);
              },
              onDone: () {
                _events.remove(localId);
              },
              cancelOnError: true,
            );
      }
    }
  }

  Future<void> _download(JobRow job, StudioApi client) async {
    final manifest = await client.studioResult(job.remoteId!);
    final relative = 'results/${job.id}/${manifest.name}';
    final target = repository.files.resolve(relative);
    await target.parent.create(recursive: true);
    final part = File('${target.path}.part');
    await client.downloadStudioResult(job.remoteId!, manifest.name, part);
    if (await part.length() != manifest.size ||
        await isolatedFileSha256(part.path) != manifest.sha256) {
      if (await part.exists()) await part.delete();
      throw const FormatException(
        'The downloaded result failed its integrity check. It will be downloaded again.',
      );
    }
    _check(job.id);
    if (await target.exists()) await target.delete();
    await part.rename(target.path);
    final original =
        'results/${job.id}/original.${job.type.contains('video') ? 'mp4' : 'jpg'}';
    await repository.files
        .resolve(job.targetPath)
        .copy(repository.files.resolve(original).path);
    final commitArtifacts = await ArtifactStore(
      repository.db,
      repository.files,
    ).stage(job, relative);
    _check(job.id);
    await repository.db.transaction(() async {
      await commitArtifacts();
      await repository.db
          .into(repository.db.results)
          .insertOnConflictUpdate(
            ResultsCompanion.insert(
              id: job.id,
              type: job.type,
              path: relative,
              originalPath: original,
              mime: manifest.mime,
              sizeBytes: manifest.size,
              sha256: manifest.sha256,
              personId: Value(job.personId),
              createdAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
      await repository.update(
        job.id,
        JobsCompanion(
          status: const Value('completed'),
          targetPath: Value(original),
          progress: const Value(1),
          error: const Value(null),
        ),
      );
    });
    if (job.targetPath != original) {
      await repository.files.delete(job.targetPath);
    }
    final inputPaths = (jsonDecode(job.inputFiles) as Map).values
        .cast<String>();
    for (final path in inputPaths) {
      if (path != original) await repository.files.delete(path);
    }
    await keepAlive.update('Result saved privately on this phone');
    await onCompleted?.call(job.id);
    await _ack((await repository.job(job.id))!, client);
  }

  Future<void> _writeEvent(String localId, StudioJobStatus event) async {
    try {
      final current = await repository.job(localId);
      if (_disposed ||
          _suspended ||
          current == null ||
          _paused.contains(localId) ||
          current.status == 'completed') {
        return;
      }
      if (const ['queued', 'running'].contains(event.status)) {
        await repository.update(
          localId,
          JobsCompanion(
            progress: Value(event.progress),
            message: Value(event.message),
            detailsJson: Value(jsonEncode(event.details)),
          ),
        );
      }
    } catch (_) {
      /* polling remains authoritative if a display update races disposal */
    }
  }

  Future<void> _ack(JobRow job, StudioApi client) async {
    try {
      await client.deleteVideoJob(job.remoteId!);
    } on ApiException catch (e) {
      if (e.statusCode != 404) rethrow;
    }
    await repository.update(
      job.id,
      const JobsCompanion(acknowledged: Value(true), error: Value(null)),
    );
  }

  Future<void> _upload(
    String id,
    StudioApi client,
    File file,
    String hash,
    Future<void> Function(double) progress,
  ) async {
    final total = await file.length();
    if (total <= 0) throw const FormatException('An input file is empty.');
    final head = await client.blobOffset(hash);
    var offset = head.offset;
    if (offset > total || (head.exists && offset != total)) {
      throw const FormatException('Invalid upload offset.');
    }
    final input = await file.open();
    try {
      var stalled = 0;
      while (!head.exists && offset < total) {
        _check(id);
        await input.setPosition(offset);
        final bytes = await input.read(min(4 * 1024 * 1024, total - offset));
        if (bytes.isEmpty) {
          throw const FormatException('Input changed during upload.');
        }
        final next = await client.uploadChunk(hash, bytes, offset, total);
        if (next < 0 || next > total || (next == offset && ++stalled > 3)) {
          throw const FormatException('Upload is not advancing.');
        }
        if (next != offset) stalled = 0;
        offset = next;
        await progress(offset / total);
      }
    } finally {
      await input.close();
    }
  }

  Future<void> pause(JobRow job) async {
    _paused.add(job.id);
    await _events.remove(job.id)?.cancel();
    await repository.update(
      job.id,
      const JobsCompanion(status: Value('paused')),
    );
    final client = api();
    if (client != null &&
        client.serverId == job.serverId &&
        job.remoteId != null) {
      try {
        await client.controlStudioJob(job.remoteId!, resume: false);
      } catch (e) {
        await repository.update(job.id, JobsCompanion(error: Value('$e')));
      }
    }
  }

  Future<void> resume(JobRow job) async {
    final client = api();
    if (client == null || client.serverId != job.serverId) {
      throw const FormatException('Connect to the PC used for this job.');
    }
    _paused.remove(job.id);
    if (job.remoteId != null &&
        !const ['lost', 'failed'].contains(job.status)) {
      await client.controlStudioJob(job.remoteId!, resume: true);
    } else if (job.remoteId != null && job.status == 'failed') {
      try {
        await client.deleteVideoJob(job.remoteId!);
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
      }
    }
    await repository.update(
      job.id,
      JobsCompanion(
        status: Value(
          job.remoteId == null || const ['lost', 'failed'].contains(job.status)
              ? 'uploading'
              : 'queued',
        ),
        remoteId: const ['lost', 'failed'].contains(job.status)
            ? const Value(null)
            : const Value.absent(),
        error: const Value(null),
      ),
    );
    start();
  }

  Future<void> remove(JobRow job) async {
    if (!const ['completed', 'failed', 'paused', 'lost'].contains(job.status)) {
      throw const FormatException('Pause this job before deleting it.');
    }
    final client = api();
    if (!job.acknowledged && job.remoteId != null) {
      if (client == null || client.serverId != job.serverId) {
        throw const FormatException(
          'Connect to the original PC to remove this job.',
        );
      }
      try {
        await client.deleteVideoJob(job.remoteId!);
      } on ApiException catch (e) {
        if (e.statusCode != 404) rethrow;
      }
    }
    _paused.add(job.id);
    await (repository.db.delete(
      repository.db.jobs,
    )..where((j) => j.id.equals(job.id))).go();
    if (job.targetPath.startsWith('work/')) {
      await repository.files.delete(job.targetPath);
    }
    for (final path
        in (jsonDecode(job.inputFiles) as Map).values.cast<String>()) {
      if (path.startsWith('work/')) await repository.files.delete(path);
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    for (final event in _events.values) {
      event.cancel();
    }
    _events.clear();
    keepAlive.stop();
  }

  /// Wait for all file/DB writes to stop before a backup replaces private storage.
  Future<bool> suspendForMaintenance() async {
    final wasActive = _timer != null || _working;
    _suspended = true;
    _timer?.cancel();
    _timer = null;
    for (final event in _events.values.toList()) {
      await event.cancel();
    }
    _events.clear();
    await Future.wait(_eventWrites.toList());
    if (_working) await _idle!.future;
    await keepAlive.stop();
    return wasActive;
  }

  void resumeAfterMaintenance(bool wasActive) {
    _suspended = false;
    if (wasActive) start();
  }
}
