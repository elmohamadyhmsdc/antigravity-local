import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../../data/db/app_database.dart';
import '../../data/files/file_store.dart';

/// Imports only verified archives into private paths. Rows are committed with the owning result.
class ArtifactStore {
  ArtifactStore(this.db, this.files);
  final AppDatabase db;
  final FileStore files;

  Future<Future<void> Function()> stage(JobRow job, String relative) async {
    final request = jsonDecode(job.requestJson) as Map<String, dynamic>;
    final params = request['params'] as Map<String, dynamic>;
    if (job.type == 'train_lora') {
      return () async {
        await db
            .into(db.loras)
            .insertOnConflictUpdate(
              LorasCompanion.insert(
                id: job.id,
                personId: Value(job.personId),
                path: relative,
                triggerWord: params['trigger_word'] as String,
                createdAt: DateTime.now().millisecondsSinceEpoch,
              ),
            );
      };
    }
    if (!const [
      'build_lora_dataset',
      'generate_lora_images',
    ].contains(job.type)) {
      return () async {};
    }
    final stream = InputFileStream(files.resolve(relative).path);
    try {
      final archive = ZipDecoder().decodeStream(stream);
      if (archive.length > 2048) {
        throw const FormatException('Too many files in result bundle.');
      }
      var size = 0;
      final items = <({String path, String caption, int size, String sha})>[];
      for (final entry in archive.files) {
        if (!entry.isFile) continue;
        files.resolve(
          'bundles/${job.id}/${entry.name}',
        ); // reject paths before basename conversion
        size += entry.size;
        if (size > 512 * 1024 * 1024 || entry.size > 32 * 1024 * 1024) {
          throw const FormatException('Result bundle is too large.');
        }
        final ext = p.posix.extension(entry.name).toLowerCase();
        if (ext == '.txt') continue;
        if (!const ['.jpg', '.jpeg', '.png'].contains(ext)) {
          throw const FormatException('Unexpected result bundle file.');
        }
        final name = p.posix.basename(entry.name);
        final path =
            '${job.type == 'build_lora_dataset' ? 'datasets' : 'portraits'}/${job.id}/$name';
        if (items.any((item) => item.path == path)) {
          throw const FormatException('Duplicate result image name.');
        }
        final captionEntry = archive.findFile(
          '${p.posix.withoutExtension(entry.name)}.txt',
        );
        if (job.type == 'build_lora_dataset' &&
            (captionEntry == null || captionEntry.size > 8192)) {
          throw const FormatException(
            'A dataset caption is missing or too long.',
          );
        }
        final caption = captionEntry == null
            ? ''
            : utf8.decode(captionEntry.content);
        final bytes = entry.content;
        await files.write(path, bytes);
        items.add((
          path: path,
          caption: caption,
          size: bytes.length,
          sha: sha256.convert(bytes).toString(),
        ));
      }
      if (items.isEmpty) {
        throw const FormatException('The result bundle contains no images.');
      }
      return () async {
        if (job.type == 'build_lora_dataset') {
          await db
              .into(db.datasets)
              .insertOnConflictUpdate(
                DatasetsCompanion.insert(
                  id: job.id,
                  personId: Value(job.personId),
                  triggerWord: params['trigger_word'] as String,
                  repeats: Value((params['repeats'] as int?) ?? 20),
                  createdAt: DateTime.now().millisecondsSinceEpoch,
                ),
              );
          await (db.delete(
            db.datasetItems,
          )..where((i) => i.datasetId.equals(job.id))).go();
          for (final item in items) {
            await db
                .into(db.datasetItems)
                .insert(
                  DatasetItemsCompanion.insert(
                    datasetId: job.id,
                    path: item.path,
                    caption: item.caption,
                  ),
                );
          }
        } else {
          for (var index = 0; index < items.length; index++) {
            final item = items[index];
            await db
                .into(db.results)
                .insertOnConflictUpdate(
                  ResultsCompanion.insert(
                    id: '${job.id}-$index',
                    type: job.type,
                    path: item.path,
                    originalPath: item.path,
                    mime: 'image/png',
                    sizeBytes: item.size,
                    sha256: item.sha,
                    personId: Value(job.personId),
                    createdAt: DateTime.now().millisecondsSinceEpoch,
                  ),
                );
          }
        }
      };
    } finally {
      await stream.close();
    }
  }
}
