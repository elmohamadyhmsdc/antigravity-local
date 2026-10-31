import 'package:drift/drift.dart';

import '../../data/api/dtos/embedding.dart';
import '../../data/db/app_database.dart';
import '../../data/files/file_store.dart';
import '../../data/index/embedding_index.dart';
import 'drawn_faces.dart';

class DrawnSweepResult {
  const DrawnSweepResult({this.faces = 0, this.bodies = 0, this.people = 0});

  final int faces;
  final int bodies;
  final int people; // unnamed people left with nothing
}

/// Scans stored before drawn faces were recognised (drawn_faces.dart) put anime/cartoon faces
/// in People, many characters inside one "person". This removes them once: the faces, the
/// drawn bodies around them, and the people they leave empty - unless the user named, pinned,
/// favourited or locked that person. New scans never store such faces.
class DrawnFaceSweep {
  DrawnFaceSweep({required this._db, required this._files, this._index});

  final AppDatabase _db;
  final FileStore _files;
  final EmbeddingIndex? _index;

  /// Bump when the drawn-face direction or threshold changes, so the sweep runs again.
  static const version = '1';
  static const doneKey = 'cleanup.drawn_faces';

  /// [run], unless it already ran for this [version].
  Future<DrawnSweepResult?> runOnce() async {
    if (await _db.setting(doneKey) == version) return null;
    final result = await run();
    await _db.putSetting(doneKey, version);
    return result;
  }

  Future<DrawnSweepResult> run() async {
    final drawn = await _drawnFaceIds();
    if (drawn.isEmpty) return const DrawnSweepResult();
    final crops = <String?>[];
    var bodies = 0, people = 0;
    await _db.transaction(() async {
      final owners = <int>{};
      for (final chunk in _chunks(drawn)) {
        final marks = List.filled(chunk.length, '?').join(',');
        final ids = [for (final i in chunk) Variable.withInt(i)];
        final faces = await _db
            .customSelect(
              'SELECT person_id, crop_path FROM faces WHERE id IN ($marks)',
              variables: ids,
              readsFrom: {_db.faces},
            )
            .get();
        for (final f in faces) {
          final p = f.readNullable<int>('person_id');
          if (p != null) owners.add(p);
          crops.add(f.readNullable<String>('crop_path'));
        }
        final figures = await _db
            .customSelect(
              'SELECT id, person_id, crop_path FROM bodies WHERE face_id IN ($marks)',
              variables: ids,
              readsFrom: {_db.bodies},
            )
            .get();
        if (figures.isNotEmpty) {
          final bodyMarks = List.filled(figures.length, '?').join(',');
          final bodyIds = [
            for (final b in figures) Variable.withInt(b.read<int>('id')),
          ];
          for (final b in figures) {
            final p = b.readNullable<int>('person_id');
            if (p != null) owners.add(p);
            crops.add(b.readNullable<String>('crop_path'));
          }
          await _db.customUpdate(
            "DELETE FROM media_detections WHERE kind = 'b' AND ref_id IN ($bodyMarks)",
            variables: bodyIds,
            updates: {_db.mediaDetections},
          );
          await _db.customUpdate(
            'DELETE FROM bodies WHERE id IN ($bodyMarks)',
            variables: bodyIds,
            updates: {_db.bodies},
          );
          bodies += figures.length;
        }
        await _db.customUpdate(
          "DELETE FROM media_detections WHERE kind = 'f' AND ref_id IN ($marks)",
          variables: ids,
          updates: {_db.mediaDetections},
        );
        await _db.customUpdate(
          'UPDATE persons SET avatar_face_id = NULL WHERE avatar_face_id IN ($marks)',
          variables: ids,
          updates: {_db.persons},
        );
        await _db.customUpdate(
          'DELETE FROM faces WHERE id IN ($marks)',
          variables: ids,
          updates: {_db.faces},
        );
      }
      for (final chunk in _chunks(owners.toList())) {
        people += await _db.customUpdate(
          '''
          DELETE FROM persons WHERE id IN (${List.filled(chunk.length, '?').join(',')})
            AND name IS NULL AND favorite = 0 AND pinned = 0 AND grouping_locked = 0
            AND NOT EXISTS (SELECT 1 FROM faces f WHERE f.person_id = persons.id)
            AND NOT EXISTS (SELECT 1 FROM bodies b WHERE b.person_id = persons.id)
          ''',
          variables: [for (final i in chunk) Variable.withInt(i)],
          updates: {_db.persons},
          updateKind: UpdateKind.delete,
        );
      }
    });
    await _files.deleteAll(crops);
    await _index?.remove(drawn);
    return DrawnSweepResult(
      faces: drawn.length,
      bodies: bodies,
      people: people,
    );
  }

  Future<List<int>> _drawnFaceIds() async {
    final out = <int>[];
    var after = 0;
    while (true) {
      final rows = await _db
          .customSelect(
            'SELECT id, embedding FROM faces WHERE id > ? ORDER BY id LIMIT 2000',
            variables: [Variable.withInt(after)],
            readsFrom: {_db.faces},
          )
          .get();
      if (rows.isEmpty) return out;
      for (final r in rows) {
        final id = r.read<int>('id');
        if (isDrawnFace(embeddingFromBlob(r.read<Uint8List>('embedding')))) {
          out.add(id);
        }
        after = id;
      }
    }
  }

  static Iterable<List<int>> _chunks(List<int> ids) sync* {
    for (var i = 0; i < ids.length; i += 500) {
      yield ids.sublist(i, i + 500 > ids.length ? ids.length : i + 500);
    }
  }
}
