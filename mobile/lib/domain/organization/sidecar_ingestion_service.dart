import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import '../../data/index/embedding_index.dart';
import '../../data/repositories/library_repository.dart' show scanVersion;
import 'sidecar_metadata.dart';

class SidecarIngestionService {
  const SidecarIngestionService({required this.db, required this.index});

  final AppDatabase db;
  final EmbeddingIndex index;

  Future<int?> ingest(SidecarMetadata meta) async {
    final now = DateTime.now().millisecondsSinceEpoch;

    return db.transaction(() async {
      // 1. Resolve or create Group
      int? localGroupId;
      final groupName = meta.ownership.groupName?.trim();
      if (groupName != null && groupName.isNotEmpty) {
        final existingGroup = await (db.select(
          db.identityGroups,
        )..where((g) => g.name.equals(groupName))).getSingleOrNull();
        if (existingGroup != null) {
          localGroupId = existingGroup.id;
        } else {
          localGroupId = await db
              .into(db.identityGroups)
              .insert(
                IdentityGroupsCompanion.insert(
                  name: groupName,
                  nameKey: groupName.toLowerCase().trim(),
                  createdAt: now,
                ),
              );
        }
      }

      // 2. Resolve or create Persons
      final personNameToId = <String, int>{};
      final personNames = <String>{
        if (meta.ownership.masterPersonName != null &&
            meta.ownership.masterPersonName!.trim().isNotEmpty)
          meta.ownership.masterPersonName!.trim(),
        for (final f in meta.faces)
          if (f.personName != null && f.personName!.trim().isNotEmpty)
            f.personName!.trim(),
        for (final b in meta.bodies)
          if (b.personName != null && b.personName!.trim().isNotEmpty)
            b.personName!.trim(),
      };

      for (final pName in personNames) {
        final existing = await (db.select(
          db.persons,
        )..where((p) => p.name.equals(pName))).getSingleOrNull();
        if (existing != null) {
          personNameToId[pName] = existing.id;
          if (localGroupId != null && existing.groupId == null) {
            await (db.update(db.persons)
                  ..where((p) => p.id.equals(existing.id)))
                .write(PersonsCompanion(groupId: Value(localGroupId)));
          }
        } else {
          final isMaster = pName == meta.ownership.masterPersonName?.trim();
          final kind = isMaster ? meta.ownership.masterPersonKind : 'person';
          final newId = await db
              .into(db.persons)
              .insert(
                PersonsCompanion.insert(
                  name: Value(pName),
                  groupId: Value(localGroupId),
                  kind: Value(kind),
                  createdAt: now,
                ),
              );
          personNameToId[pName] = newId;
        }
      }

      // 3. Upsert Media row
      int mediaId;
      final existingMedia = await (db.select(
        db.media,
      )..where((m) => m.assetId.equals(meta.assetId))).getSingleOrNull();

      if (existingMedia != null) {
        mediaId = existingMedia.id;
        await (db.update(db.media)..where((m) => m.id.equals(mediaId))).write(
          MediaCompanion(
            scanStatus: const Value('done'),
            scanVersion: const Value(scanVersion),
            width: Value(meta.mediaInfo.width),
            height: Value(meta.mediaInfo.height),
            durationMs: Value(meta.mediaInfo.durationMs),
            isSensitive: Value(meta.mediaInfo.isSensitive),
            scannedAt: Value(now),
          ),
        );
        // Clear old detections for clean in-place replacement
        await (db.delete(
          db.mediaDetections,
        )..where((d) => d.mediaId.equals(mediaId))).go();
        await (db.delete(
          db.faces,
        )..where((f) => f.mediaId.equals(mediaId))).go();
        await (db.delete(
          db.bodies,
        )..where((b) => b.mediaId.equals(mediaId))).go();
        await (db.delete(
          db.sensitiveRegions,
        )..where((s) => s.mediaId.equals(mediaId))).go();
      } else {
        mediaId = await db
            .into(db.media)
            .insert(
              MediaCompanion.insert(
                assetId: meta.assetId,
                kind: meta.mediaInfo.kind,
                width: Value(meta.mediaInfo.width),
                height: Value(meta.mediaInfo.height),
                durationMs: Value(meta.mediaInfo.durationMs),
                modifiedAt: Value(meta.mediaInfo.modifiedAt ?? now),
                takenAt: Value(meta.mediaInfo.takenAt),
                scanStatus: const Value('done'),
                scanVersion: const Value(scanVersion),
                isSensitive: Value(meta.mediaInfo.isSensitive),
                scannedAt: Value(now),
              ),
            );
      }

      // 4. Insert Faces and feed EmbeddingIndex
      final indexVectors = <(int, Float32List)>[];
      for (final f in meta.faces) {
        final pName =
            f.personName?.trim() ??
            (f.personId == meta.ownership.masterPersonId
                ? meta.ownership.masterPersonName?.trim()
                : null);
        final pId = pName != null ? personNameToId[pName] : null;
        final rawBytes = Uint8List.view(
          f.embedding.buffer,
          f.embedding.offsetInBytes,
          f.embedding.lengthInBytes,
        );

        final faceId = await db
            .into(db.faces)
            .insert(
              FacesCompanion.insert(
                mediaId: Value(mediaId),
                personId: Value(pId),
                modelId: f.embeddingModel,
                embedding: rawBytes,
                qualityScore: f.quality,
                qualityVersion: 1,
                detScore: f.quality,
                facePx: 100.0,
                sharpness: 100.0,
                yaw: Value(f.yaw),
                pitch: Value(f.pitch),
                roll: Value(f.roll),
                bboxX: f.bbox.isNotEmpty ? f.bbox[0] : 0.0,
                bboxY: f.bbox.length > 1 ? f.bbox[1] : 0.0,
                bboxW: f.bbox.length > 2 ? f.bbox[2] : 0.0,
                bboxH: f.bbox.length > 3 ? f.bbox[3] : 0.0,
                trackId: Value(f.trackId),
                createdAt: now,
              ),
            );

        // Record detection
        await db
            .into(db.mediaDetections)
            .insert(
              MediaDetectionsCompanion.insert(
                mediaId: mediaId,
                kind: 'f',
                refId: faceId,
                x: f.bbox.isNotEmpty ? f.bbox[0] : 0.0,
                y: f.bbox.length > 1 ? f.bbox[1] : 0.0,
                w: f.bbox.length > 2 ? f.bbox[2] : 0.0,
                h: f.bbox.length > 3 ? f.bbox[3] : 0.0,
              ),
            );

        indexVectors.add((faceId, f.embedding));
      }

      if (indexVectors.isNotEmpty) {
        await index.addAll(indexVectors);
      }

      // 5. Insert Bodies
      for (final b in meta.bodies) {
        final pName =
            b.personName?.trim() ??
            (b.personId == meta.ownership.masterPersonId
                ? meta.ownership.masterPersonName?.trim()
                : null);
        final pId = pName != null ? personNameToId[pName] : null;
        final appBytes = b.appearance != null
            ? Uint8List.view(
                b.appearance!.buffer,
                b.appearance!.offsetInBytes,
                b.appearance!.lengthInBytes,
              )
            : null;
        final kptsStr = b.keypoints.isNotEmpty ? jsonEncode(b.keypoints) : null;
        final outlineStr = b.outline.isNotEmpty ? jsonEncode(b.outline) : null;

        final bodyId = await db
            .into(db.bodies)
            .insert(
              BodiesCompanion.insert(
                mediaId: Value(mediaId),
                personId: Value(pId),
                bboxX: b.bbox.isNotEmpty ? b.bbox[0] : 0.0,
                bboxY: b.bbox.length > 1 ? b.bbox[1] : 0.0,
                bboxW: b.bbox.length > 2 ? b.bbox[2] : 0.0,
                bboxH: b.bbox.length > 3 ? b.bbox[3] : 0.0,
                score: 1.0,
                kpts: Value(kptsStr),
                extent: Value(b.extent),
                appearance: Value(appBytes),
                createdAt: now,
              ),
            );

        // Record detection
        await db
            .into(db.mediaDetections)
            .insert(
              MediaDetectionsCompanion.insert(
                mediaId: mediaId,
                kind: 'b',
                refId: bodyId,
                x: b.bbox.isNotEmpty ? b.bbox[0] : 0.0,
                y: b.bbox.length > 1 ? b.bbox[1] : 0.0,
                w: b.bbox.length > 2 ? b.bbox[2] : 0.0,
                h: b.bbox.length > 3 ? b.bbox[3] : 0.0,
                outline: Value(outlineStr),
              ),
            );
      }

      // 6. Insert Sensitive Regions
      for (final s in meta.sensitiveRegions) {
        await db
            .into(db.sensitiveRegions)
            .insert(
              SensitiveRegionsCompanion.insert(
                mediaId: mediaId,
                label: s.label,
                exposed: s.exposed,
                score: 1.0,
                x: s.bbox.isNotEmpty ? s.bbox[0] : 0.0,
                y: s.bbox.length > 1 ? s.bbox[1] : 0.0,
                w: s.bbox.length > 2 ? s.bbox[2] : 0.0,
                h: s.bbox.length > 3 ? s.bbox[3] : 0.0,
                modelVersion: 1,
                createdAt: now,
              ),
            );
      }

      return mediaId;
    });
  }
}
