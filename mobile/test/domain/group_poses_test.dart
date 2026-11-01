// Roadmap section 4 (Tier A): group photo, side-by-side lineup, all facing the camera - photos only.

import 'dart:convert';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/pose/group_poses.dart';
import 'package:antigravity_mobile/domain/pose/pose_geometry.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

/// A standing person whose shoulders are at [shoulderY] and whose torso is 400 px, centred at [cx].
Pose person(double cx, double shoulderY) => Pose([
  for (var i = 0; i < 17; i++)
    switch (i) {
      5 => Pt(cx + 150, shoulderY, 0.9),
      6 => Pt(cx - 150, shoulderY, 0.9),
      11 => Pt(cx + 60, shoulderY + 400, 0.9),
      12 => Pt(cx - 60, shoulderY + 400, 0.9),
      _ => const Pt(0, 0, 0),
    },
]);

GroupMember member(
  double cx,
  double shoulderY, {
  double? yaw,
  double width = 0.2,
}) => GroupMember(
  box: (x: cx / 1000 - width / 2, y: shoulderY / 1500, w: width, h: 0.5),
  pose: person(cx, shoulderY),
  faceYaw: yaw,
);

void main() {
  group('rules', () {
    test('a group needs three bodies', () {
      expect(
        multiPersonTags([member(200, 400), member(500, 400)]),
        isNot(contains(GroupTag.group)),
      );
      expect(
        multiPersonTags([member(200, 400), member(500, 400), member(800, 400)]),
        contains(GroupTag.group),
      );
    });

    test(
      'a lineup: shoulders level (within 0.3 of the median torso) and boxes apart',
      () {
        expect(
          multiPersonTags([member(200, 400), member(500, 450)]),
          contains(GroupTag.lineup),
        );
        expect(
          multiPersonTags([member(200, 400), member(500, 700)]),
          isNot(contains(GroupTag.lineup)),
          reason: '300 px apart > 0.3 x 400',
        );
        expect(
          multiPersonTags([member(500, 400), member(520, 400)]),
          isNot(contains(GroupTag.lineup)),
          reason: 'boxes overlap',
        );
        final noPose = GroupMember(box: (x: 0.7, y: 0.2, w: 0.2, h: 0.5));
        expect(
          multiPersonTags([member(200, 400), noPose]),
          isNot(contains(GroupTag.lineup)),
          reason: 'no shoulders: no answer',
        );
      },
    );

    test('all facing needs a face looking at the camera on EVERY body', () {
      expect(
        multiPersonTags([member(200, 400, yaw: 5), member(600, 400, yaw: -12)]),
        contains(GroupTag.allFacing),
      );
      expect(
        multiPersonTags([member(200, 400, yaw: 5), member(600, 400, yaw: 40)]),
        isNot(contains(GroupTag.allFacing)),
      );
      expect(
        multiPersonTags([member(200, 400, yaw: 5), member(600, 400)]),
        isNot(contains(GroupTag.allFacing)),
        reason: 'a missing face hides it',
      );
    });

    test('one body has no multi-person tag', () {
      expect(multiPersonTags([member(200, 400, yaw: 0)]), isEmpty);
    });
  });

  group('photos', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    String kpts(Pose p) => jsonEncode([
      for (final k in p.points) [k.x / 1000, k.y / 1500, k.score],
    ]);

    Future<void> body(int media, Pose p, {int? face, int? frame}) async {
      final id = await seedBody(
        db,
        mediaId: media,
        faceId: face,
        frameNumber: frame,
      );
      await (db.update(db.bodies)..where((b) => b.id.equals(id))).write(
        BodiesCompanion(
          kpts: Value(kpts(p)),
          bboxX: Value((p[5].x - 200) / 1000 - 0.05),
          bboxY: Value(p[5].y / 1500),
          bboxW: const Value(0.1),
          bboxH: const Value(0.5),
        ),
      );
    }

    test(
      'photos with several bodies get their tags; videos and single bodies do not',
      () async {
        final trio = await seedMedia(
          db,
          asset: 'trio',
          width: 1000,
          height: 1500,
        );
        await body(trio, person(200, 400));
        await body(trio, person(500, 400));
        await body(trio, person(800, 400));
        final pair = await seedMedia(
          db,
          asset: 'pair',
          width: 1000,
          height: 1500,
        );
        await body(pair, person(250, 400));
        await body(pair, person(700, 900));
        final single = await seedMedia(
          db,
          asset: 'single',
          width: 1000,
          height: 1500,
        );
        await body(single, person(500, 400));
        final video = await seedMedia(
          db,
          asset: 'v',
          kind: 'video',
          width: 1000,
          height: 1500,
        );
        await body(video, person(200, 400), frame: 0);
        await body(video, person(500, 400), frame: 0);

        final photos = GroupPhotos(db);
        final tags = await photos.tagsByPhoto();
        expect(tags.keys, [trio]);
        expect(tags[trio], containsAll([GroupTag.group, GroupTag.lineup]));
        expect(await photos.photosWith(GroupTag.group), [trio]);
        expect(await photos.photosWith(GroupTag.allFacing), isEmpty);
        expect((await photos.counts())[GroupTag.group], 1);
      },
    );

    test('face yaw comes from the linked face', () async {
      final media = await seedMedia(
        db,
        asset: 'faces',
        width: 1000,
        height: 1500,
      );
      final f1 = await seedFace(db, mediaId: media);
      final f2 = await seedFace(db, mediaId: media);
      await db.customStatement('UPDATE faces SET yaw = 4 WHERE id = $f1');
      await db.customStatement('UPDATE faces SET yaw = -9 WHERE id = $f2');
      await body(media, person(250, 400), face: f1);
      await body(media, person(700, 400), face: f2);
      expect(await GroupPhotos(db).photosWith(GroupTag.allFacing), [media]);
    });
  });
}
