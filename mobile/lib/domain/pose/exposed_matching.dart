/// Roadmap Phase 8 / section 7.5, phone half: matching the exposed-region embeddings (DINOv2, 384-d) of
/// faceless bodies.
///
/// Two layers, deliberately separated by the roadmap's own rule ("no cue is proof; every cue is calibrated"):
/// * [ExposedMatcher.findSimilar] - a ranked "similar photos" search. Always available once embeddings exist.
/// * [ExposedClusters] - persistent clusters and one-tap assignment to a person. OFF until the Phase 8 gate
///   (`the app/eval_body_embeddings.py`: pairwise precision >= 0.95 on the user's own labelled bodies) has
///   passed and the user turns it on ([ExposedClusters.enabledKey]).
///
/// All the arithmetic runs in short-lived isolates with plain data; SQLite stays on the calling isolate.
library;

import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../data/api/dtos/analyze.dart' show patchEmbeddingDim;
import '../../data/api/dtos/embedding.dart';
import '../../data/db/app_database.dart';

enum ExposedKind {
  chest('chest_embedding', 'chest_cluster_id'),
  buttocks('buttocks_embedding', 'buttocks_cluster_id');

  const ExposedKind(this.column, this.clusterColumn);
  final String column;
  final String clusterColumn;
}

typedef _Vec = ({int id, Uint8List blob});

Float32List _floats(Uint8List blob) {
  final copy = Uint8List.fromList(blob);
  return copy.buffer.asFloat32List();
}

double _dot(Float32List a, Float32List b) {
  var s = 0.0;
  final n = math.min(a.length, b.length);
  for (var i = 0; i < n; i++) {
    s += a[i] * b[i];
  }
  return s;
}

List<({int id, double similarity})> _rank(
  Uint8List query,
  List<_Vec> candidates,
  int limit,
  double minimum,
) {
  final q = _floats(query);
  final out = <({int id, double similarity})>[];
  for (final c in candidates) {
    final s = _dot(q, _floats(c.blob));
    if (s >= minimum) out.add((id: c.id, similarity: s));
  }
  out.sort((a, b) => b.similarity.compareTo(a.similarity));
  return out.take(limit).toList();
}

/// DBSCAN over cosine distance (1 - dot) of unit vectors. Returns a cluster index per input (-1 = noise).
List<int> dbscan(
  List<Float32List> vectors, {
  double eps = 0.25,
  int minPoints = 2,
}) {
  final n = vectors.length;
  final label = List<int>.filled(n, -2); // -2 unvisited, -1 noise
  List<int> neighbours(int i) => [
    for (var j = 0; j < n; j++)
      if (1 - _dot(vectors[i], vectors[j]) <= eps) j,
  ];
  var cluster = 0;
  for (var i = 0; i < n; i++) {
    if (label[i] != -2) continue;
    final seeds = neighbours(i);
    if (seeds.length < minPoints) {
      label[i] = -1;
      continue;
    }
    label[i] = cluster;
    final queue = [...seeds];
    for (var k = 0; k < queue.length; k++) {
      final j = queue[k];
      if (label[j] == -1) label[j] = cluster; // noise becomes a border point
      if (label[j] != -2) continue;
      label[j] = cluster;
      final more = neighbours(j);
      if (more.length >= minPoints) queue.addAll(more);
    }
    cluster++;
  }
  return label;
}

// Top-level wrappers keep SQLite out of the isolate closure context.
Future<List<({int id, double similarity})>> _rankIsolated(
  Uint8List query,
  List<_Vec> candidates,
  int limit,
  double minimum,
) => Isolate.run(() => _rank(query, candidates, limit, minimum));

Future<List<int>> _dbscanIsolated(
  List<Uint8List> blobs,
  double eps,
  int minPoints,
) => Isolate.run(
  () => dbscan(
    [for (final b in blobs) _floats(b)],
    eps: eps,
    minPoints: minPoints,
  ),
);

class ExposedMatcher {
  ExposedMatcher(this._db);

  final AppDatabase _db;

  Future<Uint8List?> _embeddingOf(int bodyId, ExposedKind kind) async {
    final row = await _db
        .customSelect(
          'SELECT ${kind.column} AS e FROM bodies WHERE id = ?',
          variables: [Variable.withInt(bodyId)],
          readsFrom: {_db.bodies},
        )
        .getSingleOrNull();
    return row?.readNullable<Uint8List>('e');
  }

  Future<List<_Vec>> _all(ExposedKind kind, {int? excluding}) async {
    final rows = await _db
        .customSelect(
          'SELECT id, ${kind.column} AS e FROM bodies WHERE ${kind.column} IS NOT NULL AND kind = \'person\''
          '${excluding == null ? '' : ' AND id != ?'}',
          variables: [if (excluding != null) Variable.withInt(excluding)],
          readsFrom: {_db.bodies},
        )
        .get();
    return [
      for (final r in rows)
        (id: r.read<int>('id'), blob: r.read<Uint8List>('e')),
    ];
  }

