import 'dart:convert';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../domain/scan/scan_math.dart';
import '../api/dtos/embedding.dart';
import '../db/app_database.dart';

typedef SuppressionBox = ({double x, double y, double w, double h});

class FaceSuppressionStore {
  FaceSuppressionStore(this._db);
  final AppDatabase _db;

  /// Called in the same transaction that removes the faces and their detections.
  Future<void> remember(List<int> ids) async {
    if (ids.isEmpty) return;
    final marks = List.filled(ids.length, '?').join(',');
    final vars = [for (final id in ids) Variable.withInt(id)];
    final faces = await _db
        .customSelect(
          '''
      SELECT f.*, m.asset_id FROM faces f LEFT JOIN media m ON m.id = f.media_id
      WHERE f.id IN ($marks)
    ''',
          variables: vars,
          readsFrom: {_db.faces, _db.media},
        )
        .get();
    final detections = await _db
        .customSelect(
          '''
      SELECT d.*, m.asset_id FROM media_detections d JOIN media m ON m.id = d.media_id
      WHERE d.kind = 'f' AND d.ref_id IN ($marks)
    ''',
          variables: vars,
          readsFrom: {_db.mediaDetections, _db.media},
        )
        .get();
    for (final face in faces) {
      final sources = <String, List<List<Object?>>>{};
      final seenBoxes = <String, Set<String>>{};
      void add(String asset, List<Object?> box) {
        if (seenBoxes
            .putIfAbsent(asset, () => <String>{})
            .add(jsonEncode(box))) {
          sources.putIfAbsent(asset, () => []).add(box);
        }
      }

      final primary = face.readNullable<String>('asset_id');
      if (primary != null) {
        add(primary, [
          face.read<double>('bbox_x'),
          face.read<double>('bbox_y'),
          face.read<double>('bbox_w'),
          face.read<double>('bbox_h'),
          face.readNullable<int>('frame_number'),
        ]);
      }
      for (final hit in detections.where(
        (d) => d.read<int>('ref_id') == face.read<int>('id'),
      )) {
        add(hit.read<String>('asset_id'), [
          hit.read<double>('x'),
          hit.read<double>('y'),
          hit.read<double>('w'),
          hit.read<double>('h'),
          hit.readNullable<int>('frame_number'),
        ]);
      }
      // An imported face without media metadata can only be recognised by its
      // near-duplicate embedding. This follows the scanner's existing rule.
      if (sources.isEmpty) sources[''] = [];
      await _db.batch(
        (batch) => batch.insertAll(_db.faceSuppressions, [
          for (final source in sources.entries)
            FaceSuppressionsCompanion.insert(
              assetId: source.key,
              modelId: face.read<String>('model_id'),
              embedding: face.read<Uint8List>('embedding'),
              occurrences: jsonEncode(source.value),
            ),
        ]),
      );
    }
  }

  Future<List<FaceSuppressionRow>> forAsset(String asset) => (_db.select(
    _db.faceSuppressions,
  )..where((row) => row.assetId.equals(asset) | row.assetId.equals(''))).get();

  static bool matches(
    List<FaceSuppressionRow> decisions, {
    required String asset,
    required String model,
    required Float32List embedding,
    required SuppressionBox box,
    required bool video,
    int? frame,
  }) {
    for (final decision in decisions) {
      if (decision.assetId == asset) {
        for (final raw in jsonDecode(decision.occurrences) as List) {
          final values = raw as List;
          if (values[4] == frame &&
              iou(box, (
                    x: (values[0] as num).toDouble(),
                    y: (values[1] as num).toDouble(),
                    w: (values[2] as num).toDouble(),
                    h: (values[3] as num).toDouble(),
                  )) >=
                  sameBoxIou) {
            return true;
          }
        }
      }
      if (decision.modelId == model &&
          (decision.assetId.isEmpty || video) &&
          cosine(embeddingFromBlob(decision.embedding), embedding) >=
              (decision.assetId.isEmpty ? duplicateCosine : sameFileCosine)) {
        return true;
      }
    }
    return false;
  }
}
