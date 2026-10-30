import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../domain/scan/character_descriptor.dart';
import '../../domain/scan/scan_math.dart';
import '../api/dtos/analyze.dart';
import '../api/dtos/embedding.dart';
import '../db/app_database.dart';
import '../files/file_store.dart';

class CharacterSummary {
  CharacterSummary(this.id, this.name, this.cropPath, this.samples);
  final int id;
  final String? name;
  final String? cropPath;
  final int samples;
}

/// Local character identities never enter the human face index or PC grouping.
class CharacterRepository {
  CharacterRepository(this.db, this.files);
  final AppDatabase db;
  final FileStore files;

  Stream<List<CharacterSummary>> watch() => db
      .customSelect(
        '''
    SELECT i.id, i.name, COUNT(s.id) AS samples,
      (SELECT crop_path FROM character_samples c WHERE c.identity_id = i.id
       AND c.crop_path IS NOT NULL ORDER BY c.score DESC, c.id LIMIT 1) AS crop_path
    FROM character_identities i JOIN character_samples s ON s.identity_id = i.id
    GROUP BY i.id ORDER BY samples DESC, i.id
    ''',
        readsFrom: {db.characterIdentities, db.characterSamples},
      )
      .watch()
      .map(
        (rows) => [
          for (final r in rows)
            CharacterSummary(
              r.read<int>('id'),
              r.readNullable<String>('name'),
              r.readNullable<String>('crop_path'),
              r.read<int>('samples'),
            ),
        ],
      );

  Stream<List<CharacterSampleRow>> watchSamples(int id) =>
      (db.select(db.characterSamples)
            ..where((s) => s.identityId.equals(id))
            ..orderBy([
              (s) => OrderingTerm.desc(s.score),
              (s) => OrderingTerm.asc(s.id),
            ]))
          .watch();

  Future<void> rename(int id, String name) async {
    final value = name.trim();
    if (value.length > 80) {
      throw const FormatException('Use at most 80 characters.');
    }
    await (db.update(
      db.characterIdentities,
    )..where((i) => i.id.equals(id))).write(
      CharacterIdentitiesCompanion(name: Value(value.isEmpty ? null : value)),
    );
  }

  /// Correct a false match. The sample's assignment survives a rescan.
  Future<void> separate(int sampleId) => db.transaction(() async {
    final sample = await (db.select(
      db.characterSamples,
    )..where((s) => s.id.equals(sampleId))).getSingle();
    final id = await db
        .into(db.characterIdentities)
        .insert(
          CharacterIdentitiesCompanion.insert(
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    await (db.update(db.characterSamples)..where((s) => s.id.equals(sampleId)))
        .write(CharacterSamplesCompanion(identityId: Value(id)));
    await _removeEmpty(sample.identityId);
  });

  Future<void> _removeEmpty(int id) async {
    final count =
        await (db.select(db.characterSamples)
              ..where((s) => s.identityId.equals(id))
              ..limit(1))
            .get();
    if (count.isEmpty) {
      await (db.delete(
        db.characterIdentities,
      )..where((i) => i.id.equals(id))).go();
    }
  }

  /// Called inside PhotoResultStore's transaction, before its scan checkpoint.
  Future<int> store(
    MediaRow media,
    AnalyzeImageResponse analysis, {
    int? frameNumber,
    int? timestampMs,
  }) async {
    if (analysis.characters.isEmpty) return 0;
    final existing =
        await (db.select(db.characterSamples)..where(
              (s) =>
                  s.mediaId.equals(media.id) &
                  (frameNumber == null
                      ? s.frameNumber.isNull()
                      : s.frameNumber.equals(frameNumber)),
            ))
            .get();
    final rows = await db
        .customSelect(
          '''
      SELECT * FROM (
        SELECT identity_id, descriptor, ROW_NUMBER() OVER (
          PARTITION BY identity_id ORDER BY score DESC, id DESC) AS n
        FROM character_samples WHERE model_id = ?
      ) WHERE n <= 12
      ''',
          variables: [const Variable(characterModelId)],
        )
        .get();
    final candidates = <int, List<List<double>>>{};
    for (final row in rows) {
      final blob = row.read<Uint8List>('descriptor');
      if (blob.length != characterDescriptorDim * 4) continue;
      final data = ByteData.sublistView(blob);
      (candidates[row.read<int>('identity_id')] ??= []).add([
        for (var i = 0; i < characterDescriptorDim; i++)
          data.getFloat32(i * 4, Endian.little),
      ]);
    }
    final usedSamples = <int>{};
    // Also protect identities already present in this frame after a partial/retried scan.
    final occupied = {for (final s in existing) s.identityId};
    var inserted = 0;
    for (final c in analysis.characters) {
      if (c.modelId != characterModelId ||
          c.descriptor.length != characterDescriptorDim) {
        throw const FormatException('Unsupported character descriptor');
      }
      final n = c.bbox.normalized(analysis.imageW, analysis.imageH);
      final box = clampBox(n.x, n.y, n.w, n.h);
      CharacterSampleRow? same;
      for (final s in existing) {
        if (!usedSamples.contains(s.id) &&
            iou(box, (x: s.bboxX, y: s.bboxY, w: s.bboxW, h: s.bboxH)) >= .65) {
          same = s;
          break;
        }
      }
      if (same != null) {
        usedSamples.add(same.id);
        continue; // preserve manual corrections and idempotency
      }
      final ranked = <(int, double)>[];
      for (final entry in candidates.entries) {
        if (occupied.contains(entry.key)) continue;
        final scores = [
          for (final d in entry.value) characterSimilarity(c.descriptor, d),
        ]..sort((a, b) => b.compareTo(a));
        ranked.add((entry.key, scores.first));
      }
      ranked.sort((a, b) => b.$2.compareTo(a.$2));
      int? identity;
      if (ranked.isNotEmpty &&
          ranked.first.$2 >= characterAutoMatch &&
          ranked.first.$2 - (ranked.length > 1 ? ranked[1].$2 : 0) >=
              characterMatchMargin) {
        identity = ranked.first.$1;
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      identity ??= await db
          .into(db.characterIdentities)
          .insert(CharacterIdentitiesCompanion.insert(createdAt: now));
      occupied.add(identity);
      (candidates[identity] ??= []).add(c.descriptor);
      final id = await db
          .into(db.characterSamples)
          .insert(
            CharacterSamplesCompanion.insert(
              identityId: identity,
              mediaId: media.id,
              modelId: c.modelId,
              descriptor: packFloat32(c.descriptor),
              bboxX: box.x,
              bboxY: box.y,
              bboxW: box.w,
              bboxH: box.h,
              score: c.score,
              frameNumber: Value(frameNumber),
              timestampMs: Value(timestampMs),
              createdAt: now,
            ),
          );
      if (c.cropJpeg != null) {
        final path = await files.write('characters/$id.jpg', c.cropJpeg!);
        await (db.update(db.characterSamples)..where((s) => s.id.equals(id)))
            .write(CharacterSamplesCompanion(cropPath: Value(path)));
      }
      inserted++;
    }
    return inserted;
  }
}
