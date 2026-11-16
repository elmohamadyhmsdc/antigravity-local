import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:drift/drift.dart';

import '../../data/api/dtos/analyze.dart';
import '../../data/db/app_database.dart';
import '../../data/api/dtos/embedding.dart';
import '../../data/files/file_store.dart';
import '../../data/repositories/kind_corrections.dart' show sameDetectionBox;
import '../../data/repositories/sensitive_store.dart';
import '../geometry/outline.dart';

class TargetedEntry {
  const TargetedEntry({
    required this.mediaId,
    required this.kind, // 'body' | 'area' | 'face' | 'object'
    required this.bbox,
    required this.label,
    this.personId,
    this.outline,
    this.keypoints,
    this.embedding,
    this.embeddingModelId,
    this.cropJpeg,
    this.score = 1.0,
    this.facePx = 100.0,
    this.manual = false,
    this.scope = 'single', // 'single' | 'track' | 'wholeVideo'
  });

  final int mediaId;
  final String kind;
  final BBox bbox;
  final String label;
  final int? personId;
  final List<Offset>? outline;
  final List<List<double>>? keypoints;
  final String scope;
  final Float32List? embedding;
  final String? embeddingModelId;
  final Uint8List? cropJpeg;
  final double score;
  final double facePx;
  final bool manual;
}

class TargetedApplyResult {
  const TargetedApplyResult({
    required this.undoToken,
    required this.insertedId,
  });

  final String undoToken;
  final int insertedId;
}

class _TargetedUndoItem {
  _TargetedUndoItem({
    required this.kind,
    required this.insertedId,
    this.insertedOverrideId,
    this.insertedDetectionId,
    this.settingKey,
    required this.mediaId,
  });

  final String kind;
  final int insertedId;
  final int? insertedOverrideId;
  final int? insertedDetectionId;
  final String? settingKey;
  final int mediaId;
}

class TargetedDetectionService {
  TargetedDetectionService({required this.db, this.files});

  final AppDatabase db;
  final FileStore? files;
  final Map<String, _AnimeFaceUndo> _animeUndo = {};
  int _sequence = 0;
  final Map<String, _TargetedUndoItem> _undoHistory = {};

