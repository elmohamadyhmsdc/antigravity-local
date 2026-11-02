import 'dart:convert';
import 'dart:ui';

import 'package:drift/drift.dart';

import '../../data/api/dtos/analyze.dart';
import '../../data/db/app_database.dart';
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
  TargetedDetectionService({required this.db});

  final AppDatabase db;
  final Map<String, _TargetedUndoItem> _undoHistory = {};

  Future<TargetedApplyResult> apply(TargetedEntry entry) async {
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

  Future<void> undo(String undoToken) async {
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
