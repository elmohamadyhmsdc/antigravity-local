import '../db/app_database.dart';

class LibraryInsights {
  LibraryInsights(
    this.stats,
    this.scanned,
    this.failed,
    this.identifiedFaces,
    this.bodies,
    this.identifiedBodies,
    this.topPeople,
  );
  final LibraryStats stats;
  final int scanned, failed, identifiedFaces, bodies, identifiedBodies;
  final List<({int id, String? name, int mediaCount})> topPeople;
  int get mediaCount => stats.photos + stats.videos;
}

/// Aggregates are computed by SQLite; no original images or embeddings are loaded.
class InsightsRepository {
  InsightsRepository(this.db);
  final AppDatabase db;

  Stream<LibraryInsights> watch() => db
      .customSelect(
        '''
    SELECT
      (SELECT COUNT(*) FROM persons) AS people,
      (SELECT COUNT(*) FROM faces) AS faces,
      (SELECT COUNT(*) FROM media WHERE kind = 'photo') AS photos,
      (SELECT COUNT(*) FROM media WHERE kind = 'video') AS videos,
      (SELECT COUNT(*) FROM media WHERE scan_status = 'done') AS scanned,
      (SELECT COUNT(*) FROM media WHERE scan_status = 'failed') AS failed,
      (SELECT COUNT(*) FROM faces WHERE person_id IS NOT NULL) AS identified_faces,
      (SELECT COUNT(*) FROM faces WHERE person_id IS NULL AND review_dismissed = 0) AS unsorted,
      (SELECT COUNT(*) FROM bodies) AS bodies,
      (SELECT COUNT(*) FROM bodies b LEFT JOIN faces f ON f.id = b.face_id
        WHERE COALESCE(f.person_id, b.person_id) IS NOT NULL) AS identified_bodies
    ''',
        readsFrom: {
          db.persons,
          db.media,
          db.faces,
          db.bodies,
          db.mediaDetections,
        },
      )
      .watchSingle()
      .asyncMap((row) async {
        final top = await db
            .customSelect(
              '''
        WITH sightings AS (
          SELECT d.media_id, f.person_id FROM media_detections d
          JOIN faces f ON d.kind = 'f' AND f.id = d.ref_id
          UNION
          SELECT d.media_id, COALESCE(f.person_id, b.person_id) FROM media_detections d
          JOIN bodies b ON d.kind = 'b' AND b.id = d.ref_id
          LEFT JOIN faces f ON f.id = b.face_id
        )
        SELECT p.id, p.name, COUNT(DISTINCT s.media_id) AS media_count
        FROM persons p JOIN sightings s ON s.person_id = p.id
        GROUP BY p.id ORDER BY media_count DESC, p.id LIMIT 10
      ''',
              readsFrom: {db.persons, db.faces, db.bodies, db.mediaDetections},
            )
            .get();
        return LibraryInsights(
          LibraryStats(
            people: row.read<int>('people'),
            faces: row.read<int>('faces'),
            photos: row.read<int>('photos'),
            videos: row.read<int>('videos'),
            unsorted: row.read<int>('unsorted'),
          ),
          row.read<int>('scanned'),
          row.read<int>('failed'),
          row.read<int>('identified_faces'),
          row.read<int>('bodies'),
          row.read<int>('identified_bodies'),
          [
            for (final p in top)
              (
                id: p.read<int>('id'),
                name: p.readNullable<String>('name'),
                mediaCount: p.read<int>('media_count'),
              ),
          ],
        );
      });
}