  /// Which halves of a body have an embedding (the actions only make sense then).
  Future<Set<ExposedKind>> kindsOf(int bodyId) async => {
    for (final k in ExposedKind.values)
      if (await _embeddingOf(bodyId, k) != null) k,
  };

  /// The bodies whose exposed region looks most like [bodyId]'s, best first (cosine of unit vectors).
  Future<List<({int bodyId, double similarity})>> findSimilar(
    int bodyId,
    ExposedKind kind, {
    int limit = 200,
    double minimum = -1.0,
  }) async {
    final query = await _embeddingOf(bodyId, kind);
    if (query == null) return const [];
    final ranked = await _rankIsolated(
      query,
      await _all(kind, excluding: bodyId),
      limit,
      minimum,
    );
    return [for (final r in ranked) (bodyId: r.id, similarity: r.similarity)];
  }
}

class ExposedClusters {
  ExposedClusters(this._db);

  final AppDatabase _db;

  /// Settings key; absent / anything but 'true' = OFF.
  static const enabledKey = 'body_clusters_enabled';

  /// Starting values; the Phase 8 gate sets the real ones.
  static const defaultEps = 0.25;
  static const defaultMinPoints = 2;

  Future<bool> get enabled async => await _db.setting(enabledKey) == 'true';

  Future<void> setEnabled(bool on) =>
      _db.putSetting(enabledKey, on ? 'true' : 'false');

