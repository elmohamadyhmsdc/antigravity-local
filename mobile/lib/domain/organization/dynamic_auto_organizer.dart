import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../data/db/app_database.dart';
import '../../data/platform/media_organizer.dart';
import 'master_person_resolver.dart';
import 'person_media_organizer.dart';
import 'sidecar_metadata.dart';
import 'sidecar_storage.dart';

class DynamicAutoOrganizer {
  const DynamicAutoOrganizer({
    required this.db,
    required this.organizer,
    this.sidecarStorage = const SidecarStorage(),
    this.masterResolver = const MasterPersonResolver(),
    this.enabled,
    this.deferWhileScanning,
  });

  final AppDatabase db;
  final PersonMediaOrganizer organizer;
  final SidecarStorage sidecarStorage;
  final MasterPersonResolver masterResolver;
  final Future<bool> Function()? enabled;
  final bool Function(Iterable<int> mediaIds)? deferWhileScanning;

  /// Syncs one media item and its sidecar to its target folder.
  Future<OriginalMoveResult?> syncMedia(
    int mediaId, {
    String? rootDirectory,
    int? explicitMasterId,
  }) async {
    final results = await syncBatch(
      [mediaId],
      rootDirectory: rootDirectory,
      explicitMasters: {mediaId: ?explicitMasterId},
    );
    return results[mediaId];
  }

  /// Whether photos can be moved with no confirmation sheet at all (the user granted Android's "Media
  /// management" access once). A library of thousands of photos cannot wait for a human between batches, so
  /// unattended moves run only when this is true.
  Future<bool> canMoveSilently() async {
    final bridge = organizer.bridge;
    return bridge is AndroidMediaOrganizer
        ? await bridge.canMoveWithoutPrompt()
        : true;
  }

  /// Moves many photos in ONE request, so Android asks for permission once per batch of up to 1000 files
  /// (and not at all when the user has granted "Media management"), instead of once per photo.
  Future<Map<int, OriginalMoveResult>> syncBatch(
    Iterable<int> mediaIds, {
    String? rootDirectory,
    Map<int, int> explicitMasters = const {},
  }) async {
    if (!(await enabled?.call() ?? true)) return {};
    final ids = mediaIds.toSet();
    if (deferWhileScanning?.call(ids) ?? false) return {};
    return _syncBatch(
      ids,
      rootDirectory: rootDirectory,
      explicitMasters: explicitMasters,
    );
  }

  Future<Map<int, OriginalMoveResult>> _syncBatch(
    Iterable<int> mediaIds, {
    String? rootDirectory,
    required Map<int, int> explicitMasters,
  }) async {
    if (organizer.isRunning) return {};
    final staged = <_Staged>[];
    for (final id in mediaIds.toSet()) {
      final one = await _stage(id, explicitMasters[id]);
      if (one != null) staged.add(one);
    }
    if (staged.isEmpty) return {};
    final plan = await organizer.plan(
      {for (final s in staged) s.master.id},
      choices: {for (final s in staged) s.media.id: s.master.id},
      mediaIds: {for (final s in staged) s.media.id},
    );
    final items = {
      for (final item in plan)
        if (item.canApply) item.media.id: item,
    };
    if (items.isEmpty) return {};
    final results = await organizer.apply(items.values.toList());
    final out = <int, OriginalMoveResult>{};
    for (final s in staged) {
      final item = items[s.media.id];
      final result = results
          .where((r) => r.assetId == s.media.assetId)
          .firstOrNull;
      if (item == null || result == null) continue;
      out[s.media.id] = result;
      await _finish(s, item, result, rootDirectory);
    }
    return out;
  }

