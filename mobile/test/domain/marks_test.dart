// Roadmap Phase 6 on the phone: mark geometry (the same place on another photo), mark storage with its
// patch in the private store, and the search that asks the PC to match patches.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/analyze.dart'
    show AnalyzeMarksResponse, MarkMatchDto;
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/repositories/review_questions.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/domain/marks/body_marks.dart';
import 'package:antigravity_mobile/domain/marks/mark_geometry.dart';
import 'package:antigravity_mobile/domain/pose/pose_geometry.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/seed.dart';

/// A frontal person (1000 x 1500 px): the right forearm runs from the elbow (330, 550) to the wrist (320, 700).
Pose person({
  double scale = 1,
  double dx = 0,
  double dy = 0,
  bool hips = true,
}) {
  const pts = <int, List<double>>{
    5: [650, 400],
    6: [350, 400],
    7: [670, 550],
    8: [330, 550],
    9: [680, 700],
    10: [320, 700],
    11: [560, 800],
    12: [440, 800],
    13: [560, 1050],
    14: [440, 1050],
    15: [560, 1300],
    16: [440, 1300],
  };
  return Pose([
    for (var i = 0; i < 17; i++)
      pts.containsKey(i) && (hips || i < 11)
          ? Pt(pts[i]![0] * scale + dx, pts[i]![1] * scale + dy, 0.9)
          : const Pt(0, 0, 0),
  ], extent: 'full');
}

String kpts(Pose p, int w, int h) => jsonEncode([
  for (final k in p.points) [k.x / w, k.y / h, k.score],
]);

int _assetCounter = 0;

