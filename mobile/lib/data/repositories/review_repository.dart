import 'dart:convert';

import 'package:drift/drift.dart';

import '../api/dtos/grouping.dart';
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

class ReviewCounts {
  const ReviewCounts({
    this.matches = 0,
    this.groups = 0,
    this.duplicates = 0,
    this.bodyLinks = 0,
  });

  final int matches; // faces
  final int groups;
  final int duplicates;
  final int bodyLinks;

  /// "N need a decision".
  int get total => matches + groups + duplicates + bodyLinks;

  @override
  bool operator ==(Object other) =>
      other is ReviewCounts &&
      other.matches == matches &&
      other.groups == groups &&
      other.duplicates == duplicates &&
      other.bodyLinks == bodyLinks;

  @override
  int get hashCode => Object.hash(matches, groups, duplicates, bodyLinks);
}

/// The PC's last review plan (round 3 of the grouping run), kept on the phone.
class ReviewRepository {
  ReviewRepository(this._db, this._people);

  final AppDatabase _db;
  final PeopleRepository _people;

  Stream<void> _changes() => _db
      .tableUpdates(
        TableUpdateQuery.onAllTables([
          _db.reviewMatches,
          _db.reviewGroups,
          _db.reviewDuplicates,
          _db.reviewBodyLinks,
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
    await _db.delete(_db.reviewMatches).go();
    await _db.delete(_db.reviewGroups).go();
    await _db.delete(_db.reviewDuplicates).go();
    await _db.delete(_db.reviewBodyLinks).go();

    final persons = {
      for (final r
          in await _db
              .customSelect('SELECT id FROM persons', readsFrom: {_db.persons})
              .get())
        r.read<int>('id'),
    };
    final unassigned = {
      for (final r
          in await _db
              .customSelect(
                'SELECT id FROM faces WHERE person_id IS NULL AND review_dismissed = 0',
                readsFrom: {_db.faces},
              )
              .get())
        r.read<int>('id'),
    };
    final bodies = {
      for (final r
          in await _db
              .customSelect('SELECT id FROM bodies', readsFrom: {_db.bodies})
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

  Future<ReviewCounts> counts() async {
    final matches =
        (await _db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM review_matches m JOIN faces f ON f.id = m.face_id WHERE f.person_id IS NULL AND f.review_dismissed = 0 AND NOT EXISTS (SELECT 1 FROM face_rejections r WHERE r.face_id = f.id AND r.person_id = m.person_id)',
                  readsFrom: {_db.reviewMatches, _db.faces, _db.faceRejections},
                )
                .getSingle())
            .read<int>('n');
    final groups = (await groupItems()).length;
    final duplicates =
        (await _db
                .customSelect(
                  'SELECT COUNT(*) AS n FROM review_duplicates d WHERE NOT EXISTS (SELECT 1 FROM person_distinct p WHERE p.person_a = d.person_a AND p.person_b = d.person_b)',
                  readsFrom: {_db.reviewDuplicates, _db.personDistinct},
                )
                .getSingle())
            .read<int>('n');
    final links =
        (await _db
                .customSelect(
                  '''
          SELECT COUNT(*) AS n FROM review_body_links l JOIN bodies b ON b.id = l.body_id
          LEFT JOIN faces f ON f.id = b.face_id
          WHERE f.person_id IS NULL AND b.person_id IS NULL
            AND NOT EXISTS (SELECT 1 FROM body_rejections r WHERE r.body_id = b.id AND r.person_id = l.person_id)
          ''',
                  readsFrom: {_db.reviewBodyLinks, _db.bodies, _db.faces},
                )
                .getSingle())
            .read<int>('n');
    return ReviewCounts(
      matches: matches,
      groups: groups,
      duplicates: duplicates,
      bodyLinks: links,
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
          SELECT m.face_id, m.person_id, m.score, m.decision, f.crop_path
          FROM review_matches m JOIN faces f ON f.id = m.face_id
          WHERE f.person_id IS NULL AND f.review_dismissed = 0
            AND NOT EXISTS (SELECT 1 FROM face_rejections r WHERE r.face_id = f.id AND r.person_id = m.person_id)
          ORDER BY m.person_id, m.score DESC
          ''',
          readsFrom: {_db.reviewMatches, _db.faces, _db.faceRejections},
        )
        .get();
    final byPerson = <int, List<ReviewMatchFace>>{};
    for (final r in rows) {
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
    final rows = await _db.select(_db.reviewGroups).get();
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
    final out = <ReviewGroupItem>[];
    for (final r in rows) {
      final list = [
        for (final id in PeopleRepository.decodeFaceIds(r.faceIds))
          if (faces[id] != null) faces[id]!,
      ];
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
          SELECT l.body_id, l.person_id, l.method, l.confidence, b.media_id, b.crop_path
          FROM review_body_links l JOIN bodies b ON b.id = l.body_id
          LEFT JOIN faces f ON f.id = b.face_id
          WHERE f.person_id IS NULL AND b.person_id IS NULL
            AND NOT EXISTS (SELECT 1 FROM body_rejections r WHERE r.body_id = b.id AND r.person_id = l.person_id)
          ORDER BY l.confidence DESC
          ''',
          readsFrom: {_db.reviewBodyLinks, _db.bodies, _db.faces},
        )
        .get();
    return [
      for (final r in rows)
        if (people[r.read<int>('person_id')] != null)
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
  Future<void> acceptMatches(Iterable<int> faceIds, int personId) =>
      _people.assignFaces(faceIds, personId);

  Future<void> rejectMatches(Iterable<int> faceIds, int personId) =>
      _people.rejectFaces(faceIds, fromPersonId: personId);

  /// "Not a person worth keeping": hides the faces from group suggestions and removes the group.
  Future<void> dismissGroup(int groupId) => _db.transaction(() async {
    final row = await (_db.select(
      _db.reviewGroups,
    )..where((g) => g.id.equals(groupId))).getSingleOrNull();
    if (row == null) return;
    await _people.dismissFaces(PeopleRepository.decodeFaceIds(row.faceIds));
    await (_db.delete(
      _db.reviewGroups,
    )..where((g) => g.id.equals(groupId))).go();
  });

  Future<void> forgetGroup(int groupId) =>
      (_db.delete(_db.reviewGroups)..where((g) => g.id.equals(groupId))).go();

  Future<void> acceptBodyLink(int bodyId, int personId) =>
      _people.linkBody(bodyId, personId);

  Future<void> rejectBodyLink(int bodyId, int personId) =>
      _people.rejectBody(bodyId, personId: personId);
}
