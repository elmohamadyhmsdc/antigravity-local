import 'package:drift/drift.dart';
import '../db/app_database.dart';

class ReviewTarget {
  const ReviewTarget(this.kind, this.id);
  final String kind;
  final int id;
}

/// Every actual occurrence, including photos linked to a deduplicated face.
/// Its box belongs to that occurrence, not to the canonical crop's source.
class ReviewVisual {
  const ReviewVisual({
    required this.target,
    required this.mediaId,
    required this.assetId,
    required this.mediaKind,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.timestampMs,
    required this.cropPath,
  });
  final ReviewTarget target;
  final int? mediaId;
  final String? assetId;
  final String mediaKind;
  final double x, y, w, h;
  final int? timestampMs;
  final String? cropPath;
}

class ReviewVisualRepository {
  ReviewVisualRepository(this.db);
  final AppDatabase db;

  Future<List<ReviewVisual>> load(List<ReviewTarget> targets) async {
    final order = {
      for (var i = 0; i < targets.length; i++)
        '${targets[i].kind}:${targets[i].id}': i,
    };
    final output = <ReviewVisual>[];
    for (final kind in ['f', 'b']) {
      final ids = targets
          .where((t) => t.kind == kind)
          .map((t) => t.id)
          .toSet()
          .toList();
      for (var offset = 0; offset < ids.length; offset += 300) {
        final chunk = ids.skip(offset).take(300).toList();
        final table = kind == 'f' ? 'faces' : 'bodies';
        final rows = await db.customSelect('''
          SELECT t.id AS target_id, m.id AS media_id, m.asset_id, m.kind AS media_kind,
            COALESCE(d.x, t.bbox_x) AS x, COALESCE(d.y, t.bbox_y) AS y,
            COALESCE(d.w, t.bbox_w) AS w, COALESCE(d.h, t.bbox_h) AS h,
            COALESCE(d.timestamp_ms, t.timestamp_ms) AS timestamp_ms, t.crop_path
          FROM $table t LEFT JOIN media_detections d ON d.ref_id = t.id AND d.kind = '$kind'
          LEFT JOIN media m ON m.id = COALESCE(d.media_id, t.media_id)
          WHERE t.id IN (${List.filled(chunk.length, '?').join(',')}) ORDER BY t.id, m.id, timestamp_ms
        ''', variables: chunk.map(Variable.withInt).toList()).get();
        for (final r in rows) {
          output.add(
            ReviewVisual(
              target: ReviewTarget(kind, r.read<int>('target_id')),
              mediaId: r.readNullable<int>('media_id'),
              assetId: r.readNullable<String>('asset_id'),
              mediaKind: r.readNullable<String>('media_kind') ?? 'photo',
              x: r.read<double>('x'),
              y: r.read<double>('y'),
              w: r.read<double>('w'),
              h: r.read<double>('h'),
              timestampMs: r.readNullable<int>('timestamp_ms'),
              cropPath: r.readNullable<String>('crop_path'),
            ),
          );
        }
      }
    }
    output.sort((a, b) {
      final target = order['${a.target.kind}:${a.target.id}']!.compareTo(
        order['${b.target.kind}:${b.target.id}']!,
      );
      if (target != 0) return target;
      final media = (a.mediaId ?? -1).compareTo(b.mediaId ?? -1);
      return media != 0
          ? media
          : (a.timestampMs ?? -1).compareTo(b.timestampMs ?? -1);
    });
    return output;
  }
}