  Future<TargetedApplyResult> apply(TargetedEntry entry) async {
    if (entry.kind == 'anime_face') return _applyAnimeFace(entry);
    final media = await (db.select(
      db.media,
    )..where((m) => m.id.equals(entry.mediaId))).getSingleOrNull();
    final assetId = media?.assetId ?? 'asset_${entry.mediaId}';
    final now = DateTime.now().millisecondsSinceEpoch;
    final undoToken = 'tgt_${now}_${entry.mediaId}';

    int insertedId = 0;
    int? insertedOverrideId;
    int? insertedDetectionId;
    String? settingKey;

    if (entry.kind == 'body') {
      insertedId = await db
          .into(db.bodies)
          .insert(
            BodiesCompanion.insert(
              mediaId: Value(entry.mediaId),
              bboxX: entry.bbox.x,
              bboxY: entry.bbox.y,
              bboxW: entry.bbox.w,
              bboxH: entry.bbox.h,
              score: 1.0,
              personId: Value(entry.personId),
              linkMethod: Value(entry.personId != null ? 'manual' : null),
              kpts: Value(
                entry.keypoints != null ? jsonEncode(entry.keypoints) : null,
              ),
              createdAt: now,
            ),
          );

      insertedOverrideId = await db
          .into(db.bodyOverrides)
          .insert(
            BodyOverridesCompanion.insert(
              assetId: assetId,
              x: entry.bbox.x,
              y: entry.bbox.y,
              w: entry.bbox.w,
              h: entry.bbox.h,
              scope: Value(
                entry.scope == 'wholeVideo' || entry.scope == 'track'
                    ? 'track'
                    : 'single',
              ),
            ),
          );

      insertedDetectionId = await db
          .into(db.mediaDetections)
          .insert(
            MediaDetectionsCompanion.insert(
              mediaId: entry.mediaId,
              kind: 'b',
              refId: insertedId,
              x: entry.bbox.x,
              y: entry.bbox.y,
              w: entry.bbox.w,
              h: entry.bbox.h,
              outline: Value(encodeOutline(entry.outline, entry.bbox)),
            ),
          );
    } else if (entry.kind == 'face') {
      insertedId = await db
          .into(db.faces)
          .insert(
            FacesCompanion.insert(
              mediaId: Value(entry.mediaId),
              modelId: 'buffalo_l@1',
              bboxX: entry.bbox.x,
              bboxY: entry.bbox.y,
              bboxW: entry.bbox.w,
              bboxH: entry.bbox.h,
              detScore: 1.0,
              qualityScore: 1.0,
              qualityVersion: 1,
              facePx: 100.0,
              sharpness: 1.0,
              personId: Value(entry.personId),
              embedding: Uint8List(0),
              createdAt: now,
            ),
          );

      insertedOverrideId = await db
          .into(db.faceOverrides)
          .insert(
            FaceOverridesCompanion.insert(
              assetId: assetId,
              x: entry.bbox.x,
              y: entry.bbox.y,
              w: entry.bbox.w,
              h: entry.bbox.h,
              scope: Value(
                entry.scope == 'wholeVideo' || entry.scope == 'track'
                    ? 'track'
                    : 'single',
              ),
            ),
          );

      insertedDetectionId = await db
          .into(db.mediaDetections)
          .insert(
            MediaDetectionsCompanion.insert(
              mediaId: entry.mediaId,
              kind: 'f',
              refId: insertedId,
              x: entry.bbox.x,
              y: entry.bbox.y,
              w: entry.bbox.w,
              h: entry.bbox.h,
              outline: Value(encodeOutline(entry.outline, entry.bbox)),
            ),
          );
    } else if (entry.kind == 'object') {
      insertedId = await db
          .into(db.equipmentObjects)
          .insert(
            EquipmentObjectsCompanion.insert(
              mediaId: entry.mediaId,
              objectKey: 'manual:$now',
              label: entry.label,
              x: entry.bbox.x,
              y: entry.bbox.y,
              w: entry.bbox.w,
              h: entry.bbox.h,
              state: const Value('confirmed'),
            ),
          );

      insertedDetectionId = await db
          .into(db.mediaDetections)
          .insert(
            MediaDetectionsCompanion.insert(
              mediaId: entry.mediaId,
              kind: 'e',
              refId: insertedId,
              x: entry.bbox.x,
              y: entry.bbox.y,
              w: entry.bbox.w,
              h: entry.bbox.h,
              outline: Value(encodeOutline(entry.outline, entry.bbox)),
            ),
          );
    } else if (entry.kind == 'area') {
      settingKey =
          'area.name.${entry.mediaId}_${(entry.bbox.x * 1000).toInt()}_${(entry.bbox.y * 1000).toInt()}';
      await db.putSetting(settingKey, entry.label);

      insertedId = await db
          .into(db.sensitiveRegions)
          .insert(
            SensitiveRegionsCompanion.insert(
              mediaId: entry.mediaId,
              label: entry.label,
              exposed: true,
              score: 1.0,
              x: entry.bbox.x,
              y: entry.bbox.y,
              w: entry.bbox.w,
              h: entry.bbox.h,
              modelVersion: 1,
              userState: const Value('confirmed'),
              createdAt: now,
            ),
          );

      await SensitiveStore(db).markChecked(entry.mediaId, 1);

      insertedDetectionId = await db
          .into(db.mediaDetections)
          .insert(
            MediaDetectionsCompanion.insert(
              mediaId: entry.mediaId,
              kind: 'a',
              refId: insertedId,
              x: entry.bbox.x,
              y: entry.bbox.y,
              w: entry.bbox.w,
              h: entry.bbox.h,
              outline: Value(encodeOutline(entry.outline, entry.bbox)),
            ),
          );
    }

    _undoHistory[undoToken] = _TargetedUndoItem(
      kind: entry.kind,
      insertedId: insertedId,
      insertedOverrideId: insertedOverrideId,
      insertedDetectionId: insertedDetectionId,
      settingKey: settingKey,
      mediaId: entry.mediaId,
    );

    return TargetedApplyResult(undoToken: undoToken, insertedId: insertedId);
  }

