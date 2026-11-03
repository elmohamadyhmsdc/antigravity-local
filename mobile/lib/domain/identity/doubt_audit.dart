import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../data/api/dtos/embedding.dart';
import '../../data/db/app_database.dart';
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

  /// The similarity under which a face is out whatever the person's spread. Looser for real faces
  /// (profiles and lighting move a face a lot), tight for CCIP vectors (a drawing is its character).
  double get _floor => _character ? 0.70 : 0.35;

  /// A better home must score at least this against the other person's core.
  double get _suggestFloor => _character ? 0.82 : 0.45;

  Future<DoubtResult> run() async {
    final people = await _db
        .customSelect(
          'SELECT id FROM persons WHERE kind = ? AND grouping_locked = 0 ORDER BY id',
          variables: [Variable.withString(kind)],
          readsFrom: {_db.persons},
        )
        .get();

    final flagged = <int, List<_Doubt>>{};
    final cores = <int, Float32List>{};
    final vectors = <int, Float32List>{};
    final slice = Stopwatch()..start();
    for (final p in people) {
      final pid = p.read<int>('id');
      final rows = await _db
          .customSelect(
            '''
            SELECT f.id, f.embedding, f.quality_score, f.yaw, f.pitch,
                   fc.face_id IS NOT NULL AS confirmed
            FROM faces f
            LEFT JOIN face_confirmations fc ON fc.face_id = f.id AND fc.person_id = f.person_id
            WHERE f.person_id = ? AND f.hidden = 0
            ''',
            variables: [Variable.withInt(pid)],
            readsFrom: {_db.faces, _db.faceConfirmations},
          )
          .get();
      final faces = <IdentityFace>[];
      final trusted = <int>{};
      for (final r in rows) {
        final v = _vector(r.read<Uint8List>('embedding'));
        if (v == null) continue;
        final id = r.read<int>('id');
        vectors[id] = v;
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
      if (faces.length >= 3) {
        final selection = selectIdentity(
          faces,
          floor: _floor,
          maxTrim: 0.6,
          dedupe: false,
          medoidSample: 60,
          trusted: trusted,
        );
        final doubts = [
          for (final id in selection.outliers)
            if (selection.similarity.containsKey(id))
              _Doubt(id, selection.similarity[id]!),
        ];
        if (doubts.isNotEmpty) flagged[pid] = doubts;
        cores[pid] = _core(selection.kept);
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
        final v = vectors[d.faceId]!;
        int? best;
        var bestScore = -1.0;
        for (final c in cores.entries) {
          if (c.key == entry.key) continue;
          final s = _cosine(v, c.value);
          if (s > bestScore) {
            bestScore = s;
            best = c.key;
          }
        }
        if (best != null &&
            bestScore >= _suggestFloor &&
            bestScore > d.score + 0.05) {
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
      await _db.batch((b) {
        for (final e in flagged.entries) {
          for (final d in e.value) {
            count++;
            b.insert(
              _db.reviewDoubtful,
              ReviewDoubtfulCompanion.insert(
                faceId: Value(d.faceId),
                personId: e.key,
                score: d.score,
                suggestedPersonId: Value(d.suggested),
                suggestedScore: Value(d.suggestedScore),
              ),
              mode: InsertMode.insertOrReplace,
            );
          }
        }
      });
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
      return v;
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
  _Doubt(this.faceId, this.score);

  final int faceId;
  final double score;
  int? suggested;
  double? suggestedScore;
}