  /// Who owns this media and what the app knows about it; null when nobody does.
  Future<_Staged?> _stage(int mediaId, int? explicitMasterId) async {
    final media = await (db.select(
      db.media,
    )..where((m) => m.id.equals(mediaId))).getSingleOrNull();
    if (media == null) return null;

    final detections = await (db.select(
      db.mediaDetections,
    )..where((d) => d.mediaId.equals(mediaId))).get();
    final faceRefs = [
      for (final d in detections)
        if (d.kind == 'f') d.refId,
    ];
    final bodyRefs = [
      for (final d in detections)
        if (d.kind == 'b') d.refId,
    ];
    final faces =
        await (db.select(db.faces)..where(
              (f) =>
                  (f.mediaId.equals(mediaId) | f.id.isIn(faceRefs)) &
                  f.hidden.not() &
                  (f.ownership.isNull() | f.ownership.equals('none').not()),
            ))
            .get();
    final bodies =
        await (db.select(db.bodies)..where(
              (b) =>
                  (b.mediaId.equals(mediaId) | b.id.isIn(bodyRefs)) &
                  b.hidden.not() &
                  (b.ownership.isNull() | b.ownership.equals('none').not()),
            ))
            .get();
    final ownerIds = (await organizer.ownersForMedia([mediaId]))[mediaId];
    if (ownerIds == null || ownerIds.isEmpty) return null;
    if (explicitMasterId != null && !ownerIds.contains(explicitMasterId)) {
      return null;
    }

    final candidates = await (db.select(
      db.persons,
    )..where((p) => p.id.isIn(ownerIds))).get();
    if (candidates.isEmpty) return null;

    final faceBoxes = <int, List<double>>{};
    final occurrences = {
      for (final d in detections)
        if (d.kind == 'f') d.refId: d,
    };
    for (final face in faces) {
      final owner = face.personId;
      if (owner == null) continue;
      final d = occurrences[face.id];
      final box = [
        d?.x ?? face.bboxX,
        d?.y ?? face.bboxY,
        d?.w ?? face.bboxW,
        d?.h ?? face.bboxH,
      ];
      final prior = faceBoxes[owner];
      if (prior == null || box[2] * box[3] > prior[2] * prior[3]) {
        faceBoxes[owner] = box;
      }
    }

    final masterPerson = masterResolver.resolveMasterByBbox(
      candidates: candidates,
      faceBoxes: faceBoxes,
      explicitChoice: explicitMasterId,
    );

    if (masterPerson == null || !canOrganizePerson(masterPerson)) return null;

    return _Staged(media, faces, bodies, masterPerson);
  }

