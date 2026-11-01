import 'dart:convert';

import 'package:drift/drift.dart';

import '../db/app_database.dart';

const actionFramePrefix = 'action.frame.v1.';
const actionCatalogPrefix = 'action.catalog.v1.';

/// Called inside the identity merge transaction; examples and reviewed events
/// refer to current local person IDs, while matching remains identity agnostic.
Future<void> mergeActionPersonReferences(
  AppDatabase db,
  int source,
  int target,
) async {
  final rows = await (db.select(
    db.settings,
  )..where((s) => s.key.like('$actionCatalogPrefix%'))).get();
  for (final row in rows) {
    final json = jsonDecode(row.value) as Map<String, dynamic>;
    var changed = false;
    for (final field in ['examples', 'matches']) {
      for (final item in json[field] as List) {
        final ids = (item['people'] as List).cast<int>();
        if (!ids.contains(source)) continue;
        item['people'] = {
          for (final id in ids) id == source ? target : id,
        }.toList();
        changed = true;
      }
    }
    if (changed) await db.putSetting(row.key, jsonEncode(json));
  }
}

/// Actual per-frame poses, separate from the compact identity views. Reusing a
/// track's saved crop/keypoints at later timestamps would invent motion.
class ActionFrameStore {
  ActionFrameStore(this.db);
  final AppDatabase db;

  Future<void> put(
    MediaRow media, {
    required int frameNumber,
    required int timeMs,
    required int width,
    required int height,
    required List<Map<String, dynamic>> bodies,
  }) => db.putSetting(
    '$actionFramePrefix${media.id}.$timeMs',
    jsonEncode({
      'asset': media.assetId,
      'modified': media.modifiedAt,
      'frame': frameNumber,
      'time': timeMs,
      'width': width,
      'height': height,
      'bodies': bodies,
    }),
  );

  Future<List<Map<String, dynamic>>> load(MediaRow media) async {
    final rows = await (db.select(
      db.settings,
    )..where((s) => s.key.like('$actionFramePrefix${media.id}.%'))).get();
    final frames = <Map<String, dynamic>>[];
    for (final row in rows) {
      try {
        final json = jsonDecode(row.value) as Map<String, dynamic>;
        if (json['asset'] == media.assetId &&
            json['modified'] == media.modifiedAt) {
          frames.add(json);
        }
      } on FormatException {
        /* Ignore corrupt evidence, never fabricate it. */
      }
    }
    frames.sort((a, b) => (a['time'] as int).compareTo(b['time'] as int));
    return frames;
  }
}
