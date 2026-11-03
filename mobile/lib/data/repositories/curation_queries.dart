import 'package:drift/drift.dart' show Variable;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../db/app_database.dart';
import '../../domain/curation/auto_dataset_curator.dart';
import '../../providers.dart';

final curationQueriesProvider = Provider<CurationQueries>((ref) {
  final db = ref.watch(databaseProvider);
  return CurationQueries(db);
});

class CurationQueries {
  CurationQueries(this.db);
  final AppDatabase db;

  Future<List<CurationCandidate>> loadCandidatesForPerson(int personId) async {
    final results = <CurationCandidate>[];

    // 1. Faces
    final faceRows = await db.customSelect(
      'SELECT md.id AS det, md.media_id, md.ref_id, md.x, md.y, md.w, md.h, '
      'md.frame_number, md.timestamp_ms, f.quality_score AS q, f.yaw, f.pitch, '
      'm.asset_id, m.kind '
      'FROM media_detections md '
      'JOIN faces f ON f.id = md.ref_id '
      'JOIN media m ON m.id = md.media_id '
      "WHERE md.kind = 'f' AND f.person_id = ? AND f.hidden = 0 AND (f.ownership IS NULL OR f.ownership != 'none')",
      variables: [Variable.withInt(personId)],
    ).get();

    for (final r in faceRows) {
      results.add(CurationCandidate(
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
      ));
    }

    // 2. Bodies (Upper & Full)
    final bodyRows = await db.customSelect(
      'SELECT md.id AS det, md.media_id, md.ref_id, md.x, md.y, md.w, md.h, '
      'md.frame_number, md.timestamp_ms, b.score AS q, b.extent, '
      'm.asset_id, m.kind, '
      '(SELECT COUNT(*) FROM sensitive_regions sr WHERE sr.media_id = m.id AND sr.exposed = 1) AS exposed_count '
      'FROM media_detections md '
      'JOIN bodies b ON b.id = md.ref_id '
      'LEFT JOIN faces f ON f.id = b.face_id '
      'JOIN media m ON m.id = md.media_id '
      "WHERE md.kind = 'b' AND b.hidden = 0 AND (b.ownership IS NULL OR b.ownership != 'none') AND "
      "(b.person_id = ? OR (b.person_id IS NULL AND f.person_id = ? AND f.hidden = 0 AND (f.ownership IS NULL OR f.ownership != 'none')))",
      variables: [Variable.withInt(personId), Variable.withInt(personId)],
    ).get();

    for (final r in bodyRows) {
      final ext = r.readNullable<String>('extent');
      final isUpper = ext == 'upper';
      final exposedCount = r.readNullable<int>('exposed_count') ?? 0;
      final hasExposed = exposedCount > 0;

      results.add(CurationCandidate(
        detectionId: r.read<int>('det'),
        mediaId: r.read<int>('media_id'),
        assetId: r.read<String>('asset_id'),
        isVideo: r.read<String>('kind') == 'video',
        category: isUpper ? CurationCategory.upper : CurationCategory.body,
        quality: r.readNullable<double>('q') ?? 0.5,
        extent: ext,
        hasExposedRegion: hasExposed,
        skinRatio: hasExposed ? 0.7 : 0.25,
        frameNumber: r.readNullable<int>('frame_number'),
        timestampMs: r.readNullable<int>('timestamp_ms'),
        boxW: r.read<double>('w'),
        boxH: r.read<double>('h'),
      ));
    }

    return results;
  }
}
