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

  static String anchor(List<FaceRow> faces, {String modelId = 'buffalo_l@1'}) {
    final dimension = switch (modelId) {
      'buffalo_l@1' => embeddingDim,
      characterEmbeddingModelId => characterEmbeddingDim,
      _ => throw const FormatException('Unsupported identity model.'),
    };
    if (faces.isEmpty) {
      throw const FormatException(
        'Scan and assign a clear face for this person first.',
      );
    }
    final mean = Float32List(dimension);
    for (final face in faces.take(40)) {
      if (face.modelId != modelId || !face.qualityScore.isFinite) {
        throw const FormatException(
          'Source faces use incompatible identity models.',
        );
      }
      final vector = vectorFromBlob(face.embedding);
      if (vector.length != dimension || vector.any((v) => !v.isFinite)) {
        throw const FormatException('A source identity embedding is invalid.');
      }
      for (var index = 0; index < dimension; index++) {
        mean[index] += vector[index] * max(face.qualityScore, .001);
      }
    }
    final norm = sqrt(mean.fold<double>(0, (sum, v) => sum + v * v));
    if (!norm.isFinite || norm < 1e-8) {
      throw const FormatException(
        'The source identity has no usable embeddings.',
      );
    }
    for (var index = 0; index < dimension; index++) {
      mean[index] /= norm;
    }
    return encodeVector(mean);
  }

  /// Only explicitly linked portraits can augment this model's real identity.
  Future<int> buildIdentity(LoraRow lora, MobileApi api) async {
    if (lora.personId == null) {
      throw const FormatException('Assign this LoRA to a person first.');
    }
    final studio = StudioRepository(db, files);
    final person = await (db.select(
      db.persons,
    )..where((p) => p.id.equals(lora.personId!))).getSingleOrNull();
    if (person == null) {
      throw const FormatException('The source identity no longer exists.');
    }
    final character = person.kind == 'character';
    final modelId = character ? characterEmbeddingModelId : 'buffalo_l@1';
    final real = await studio.sourceFaces(lora.personId!);
    final capabilities = await api.capabilities();
    final provenance = await studio.identityModelForLora(lora.id);
    if (provenance != null && provenance != modelId) {
      throw const FormatException(
        'This model and source identity use different embedding models.',
      );
    }
    if (character &&
        (!capabilities.hasOperationSupport ||
            !capabilities.supportsOperation(
              'analyze',
              'character',
              mediaType: 'photo',
              identityModelId: modelId,
            ))) {
      throw const FormatException(
        'This PC does not report character identity analysis. Update the PC server and reconnect.',
      );
    }
    if ((!character && capabilities.embeddingModelId != modelId) ||
        real.any((face) => face.modelId != modelId)) {
      throw const FormatException(
        'Source faces use incompatible identity models. Rescan this identity.',
      );
    }
    final anchorVector = decodeVector(
      anchor(real, modelId: modelId),
      character ? characterEmbeddingDim : embeddingDim,
    );
    final portraits = <ResultRow>[];
    var offset = 0;
    while (portraits.length < 32) {
      final page =
          await (db.select(db.results)
                ..where(
                  (r) =>
                      r.type.equals('generate_lora_images') &
                      r.personId.equals(lora.personId!) &
                      r.mime.equals('image/png'),
                )
                ..orderBy([(r) => OrderingTerm.desc(r.createdAt)])
                ..limit(64, offset: offset))
              .get();
      for (final picture in page) {
        if ((await studio.contextFor(picture.id))?.modelId == lora.id) {
          portraits.add(picture);
        }
        if (portraits.length == 32) break;
      }
      if (page.length < 64) break;
      offset += page.length;
    }
    if (portraits.isEmpty) {
      throw const FormatException(
        'No generated portraits are linked to this model. Older results without a verified model link cannot be used.',
      );
    }
    final accepted = <Map<String, dynamic>>[];
    for (final picture in portraits) {
      final result = await api.analyzeImage(
        await files.resolve(picture.path).readAsBytes(),
        options: AnalyzeOptions(
          detectBodies: false,
          detectCharacters: character,
          forceKind: character ? 'character' : null,
          facelessCharacters: !character,
        ),
      );
      if (!character && result.modelId != modelId) {
        throw const FormatException(
          'The PC embedding model changed. Build the identity again.',
        );
      }
      if (character) {
        final candidates = <({CharacterFace face, double score})>[];
        for (final candidate in result.characters) {
          final face = candidate.face;
          final vector = face?.embedding;
          if (face == null ||
              !face.score.isFinite ||
              face.score <= 0 ||
              vector == null ||
              vector.length != characterEmbeddingDim ||
              vector.any((v) => !v.isFinite)) {
            continue;
          }
          final norm = sqrt(vector.fold<double>(0, (sum, v) => sum + v * v));
          if (!norm.isFinite || norm < 1e-8) continue;
          var dot = 0.0;
          for (var index = 0; index < characterEmbeddingDim; index++) {
            dot += anchorVector[index] * vector[index] / norm;
          }
          candidates.add((face: face, score: dot));
        }
        candidates.sort((a, b) => b.score.compareTo(a.score));
        if (candidates.isNotEmpty &&
            candidates.first.score >= .86 &&
            (candidates.length == 1 ||
                candidates.first.score - candidates[1].score >= .05)) {
          final vector = candidates.first.face.embedding!;
          final norm = sqrt(vector.fold<double>(0, (sum, v) => sum + v * v));
          accepted.add({
            'embedding': encodeVector(
              Float32List.fromList([for (final v in vector) v / norm]),
            ),
            'quality': candidates.first.face.score,
          });
        }
        continue;
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
          jsonEncode({'model_id': modelId, 'faces': accepted}),
        ),
      ),
    );
    return accepted.length;
  }
}
