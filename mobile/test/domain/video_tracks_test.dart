// A person who stays in a video is one track: a few varied face/body rows, every other frame only
// a detection. Review asks once per track, and old per-frame libraries can be compacted.

import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/grouping.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/index/embedding_index.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/data/repositories/review_repository.dart';
import 'package:antigravity_mobile/domain/grouping/plan_applier.dart';
import 'package:antigravity_mobile/domain/scan/photo_result_store.dart';
import 'package:antigravity_mobile/domain/scan/video_compactor.dart';
import 'package:antigravity_mobile/domain/scan/video_tracks.dart';
import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late Directory tmp;
  late FileStore files;
  late InMemoryEmbeddingIndex index;
  late PhotoResultStore store;
  late PeopleRepository people;
  late ReviewRepository review;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    tmp = Directory.systemTemp.createTempSync('ag_tracks_');
    files = FileStore(Directory('${tmp.path}/crops'));
    index = InMemoryEmbeddingIndex();
    store = PhotoResultStore(db: db, files: files, index: index);
    people = PeopleRepository(db, files, index: index);
    review = ReviewRepository(db, people);
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<MediaRow> video({String status = 'scanning'}) async {
    final id = await seedMedia(
      db,
      asset: 'v$status',
      kind: 'video',
      status: status,
    );
    return (db.select(db.media)..where((m) => m.id.equals(id))).getSingle();
  }

  Future<int> count(String sql) async =>
      (await db.customSelect(sql).getSingle()).read<int>('n');

  Future<void> frames(
    MediaRow media,
    int n,
    List<Map<String, dynamic>> Function(int frame) faces, {
    List<Map<String, dynamic>> Function(int frame)? bodies,
    List<(int, int)> pairs = const [],
  }) async {
    for (var f = 0; f < n; f++) {
      await store.store(
        media,
        analysis(
          faces: faces(f),
          bodies: bodies?.call(f) ?? const [],
          pairs: pairs,
        ),
        frameNumber: f * 15,
        timestampMs: f * 500,
        complete: false,
      );
    }
  }

  group('scanning a video', () {
    test(
      'one person over 30 frames keeps at most a few varied faces and one body, all frames still recorded',
      () async {
        final media = await video();
        final sara = unitVec(1);
        await frames(
          media,
          30,
          (f) => [
            faceJson(
              near(sara, 100 + f, 0.7),
              box: [100.0 + f * 3, 100, 200, 240],
            ),
          ],
          bodies: (f) => [
            bodyJson(box: [50.0 + f * 3, 60, 400, 700]),
          ],
          pairs: [(0, 0)],
        );
        final faces = await db.select(db.faces).get();
        expect(faces.length, maxFacesPerTrack);
        expect(faces.map((f) => f.trackId).toSet(), {faces.first.id});
        expect(
          await count(
            "SELECT COUNT(*) AS n FROM media_detections WHERE kind = 'f'",
          ),
          30,
          reason: '"which frames is she in?" still has every frame',
        );
        expect(
          await count(
            "SELECT COUNT(*) AS n FROM media_detections d WHERE kind = 'f' AND NOT EXISTS (SELECT 1 FROM faces f WHERE f.id = d.ref_id)",
          ),
          0,
        );
        final bodies = await db.select(db.bodies).get();
        expect(bodies.length, 1, reason: 'the same outfit adds nothing');
        expect(bodies.single.trackId, bodies.single.id);
        expect(
          await count(
            "SELECT COUNT(*) AS n FROM media_detections WHERE kind = 'b'",
          ),
          30,
        );
        expect(await index.size(), maxFacesPerTrack);
      },
    );

    test('two people side by side stay two tracks', () async {
      final media = await video();
      final a = unitVec(1), b = unitVec(2);
      await frames(
        media,
        10,
        (f) => [
          faceJson(near(a, 200 + f, 0.3), box: [100, 100, 200, 240]),
          faceJson(near(b, 300 + f, 0.3), box: [600, 100, 200, 240]),
        ],
      );
      final faces = await db.select(db.faces).get();
      final byTrack = <int, Set<bool>>{};
      for (final f in faces) {
        byTrack.putIfAbsent(f.trackId!, () => {}).add(f.bboxX < 0.5);
      }
      expect(byTrack.length, 2);
      expect(byTrack.values.every((sides) => sides.length == 1), isTrue);
    });

    test(
      'a clearly sharper view replaces the weakest unsorted one of a full track',
      () async {
        final media = await video();
        final sara = unitVec(1);
        await frames(
          media,
          8,
          (f) => [
            faceJson(near(sara, 400 + f, 0.7), quality: f == 7 ? 0.95 : 0.5),
          ],
        );
        final faces = await db.select(db.faces).get();
        expect(faces.length, maxFacesPerTrack);
        expect(faces.map((f) => f.qualityScore), contains(0.95));
      },
    );

    test('photos are never tracked', () async {
      final id = await seedMedia(db, asset: 'p1');
      final media = await (db.select(
        db.media,
      )..where((m) => m.id.equals(id))).getSingle();
      await store.store(media, analysis(faces: [faceJson(unitVec(1))]));
      expect((await db.select(db.faces).getSingle()).trackId, isNull);
    });
  });

  group('review', () {
    Future<List<int>> trackOfSara() async {
      final media = await video();
      final sara = unitVec(1);
      await frames(media, 12, (f) => [faceJson(near(sara, 500 + f, 0.7))]);
      return [for (final f in await db.select(db.faces).get()) f.id];
    }

    test(
      'a track is one match question; accepting it sorts every face of the track',
      () async {
        final ids = await trackOfSara();
        final sara = await seedPerson(db, name: 'Sara');
        await db.batch(
          (b) => b.insertAll(db.reviewMatches, [
            for (final id in ids)
              ReviewMatchesCompanion.insert(
                faceId: Value(id),
                personId: sara,
                score: 0.5,
                margin: 0.1,
                decision: 'suggest',
              ),
          ]),
        );
        expect((await review.counts()).matches, 1);
        final card = (await review.matches()).single;
        expect(card.faces.length, 1);
        await review.acceptMatches([card.faces.single.faceId], sara);
        expect(
          (await db.select(db.faces).get()).map((f) => f.personId).toSet(),
          {sara},
        );
      },
    );

    test('"Not them" on the shown face refuses the whole track', () async {
      final ids = await trackOfSara();
      final sara = await seedPerson(db, name: 'Sara');
      await review.rejectMatches([ids.first], sara);
      expect(
        await count('SELECT COUNT(*) AS n FROM face_rejections'),
        ids.length,
      );
    });

    test(
      'a new-person group shows one face per track and takes them all',
      () async {
        final ids = await trackOfSara();
        await db
            .into(db.reviewGroups)
            .insert(
              ReviewGroupsCompanion.insert(
                faceIds: '[${ids.join(',')}]',
                cohesion: 0.7,
                quality: 0.7,
              ),
            );
        final group = (await review.groupItems()).single;
        expect(group.faces.length, 1);
        final person = await review.createPersonFromGroup(
          faceIds: [group.faces.single.faceId],
        );
        expect(
          (await db.select(db.faces).get()).map((f) => f.personId).toSet(),
          {person},
        );
      },
    );

    test(
      'auto-grouping one face of a track brings the rest, but not a refused one',
      () async {
        final ids = await trackOfSara();
        final sara = await seedPerson(db, name: 'Sara');
        await db
            .into(db.faceRejections)
            .insert(
              FaceRejectionsCompanion.insert(faceId: ids.last, personId: sara),
            );
        await PlanApplier(db).applyFacePlan(
          GroupingPlanResponse.fromJson({
            'mode': 'apply',
            'assignments': [
              {
                'face_id': ids.first,
                'person_id': sara,
                'score': 0.7,
                'margin': 0.3,
                'decision': 'auto',
              },
            ],
            'groups': <Object>[],
            'duplicates': <Object>[],
            'body_links': <Object>[],
            'unsorted_face_ids': <Object>[],
          }),
        );
        final byId = {for (final f in await db.select(db.faces).get()) f.id: f};
        for (final id in ids) {
          expect(byId[id]!.personId, id == ids.last ? isNull : sara);
        }
      },
    );
  });

  group('compacting a video scanned before tracking', () {
    test(
      'per-frame rows collapse into tracks; detections, bodies and decisions survive',
      () async {
        final media = await video(status: 'done');
        final sara = await seedPerson(db, name: 'Sara');
        final base = unitVec(1);
        final faceIds = <int>[];
        for (var f = 0; f < 40; f++) {
          final crop = 'faces/legacy$f.jpg';
          await files.write(crop, Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9]));
          final id = await seedFace(
            db,
            mediaId: media.id,
            frameNumber: f * 15,
            embedding: near(base, 600 + f, 0.3),
            cropPath: crop,
            personId: f < 20 ? sara : null,
          );
          faceIds.add(id);
          await seedBody(
            db,
            mediaId: media.id,
            faceId: id,
            frameNumber: f * 15,
            appearance: outfit(1),
          );
        }
        // the cover must stay; a correction on a removed face moves to the one that stays
        await (db.update(db.persons)..where((p) => p.id.equals(sara))).write(
          PersonsCompanion(avatarFaceId: Value(faceIds[5])),
        );
        final other = await seedPerson(db, name: 'Other');
        await db
            .into(db.faceRejections)
            .insert(
              FaceRejectionsCompanion.insert(
                faceId: faceIds[30],
                personId: other,
              ),
            );

        final compactor = VideoCompactor(db: db, files: files, index: index);
        expect(await compactor.pendingVideos(), [media.id]);
        final result = await compactor.compactVideo(media.id);

        final faces = await db.select(db.faces).get();
        expect(faces.length, lessThan(6));
        expect(result.facesRemoved, 40 - faces.length);
        expect(faces.every((f) => f.trackId != null), isTrue);
        expect(faces.map((f) => f.id), contains(faceIds[5]));
        expect(
          faces.where((f) => f.personId == sara).length +
              faces.where((f) => f.personId == null).length,
          faces.length,
        );
        expect(faces.any((f) => f.personId == sara), isTrue);
        expect(faces.any((f) => f.personId == null), isTrue);
        expect(
          await count(
            "SELECT COUNT(*) AS n FROM media_detections WHERE kind = 'f'",
          ),
          40,
        );
        expect(
          await count(
            "SELECT COUNT(*) AS n FROM media_detections d WHERE NOT EXISTS (SELECT 1 FROM faces f WHERE d.kind = 'f' AND f.id = d.ref_id) AND NOT EXISTS (SELECT 1 FROM bodies b WHERE d.kind = 'b' AND b.id = d.ref_id)",
          ),
          0,
        );
        expect(
          await count(
            'SELECT COUNT(*) AS n FROM bodies b WHERE b.face_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM faces f WHERE f.id = b.face_id)',
          ),
          0,
        );
        expect(await count('SELECT COUNT(*) AS n FROM bodies'), lessThan(40));
        final unsorted = faces
            .where((f) => f.personId == null)
            .map((f) => f.id);
        expect(
          await count(
            'SELECT COUNT(*) AS n FROM face_rejections WHERE person_id = $other AND face_id IN (${unsorted.join(',')})',
          ),
          greaterThan(0),
        );
        final remaining = Directory('${tmp.path}/crops/faces').listSync();
        expect(
          remaining.length,
          faces.length,
          reason: 'removed crops free space',
        );

        expect(await compactor.pendingVideos(), isEmpty);
        final again = await compactor.compactVideo(media.id);
        expect((again.facesRemoved, again.bodiesRemoved), (0, 0));
      },
    );

    test('compacting is what the scan would have stored', () async {
      final media = await video(status: 'done');
      final base = unitVec(3);
      for (var f = 0; f < 30; f++) {
        await seedFace(
          db,
          mediaId: media.id,
          frameNumber: f * 15,
          embedding: near(base, 700 + f, 0.7),
        );
      }
      await VideoCompactor(db: db, files: files).compactVideo(media.id);
      expect(await count('SELECT COUNT(*) AS n FROM faces'), maxFacesPerTrack);
      expect(
        (await db
                .customSelect(
                  'SELECT COUNT(DISTINCT track_id) AS n FROM faces WHERE media_id = ?',
                  variables: [Variable.withInt(media.id)],
                )
                .getSingle())
            .read<int>('n'),
        1,
      );
    });
  });
}
