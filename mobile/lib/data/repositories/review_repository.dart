import 'dart:convert';
import 'dart:math' as math;

import 'package:drift/drift.dart';

import '../api/dtos/grouping.dart';
import '../../domain/grouping/identity_evidence.dart';
import '../db/app_database.dart';
import 'people_repository.dart';
import 'review_questions.dart';

class ReviewMatchFace {
  const ReviewMatchFace({
    required this.faceId,
    required this.cropPath,
    required this.score,
    required this.decision,
  });

  final int faceId;
  final String? cropPath;
  final double score;
  final String decision; // auto | suggest
}

/// "These faces look like Sara" - the Matches tab.
class ReviewMatchGroup {
  const ReviewMatchGroup({required this.person, required this.faces});

  final PersonSummary person;
  final List<ReviewMatchFace> faces;
}

class ReviewGroupFace {
  const ReviewGroupFace({
    required this.faceId,
    required this.cropPath,
    required this.quality,
  });

  final int faceId;
  final String? cropPath;
  final double quality;
}

/// "These faces look like one new person" - the New groups tab.
class ReviewGroupItem {
  const ReviewGroupItem({
    required this.id,
    required this.faces,
    required this.cohesion,
    required this.quality,
  });

  final int id;
  final List<ReviewGroupFace> faces;
  final double cohesion;
  final double quality;
}

/// "These two may be the same person" - the Duplicates tab.
class ReviewDuplicateItem {
  const ReviewDuplicateItem({
    required this.a,
    required this.b,
    required this.score,
  });

  final PersonSummary a;
  final PersonSummary b;
  final double score;
}

/// "This body wears the same outfit as Sara" - the Outfit links tab.
class ReviewBodyLinkItem {
  const ReviewBodyLinkItem({
    required this.bodyId,
    required this.mediaId,
    required this.cropPath,
    required this.person,
    required this.method,
    required this.confidence,
  });

  final int bodyId;
  final int? mediaId;
  final String? cropPath;
  final PersonSummary person;
  final String method;
  final double confidence;
}

/// A face already on a person that the audit doubts.
class ReviewDoubtfulFace {
  const ReviewDoubtfulFace({
    required this.faceId,
    required this.cropPath,
    required this.score,
    this.suggested,
  });

  final int faceId;
  final String? cropPath;

  /// How much it looks like the person's core (low = most doubtful).
  final double score;

  /// Another person it fits better, when there is one.
  final PersonSummary? suggested;
}

/// "Are you sure these are Sara?" - a batch of her most doubtful faces. A person with more doubtful
/// faces than [chunkSize] is several questions, worst first.
class ReviewDoubtfulItem {
  const ReviewDoubtfulItem({
    required this.person,
    required this.faces,
    required this.remaining,
  });

  /// Faces per question: a screenful you can scan at once.
  static const chunkSize = 24;

  final PersonSummary person;
  final List<ReviewDoubtfulFace> faces;

  /// Doubtful faces of this person in all (this batch included).
  final int remaining;

  double get averageScore =>
      faces.fold<double>(0, (s, f) => s + f.score) / faces.length;
}

class ReviewCounts {
  const ReviewCounts({
    this.matches = 0,
    this.groups = 0,
    this.duplicates = 0,
    this.bodyLinks = 0,
    this.doubtful = 0,
  });

  final int matches; // faces
  final int groups;
  final int duplicates;
  final int bodyLinks;
  final int doubtful; // faces on a person that the audit doubts

  /// "N need a decision".
  int get total => matches + groups + duplicates + bodyLinks + doubtful;

  @override
  bool operator ==(Object other) =>
      other is ReviewCounts &&
      other.matches == matches &&
      other.groups == groups &&
      other.duplicates == duplicates &&
      other.bodyLinks == bodyLinks &&
      other.doubtful == doubtful;

  @override
  int get hashCode =>
      Object.hash(matches, groups, duplicates, bodyLinks, doubtful);
}

/// The PC's last review plan (round 3 of the grouping run), kept on the phone.
class ReviewRepository {
  ReviewRepository(this._db, this._people);

  final AppDatabase _db;
  final PeopleRepository _people;

  /// 'person' or 'character': each kind has its own review plan, stored side by side.
  String get kind => _people.kind;

