import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../domain/identity/identity_selection.dart';
import '../../domain/scan/scan_math.dart' show appearanceFromBlob;
import '../api/dtos/embedding.dart' show vectorFromBlob;
import '../db/app_database.dart';
import '../../domain/curation/auto_dataset_curator.dart';
import '../../providers.dart';

final curationQueriesProvider = Provider<CurationQueries>((ref) {
  final db = ref.watch(databaseProvider);
  return CurationQueries(db);
});

/// A face smaller than this (px, as the PC measured it) carries too little detail to train on
/// (real faces; drawn faces are cleaner and may be smaller).
const curationMinFacePx = 80.0;
const curationMinCharacterFacePx = 48.0;

/// A body shorter than this in pixels teaches a model nothing about the person.
const curationMinBodyHeightPx = 384.0;

class CurationQueries {
  CurationQueries(this.db);
  final AppDatabase db;

  Future<List<CurationCandidate>> loadCandidatesForPerson(int personId) async {
    final results = <CurationCandidate>[];

    // 1. Faces: stored, visible, big enough to learn from
    final faceRows = await db
        .customSelect(
          'SELECT md.id AS det, md.media_id, md.ref_id, md.x, md.y, md.w, md.h, '
          'md.frame_number, md.timestamp_ms, f.quality_score AS q, f.yaw, f.pitch, '
          'f.face_px, f.embedding, m.asset_id, m.kind '
          'FROM media_detections md '
          'JOIN faces f ON f.id = md.ref_id '
          'JOIN media m ON m.id = md.media_id '
          "WHERE md.kind = 'f' AND f.person_id = ? AND f.hidden = 0 AND (f.ownership IS NULL OR f.ownership != 'none') "
          "AND f.face_px >= CASE WHEN f.kind = 'character' THEN ? ELSE ? END",
          variables: [
            Variable.withInt(personId),
            Variable.withReal(curationMinCharacterFacePx),
            Variable.withReal(curationMinFacePx),
          ],
        )
        .get();

    for (final r in faceRows) {
      results.add(
        CurationCandidate(
          detectionId: r.read<int>('det'),
          mediaId: r.read<int>('media_id'),
          assetId: r.read<String>('asset_id'),
          isVideo: r.read<String>('kind') == 'video',
          category: CurationCategory.face,
          quality: r.readNullable<double>('q') ?? 0.5,
          yaw: r.readNullable<double>('yaw'),
          pitch: r.readNullable<double>('pitch'),
          frameNumber: r.readNullable<int>('frame_number'),
          timestampMs: r.readNullable<int>('timestamp_ms'),
          boxW: r.read<double>('w'),
          boxH: r.read<double>('h'),
          refId: r.read<int>('ref_id'),
          facePx: r.read<double>('face_px'),
          embedding: _vector(r.readNullable<Uint8List>('embedding')),
        ),
      );
    }

    // Faces that do not look like the rest of this person are somebody else's picture (a wrong grouping):
    // neither they nor the bodies tied to them may train this person's model.
    final seen = <int, IdentityFace>{};
    for (final c in results) {
      final e = c.embedding;
      if (c.refId != null && e != null) {
        seen[c.refId!] = IdentityFace(
          id: c.refId!,
          embedding: e,
          quality: c.quality,
          yaw: c.yaw,
          pitch: c.pitch,
        );
      }
    }
    final notThem = selectIdentity(
      seen.values.toList(),
      dedupe: false,
    ).outliers.toSet();
    results.removeWhere((c) => c.refId != null && notThem.contains(c.refId));

    // 2. Bodies (upper & full). Only bodies that are this person's for a reason that holds: the body
    // of one of their faces, or a link the user made. An outfit / weak-face / event guess is evidence for
    // grouping, not a reason to train on a body. A head-and-shoulders crop is a face picture, not a body.
    final bodyRows = await db
        .customSelect(
          'SELECT md.id AS det, md.media_id, md.ref_id, md.x, md.y, md.w, md.h, '
          'md.frame_number, md.timestamp_ms, b.score AS q, b.extent, b.appearance, b.face_id, '
          'm.asset_id, m.kind, m.height AS media_h, '
          '(SELECT COUNT(*) FROM sensitive_regions sr WHERE sr.body_id = b.id AND sr.exposed = 1) AS exposed_count '
          'FROM media_detections md '
          'JOIN bodies b ON b.id = md.ref_id '
          'LEFT JOIN faces f ON f.id = b.face_id '
          'JOIN media m ON m.id = md.media_id '
          "WHERE md.kind = 'b' AND b.hidden = 0 AND (b.ownership IS NULL OR b.ownership != 'none') "
          "AND (b.extent IS NULL OR b.extent != 'head') AND "
          "((b.person_id = ? AND (b.link_method IS NULL OR b.link_method = 'manual')) OR "
          "(b.person_id IS NULL AND f.person_id = ? AND f.hidden = 0 AND (f.ownership IS NULL OR f.ownership != 'none')))",
          variables: [Variable.withInt(personId), Variable.withInt(personId)],
        )
        .get();

    for (final r in bodyRows) {
      final ownFace = r.readNullable<int>('face_id');
      if (ownFace != null && notThem.contains(ownFace)) continue;
      final mediaHeight = r.readNullable<int>('media_h');
      if (mediaHeight != null &&
          mediaHeight > 0 &&
          r.read<double>('h') * mediaHeight < curationMinBodyHeightPx) {
        continue;
      }
      final ext = r.readNullable<String>('extent');
      final isUpper = ext == 'upper';
      final hasExposed = (r.readNullable<int>('exposed_count') ?? 0) > 0;
      final appearance = r.readNullable<Uint8List>('appearance');

      results.add(
        CurationCandidate(
          detectionId: r.read<int>('det'),
          mediaId: r.read<int>('media_id'),
          assetId: r.read<String>('asset_id'),
          isVideo: r.read<String>('kind') == 'video',
          category: isUpper ? CurationCategory.upper : CurationCategory.body,
          quality: r.readNullable<double>('q') ?? 0.5,
          extent: ext,
          hasExposedRegion: hasExposed,
          // measured nowhere: an exposed region is the only skin evidence there is
          skinRatio: hasExposed ? 0.7 : 0.0,
          frameNumber: r.readNullable<int>('frame_number'),
          timestampMs: r.readNullable<int>('timestamp_ms'),
          boxW: r.read<double>('w'),
          boxH: r.read<double>('h'),
          refId: r.read<int>('ref_id'),
          appearance: appearance == null || appearance.isEmpty
              ? null
              : appearanceFromBlob(appearance),
        ),
      );
    }

    return results;
  }

  static Float32List? _vector(Uint8List? blob) {
    if (blob == null || blob.isEmpty) return null;
    try {
      return vectorFromBlob(blob);
    } on FormatException {
      return null;
    }
  }
}