  Future<void> _finish(
    _Staged staged,
    PersonOrganizeItem item,
    OriginalMoveResult result,
    String? rootDirectory,
  ) async {
    final media = staged.media;
    final faces = staged.faces;
    final bodies = staged.bodies;
    final masterPerson = staged.master;
    final mediaId = media.id;
    if (result.moved && result.actual != null) {
      // Find Group if present
      String? groupName;
      if (masterPerson.groupId != null) {
        final g = await (db.select(
          db.identityGroups,
        )..where((g) => g.id.equals(masterPerson.groupId!))).getSingleOrNull();
        groupName = g?.name;
      }

      // Build Person names lookup
      final people = await db.select(db.persons).get();
      final peopleNames = {for (final p in people) p.id: p.name};

      // Formulate Sidecar Metadata
      final detections = await (db.select(
        db.mediaDetections,
      )..where((d) => d.mediaId.equals(mediaId))).get();
      final sensitive = await (db.select(
        db.sensitiveRegions,
      )..where((s) => s.mediaId.equals(mediaId))).get();

      final sidecar = SidecarMetadata(
        version: 1,
        assetId: media.assetId,
        mediaInfo: SidecarMediaInfo(
          kind: media.kind,
          width: media.width ?? 0,
          height: media.height ?? 0,
          durationMs: media.durationMs ?? 0,
          takenAt: media.takenAt,
          modifiedAt: result.actual!.modifiedAt,
          isSensitive: media.isSensitive,
        ),
        ownership: SidecarOwnership(
          groupId: masterPerson.groupId,
          groupName: groupName,
          masterPersonId: masterPerson.id,
          masterPersonName: masterPerson.name,
          masterPersonKind: masterPerson.kind,
        ),
        faces: [
          for (final f in faces)
            SidecarFace(
              faceId: f.id,
              personId: f.personId,
              personName: f.personId != null ? peopleNames[f.personId!] : null,
              bbox: [f.bboxX, f.bboxY, f.bboxW, f.bboxH],
              quality: f.qualityScore,
              yaw: f.yaw ?? 0.0,
              pitch: f.pitch ?? 0.0,
              roll: f.roll ?? 0.0,
              embeddingModel: f.modelId,
              embedding: Float32List.view(
                f.embedding.buffer,
                f.embedding.offsetInBytes,
                f.embedding.lengthInBytes ~/ 4,
              ),
              trackId: f.trackId,
            ),
        ],
        bodies: [
          for (final b in bodies)
            SidecarBody(
              bodyId: b.id,
              personId: b.personId,
              personName: b.personId != null ? peopleNames[b.personId!] : null,
              bbox: [b.bboxX, b.bboxY, b.bboxW, b.bboxH],
              keypoints: b.kpts != null
                  ? [
                      for (final p in (jsonDecode(b.kpts!) as List))
                        [for (final v in (p as List)) (v as num).toDouble()],
                    ]
                  : const [],
              appearance: b.appearance != null
                  ? Float32List.view(
                      b.appearance!.buffer,
                      b.appearance!.offsetInBytes,
                      b.appearance!.lengthInBytes ~/ 4,
                    )
                  : null,
              extent: b.extent ?? 'full',
              outline: () {
                final d = detections
                    .where((det) => det.kind == 'b' && det.refId == b.id)
                    .firstOrNull;
                if (d?.outline == null) return const <List<double>>[];
                try {
                  return [
                    for (final p in (jsonDecode(d!.outline!) as List))
                      [for (final v in (p as List)) (v as num).toDouble()],
                  ];
                } catch (_) {
                  return const <List<double>>[];
                }
              }(),
            ),
        ],
        sensitiveRegions: [
          for (final s in sensitive)
            SidecarSensitiveRegion(
              label: s.label,
              bbox: [s.x, s.y, s.w, s.h],
              exposed: s.exposed,
            ),
        ],
      );

      // The sidecar is a courtesy copy of what the app knows. The photo has already moved, so a sidecar that
      // cannot be written (the path is relative to the read-only system root, or Android refuses a .json inside
      // DCIM) must never fail the move or stop a scan.
      try {
        final root =
            rootDirectory ??
            (Platform.isAndroid ? '/storage/emulated/0' : null);
        final prefix = root != null ? '$root/' : '';
        final newMediaPath =
            '$prefix${result.actual!.path}${result.actual!.name}';
        await sidecarStorage.writeSidecar(newMediaPath, sidecar);

        // Clean up old sidecar if target location changed
        if (item.source?.available == true &&
            (item.source!.path != result.actual!.path ||
                item.source!.name != result.actual!.name)) {
          final oldMediaPath =
              '$prefix${item.source!.path}${item.source!.name}';
          await sidecarStorage.deleteSidecar(oldMediaPath);
        }
      } on FileSystemException {
        // keep the result: the photo is organized, only its sidecar is missing
      }
    }
  }

  /// A user-selected move works independently of automatic folder sync.
  Future<OriginalMoveResult?> setMasterPerson(
    int mediaId,
    int personId, {
    String? rootDirectory,
  }) async {
    final results = await _syncBatch(
      [mediaId],
      rootDirectory: rootDirectory,
      explicitMasters: {mediaId: personId},
    );
    return results[mediaId];
  }

  Future<List<OriginalMoveResult>> syncPersonGroup(
    int personId, {
    String? rootDirectory,
  }) => syncPeopleFolders([personId], rootDirectory: rootDirectory);

  Future<List<OriginalMoveResult>> syncPeopleFolders(
    Iterable<int> personIds, {
    String? rootDirectory,
  }) async {
    try {
      final named = await organizer.namedPersonIds();
      final ids = await organizer.mediaForPeople(
        personIds.where(named.contains),
      );
      final results = await syncBatch(ids, rootDirectory: rootDirectory);
      return results.values.toList();
    } catch (_) {
      // The identity change has already been saved. Remaining files can be
      // moved from the organizer preview when Android is ready.
      return [];
    }
  }
}

class _Staged {
  const _Staged(this.media, this.faces, this.bodies, this.master);
  final MediaRow media;
  final List<FaceRow> faces;
  final List<BodyRow> bodies;
  final PersonRow master;
}
