import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart';

import '../db/app_database.dart';
import '../files/file_store.dart';
import '../../domain/scan/video_scan.dart';

class StudioRepository {
  StudioRepository(this.db, this.files);
  final AppDatabase db;
  final FileStore files;

  Stream<List<JobRow>> watchJobs() => (db.select(
    db.jobs,
  )..orderBy([(j) => OrderingTerm.desc(j.createdAt)])).watch();
  Stream<JobRow?> watchJob(String id) =>
      (db.select(db.jobs)..where((j) => j.id.equals(id))).watchSingleOrNull();
  Future<JobRow?> job(String id) =>
      (db.select(db.jobs)..where((j) => j.id.equals(id))).getSingleOrNull();
  Stream<List<ResultRow>> watchResults() => (db.select(
    db.results,
  )..orderBy([(r) => OrderingTerm.desc(r.createdAt)])).watch();
  Stream<ResultRow?> watchResult(String id) => (db.select(
    db.results,
  )..where((r) => r.id.equals(id))).watchSingleOrNull();

  Future<List<FaceRow>> sourceFaces(int personId) =>
      (db.select(db.faces)
            ..where((f) => f.personId.equals(personId))
            ..orderBy([(f) => OrderingTerm.desc(f.qualityScore)])
            ..limit(100))
          .get();

  static List<Map<String, dynamic>> encodeFaces(
    Iterable<FaceRow> faces,
    String modelId,
  ) {
    final chosen = faces.toList();
    if (chosen.isEmpty || chosen.any((f) => f.modelId != modelId)) {
      throw const FormatException(
        'Choose source faces that use the PC embedding model.',
      );
    }
    return [
      for (final f in chosen)
        {
          'embedding': base64Encode(f.embedding),
          'quality': f.qualityScore,
          'pose': {
            'yaw': f.yaw ?? 0,
            'pitch': f.pitch ?? 0,
            'roll': f.roll ?? 0,
          },
        },
    ];
  }

  Future<String> enqueue({
    required String serverId,
    required String type,
    required Map<String, dynamic> params,
    required File target,
    required bool video,
    int? personId,
  }) async {
    return enqueueInputs(
      serverId: serverId,
      type: type,
      params: params,
      inputs: {
        'target': [target],
      },
      personId: personId,
    );
  }

  Future<String> enqueueInputs({
    required String serverId,
    required String type,
    required Map<String, dynamic> params,
    required Map<String, List<File>> inputs,
    int? personId,
  }) async {
    if (inputs.isEmpty || inputs.values.any((list) => list.isEmpty)) {
      throw const FormatException('Choose input files.');
    }
    final id =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final stagedFiles = <String, String>{};
    final wireInputs = <String, dynamic>{};
    String? firstPath, firstSha;
    var firstSize = 0;
    try {
      for (final slot in inputs.entries) {
        final hashes = <String>[];
        for (var index = 0; index < slot.value.length; index++) {
          final relative = 'work/$id/${slot.key}-$index.bin';
          final staged = files.resolve(relative);
          await staged.parent.create(recursive: true);
          await slot.value[index].copy(staged.path);
          final size = await staged.length();
          if (size <= 0) throw const FormatException('An input file is empty.');
          final hash = await isolatedFileSha256(staged.path);
          stagedFiles[hash] = relative;
          hashes.add(hash);
          firstPath ??= relative;
          firstSha ??= hash;
          if (firstSize == 0) firstSize = size;
        }
        wireInputs[slot.key] = const ['images', 'refs'].contains(slot.key)
            ? hashes
            : hashes.single;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      await db
          .into(db.jobs)
          .insert(
            JobsCompanion.insert(
              id: id,
              serverId: serverId,
              type: type,
              requestJson: jsonEncode({
                'client_job_id': id,
                'type': type,
                'inputs': wireInputs,
                'params': params,
              }),
              targetPath: firstPath!,
              targetSha: firstSha!,
              targetSize: firstSize,
              inputFiles: Value(jsonEncode(stagedFiles)),
              personId: Value(personId),
              status: 'uploading',
              createdAt: now,
              updatedAt: now,
            ),
          );
      return id;
    } catch (_) {
      for (final relative in stagedFiles.values) {
        await files.delete(relative);
      }
      rethrow;
    }
  }

  Future<void> update(String id, JobsCompanion row) =>
      (db.update(db.jobs)..where((j) => j.id.equals(id))).write(row);

  Future<void> favourite(ResultRow row) =>
      (db.update(db.results)..where((r) => r.id.equals(row.id))).write(
        ResultsCompanion(favourite: Value(!row.favourite)),
      );

  Future<void> deleteResult(ResultRow row) async {
    final datasetFiles = await (db.select(
      db.datasetItems,
    )..where((i) => i.datasetId.equals(row.id))).get();
    await db.transaction(() async {
      await (db.delete(db.results)..where((r) => r.id.equals(row.id))).go();
      // A removed result must never be silently downloaded again by an ACK retry.
      await update(row.id, const JobsCompanion(acknowledged: Value(true)));
      await (db.delete(db.loras)..where((l) => l.id.equals(row.id))).go();
      await (db.delete(db.datasets)..where((d) => d.id.equals(row.id))).go();
    });
    await files.deleteAll([row.path, row.originalPath]);
    await files.deleteAll(datasetFiles.map((i) => i.path));
  }
}
