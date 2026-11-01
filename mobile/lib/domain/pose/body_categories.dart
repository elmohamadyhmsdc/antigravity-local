/// Roadmap Phase 3 (section 6): categories built from an example. The user picks a body, names its pose
/// or its outfit, previews who else matches, removes the wrong ones, and saves. New scans are scored
/// against the saved categories; a body the user removed ("rejected") is never added again.
///
/// A category copies its exemplar (`exemplar_feature` / `exemplar_appearance`), so deleting the exemplar
/// body keeps the category. Only people-kind bodies take part (characters are not mixed in).
library;

import 'dart:isolate';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../data/api/dtos/embedding.dart';
import '../../data/db/app_database.dart';
import '../scan/scan_math.dart';
import 'pose_descriptor.dart';
import 'pose_index.dart';

/// Starting values; Phase 0 (`eval_pose_filters.py`) replaces them with measured ones.
const defaultPoseThreshold = 0.80;
const defaultOutfitThreshold = 0.90;

/// A pose match also needs this much of both bodies' points in common (an upper-body crop does not
/// match a full body just because the shared points agree).
const minPoseCoverage = 0.7;

class CategoryMatch {
  const CategoryMatch(this.bodyId, this.similarity);
  final int bodyId;
  final double similarity;
}

/// What the preview shows before anything is saved.
class PoseDraft {
  const PoseDraft({
    required this.exemplarBodyId,
    required this.exemplar,
    required this.threshold,
    required this.matches,
  });
  final int exemplarBodyId;
  final PoseFeature exemplar;
  final double threshold;
  final List<CategoryMatch> matches;
}

class OutfitDraft {
  const OutfitDraft({
    required this.exemplarBodyId,
    required this.appearance,
    required this.lowerOnly,
    required this.threshold,
    required this.personId,
    required this.matches,
  });
  final int exemplarBodyId;
  final List<double> appearance;
  final bool lowerOnly;
  final double threshold;
  final int? personId;
  final List<CategoryMatch> matches;
}

class BodyCategories {
  BodyCategories(this._db, {PoseIndex? poses})
    : _poses = poses ?? PoseIndex(_db);

  final AppDatabase _db;
  final PoseIndex _poses;

  // ---- poses ----------------------------------------------------------------------------------

