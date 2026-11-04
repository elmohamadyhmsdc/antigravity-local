import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/api/dtos/grouping.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/file_store.dart';
import 'package:antigravity_mobile/data/repositories/people_repository.dart';
import 'package:antigravity_mobile/data/repositories/review_repository.dart';
import 'package:antigravity_mobile/domain/grouping/plan_applier.dart';
import 'package:antigravity_mobile/domain/pose/exposed_matching.dart';
import 'package:antigravity_mobile/domain/pose/group_pose_matcher.dart';
import 'package:antigravity_mobile/domain/pose/pose_descriptor.dart';
import 'package:antigravity_mobile/domain/pose/pose_geometry.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';
import 'pose_test.dart' as skeleton;

void main() {
  test('one changed arm or leg cannot hide behind matching face and torso', () {
    final original = buildPoseFeature(skeleton.pose(skeleton.standing()))!;
    for (final change in [
      {
        Kp.lWrist: [680.0, 250.0],
      },
      {
        Kp.lAnkle: [900.0, 950.0],
      },
    ]) {
      final different = buildPoseFeature(
        skeleton.pose(skeleton.moved(skeleton.standing(), change)),
      )!;
      expect(
        comparePoses(original, different)!.similarity,
        lessThan(minimumPoseSimilarity),
      );
    }
    final noise = {
      for (final p in skeleton.standing().entries)
        p.key: [p.value[0] + (p.key.isEven ? 3 : -3), p.value[1] + 2],
    };
    expect(
      comparePoses(
        original,
        buildPoseFeature(skeleton.pose(noise))!,
      )!.similarity,
      greaterThan(.95),
    );
  });

  test('bad descriptors and non-finite joints are not comparable', () {
    final good = buildPoseFeature(skeleton.pose(skeleton.standing()))!;
    expect(
      comparePoses(good, PoseFeature.fromBlob(Uint8List(3), 17, 'torso')),
      isNull,
    );
    expect(
      comparePoses(
        good,
        PoseFeature(Float32List(34)..[0] = double.nan, good.mask, 'torso'),
      ),
      isNull,
    );
    final bad = skeleton.moved(skeleton.standing(), {
      Kp.lWrist: [double.infinity, 1],
    });
    expect(buildPoseFeature(skeleton.pose(bad)), isNull);
  });

  test('five matching people cannot conceal a sixth with a different pose', () {
    Pose member(int index, {bool raised = false}) {
      final base = raised
          ? skeleton.moved(skeleton.standing(), {
              Kp.lWrist: [680, 100],
            })
          : skeleton.standing();
      return skeleton.pose({
        for (final p in base.entries)
          p.key: [p.value[0] + index * 1200, p.value[1]],
      });
    }

    final original = buildGroupPose([for (var i = 0; i < 6; i++) member(i)])!;
    final changed = buildGroupPose([
      for (var i = 0; i < 6; i++) member(i, raised: i == 3),
    ])!;
    expect(compareGroupPoses(original, changed), lessThan(.65));
  });

  group('area and review regression guards', () {
    late AppDatabase db;
    late Directory directory;
    late ReviewRepository review;
    var nextMedia = 0;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      directory = Directory.systemTemp.createTempSync('discovery_precision_');
      review = ReviewRepository(db, PeopleRepository(db, FileStore(directory)));
    });
    tearDown(() async {
      await db.close();
      directory.deleteSync(recursive: true);
    });

    Future<int> area(double degrees, {int? person, double scale = 1}) async {
      final vector = Float32List(384)
        ..[0] = math.cos(degrees * math.pi / 180) * scale
        ..[1] = math.sin(degrees * math.pi / 180) * scale;
      final media = await seedMedia(db, asset: 'area-${nextMedia++}');
      final id = await seedBody(db, mediaId: media, personId: person);
      await (db.update(db.bodies)..where((b) => b.id.equals(id))).write(
        BodiesCompanion(chestEmbedding: Value(packFloat32(vector))),
      );
      return id;
    }

    test(
      'area search normalises vectors, rejects corrupt data and honours person scope',
      () async {
        final person = await seedPerson(db);
        final query = await area(0, scale: 3);
        final close = await area(5, scale: 8, person: person);
        await area(10);
        await area(90, person: person);
        final malformed = await area(1, person: person);
        await (db.update(db.bodies)..where((b) => b.id.equals(malformed)))
            .write(BodiesCompanion(chestEmbedding: Value(Uint8List(3))));
        final matches = await ExposedMatcher(
          db,
        ).findSimilar(query, ExposedKind.chest, personId: person);
        expect(matches.map((r) => r.bodyId), [close]);
        expect(
          matches.single.similarity,
          closeTo(math.cos(5 * math.pi / 180), 1e-6),
        );
      },
    );

    test(
      'density bridges do not merge unlike areas; names and exclusions survive rebuilding',
      () async {
        final a = await area(0);
        final b = await area(20);
        final c = await area(40);
        final service = ExposedClusters(db);
        await service.setEnabled(true);
        await service.rebuild(ExposedKind.chest);
        final first = (await service.clusters()).single;
        expect(first.bodyIds, [a, b]);
        expect(first.bodyIds, isNot(contains(c)));
        await db.putSetting('cluster.name.${first.cluster.id}', 'Saved area');
        await service.rebuild(ExposedKind.chest);
        expect((await service.clusters()).single.cluster.id, first.cluster.id);
        expect(
          await db.setting('cluster.name.${first.cluster.id}'),
          'Saved area',
        );
        await service.rejectMember(b, ExposedKind.chest);
        await service.rebuild(ExposedKind.chest);
        expect(
          (await service.clusters()).expand((g) => g.bodyIds),
          isNot(contains(b)),
        );
      },
    );

    test('false body detections cannot match or form area clusters', () async {
      final query = await area(0);
      final hidden = await area(0);
      await (db.update(db.bodies)..where((b) => b.id.equals(hidden))).write(
        const BodiesCompanion(hidden: Value(true)),
      );
      expect(
        await ExposedMatcher(db).findSimilar(query, ExposedKind.chest),
        isEmpty,
      );
      expect(await ExposedMatcher(db).kindsOf(hidden), isEmpty);
      final clusters = ExposedClusters(db);
      await clusters.setEnabled(true);
      await clusters.rebuild(ExposedKind.chest);
      expect(await clusters.clusters(), isEmpty);
    });

    test(
      'excluding every member hides an existing area group immediately',
      () async {
        final a = await area(0);
        final b = await area(0);
        final clusters = ExposedClusters(db);
        await clusters.setEnabled(true);
        await clusters.rebuild(ExposedKind.chest);
        expect((await clusters.clusters()).single.bodyIds, [a, b]);
        await (db.update(db.bodies)..where((body) => body.id.isIn([a, b])))
            .write(const BodiesCompanion(hidden: Value(true)));
        expect(await clusters.clusters(), isEmpty);
      },
    );

    test(
      'clothing-only plans never auto-link people or enter review, including stale rows',
      () async {
        final person = await seedPerson(db);
        await seedFace(db, personId: person);
        final links = <BodyLinkPlan>[];
        for (final method in ['appearance', 'event_outfit', 'weak_face']) {
          final body = await seedBody(db);
          links.add(
            BodyLinkPlan(
              bodyId: body,
              personId: person,
              method: method,
              confidence: .99,
              decision: 'auto',
            ),
          );
        }
        expect(
          await PlanApplier(db).applyBodyPlan(
            GroupingPlanResponse(mode: 'apply', bodyLinks: links),
          ),
          1,
        );
        final bodies = await db.select(db.bodies).get();
        expect(bodies.map((b) => b.personId), [null, null, person]);

        final suggestions = <BodyLinkPlan>[];
        for (final method in ['appearance', 'event_outfit', 'weak_face']) {
          final body = await seedBody(db);
          suggestions.add(
            BodyLinkPlan(
              bodyId: body,
              personId: person,
              method: method,
              confidence: .99,
              decision: 'suggest',
            ),
          );
          await db
              .into(db.reviewBodyLinks)
              .insert(
                ReviewBodyLinksCompanion.insert(
                  bodyId: Value(body),
                  personId: person,
                  method: method,
                  confidence: .99,
                ),
              );
        }
        expect((await review.bodyLinks()).map((r) => r.method), ['weak_face']);
        expect((await review.counts()).bodyLinks, 1);
        await review.replaceAll(
          GroupingPlanResponse(mode: 'review', bodyLinks: suggestions),
        );
        expect(
          (await db.select(db.reviewBodyLinks).get()).map((r) => r.method),
          ['weak_face'],
        );
      },
    );
  });
}
