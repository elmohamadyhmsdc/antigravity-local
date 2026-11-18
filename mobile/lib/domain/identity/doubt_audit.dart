import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../data/api/dtos/embedding.dart';
import '../../data/db/app_database.dart';
import '../grouping/grouping_config.dart';
import '../grouping/grouping_inputs.dart' show activeEmbeddingModel;
import 'identity_selection.dart';

class DoubtResult {
  const DoubtResult({this.people = 0, this.faces = 0});

  /// People who have at least one doubtful face.
  final int people;
  final int faces;
}

/// "Are you sure these are Sara?" - looks at every face already on a person, the ones the user named
/// included, and lists the ones that do not look like the rest. Pure phone work (no PC): it compares
/// each face with the person's own core, which is the average of the faces the user vouched for
/// (`face_confirmations`) when there are a few, else the medoid of the person's faces.
///
/// A mistake in a library this size cannot be found by hand, so the result is a list the quick review
/// asks about in bulk (`review_doubtful`), worst first, each with the other person it fits better when
/// there is one. Nothing is moved here: only the user's answer changes anything.
class DoubtAudit {
  DoubtAudit(this._db, {this.kind = 'person'});

  final AppDatabase _db;

  /// 'person' (ArcFace, 512-d) or 'character' (CCIP, 768-d).
  final String kind;

  bool get _character => kind == 'character';
  int get _dim => _character ? characterEmbeddingDim : embeddingDim;
  double get _minFacePx =>
      _character ? groupingMinCharacterFacePx : groupingMinFacePx;

  /// The similarity under which a face is out whatever the person's spread. Looser for real faces
  /// (profiles and lighting move a face a lot), tight for CCIP vectors (a drawing is its character).
  double get _floor => _character ? 0.70 : 0.35;

  /// A better home must score at least this against the other person's core.
  double get _suggestFloor => _character ? 0.82 : 0.45;