  /// The preview for "name this pose": every comparable body at or above [threshold], best first.
  /// Null when the exemplar has no descriptor (hips or shoulders not visible).
  Future<PoseDraft?> draftPose(
    int exemplarBodyId, {
    double threshold = defaultPoseThreshold,
    double sigma = defaultPoseSigma,
  }) async {
    final row =
        await (_db.select(_db.bodyPoseFeatures)..where(
              (x) =>
                  x.bodyId.equals(exemplarBodyId) &
                  x.visibleMask.isBiggerThanValue(0),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    final exemplar = PoseFeature.fromBlob(
      row.feature,
      row.visibleMask,
      row.scaleSource,
    );
    return PoseDraft(
      exemplarBodyId: exemplarBodyId,
      exemplar: exemplar,
      threshold: threshold,
      matches: await _poseMatches(exemplar, threshold, sigma),
    );
  }

  Future<List<CategoryMatch>> _poseMatches(
    PoseFeature exemplar,
    double threshold,
    double sigma,
  ) async {
    final ranked = await _poses.findSimilarToFeature(
      exemplar,
      limit: 100000,
      sigma: sigma,
      strict: true,
    );
    return [
      for (final r in ranked)
        if (r.similarity >= threshold && r.coverage >= minPoseCoverage)
          CategoryMatch(r.bodyId, r.similarity),
    ];
  }

  /// Saves the category with the draft's matches minus [removed] (those become `rejected`). The
  /// exemplar body is a `manual` match.
  Future<int> savePose(
    PoseDraft draft,
    String name, {
    Set<int> removed = const {},
    String kind = 'person',
  }) => _db.transaction(() async {
    final id = await _db
        .into(_db.poseCategories)
        .insert(
          PoseCategoriesCompanion.insert(
            name: name.trim(),
            kind: Value(kind),
            exemplarBodyId: Value(draft.exemplarBodyId),
            exemplarFeature: draft.exemplar.toBlob(),
            exemplarMask: draft.exemplar.mask,
            exemplarScaleSource: draft.exemplar.scaleSource,
            threshold: draft.threshold,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    for (final m in draft.matches) {
      await _setPoseMatch(
        id,
        m.bodyId,
        m.similarity,
        removed.contains(m.bodyId) ? 'rejected' : 'auto',
      );
    }
    await _setPoseMatch(id, draft.exemplarBodyId, 1, 'manual');
    return id;
  });

  Future<void> _setPoseMatch(
    int categoryId,
    int bodyId,
    double similarity,
    String state,
  ) => _db
      .into(_db.bodyPoseMatches)
      .insert(
        BodyPoseMatchesCompanion.insert(
          bodyId: bodyId,
          categoryId: categoryId,
          similarity: similarity,
          state: state,
        ),
        mode: InsertMode.insertOrReplace,
      );

  /// After a scan: scores the bodies this category has never seen. Bodies that already have a row
  /// (including `rejected` ones) are left alone. Returns how many were added.
  Future<int> rescorePose(int categoryId) async {
    final c = await (_db.select(
      _db.poseCategories,
    )..where((x) => x.id.equals(categoryId))).getSingleOrNull();
    if (c == null || c.kind == 'group_pose') return 0;
    final exemplar = PoseFeature.fromBlob(
      c.exemplarFeature,
      c.exemplarMask,
      c.exemplarScaleSource,
    );
    final known = {
      for (final m in await (_db.select(
        _db.bodyPoseMatches,
      )..where((x) => x.categoryId.equals(categoryId))).get())
        m.bodyId,
    };
    var added = 0;
    for (final m in await _poseMatches(
      exemplar,
      c.threshold,
      defaultPoseSigma,
    )) {
      if (known.contains(m.bodyId)) continue;
      await _setPoseMatch(categoryId, m.bodyId, m.similarity, 'auto');
      added++;
    }
    return added;
  }

  Future<int> rescoreAllPoses() async {
    var added = 0;
    for (final c in await _db.select(_db.poseCategories).get()) {
      added += await rescorePose(c.id);
    }
    return added;
  }

  Future<void> setPoseState(
    int categoryId,
    int bodyId,
    String state, {
    double similarity = 1,
  }) => _setPoseMatch(categoryId, bodyId, similarity, state);

  /// Bodies in the category (auto + manual), best first.
  Future<List<int>> bodiesInPose(int categoryId) async => [
    for (final m
        in await (_db.select(_db.bodyPoseMatches)
              ..where(
                (x) =>
                    x.categoryId.equals(categoryId) &
                    x.state.isIn(const ['auto', 'manual']),
              )
              ..orderBy([(x) => OrderingTerm.desc(x.similarity)]))
            .get())
      m.bodyId,
  ];

  Future<void> deletePose(int categoryId) => (_db.delete(
    _db.poseCategories,
  )..where((x) => x.id.equals(categoryId))).go();

  Future<void> renamePose(int categoryId, String name) =>
      (_db.update(_db.poseCategories)..where((x) => x.id.equals(categoryId)))
          .write(PoseCategoriesCompanion(name: Value(name.trim())));

  // ---- outfits --------------------------------------------------------------------------------

  /// Preview for "name this outfit". [personId] null = global; else only that person's bodies.
  /// [lowerOnly] compares the legs region only (a bare or covered torso says nothing).
  Future<OutfitDraft?> draftOutfit(
    int exemplarBodyId, {
    bool lowerOnly = false,
    double threshold = defaultOutfitThreshold,
    int? personId,
  }) async {
    final body = await (_db.select(
      _db.bodies,
    )..where((b) => b.id.equals(exemplarBodyId))).getSingleOrNull();
    final blob = body?.appearance;
    if (blob == null) return null;
    final appearance = _floats(blob);
    return OutfitDraft(
      exemplarBodyId: exemplarBodyId,
      appearance: appearance,
      lowerOnly: lowerOnly,
      threshold: threshold,
      personId: personId,
      matches: await _outfitMatches(appearance, lowerOnly, threshold, personId),
    );
  }

  Future<List<CategoryMatch>> _outfitMatches(
    List<double> appearance,
    bool lowerOnly,
    double threshold,
    int? personId,
  ) async {
    final rows = await _db
        .customSelect(
          '''SELECT b.id, b.appearance FROM bodies b LEFT JOIN faces f ON f.id = b.face_id
             WHERE b.kind = 'person' AND b.appearance IS NOT NULL
             ${personId == null ? '' : 'AND COALESCE(f.person_id, b.person_id) = ?'}''',
          variables: [if (personId != null) Variable.withInt(personId)],
          readsFrom: {_db.bodies, _db.faces},
        )
        .get();
    final data = [
      for (final r in rows)
        (id: r.read<int>('id'), appearance: r.read<Uint8List>('appearance')),
    ];
    final query = lowerOnly
        ? [...List<double>.filled(40, 0), ...appearance.skip(40)]
        : appearance;
    return _outfitIsolated(data, query, threshold);
  }

  Future<int> saveOutfit(
    OutfitDraft draft,
    String name, {
    Set<int> removed = const {},
    String kind = 'person',
  }) => _db.transaction(() async {
    final id = await _db
        .into(_db.outfitCategories)
        .insert(
          OutfitCategoriesCompanion.insert(
            name: name.trim(),
            kind: Value(kind),
            personId: Value(draft.personId),
            exemplarBodyId: Value(draft.exemplarBodyId),
            exemplarAppearance: packFloat32(draft.appearance),
            lowerOnly: Value(draft.lowerOnly),
            threshold: draft.threshold,
            createdAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
    for (final m in draft.matches) {
      await _setOutfitMatch(
        id,
        m.bodyId,
        m.similarity,
        removed.contains(m.bodyId) ? 'rejected' : 'auto',
      );
    }
    await _setOutfitMatch(id, draft.exemplarBodyId, 1, 'manual');
    return id;
  });

  Future<void> _setOutfitMatch(
    int categoryId,
    int bodyId,
    double similarity,
    String state,
  ) => _db
      .into(_db.bodyOutfitMatches)
      .insert(
        BodyOutfitMatchesCompanion.insert(
          bodyId: bodyId,
          categoryId: categoryId,
          similarity: similarity,
          state: state,
        ),
        mode: InsertMode.insertOrReplace,
      );

  Future<int> rescoreOutfit(int categoryId) async {
    final c = await (_db.select(
      _db.outfitCategories,
    )..where((x) => x.id.equals(categoryId))).getSingleOrNull();
    if (c == null) return 0;
    final known = {
      for (final m in await (_db.select(
        _db.bodyOutfitMatches,
      )..where((x) => x.categoryId.equals(categoryId))).get())
        m.bodyId,
    };
    var added = 0;
    final exemplar = _floats(c.exemplarAppearance);
    for (final m in await _outfitMatches(
      exemplar,
      c.lowerOnly,
      c.threshold,
      c.personId,
    )) {
      if (known.contains(m.bodyId)) continue;
      await _setOutfitMatch(categoryId, m.bodyId, m.similarity, 'auto');
      added++;
    }
    return added;
  }

  Future<int> rescoreAllOutfits() async {
    var added = 0;
    for (final c in await _db.select(_db.outfitCategories).get()) {
      added += await rescoreOutfit(c.id);
    }
    return added;
  }

  Future<void> setOutfitState(
    int categoryId,
    int bodyId,
    String state, {
    double similarity = 1,
  }) => _setOutfitMatch(categoryId, bodyId, similarity, state);

  Future<List<int>> bodiesInOutfit(int categoryId) async => [
    for (final m
        in await (_db.select(_db.bodyOutfitMatches)
              ..where(
                (x) =>
                    x.categoryId.equals(categoryId) &
                    x.state.isIn(const ['auto', 'manual']),
              )
              ..orderBy([(x) => OrderingTerm.desc(x.similarity)]))
            .get())
      m.bodyId,
  ];

  Future<void> deleteOutfit(int categoryId) => (_db.delete(
    _db.outfitCategories,
  )..where((x) => x.id.equals(categoryId))).go();

  static List<double> _floats(Uint8List blob) {
    final view = ByteData.sublistView(blob);
    return [
      for (var i = 0; i + 4 <= blob.length; i += 4)
        view.getFloat32(i, Endian.little),
    ];
  }
}

List<CategoryMatch> _outfitScore(
  List<({int id, Uint8List appearance})> rows,
  List<double> query,
  double threshold,
) {
  final out = <CategoryMatch>[];
  for (final r in rows) {
    final view = ByteData.sublistView(r.appearance);
    final other = [
      for (var i = 0; i + 4 <= r.appearance.length; i += 4)
        view.getFloat32(i, Endian.little),
    ];
    final s = appearanceSimilarity(query, other);
    if (s >= threshold) out.add(CategoryMatch(r.id, s));
  }
  out.sort((a, b) => b.similarity.compareTo(a.similarity));
  return out;
}

// A top-level wrapper keeps SQLite out of the isolate closure context.
Future<List<CategoryMatch>> _outfitIsolated(
  List<({int id, Uint8List appearance})> rows,
  List<double> query,
  double threshold,
) => Isolate.run(() => _outfitScore(rows, query, threshold));
