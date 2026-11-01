import 'dart:convert';

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/pose/body_categories.dart';
import 'package:antigravity_mobile/domain/pose/group_pose_matcher.dart';
import 'package:antigravity_mobile/domain/pose/pose_geometry.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

Pose person(double x, {double y = 0, double scale = 1, bool raised = false}) {
  final pts = [
    [50, 10],
    [54, 8],
    [46, 8],
    [58, 10],
    [42, 10],
    [65, 25],
    [35, 25],
    [72, raised ? 10 : 43],
    [28, 43],
    [74, raised ? 0 : 60],
    [26, 60],
    [59, 55],
    [41, 55],
    [61, 75],
    [39, 75],
    [65, 95],
    [35, 95],
  ];
  return Pose([
    for (final p in pts) Pt(x + p[0] * scale, y + p[1] * scale, .9),
  ], extent: 'full');
}

void main() {
  test(
    'whole group is invariant to detection order, translation and uniform scale',
    () {
      final a = buildGroupPose([person(0), person(70, raised: true)])!;
      final b = buildGroupPose([
        person(340, y: 100, scale: 2, raised: true),
        person(200, y: 100, scale: 2),
      ])!;
      expect(compareGroupPoses(a, b), closeTo(1, 1e-6));
      final decoded = GroupPoseFeature.decode(a.encode());
      expect(compareGroupPoses(a, decoded), closeTo(1, 1e-6));
    },
  );
  test('relative distance and individual poses distinguish actions', () {
    final touching = buildGroupPose([person(0), person(20, raised: true)])!;
    final apart = buildGroupPose([person(0), person(180, raised: true)])!;
    final different = buildGroupPose([person(0), person(20)])!;
    expect(compareGroupPoses(touching, apart), lessThan(.1));
    expect(compareGroupPoses(touching, different), lessThan(.99));
    expect(
      compareGroupPoses(
        touching,
        buildGroupPose([person(0), person(20), person(40)])!,
      ),
      isNull,
    );
  });
  test('missing torso is not silently omitted from the group', () {
    final p = person(0);
    final hidden = Pose([
      for (var i = 0; i < 17; i++) Pt(p[i].x, p[i].y, i == 11 ? 0 : .9),
    ]);
    expect(buildGroupPose([person(10), hidden]), isNull);
    expect(buildGroupPose([person(0)]), isNull);
  });

  test(
    'saved group descriptors survive their source and never enter single-person rescoring',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final service = GroupPoseMatcher(db);
      Future<int> photo(
        String asset, {
        double distance = 70,
        String kind = 'photo',
      }) async {
        final media = await seedMedia(
          db,
          asset: asset,
          width: 500,
          height: 300,
          kind: kind,
        );
        for (final p in [person(0), person(distance, raised: true)]) {
          final body = await seedBody(db, mediaId: media);
          await (db.update(db.bodies)..where((b) => b.id.equals(body))).write(
            BodiesCompanion(
              kpts: Value(
                jsonEncode([
                  for (final point in p.points)
                    [point.x / 500, point.y / 300, point.score],
                ]),
              ),
              extent: const Value('full'),
            ),
          );
        }
        return media;
      }

      final source = await photo('source'),
          alike = await photo('alike'),
          apart = await photo('apart', distance: 200);
      await photo('video', kind: 'video');
      final example = (await service.photo(source))!;
      final id = await service.save('Partner stretch', example);
      expect(await BodyCategories(db).rescoreAllPoses(), 0);
      var results = await service.similar(
        example.feature!,
        excludingMedia: source,
        categoryId: id,
      );
      expect(results.map((r) => r.photo.mediaId), contains(alike));
      expect(results.map((r) => r.photo.mediaId), isNot(contains(apart)));
      await service.reject(
        id,
        results.firstWhere((r) => r.photo.mediaId == alike).photo,
      );
      expect(
        await service.similar(
          example.feature!,
          excludingMedia: source,
          categoryId: id,
        ),
        isEmpty,
      );
      await (db.delete(db.media)..where((m) => m.id.equals(source))).go();
      final stored = (await service.categories()).single;
      expect(stored.exemplarBodyId, isNull);
      expect(
        compareGroupPoses(
          example.feature!,
          GroupPoseFeature.decode(stored.exemplarFeature),
        ),
        closeTo(1, 1e-6),
      );
    },
  );
}