void main() {
  group('geometry', () {
    test(
      'a mark keeps its place on another photo at another scale and position',
      () {
        final box = (
          x: 310.0,
          y: 590.0,
          w: 40.0,
          h: 60.0,
        ); // on the right forearm
        final anchor = anchorFor(person(), 'r_forearm', box)!;
        final same = rectFor(person(), 'r_forearm', anchor)!;
        expect(same.cx, closeTo(330, 1.0));
        expect(same.cy, closeTo(620, 1.0));
        expect(same.width, closeTo(60, 3));
        final moved = rectFor(
          person(scale: 0.5, dx: 100, dy: 30),
          'r_forearm',
          anchor,
        )!;
        expect(moved.cx, closeTo(330 * 0.5 + 100, 1.0));
        expect(moved.cy, closeTo(620 * 0.5 + 30, 1.0));
        expect(
          moved.width,
          closeTo(same.width / 2, 2),
          reason: 'scales with the segment',
        );
      },
    );

    test(
      'the opposite segment lands on the other arm; the torso is its own opposite',
      () {
        expect(oppositeSegment('r_forearm'), 'l_forearm');
        expect(oppositeSegment('l_lower_leg'), 'r_lower_leg');
        expect(oppositeSegment('chest'), 'chest');
        expect(oppositeSegment('hips'), 'hips');
        final anchor = anchorFor(person(), 'r_forearm', (
          x: 310,
          y: 590,
          w: 40,
          h: 60,
        ))!;
        final other = rectFor(person(), 'l_forearm', anchor)!;
        expect(
          other.cx,
          closeTo(680, 15),
          reason: 'on the left forearm (x ~ 675)',
        );
      },
    );

    test(
      'anchors must be visible; the torso falls back to the shoulder span when the hips are out of frame',
      () {
        expect(segmentVisible(person(), 'r_forearm'), isTrue);
        final hidden = Pose([
          for (var i = 0; i < 17; i++)
            i == 10 ? const Pt(0, 0, 0.1) : person()[i],
        ]);
        expect(segmentVisible(hidden, 'r_forearm'), isFalse);
        expect(
          segmentVisible(person(hips: false), 'chest'),
          isTrue,
          reason: 'shoulder span stands in',
        );
        expect(segmentVisible(person(hips: false), 'hips'), isFalse);
        expect(
          anchorFor(person(hips: false), 'hips', (x: 0, y: 0, w: 10, h: 10)),
          isNull,
        );
        expect(segmentVisible(person(), 'not_a_segment'), isFalse);
        final torso = anchorFor(person(), 'chest', (
          x: 450,
          y: 450,
          w: 100,
          h: 100,
        ))!;
        final noHips = rectFor(person(hips: false), 'chest', torso)!;
        expect(noHips.cx, closeTo(500, 40));
      },
    );

    test('evidence thresholds are a suggestion, never an automatic link', () {
      expect(markEvidence(inliers: 40, inlierRatio: 0.7), MarkEvidence.strong);
      expect(markEvidence(inliers: 40, inlierRatio: 0.3), MarkEvidence.weak);
      expect(markEvidence(inliers: 14, inlierRatio: 0.9), MarkEvidence.weak);
      expect(markEvidence(inliers: 5, inlierRatio: 1), MarkEvidence.none);
    });
  });

  group('store and search', () {
    late AppDatabase db;
    late Directory tmp;
    late FileStore files;
    late BodyMarkStore store;
    late FakeMobileApi api;
    late MarkMatcher matcher;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      tmp = Directory.systemTemp.createTempSync('ag_marks_');
      files = FileStore(Directory('${tmp.path}/crops'));
      store = BodyMarkStore(db, files);
      api = FakeMobileApi();
      matcher = MarkMatcher(db, store, () => api);
    });
    tearDown(() async {
      await db.close();
      tmp.deleteSync(recursive: true);
    });

    Future<int> faceless(
      Pose p, {
      int? takenAt,
      bool withFace = false,
      int? personId,
    }) async {
      final media = await seedMedia(
        db,
        asset: 'p${_assetCounter++}',
        width: 1000,
        height: 1500,
        takenAt: takenAt,
      );
      final id = await seedBody(
        db,
        mediaId: media,
        personId: personId,
        linkMethod: personId == null ? null : 'manual',
      );
      await (db.update(db.bodies)..where((b) => b.id.equals(id))).write(
        BodiesCompanion(
          kpts: Value(kpts(p, 1000, 1500)),
          extent: const Value('full'),
        ),
      );
      return id;
    }

    test(
      'a mark is stored with its patch in the private store and deleted with it',
      () async {
        final lina = await seedPerson(db, name: 'Lina');
        final anchor = anchorFor(person(), 'r_forearm', (
          x: 310,
          y: 590,
          w: 40,
          h: 60,
        ))!;
        final id = await store.create(
          personId: lina,
          segment: 'r_forearm',
          anchor: anchor,
          patch: Uint8List.fromList([1, 2, 3]),
          label: 'dragon',
        );
        final mark = (await store.ofPerson(lina)).single;
        expect(
          (mark.id, mark.segment, mark.patchPath, mark.label),
          (id, 'r_forearm', 'marks/$id.png', 'dragon'),
        );
        expect(await store.patchOf(mark), [1, 2, 3]);
        expect(
          (await files.allFiles()).map((e) => e.$1),
          contains('marks/$id.png'),
          reason: 'so a backup carries it',
        );
        await store.delete(id);
        expect(await store.ofPerson(lina), isEmpty);
        expect(File('${tmp.path}/crops/marks/$id.png').existsSync(), isFalse);
      },
    );

    test('person deletion removes the marks rows', () async {
      final lina = await seedPerson(db);
      await store.create(
        personId: lina,
        segment: 'chest',
        anchor: {
          'c': [0.1, 0.0],
          'size': [0.2, 0.2],
        },
        patch: Uint8List(3),
      );
      await (db.delete(db.persons)..where((p) => p.id.equals(lina))).go();
      expect(await db.select(db.bodyMarks).get(), isEmpty);
    });

    test(
      'candidates are faceless bodies showing the segment; the person events come first',
      () async {
        final lina = await seedPerson(db);
        await faceless(
          person(),
          takenAt: 1000000,
          personId: lina,
        ); // her own body defines the event
        final far = await faceless(
          person(),
          takenAt: 1000000 + 5 * 24 * 3600 * 1000,
        );
        final near = await faceless(person(), takenAt: 1000000 + 3600 * 1000);
        await faceless(
          person(hips: false),
          takenAt: 1000000,
        ); // no hips: the chest may still be visible but not a forearm? it has
        await faceless(
          Pose([
            for (var i = 0; i < 17; i++)
              i == 10 ? const Pt(0, 0, 0) : person()[i],
          ]),
          takenAt: 1000000,
        ); // wrist hidden
        final owned = await faceless(
          person(),
          takenAt: 1000000,
          personId: lina,
        );
        final anchor = anchorFor(person(), 'r_forearm', (
          x: 310,
          y: 590,
          w: 40,
          h: 60,
        ))!;
        final markId = await store.create(
          personId: lina,
          segment: 'r_forearm',
          anchor: anchor,
          patch: Uint8List(3),
        );
        final mark = (await store.ofPerson(lina)).single;
        final found = await matcher.candidates(mark);
        final ids = found.map((c) => c.body.id).toList();
        expect(ids, isNot(contains(owned)), reason: 'somebody has it already');
        expect(
          ids.indexOf(near),
          lessThan(ids.indexOf(far)),
          reason: 'her event first',
        );
        expect(found.first.sameEvent, isTrue);
        expect(markId, isPositive);
      },
    );

    test(
      'search sends patches of the segment and its opposite, keeps the better one, and suggests only evidence',
      () async {
        final lina = await seedPerson(db);
        await faceless(person(), takenAt: 1, personId: lina);
        final hit = await faceless(person(), takenAt: 2);
        final miss = await faceless(person(), takenAt: 3);
        final mirror = await faceless(person(), takenAt: 4);
        final anchor = anchorFor(person(), 'r_forearm', (
          x: 310,
          y: 590,
          w: 40,
          h: 60,
        ))!;
        await store.create(
          personId: lina,
          segment: 'r_forearm',
          anchor: anchor,
          patch: Uint8List.fromList([9]),
        );
        final mark = (await store.ofPerson(lina)).single;
        final cut = <(int, String)>[];
        Future<Uint8List?> cutter(MediaRow media, MarkRect rect) async {
          cut.add((media.id, rect.cx.round().toString()));
          return Uint8List.fromList([media.id, cut.length]);
        }

        final candidates = await matcher.candidates(mark);
        final order = candidates.map((c) => c.body.id).toList();
        // two patches per body: straight (even slot) then opposite (odd slot)
        api.marksHandler = (count) => AnalyzeMarksResponse(
          results: [
            for (var i = 0; i < count; i++)
              MarkMatchDto(
                index: i,
                inliers: switch ((order[i ~/ 2], i.isEven)) {
                  (final b, true) when b == hit => 40,
                  (final b, false) when b == mirror => 30,
                  (final b, _) when b == miss => 4,
                  _ => 0,
                },
                matches: 50,
                inlierRatio: switch ((order[i ~/ 2], i.isEven)) {
                  (final b, true) when b == hit => 0.8,
                  (final b, false) when b == mirror => 0.6,
                  _ => 0.1,
                },
                mirrored: i.isOdd,
              ),
          ],
        );
        final hits = (await matcher.search(mark, cutter))!;
        expect(api.markCalls.single.reference, [9]);
        expect(
          api.markCalls.single.candidates,
          hasLength(candidates.length * 2),
        );
        expect(
          hits.map((h) => h.bodyId),
          [hit, mirror],
          reason: 'best first; the miss is not a suggestion',
        );
        expect(hits.first.evidence, MarkEvidence.strong);
        expect(hits.first.viaOppositeSegment, isFalse);
        expect(hits.last.viaOppositeSegment, isTrue);
        expect(hits.last.mirrored, isTrue);
      },
    );

    test(
      'no server, no patch, or an unreadable original gives no result instead of a crash',
      () async {
        final lina = await seedPerson(db);
        final anchor = anchorFor(person(), 'r_forearm', (
          x: 310,
          y: 590,
          w: 40,
          h: 60,
        ))!;
        await store.create(
          personId: lina,
          segment: 'r_forearm',
          anchor: anchor,
          patch: Uint8List.fromList([1]),
        );
        final mark = (await store.ofPerson(lina)).single;
        expect(
          await MarkMatcher(
            db,
            store,
            () => null,
          ).search(mark, (_, _) async => null),
          isNull,
        );
        await faceless(person(), takenAt: 1);
        expect(
          await matcher.search(mark, (_, _) async => null),
          isEmpty,
          reason: 'nothing could be cut: nothing asked',
        );
        expect(api.markCalls, isEmpty);
        await files.delete(mark.patchPath);
        expect(
          await matcher.search(mark, (_, _) async => Uint8List(1)),
          isNull,
          reason: 'the reference patch is gone',
        );
      },
    );
  });

  test(
    'Quick Review rates a tattoo suggestion by the confidence it was queued with',
    () {
      expect(
        likelihoodOf(ReviewQuestionKind.outfit, 0.95, method: 'tattoo'),
        Likelihood.veryLikely,
      );
      expect(
        likelihoodOf(ReviewQuestionKind.outfit, 0.80, method: 'tattoo'),
        Likelihood.likely,
      );
      expect(
        likelihoodOf(ReviewQuestionKind.outfit, 0.5, method: 'tattoo'),
        Likelihood.maybe,
      );
    },
  );
}
