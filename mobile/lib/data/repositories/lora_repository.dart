import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../api/dtos/embedding.dart';
import '../api/dtos/analyze.dart';
import '../api/mobile_api.dart';
import '../db/app_database.dart';
import '../files/file_store.dart';
import 'studio_repository.dart';

class LoraRepository {
  LoraRepository(this.db, this.files);
  final AppDatabase db;
  final FileStore files;
  Stream<List<DatasetRow>> watchDatasets() => (db.select(
    db.datasets,
  )..orderBy([(d) => OrderingTerm.desc(d.createdAt)])).watch();
  Stream<List<LoraRow>> watchLoras() => (db.select(
    db.loras,
  )..orderBy([(l) => OrderingTerm.desc(l.createdAt)])).watch();
  Stream<List<DatasetItemRow>> watchItems(String id) => (db.select(
    db.datasetItems,
  )..where((i) => i.datasetId.equals(id))).watch();
  Future<DatasetRow?> dataset(String id) =>
      (db.select(db.datasets)..where((d) => d.id.equals(id))).getSingleOrNull();
  Future<void> updateItem(
    DatasetItemRow item, {
    String? caption,
    bool? included,
  }) => (db.update(db.datasetItems)..where((i) => i.id.equals(item.id))).write(
    DatasetItemsCompanion(
      caption: caption == null ? const Value.absent() : Value(caption),
      included: included == null ? const Value.absent() : Value(included),
    ),
  );

  Future<File> exportDataset(String id) async {
    final data = await dataset(id);
    if (data == null) {
      throw const FormatException('This dataset is no longer on the phone.');
    }
    final items = (await (db.select(
      db.datasetItems,
    )..where((i) => i.datasetId.equals(id) & i.included.equals(true))).get());
    if (items.isEmpty) {
      throw const FormatException('Include at least one dataset image.');
    }
    final output = files.resolve(
      'work/exports/$id-${DateTime.now().microsecondsSinceEpoch}.zip',
    );
    await output.parent.create(recursive: true);
    final encoder = ZipFileEncoder()..create(output.path);
    try {
      for (final item in items) {
        final name = p.posix.basename(item.path);
        final folder = '${data.repeats}_${data.triggerWord} person';
        await encoder.addFile(files.resolve(item.path), '$folder/$name', 0);
        encoder.addArchiveFile(
          ArchiveFile.string(
            '$folder/${p.posix.withoutExtension(name)}.txt',
            item.caption,
          ),
        );
      }
      await encoder.close();
      return output;
    } catch (_) {
      try {
        await encoder.close();
      } catch (_) {}
      if (await output.exists()) await output.delete();
      rethrow;
    }
  }

  static String anchor(List<FaceRow> faces) {
    if (faces.isEmpty) {
      throw const FormatException(
        'Scan and assign a clear face for this person first.',
      );
    }
    final mean = Float32List(512);
    for (final face in faces.take(40)) {
      final vector = decodeEmbedding(base64Encode(face.embedding));
      for (var index = 0; index < 512; index++) {
        mean[index] += vector[index] * max(face.qualityScore, .001);
      }
    }
    final norm = sqrt(mean.fold<double>(0, (sum, v) => sum + v * v));
    if (norm < 1e-8) {
      throw const FormatException(
        'The source identity has no usable embeddings.',
      );
    }
    for (var index = 0; index < 512; index++) {
      mean[index] /= norm;
    }
    return encodeEmbedding(mean);
  }

  /// Generated portraits augment a real identity only after the same 0.4 anchor gate as desktop.
  Future<int> buildIdentity(LoraRow lora, MobileApi api) async {
    if (lora.personId == null) {
      throw const FormatException('Assign this LoRA to a person first.');
    }
    final real = await StudioRepository(db, files).sourceFaces(lora.personId!);
    final capabilities = await api.capabilities();
    if (real.any((face) => face.modelId != capabilities.embeddingModelId)) {
      throw const FormatException(
        'Rescan this person with the current PC embedding model.',
      );
    }
    final anchorVector = decodeEmbedding(anchor(real));
    final portraits =
        await (db.select(db.results)
              ..where(
                (r) =>
                    r.type.equals('generate_lora_images') &
                    r.personId.equals(lora.personId!) &
                    r.mime.equals('image/png'),
              )
              ..limit(32))
            .get();
    final accepted = <Map<String, dynamic>>[];
    for (final picture in portraits) {
      final result = await api.analyzeImage(
        await files.resolve(picture.path).readAsBytes(),
        options: const AnalyzeOptions(detectBodies: false),
      );
      if (result.modelId != capabilities.embeddingModelId) {
        throw const FormatException(
          'The PC embedding model changed. Build the identity again.',
        );
      }
      for (final face in result.faces) {
        var similarity = 0.0;
        for (var index = 0; index < 512; index++) {
          similarity += anchorVector[index] * face.embedding[index];
        }
        if (face.passesGate && similarity >= .4) {
          accepted.add({
            'embedding': encodeEmbedding(face.embedding),
            'quality': face.quality.score,
            'pose': {
              'yaw': face.quality.pose?.yaw ?? 0,
              'pitch': face.quality.pose?.pitch ?? 0,
              'roll': face.quality.pose?.roll ?? 0,
            },
          });
        }
      }
    }
    if (accepted.isEmpty) {
      throw const FormatException(
        'No generated portrait matched the real person. Generate clearer portraits.',
      );
    }
    await (db.update(db.loras)..where((l) => l.id.equals(lora.id))).write(
      LorasCompanion(
        identityJson: Value(
          jsonEncode({
            'model_id': capabilities.embeddingModelId,
            'faces': accepted,
          }),
        ),
      ),
    );
    return accepted.length;
  }
}