  /// Re-clusters one half. Returns the number of clusters, or null when the feature is off. A person already
  /// assigned to a cluster keeps it (the cluster's `person_id` is a cache of the bodies' own links).
  Future<int?> rebuild(
    ExposedKind kind, {
    double eps = defaultEps,
    int minPoints = defaultMinPoints,
  }) async {
    if (!await enabled) return null;
    final rows = await _db
        .customSelect(
          'SELECT id, ${kind.column} AS e FROM bodies WHERE ${kind.column} IS NOT NULL AND kind = \'person\' ORDER BY id',
          readsFrom: {_db.bodies},
        )
        .get();
    if (rows.isEmpty) return 0;
    final ids = [for (final r in rows) r.read<int>('id')];
    final blobs = [for (final r in rows) r.read<Uint8List>('e')];
    final labels = await _dbscanIsolated(blobs, eps, minPoints);
    final members = <int, List<int>>{};
    for (var i = 0; i < ids.length; i++) {
      if (labels[i] >= 0) members.putIfAbsent(labels[i], () => []).add(i);
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await _db.transaction(() async {
      await _db.customUpdate(
        'UPDATE bodies SET ${kind.clusterColumn} = NULL WHERE ${kind.clusterColumn} IS NOT NULL',
        updates: {_db.bodies},
      );
      await _db.customUpdate(
        'DELETE FROM body_clusters WHERE cluster_type = ?',
        variables: [Variable.withString(kind.name)],
        updates: {_db.bodyClusters},
      );
      for (final group in members.values) {
        final centroid = Float32List(patchEmbeddingDim);
        for (final i in group) {
          final v = _floats(blobs[i]);
          for (var d = 0; d < patchEmbeddingDim; d++) {
            centroid[d] += v[d] / group.length;
          }
        }
        final clusterId = await _db
            .into(_db.bodyClusters)
            .insert(
              BodyClustersCompanion.insert(
                clusterType: kind.name,
                centroidEmbedding: packFloat32(centroid),
                bodyCount: Value(group.length),
                createdAt: now,
              ),
            );
        await _db.customUpdate(
          'UPDATE bodies SET ${kind.clusterColumn} = ? WHERE id IN (${group.map((i) => ids[i]).join(',')})',
          variables: [Variable.withInt(clusterId)],
          updates: {_db.bodies},
        );
        // the cluster is a cache of the bodies' own links: the person most of its members already belong to
        final owners = await _db
            .customSelect(
              "SELECT COALESCE(f.person_id, b.person_id) AS p, COUNT(*) AS n FROM bodies b LEFT JOIN faces f ON f.id = b.face_id "
              "WHERE b.${kind.clusterColumn} = ? AND COALESCE(f.person_id, b.person_id) IS NOT NULL GROUP BY p ORDER BY n DESC LIMIT 1",
              variables: [Variable.withInt(clusterId)],
              readsFrom: {_db.bodies, _db.faces},
            )
            .get();
        if (owners.isNotEmpty) {
          await (_db.update(
            _db.bodyClusters,
          )..where((c) => c.id.equals(clusterId))).write(
            BodyClustersCompanion(personId: Value(owners.first.read<int>('p'))),
          );
        }
      }
    });
    await publishSuggestions();
    return members.length;
  }

  /// One tap: every body of the cluster that nobody has claimed becomes [personId]'s by hand (a face or a link
  /// the user made stays). The cluster remembers the person. Returns how many bodies were linked.
  Future<int> assign(int clusterId, int personId) => _db.transaction(() async {
    final cluster = await (_db.select(
      _db.bodyClusters,
    )..where((c) => c.id.equals(clusterId))).getSingleOrNull();
    if (cluster == null) return 0;
    final column = cluster.clusterType == 'buttocks'
        ? 'buttocks_cluster_id'
        : 'chest_cluster_id';
    final linked = await _db.customUpdate(
      'UPDATE bodies SET person_id = ?, link_method = \'manual\', link_confidence = 1 '
      'WHERE $column = ? AND person_id IS NULL AND (ownership IS NULL OR ownership != \'none\') AND hidden = 0 '
      'AND NOT EXISTS (SELECT 1 FROM faces f WHERE f.id = bodies.face_id AND f.person_id IS NOT NULL) '
      'AND NOT EXISTS (SELECT 1 FROM body_rejections r WHERE r.body_id = bodies.id AND r.person_id = ?)',
      variables: [
        Variable.withInt(personId),
        Variable.withInt(clusterId),
        Variable.withInt(personId),
      ],
      updates: {_db.bodies},
    );
    await (_db.update(_db.bodyClusters)..where((c) => c.id.equals(clusterId)))
        .write(BodyClustersCompanion(personId: Value(personId)));
    return linked;
  });

  /// The clusters with their member bodies, biggest first.
  Future<List<({BodyClusterRow cluster, List<int> bodyIds})>> clusters() async {
    final out = <({BodyClusterRow cluster, List<int> bodyIds})>[];
    for (final c in await (_db.select(
      _db.bodyClusters,
    )..orderBy([(c) => OrderingTerm.desc(c.bodyCount)])).get()) {
      final column = c.clusterType == 'buttocks'
          ? 'buttocks_cluster_id'
          : 'chest_cluster_id';
      final rows = await _db
          .customSelect(
            'SELECT id FROM bodies WHERE $column = ? ORDER BY id',
            variables: [Variable.withInt(c.id)],
            readsFrom: {_db.bodies},
          )
          .get();
      out.add((cluster: c, bodyIds: [for (final r in rows) r.read<int>('id')]));
    }
    return out;
  }

  /// Quick Review "one tap": the bodies nobody has claimed in a cluster that belongs to a person become
  /// `cluster` suggestions for that person (confidence 0.85). Never an automatic link; the review tables are
  /// replaced by each grouping run, so this is repeated by [rebuild] / [assign]. Returns how many were queued.
  Future<int> publishSuggestions() async {
    if (!await enabled) return 0;
    return _db.customUpdate(
      '''INSERT OR REPLACE INTO review_body_links (body_id, person_id, method, confidence)
         SELECT b.id, c.person_id, 'cluster', 0.85 FROM bodies b
         JOIN body_clusters c ON c.id = b.chest_cluster_id OR c.id = b.buttocks_cluster_id
         WHERE c.person_id IS NOT NULL AND b.person_id IS NULL AND b.face_id IS NULL AND b.kind = 'person'
           AND (b.ownership IS NULL OR b.ownership != 'none') AND b.hidden = 0
           AND NOT EXISTS (SELECT 1 FROM body_rejections r WHERE r.body_id = b.id AND r.person_id = c.person_id)''',
      updates: {_db.reviewBodyLinks},
    );
  }

  /// Bridge photos (a body in both a chest and a buttocks cluster): the OTHER cluster is only SUGGESTED, never
  /// assigned automatically, and only with at least [minBridges] independent bridge photos.
  Future<List<({int fromCluster, int toCluster, int bridges})>>
  bridgeSuggestions({int minBridges = 2}) async {
    final rows = await _db
        .customSelect(
          '''SELECT chest_cluster_id AS a, buttocks_cluster_id AS b, COUNT(*) AS n FROM bodies
             WHERE chest_cluster_id IS NOT NULL AND buttocks_cluster_id IS NOT NULL
             GROUP BY chest_cluster_id, buttocks_cluster_id HAVING COUNT(*) >= ?''',
          variables: [Variable.withInt(minBridges)],
          readsFrom: {_db.bodies},
        )
        .get();
    final assigned = {
      for (final c in await _db.select(_db.bodyClusters).get())
        if (c.personId != null) c.id: c.personId,
    };
    return [
      for (final r in rows)
        if ((assigned[r.read<int>('a')] == null) !=
            (assigned[r.read<int>('b')] == null))
          (
            fromCluster: assigned[r.read<int>('a')] != null
                ? r.read<int>('a')
                : r.read<int>('b'),
            toCluster: assigned[r.read<int>('a')] != null
                ? r.read<int>('b')
                : r.read<int>('a'),
            bridges: r.read<int>('n'),
          ),
    ];
  }
}