  Future<DoubtResult> run({
    int? anchorPersonId,
    bool anchorAll = false,
    bool rebuilding = false,
  }) async {
    final people = await _db
        .customSelect(
          'SELECT id, avatar_face_id FROM persons WHERE kind = ? AND grouping_locked = 0 AND hidden = 0 ORDER BY id',
          variables: [Variable.withString(kind)],
          readsFrom: {_db.persons},
        )
        .get();

    final model = await activeEmbeddingModel(_db, kind);
    final flagged = <int, List<_Doubt>>{};
    final cores = <int, Float32List>{};
    final exemplars = <int, List<IdentityFace>>{};
    final coreModels = <int, String>{};
    final slice = Stopwatch()..start();
    for (final p in people) {
      final pid = p.read<int>('id');
      final rows = await _db
          .customSelect(
            '''
            SELECT f.id, f.embedding, f.model_id, f.quality_score, f.face_px, f.det_score, f.sharpness, f.yaw, f.pitch,
                   fc.face_id IS NOT NULL AS confirmed
            FROM faces f
            LEFT JOIN face_confirmations fc ON fc.face_id = f.id AND fc.person_id = f.person_id
            WHERE f.person_id = ? AND f.hidden = 0 AND (f.ownership IS NULL OR f.ownership != 'none') AND (?2 IS NULL OR f.model_id = ?2)
            ''',
            variables: [Variable.withInt(pid), Variable<String>(model)],
            readsFrom: {_db.faces, _db.faceConfirmations},
          )
          .get();
      final faces = <IdentityFace>[];
      final trusted = <int>{};
      final modelIds = <String>{};
      for (final r in rows) {
        // Missing/poor evidence is not an accusation of wrong identity.
        if (!r.read<double>('quality_score').isFinite ||
            r.read<double>('quality_score') < 0.45 ||
            r.read<double>('face_px') < _minFacePx ||
            r.read<double>('det_score') < 0.5 ||
            (!_character && r.read<double>('sharpness') <= 0)) {
          continue;
        }
        final v = _vector(r.read<Uint8List>('embedding'));
        if (v == null) continue;
        final id = r.read<int>('id');
        modelIds.add(r.read<String>('model_id'));
        if (r.read<bool>('confirmed')) trusted.add(id);
        faces.add(
          IdentityFace(
            id: id,
            embedding: v,
            quality: r.read<double>('quality_score'),
            yaw: r.readNullable<double>('yaw'),
            pitch: r.readNullable<double>('pitch'),
          ),
        );
      }
      if ((pid == anchorPersonId || anchorAll) && trusted.isEmpty) {
        final cover = p.readNullable<int>('avatar_face_id');
        if (faces.any((f) => f.id == cover)) trusted.add(cover!);
      }
      final anchored =
          pid == anchorPersonId ||
          ((anchorAll || rebuilding) && trusted.isNotEmpty);
      if (faces.length >= (anchored ? 2 : 3)) {
        // Old imports can contain compatible-sized but unrelated model spaces.
        // Without a selected library model, do not invent comparisons across them.
        if (modelIds.length != 1) continue;
        final selection = selectIdentity(
          faces,
          floor: _floor,
          maxTrim: 0.6,
          dedupe: false,
          medoidSample: 60,
          trusted: trusted,
          minToTrim: anchored
              ? 2
              : rebuilding || anchorAll
              ? 3
              : 5,
          minTrusted: anchored ? 1 : 3,
        );
        // Keep different confirmed views instead of reducing a person to one
        // average face. An unusual but supported profile is not a repair task.
        final refs = selectIdentity(
          trusted.isEmpty
              ? selection.kept
              : faces.where((f) => trusted.contains(f.id)).toList(),
          top: 24,
          minToTrim: 1000000,
          dedupe: true,
        ).kept;
        exemplars[pid] = refs;
        final doubts = <_Doubt>[];
        final outliers = selection.outliers.toSet();
        for (final f in faces) {
          if (!outliers.contains(f.id)) continue;
          final score = selection.similarity[f.id];
          if (score == null) continue;
          final nearest = refs.fold<double>(
            -1,
            (s, ref) => math.max(s, _cosine(f.embedding, ref.embedding)),
          );
          if (nearest >= (_character ? 0.82 : 0.45)) continue;
          doubts.add(_Doubt(f.id, f.embedding, math.max(score, nearest)));
        }
        if (doubts.isNotEmpty) flagged[pid] = doubts;
        cores[pid] = _core(refs);
        coreModels[pid] = modelIds.single;
      }
      // a big library is a lot of arithmetic: never hold the screen (or the Pause button) for long
      if (slice.elapsedMilliseconds > 12) {
        await Future<void>.delayed(Duration.zero);
        slice
          ..reset()
          ..start();
      }
    }

    // Where a doubtful face fits better: the other person whose core it is closest to.
    for (final entry in flagged.entries) {
      for (final d in entry.value) {
        final v = d.embedding;
        int? best;
        var bestScore = -1.0, runnerUp = -1.0;
        // Coarse identity retrieval first. Do not run 24 exemplar comparisons
        // against every person for every face in a large repair backlog.
        final candidates = [
          for (final c in cores.entries)
            if (c.key != entry.key &&
                coreModels[c.key] == coreModels[entry.key])
              (c.key, _cosine(v, c.value)),
        ]..sort((a, b) => b.$2.compareTo(a.$2));
        for (final candidate in candidates.take(8)) {
          final refs = exemplars[candidate.$1]!;
          final scores = [for (final f in refs) _cosine(v, f.embedding)]
            ..sort((a, b) => b.compareTo(a));
          final top = scores.take(3).toList();
          final s =
              0.5 * candidate.$2 +
              0.5 * top.reduce((a, b) => a + b) / top.length;
          if (s > bestScore) {
            runnerUp = bestScore;
            bestScore = s;
            best = candidate.$1;
          } else if (s > runnerUp) {
            runnerUp = s;
          }
        }
        if (slice.elapsedMilliseconds > 12) {
          await Future<void>.delayed(Duration.zero);
          slice
            ..reset()
            ..start();
        }
        if (best != null &&
            bestScore >= _suggestFloor &&
            bestScore > d.score + 0.10 &&
            bestScore > runnerUp + 0.10) {
          d.suggested = best;
          d.suggestedScore = bestScore;
        }
      }
    }

    var count = 0;
    await _db.transaction(() async {
      await _db.customUpdate(
        'DELETE FROM review_doubtful WHERE person_id IN (SELECT id FROM persons WHERE kind = ?)',
        variables: [Variable.withString(kind)],
        updates: {_db.reviewDoubtful},
      );
      for (final e in flagged.entries) {
        for (final d in e.value) {
          // Audit calculation yields to the UI. Recheck the exact face and
          // assignment so a correction/rescan during it cannot revive an error.
          final inserted = await _db.customUpdate(
            '''
            INSERT OR REPLACE INTO review_doubtful
              (face_id, person_id, score, suggested_person_id, suggested_score)
            SELECT f.id, f.person_id, ?, ?, ? FROM faces f JOIN persons p ON p.id = f.person_id
            WHERE f.id = ? AND f.person_id = ? AND f.embedding = ?
              AND f.hidden = 0 AND p.grouping_locked = 0
              AND (f.ownership IS NULL OR f.ownership != 'none')
              AND NOT EXISTS (SELECT 1 FROM face_confirmations c WHERE c.face_id = f.id AND c.person_id = f.person_id)
          ''',
            variables: [
              Variable.withReal(d.score),
              Variable<int>(d.suggested),
              Variable<double>(d.suggestedScore),
              Variable.withInt(d.faceId),
              Variable.withInt(e.key),
              Variable<Uint8List>(embeddingToBlob(d.embedding)),
            ],
            updates: {_db.reviewDoubtful},
          );
          count += inserted;
        }
      }
    });
    return DoubtResult(people: flagged.length, faces: count);
  }

  Float32List? _vector(Uint8List blob) {
    try {
      final v = vectorFromBlob(blob);
      if (v.length != _dim) return null;
      for (final x in v) {
        if (!x.isFinite) return null;
      }
      var norm = 0.0;
      for (final x in v) {
        norm += x * x;
      }
      return norm > 1e-12 && norm.isFinite ? v : null;
    } on FormatException {
      return null;
    }
  }

  static Float32List _core(List<IdentityFace> faces) {
    final sum = Float32List(faces.first.embedding.length);
    for (final f in faces) {
      var norm = 0.0;
      for (final x in f.embedding) {
        norm += x * x;
      }
      final inv = norm > 0 ? 1.0 / math.sqrt(norm) : 0.0;
      for (var i = 0; i < sum.length; i++) {
        sum[i] += f.embedding[i] * inv * f.quality;
      }
    }
    return sum;
  }

  static double _cosine(Float32List a, Float32List b) {
    var dot = 0.0, na = 0.0, nb = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    return na > 0 && nb > 0 ? dot / math.sqrt(na * nb) : 0.0;
  }
}

class _Doubt {
  _Doubt(this.faceId, this.embedding, this.score);

  final int faceId;
  final Float32List embedding;
  final double score;
  int? suggested;
  double? suggestedScore;
}