  Stream<void> _changes() => _db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          _db.reviewMatches,
          _db.reviewGroups,
          _db.reviewDuplicates,
          _db.reviewBodyLinks,
          _db.reviewDoubtful,
          _db.faceConfirmations,
          _db.faces,
          _db.persons,
          _db.bodies,
          _db.faceRejections,
          _db.bodyRejections,
          _db.personDistinct,
          _db.reviewSnoozes,
        ]),
      )
      .map((_) {});

  /// Replaces the stored suggestions (one transaction). Suggestions about things that no longer
  /// exist (a face assigned meanwhile, a deleted person) are dropped.
  Future<void> replaceAll(
    GroupingPlanResponse review,
  ) => _db.transaction(() async {
    final own = [Variable.withString(kind)];
    await _db.customUpdate(
      'DELETE FROM review_matches WHERE face_id IN (SELECT id FROM faces WHERE kind = ?)',
      variables: own,
      updates: {_db.reviewMatches},
    );
    await (_db.delete(
      _db.reviewGroups,
    )..where((g) => g.kind.equals(kind))).go();
    await _db.customUpdate(
      'DELETE FROM review_duplicates WHERE person_a IN (SELECT id FROM persons WHERE kind = ?)',
      variables: own,
      updates: {_db.reviewDuplicates},
    );
    await _db.customUpdate(
      'DELETE FROM review_body_links WHERE body_id IN (SELECT id FROM bodies WHERE kind = ?)',
      variables: own,
      updates: {_db.reviewBodyLinks},
    );

    final persons = {
      for (final r
          in await _db
              .customSelect(
                'SELECT id FROM persons WHERE kind = ?',
                variables: own,
                readsFrom: {_db.persons},
              )
              .get())
        r.read<int>('id'),
    };
    final unassigned = {
      for (final r
          in await _db
              .customSelect(
                'SELECT id FROM faces WHERE person_id IS NULL AND review_dismissed = 0 AND kind = ?',
                variables: own,
                readsFrom: {_db.faces},
              )
              .get())
        r.read<int>('id'),
    };
    final bodies = {
      for (final r
          in await _db
              .customSelect(
                'SELECT id FROM bodies WHERE kind = ?',
                variables: own,
                readsFrom: {_db.bodies},
              )
              .get())
        r.read<int>('id'),
    };
    final rejected = {
      for (final row in await _db.select(_db.faceRejections).get())
        '${row.faceId}:${row.personId}',
    };
    final distinct = {
      for (final row in await _db.select(_db.personDistinct).get())
        '${row.personA}:${row.personB}',
    };
    final rejectedBodies = {
      for (final row in await _db.select(_db.bodyRejections).get())
        '${row.bodyId}:${row.personId}',
    };

    await _db.batch((b) {
      b.insertAll(_db.reviewMatches, [
        for (final a in review.assignments)
          if (persons.contains(a.personId) &&
              unassigned.contains(a.faceId) &&
              !rejected.contains('${a.faceId}:${a.personId}'))
            ReviewMatchesCompanion.insert(
              faceId: Value(a.faceId),
              personId: a.personId,
              score: a.score,
              margin: a.margin,
              decision: a.decision,
            ),
      ], mode: InsertMode.insertOrReplace);
      b.insertAll(_db.reviewGroups, [
        for (final g in review.groups)
          if (g.faceIds.any(unassigned.contains))
            ReviewGroupsCompanion.insert(
              faceIds: jsonEncode(
                g.faceIds.where(unassigned.contains).toList(),
              ),
              cohesion: g.cohesion,
              quality: g.quality,
              autoCreate: Value(g.autoCreate),
              kind: Value(kind),
            ),
      ]);
      b.insertAll(_db.reviewDuplicates, [
        for (final d in review.duplicates)
          if (persons.contains(d.personA) &&
              persons.contains(d.personB) &&
              !distinct.contains(
                '${d.personA < d.personB ? d.personA : d.personB}:${d.personA < d.personB ? d.personB : d.personA}',
              ))
            ReviewDuplicatesCompanion.insert(
              personA: d.personA < d.personB ? d.personA : d.personB,
              personB: d.personA < d.personB ? d.personB : d.personA,
              score: d.score,
            ),
      ], mode: InsertMode.insertOrReplace);
      b.insertAll(_db.reviewBodyLinks, [
        for (final l in review.bodyLinks)
          if (!l.isAuto &&
              !isClothingOnlyLink(l.method) &&
              persons.contains(l.personId) &&
              bodies.contains(l.bodyId) &&
              !rejectedBodies.contains('${l.bodyId}:${l.personId}'))
            ReviewBodyLinksCompanion.insert(
              bodyId: Value(l.bodyId),
              personId: l.personId,
              method: l.method,
              confidence: l.confidence,
            ),
      ], mode: InsertMode.insertOrReplace);
    });
  });

  // ---- reading --------------------------------------------------------------------

  /// A video track is one question: counts, cards and decisions all treat it as a single face.
  Future<ReviewCounts> counts() async {
    final matches =
        (await _db
                .customSelect(
                  "SELECT COUNT(DISTINCT m.person_id || ':' || COALESCE(f.track_id, -f.id)) AS n FROM review_matches m JOIN faces f ON f.id = m.face_id WHERE f.person_id IS NULL AND f.review_dismissed = 0 AND f.kind = ? AND NOT EXISTS (SELECT 1 FROM face_rejections r WHERE r.face_id = f.id AND r.person_id = m.person_id)",
                  variables: [Variable.withString(kind)],
                  readsFrom: {_db.reviewMatches, _db.faces, _db.faceRejections},
                )
                .getSingle())
            .read<int>('n');
    final groups = (await groupItems()).length;
    final duplicates =
        (await _db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM review_duplicates d JOIN persons pa ON pa.id = d.person_a WHERE pa.kind = ? AND NOT EXISTS (SELECT 1 FROM person_distinct p WHERE p.person_a = d.person_a AND p.person_b = d.person_b)',
                  variables: [Variable.withString(kind)],
                  readsFrom: {
                    _db.reviewDuplicates,
                    _db.personDistinct,
                    _db.persons,
                  },
                )
                .getSingle())
            .read<int>('n');
    final links =
        (await _db
                .customSelect(
                  '''
          SELECT COUNT(DISTINCT l.person_id || ':' || COALESCE(b.track_id, -b.id)) AS n
          FROM review_body_links l JOIN bodies b ON b.id = l.body_id
          LEFT JOIN faces f ON f.id = b.face_id
          WHERE f.person_id IS NULL AND b.person_id IS NULL AND b.kind = ?
            AND l.method NOT IN ('appearance', 'event_outfit')
            AND b.hidden = 0 AND (b.ownership IS NULL OR b.ownership != 'none')
            AND NOT EXISTS (SELECT 1 FROM body_rejections r WHERE r.body_id = b.id AND r.person_id = l.person_id)
          ''',
                  variables: [Variable.withString(kind)],
                  readsFrom: {_db.reviewBodyLinks, _db.bodies, _db.faces},
                )
                .getSingle())
            .read<int>('n');
    final doubtful =
        (await _db
                .customSelect(
                  '''
          SELECT COUNT(*) AS n FROM review_doubtful d JOIN faces f ON f.id = d.face_id
          WHERE f.person_id = d.person_id AND f.hidden = 0 AND f.kind = ?
            AND NOT EXISTS (SELECT 1 FROM face_confirmations c WHERE c.face_id = f.id AND c.person_id = f.person_id)
          ''',
                  variables: [Variable.withString(kind)],
                  readsFrom: {
                    _db.reviewDoubtful,
                    _db.faces,
                    _db.faceConfirmations,
                  },
                )
                .getSingle())
            .read<int>('n');
    return ReviewCounts(
      matches: matches,
      groups: groups,
      duplicates: duplicates,
      bodyLinks: links,
      doubtful: doubtful,
    );
  }

  Stream<ReviewCounts> watchCounts() async* {
    yield await counts();
    yield* _changes().asyncMap((_) => counts());
  }

  Stream<List<ReviewMatchGroup>> watchMatches() async* {
    yield await matches();
    yield* _changes().asyncMap((_) => matches());
  }

  Future<List<ReviewMatchGroup>> matches() async {
    final people = {for (final p in await _people.people()) p.id: p};
    final rows = await _db
        .customSelect(
          '''
          SELECT m.face_id, m.person_id, m.score, m.decision, f.crop_path, f.track_id
          FROM review_matches m JOIN faces f ON f.id = m.face_id
          WHERE f.person_id IS NULL AND f.review_dismissed = 0 AND f.kind = ?
            AND NOT EXISTS (SELECT 1 FROM face_rejections r WHERE r.face_id = f.id AND r.person_id = m.person_id)
          ORDER BY m.person_id, m.score DESC
          ''',
          variables: [Variable.withString(kind)],
          readsFrom: {_db.reviewMatches, _db.faces, _db.faceRejections},
        )
        .get();
    final byPerson = <int, List<ReviewMatchFace>>{};
    final shown =
        <String>{}; // person:track - the best-scoring face stands for its track
    for (final r in rows) {
      final track = r.readNullable<int>('track_id');
      if (track != null && !shown.add('${r.read<int>('person_id')}:$track')) {
        continue;
      }
      byPerson
          .putIfAbsent(r.read<int>('person_id'), () => [])
          .add(
            ReviewMatchFace(
              faceId: r.read<int>('face_id'),
              cropPath: r.readNullable<String>('crop_path'),
              score: r.read<double>('score'),
              decision: r.read<String>('decision'),
            ),
          );
    }
    final out = [
      for (final e in byPerson.entries)
        if (people[e.key] != null)
          ReviewMatchGroup(person: people[e.key]!, faces: e.value),
    ]..sort((a, b) => b.faces.length.compareTo(a.faces.length));
    return out;
  }

  Stream<List<ReviewGroupItem>> watchGroups() async* {
    yield await groupItems();
    yield* _changes().asyncMap((_) => groupItems());
  }

  /// Groups whose faces are still unsorted (a face sorted since the plan was made drops out).
  Future<List<ReviewGroupItem>> groupItems() async {
    final rows = await (_db.select(
      _db.reviewGroups,
    )..where((g) => g.kind.equals(kind))).get();
    if (rows.isEmpty) return const [];
    final faces = <int, ReviewGroupFace>{};
    final all = rows
        .expand((r) => PeopleRepository.decodeFaceIds(r.faceIds))
        .toSet();
    for (final f in await _people.facesByIds(all)) {
      if (f.personId == null && !f.dismissed) {
        faces[f.id] = ReviewGroupFace(
          faceId: f.id,
          cropPath: f.cropPath,
          quality: f.quality,
        );
      }
    }
    final tracks = await _trackOf(faces.keys);
    final out = <ReviewGroupItem>[];
    for (final r in rows) {
      final best =
          <
            Object,
            ReviewGroupFace
          >{}; // track (or the face itself) -> best face
      for (final id in PeopleRepository.decodeFaceIds(r.faceIds)) {
        final face = faces[id];
        if (face == null) continue;
        final key = tracks[id] ?? 'f$id';
        if (best[key] == null || face.quality > best[key]!.quality) {
          best[key] = face;
        }
      }
      final list = best.values.toList();
      if (list.isNotEmpty) {
        out.add(
          ReviewGroupItem(
            id: r.id,
            faces: list,
            cohesion: r.cohesion,
            quality: r.quality,
          ),
        );
      }
    }
    return out;
  }

  Stream<List<ReviewDuplicateItem>> watchDuplicates() async* {
    yield await duplicates();
    yield* _changes().asyncMap((_) => duplicates());
  }

  Future<List<ReviewDuplicateItem>> duplicates() async {
    final people = {for (final p in await _people.people()) p.id: p};
    final distinct = {
      for (final row in await _db.select(_db.personDistinct).get())
        (row.personA, row.personB),
    };
    final rows = await (_db.select(
      _db.reviewDuplicates,
    )..orderBy([(d) => OrderingTerm.desc(d.score)])).get();
    return [
      for (final r in rows)
        if (people[r.personA] != null &&
            people[r.personB] != null &&
            !distinct.contains((r.personA, r.personB)))
          ReviewDuplicateItem(
            a: people[r.personA]!,
            b: people[r.personB]!,
            score: r.score,
          ),
    ];
  }

  /// The PC's score for a pair, if it flagged it.
  Future<double?> duplicateScore(int a, int b) async {
    if (await _people.areDistinct(a, b)) return null;
    final x = a < b ? a : b;
    final y = a < b ? b : a;
    final row =
        await (_db.select(_db.reviewDuplicates)
              ..where((d) => d.personA.equals(x) & d.personB.equals(y)))
            .getSingleOrNull();
    return row?.score;
  }

  Stream<List<ReviewBodyLinkItem>> watchBodyLinks() async* {
    yield await bodyLinks();
    yield* _changes().asyncMap((_) => bodyLinks());
  }

  Future<List<ReviewBodyLinkItem>> bodyLinks() async {
    final people = {for (final p in await _people.people()) p.id: p};
    final rows = await _db
        .customSelect(
          '''
          SELECT l.body_id, l.person_id, l.method, l.confidence, b.media_id, b.crop_path, b.track_id
          FROM review_body_links l JOIN bodies b ON b.id = l.body_id
          LEFT JOIN faces f ON f.id = b.face_id
          WHERE f.person_id IS NULL AND b.person_id IS NULL AND b.kind = ?
            AND l.method NOT IN ('appearance', 'event_outfit')
            AND b.hidden = 0 AND (b.ownership IS NULL OR b.ownership != 'none')
            AND NOT EXISTS (SELECT 1 FROM body_rejections r WHERE r.body_id = b.id AND r.person_id = l.person_id)
          ORDER BY l.confidence DESC
          ''',
          variables: [Variable.withString(kind)],
          readsFrom: {_db.reviewBodyLinks, _db.bodies, _db.faces},
        )
        .get();
    final shown = <String>{};
    return [
      for (final r in rows)
        if (people[r.read<int>('person_id')] != null &&
            (r.readNullable<int>('track_id') == null ||
                shown.add(
                  '${r.read<int>('person_id')}:${r.read<int>('track_id')}',
                )))
          ReviewBodyLinkItem(
            bodyId: r.read<int>('body_id'),
            mediaId: r.readNullable<int>('media_id'),
            cropPath: r.readNullable<String>('crop_path'),
            person: people[r.read<int>('person_id')]!,
            method: r.read<String>('method'),
            confidence: r.read<double>('confidence'),
          ),
    ];
  }

  /// Match suggestions for one person (the Suggestions tab of their page).
  Future<List<ReviewMatchFace>> matchesFor(int personId) async {
    final all = await matches();
    for (final g in all) {
      if (g.person.id == personId) return g.faces;
    }
    return const [];
  }

  Stream<List<ReviewMatchFace>> watchMatchesFor(int personId) async* {
    yield await matchesFor(personId);
    yield* _changes().asyncMap((_) => matchesFor(personId));
  }

  // ---- "are you sure?" ------------------------------------------------------------

  Stream<List<ReviewDoubtfulItem>> watchDoubtful() async* {
    yield await doubtful();
    yield* _changes().asyncMap((_) => doubtful());
  }

  /// Faces on a person that the audit doubts, per person, worst first, in batches of
  /// [ReviewDoubtfulItem.chunkSize]. A face answered since (confirmed, moved, rejected, hidden) is gone.
  Future<List<ReviewDoubtfulItem>> doubtful() async {
    final people = {for (final p in await _people.people()) p.id: p};
    final rows = await _db
        .customSelect(
          '''
          SELECT d.face_id, d.person_id, d.score, d.suggested_person_id, f.crop_path
          FROM review_doubtful d JOIN faces f ON f.id = d.face_id
          WHERE f.person_id = d.person_id AND f.hidden = 0 AND f.kind = ?
            AND NOT EXISTS (SELECT 1 FROM face_confirmations c WHERE c.face_id = f.id AND c.person_id = f.person_id)
          ORDER BY d.person_id, d.score ASC, d.face_id
          ''',
          variables: [Variable.withString(kind)],
          readsFrom: {_db.reviewDoubtful, _db.faces, _db.faceConfirmations},
        )
        .get();
    final byPerson = <int, List<ReviewDoubtfulFace>>{};
    for (final r in rows) {
      final pid = r.read<int>('person_id');
      if (people[pid] == null) continue;
      final suggested = r.readNullable<int>('suggested_person_id');
      byPerson
          .putIfAbsent(pid, () => [])
          .add(
            ReviewDoubtfulFace(
              faceId: r.read<int>('face_id'),
              cropPath: r.readNullable<String>('crop_path'),
              score: r.read<double>('score'),
              suggested: suggested == null ? null : people[suggested],
            ),
          );
    }
    final out = <ReviewDoubtfulItem>[];
    for (final e in byPerson.entries) {
      for (var i = 0; i < e.value.length; i += ReviewDoubtfulItem.chunkSize) {
        out.add(
          ReviewDoubtfulItem(
            person: people[e.key]!,
            faces: e.value.sublist(
              i,
              math.min(i + ReviewDoubtfulItem.chunkSize, e.value.length),
            ),
            remaining: e.value.length,
          ),
        );
      }
    }
    return out;
  }

  /// "Yes, these are her."
  Future<void> confirmDoubtful(Iterable<int> faceIds, int personId) =>
      _people.confirmFaces(faceIds, personId);

  /// "No, these are not her": they leave her, and auto-grouping never puts them back. With
  /// [moveTo], a face the audit found a better home for goes there instead of waiting unsorted.
  Future<void> removeDoubtful(
    Iterable<int> faceIds,
    int personId, {
    Map<int, int> moveTo = const {},
  }) => _db.transaction(() async {
    final ids = faceIds.toList();
    await _people.rejectFaces(ids, fromPersonId: personId);
    final byTarget = <int, List<int>>{};
    for (final id in ids) {
      final to = moveTo[id];
      if (to != null && to != personId) {
        byTarget.putIfAbsent(to, () => []).add(id);
      }
    }
    for (final e in byTarget.entries) {
      await _people.assignFaces(e.value, e.key);
    }
  });

  // ---- quick review ---------------------------------------------------------------

  Future<Map<String, ReviewSnooze>> _snoozes() async => {
    for (final r in await _db.select(_db.reviewSnoozes).get())
      r.questionKey: ReviewSnooze(score: r.score, evidence: r.evidence),
  };

  /// One question at a time for the quick review: everything the tabs show, minus "Not sure"
  /// answers that no new evidence has reopened.
  Future<List<ReviewQuestion>> questions() async => buildQuestions(
    matches: await matches(),
    groups: await groupItems(),
    duplicates: await duplicates(),
    outfits: await bodyLinks(),
    doubtful: await doubtful(),
    snoozes: await _snoozes(),
  );

  Stream<List<ReviewQuestion>> watchQuestions() async* {
    yield await questions();
    yield* _changes().asyncMap((_) => questions());
  }

  /// "Not sure": park the question on this phone until its score or its faces grow.
  Future<void> snooze(ReviewQuestion q) => _db
      .into(_db.reviewSnoozes)
      .insertOnConflictUpdate(
        ReviewSnoozesCompanion.insert(
          questionKey: q.key,
          score: q.score,
          evidence: q.evidence,
          snoozedAt: DateTime.now().millisecondsSinceEpoch,
        ),
      );

  Future<void> unsnooze(String key) => (_db.delete(
    _db.reviewSnoozes,
  )..where((s) => s.questionKey.equals(key))).go();

  // ---- decisions ------------------------------------------------------------------

  /// "Add these faces to the person" for a whole Matches card.
  Future<void> acceptMatches(Iterable<int> faceIds, int personId) async =>
      _people.assignFaces(
        await expandTracks(faceIds, notRejectedBy: personId),
        personId,
      );

  Future<void> rejectMatches(Iterable<int> faceIds, int personId) async =>
      _people.rejectFaces(await expandTracks(faceIds), fromPersonId: personId);

  /// A New groups card becomes a person: its faces and the rest of their video tracks.
  Future<int> createPersonFromGroup({
    String? name,
    required Iterable<int> faceIds,
  }) async =>
      _people.createPerson(name: name, faceIds: await expandTracks(faceIds));

  Future<void> assignGroup(Iterable<int> faceIds, int personId) async =>
      _people.assignFaces(
        await expandTracks(faceIds, notRejectedBy: personId),
        personId,
      );

  /// "Ignore": not a person worth keeping / not important. Hides the faces from group suggestions and
  /// from grouping for good, and removes the group. Returns the faces (video tracks included) so the
  /// answer can be undone.
  Future<List<int>> dismissGroup(int groupId) => _db.transaction(() async {
    final row = await (_db.select(
      _db.reviewGroups,
    )..where((g) => g.id.equals(groupId))).getSingleOrNull();
    if (row == null) return const <int>[];
    final ids = await expandTracks(PeopleRepository.decodeFaceIds(row.faceIds));
    await _people.dismissFaces(ids);
    await (_db.delete(
      _db.reviewGroups,
    )..where((g) => g.id.equals(groupId))).go();
    return ids;
  });

  /// "Ignore" for faces the review asked about: they (and the rest of their video tracks) never come
  /// back in Review or in grouping. They stay in the library.
  Future<List<int>> ignoreFaces(Iterable<int> faceIds) async {
    final ids = await expandTracks(faceIds);
    await _people.dismissFaces(ids);
    return ids;
  }

  /// "Ignore" for faces already on a person ("Are you sure these are X?"): they leave her, are never
  /// put back, and are not asked about again.
  Future<List<int>> ignoreDoubtful(Iterable<int> faceIds, int personId) =>
      _db.transaction(() async {
        final ids = faceIds.toList();
        await _people.rejectFaces(ids, fromPersonId: personId);
        await _people.dismissFaces(ids);
        return ids;
      });

  /// Undo of an "Ignore": the faces are unsorted again and Review / grouping consider them.
  Future<void> restoreIgnored(Iterable<int> faceIds) =>
      _people.clearAssignments(faceIds);

  Future<void> forgetGroup(int groupId) =>
      (_db.delete(_db.reviewGroups)..where((g) => g.id.equals(groupId))).go();

  Future<void> acceptBodyLink(int bodyId, int personId) =>
      _db.transaction(() async {
        for (final id in await _expandBodyTrack(bodyId, personId)) {
          await _people.linkBody(id, personId);
        }
      });

  Future<void> rejectBodyLink(int bodyId, int personId) =>
      _db.transaction(() async {
        for (final id in await _expandBodyTrack(bodyId, null)) {
          await _people.rejectBody(id, personId: personId);
        }
      });

  // ---- video tracks ---------------------------------------------------------------

  /// The faces plus the still unsorted faces of their video tracks (a review card shows one
  /// face per track, but the answer is about the whole appearance). `notRejectedBy` leaves out
  /// track faces the user already said are not that person.
  Future<List<int>> expandTracks(
    Iterable<int> faceIds, {
    int? notRejectedBy,
  }) async {
    final ids = faceIds.toSet();
    final tracks = (await _trackOf(ids)).values.toSet().toList();
    for (var i = 0; i < tracks.length; i += 500) {
      final chunk = tracks.sublist(i, math.min(i + 500, tracks.length));
      for (final r
          in await _db
              .customSelect(
                'SELECT id FROM faces WHERE person_id IS NULL AND review_dismissed = 0 AND NOT EXISTS (SELECT 1 FROM face_rejections r WHERE r.face_id = faces.id AND r.person_id IS ?) AND track_id IN (${List.filled(chunk.length, '?').join(',')}) ORDER BY id',
                variables: [
                  Variable<int>(notRejectedBy),
                  for (final t in chunk) Variable.withInt(t),
                ],
                readsFrom: {_db.faces, _db.faceRejections},
              )
              .get()) {
        ids.add(r.read<int>('id'));
      }
    }
    return ids.toList();
  }

  Future<Map<int, int>> _trackOf(Iterable<int> faceIds) async {
    final ids = faceIds.toSet().toList();
    final out = <int, int>{};
    for (var i = 0; i < ids.length; i += 500) {
      final chunk = ids.sublist(i, math.min(i + 500, ids.length));
      for (final r
          in await _db
              .customSelect(
                'SELECT id, track_id FROM faces WHERE track_id IS NOT NULL AND id IN (${List.filled(chunk.length, '?').join(',')})',
                variables: [for (final id in chunk) Variable.withInt(id)],
                readsFrom: {_db.faces},
              )
              .get()) {
        out[r.read<int>('id')] = r.read<int>('track_id');
      }
    }
    return out;
  }

  /// The body plus the unlinked bodies of its video track (minus those already refused for
  /// `notRejectedBy`).
  Future<List<int>> _expandBodyTrack(int bodyId, int? notRejectedBy) async => [
    bodyId,
    for (final r
        in await _db
            .customSelect(
              '''
              SELECT o.id FROM bodies b JOIN bodies o ON o.track_id = b.track_id AND o.id != b.id
              LEFT JOIN faces f ON f.id = o.face_id
              WHERE b.id = ? AND o.person_id IS NULL AND f.person_id IS NULL
                AND NOT EXISTS (SELECT 1 FROM body_rejections r WHERE r.body_id = o.id AND r.person_id IS ?)
              ORDER BY o.id
              ''',
              variables: [
                Variable.withInt(bodyId),
                Variable<int>(notRejectedBy),
              ],
              readsFrom: {_db.bodies, _db.faces, _db.bodyRejections},
            )
            .get())
      r.read<int>('id'),
  ];
}