  Future<TargetedApplyResult> _applyAnimeFace(TargetedEntry entry) async {
    final vector = entry.embedding;
    final box = entry.bbox;
    final store = files;
    if (store == null ||
        entry.embeddingModelId != characterEmbeddingModelId ||
        vector == null || vector.length != characterEmbeddingDim ||
        vector.any((v) => !v.isFinite) ||
        (vector.fold<double>(0, (sum, v) => sum + v * v) - 1).abs() > .01 ||
        entry.cropJpeg == null || entry.cropJpeg!.isEmpty ||
        !entry.score.isFinite || entry.score < 0 || entry.score > 1 ||
        !entry.facePx.isFinite || entry.facePx < 8) {
      throw const FormatException('A character face needs a valid CCIP identity and crop. Update the PC server and retry.');
    }
    if ([box.x, box.y, box.w, box.h].any((v) => !v.isFinite) ||
        box.x < 0 || box.y < 0 || box.w <= 0 || box.h <= 0 ||
        box.x + box.w > 1.000001 || box.y + box.h > 1.000001) {
      throw const FormatException('The face box must be inside the photo.');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final token = 'anime_${now}_${_sequence++}';
    String? cropPath;
    late _AnimeFaceUndo undo;
    try {
      await db.transaction(() async {
        final media = await (db.select(db.media)
              ..where((m) => m.id.equals(entry.mediaId))).getSingleOrNull();
        if (media == null || media.kind != 'photo') {
          throw StateError('Select an existing photo to add an anime face.');
        }
        final existing = await (db.select(db.mediaDetections)
              ..where((d) => d.mediaId.equals(media.id) & d.kind.equals('f'))).get();
        for (final detection in existing) {
          if (sameDetectionBox(
            (x: box.x, y: box.y, w: box.w, h: box.h),
            (x: detection.x, y: detection.y, w: detection.w, h: detection.h),
            'face',
          )) {
            throw StateError('A face is already marked here. Select its existing box to edit it.');
          }
        }
        int? personId = entry.personId;
        int? createdPersonId;
        if (personId != null) {
          final ownerId = personId;
          final owner = await (db.select(db.persons)
                ..where((p) => p.id.equals(ownerId))).getSingle();
          if (owner.kind != 'character') {
            throw StateError('An anime face can only belong to a character.');
          }
        } else if (entry.label.trim().isNotEmpty) {
          personId = createdPersonId = await db.into(db.persons).insert(
            PersonsCompanion.insert(
              name: Value(entry.label.trim()),
              kind: const Value('character'),
              createdAt: now,
            ),
          );
        }
        final faceId = await db.into(db.faces).insert(
          FacesCompanion.insert(
            mediaId: Value(media.id),
            modelId: characterEmbeddingModelId,
            kind: const Value('character'),
            embedding: embeddingToBlob(vector),
            bboxX: box.x, bboxY: box.y, bboxW: box.w, bboxH: box.h,
            // A user supplied box is explicit evidence, not detector confidence.
            detScore: entry.score,
            qualityScore: entry.manual ? .70 : entry.score,
            qualityVersion: 100,
            facePx: entry.facePx,
            sharpness: 0,
            personId: Value(personId),
            createdAt: now,
          ),
        );
        cropPath = store.faceCropPath(faceId);
        await store.writeFaceCrop(faceId, entry.cropJpeg!);
        await (db.update(db.faces)..where((f) => f.id.equals(faceId))).write(
          FacesCompanion(cropPath: Value(cropPath)),
        );
        if (createdPersonId != null) {
          final newOwnerId = createdPersonId;
          await (db.update(db.persons)..where((p) => p.id.equals(newOwnerId)))
              .write(PersonsCompanion(avatarFaceId: Value(faceId)));
        }
        final overrideId = await db.into(db.kindOverrides).insert(
          KindOverridesCompanion.insert(
            assetId: media.assetId, kind: 'character', part: const Value('face'),
            x: Value(box.x), y: Value(box.y), w: Value(box.w), h: Value(box.h),
            createdAt: now,
          ),
        );
        final detectionId = await db.into(db.mediaDetections).insert(
          MediaDetectionsCompanion.insert(
            mediaId: media.id, kind: 'f', refId: faceId,
            x: box.x, y: box.y, w: box.w, h: box.h,
          ),
        );
        undo = _AnimeFaceUndo(faceId, detectionId, overrideId, createdPersonId, cropPath!);
      });
    } catch (_) {
      await store.delete(cropPath);
      rethrow;
    }
    _animeUndo[token] = undo;
    return TargetedApplyResult(undoToken: token, insertedId: undo.faceId);
  }

  Future<void> undo(String undoToken) async {
    final anime = _animeUndo[undoToken];
    if (anime != null) {
      await db.transaction(() async {
        await (db.delete(db.mediaDetections)
              ..where((d) => d.id.equals(anime.detectionId))).go();
        await (db.update(db.persons)
              ..where((p) => p.avatarFaceId.equals(anime.faceId)))
            .write(const PersonsCompanion(avatarFaceId: Value(null)));
        await (db.delete(db.faces)
              ..where((f) => f.id.equals(anime.faceId))).go();
        await (db.delete(db.kindOverrides)
              ..where((o) => o.id.equals(anime.overrideId))).go();
        if (anime.createdPersonId case final personId?) {
          await db.customUpdate(
            'DELETE FROM persons WHERE id = ? '
            'AND NOT EXISTS (SELECT 1 FROM faces WHERE person_id = ?) '
            'AND NOT EXISTS (SELECT 1 FROM bodies WHERE person_id = ?)',
            variables: [Variable.withInt(personId), Variable.withInt(personId),
              Variable.withInt(personId)],
            updates: {db.persons},
          );
        }
      });
      _animeUndo.remove(undoToken);
      await files?.delete(anime.cropPath);
      return;
    }
    final item = _undoHistory.remove(undoToken);
    if (item == null) return;

    if (item.insertedDetectionId != null) {
      await (db.delete(
        db.mediaDetections,
      )..where((d) => d.id.equals(item.insertedDetectionId!))).go();
    }

    if (item.kind == 'body') {
      await (db.delete(
        db.bodies,
      )..where((b) => b.id.equals(item.insertedId))).go();
      if (item.insertedOverrideId != null) {
        await (db.delete(
          db.bodyOverrides,
        )..where((o) => o.id.equals(item.insertedOverrideId!))).go();
      }
    } else if (item.kind == 'face') {
      await (db.delete(
        db.faces,
      )..where((f) => f.id.equals(item.insertedId))).go();
      if (item.insertedOverrideId != null) {
        await (db.delete(
          db.faceOverrides,
        )..where((o) => o.id.equals(item.insertedOverrideId!))).go();
      }
    } else if (item.kind == 'object') {
      await (db.delete(
        db.equipmentObjects,
      )..where((o) => o.id.equals(item.insertedId))).go();
    } else if (item.kind == 'area') {
      await (db.delete(
        db.sensitiveRegions,
      )..where((s) => s.id.equals(item.insertedId))).go();
      if (item.settingKey != null) {
        await (db.delete(
          db.settings,
        )..where((s) => s.key.equals(item.settingKey!))).go();
      }
      await SensitiveStore(db).recompute(item.mediaId);
    }
  }
}

class _AnimeFaceUndo {
  const _AnimeFaceUndo(this.faceId, this.detectionId, this.overrideId,
      this.createdPersonId, this.cropPath);
  final int faceId;
  final int detectionId;
  final int overrideId;
  final int? createdPersonId;
  final String cropPath;
}
