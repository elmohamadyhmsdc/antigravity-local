// The grouping wire format against the golden fixtures the PC's tests also use, and what the phone
// reads out of its database to build a request (person models, pending faces, bodies).

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:antigravity_mobile/data/api/dtos/embedding.dart';
import 'package:antigravity_mobile/data/api/dtos/grouping.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/grouping/grouping_config.dart';
import 'package:antigravity_mobile/domain/grouping/grouping_inputs.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fixtures.dart';
import '../support/seed.dart';

const _golden = ['apply_basic', 'review_all', 'review_distinct_pair'];

void main() {
  group('wire format (golden fixtures)', () {
    for (final name in _golden) {
      test('GroupingPlanRequest.$name survives parse -> toJson unchanged', () {
        final json = fixture('GroupingPlanRequest.$name');
        final request = GroupingPlanRequest.fromJson(json);
        expect(request.toJson(), json);
        expect(request.models, isNotEmpty);
        expect(request.pending, isNotEmpty);
        expect(request.pending.first.embedding.length, embeddingDim);
      });

      test(
        'GroupingPlanResponse.$name parses and survives parse -> toJson unchanged',
        () {
          final json = fixture('GroupingPlanResponse.$name');
          final response = GroupingPlanResponse.fromJson(json);
          expect(response.toJson(), json);
          expect(response.mode, json['mode']);
        },
      );
    }

    test(
      'the apply response carries the auto assignments, the auto-create group and both body links',
      () {
        final r = GroupingPlanResponse.fromJson(
          fixture('GroupingPlanResponse.apply_basic'),
        );
        expect(r.assignments.map((a) => (a.faceId, a.personId)), [
          (101, 1),
          (102, 2),
        ]);
        expect(r.assignments.every((a) => a.isAuto), isTrue);
        expect(r.groups.single.faceIds, [103, 104, 105]);
        expect(r.groups.single.autoCreate, isTrue);
        expect(
          r.bodyLinks.map((l) => (l.bodyId, l.isAuto)),
          [(2, true), (3, false)],
          reason:
              'apply mode also lists suggestions; only the auto one is applied',
        );
      },
    );

    test(
      'the review response has the duplicate pair and the faces that stay unsorted',
      () {
        final r = GroupingPlanResponse.fromJson(
          fixture('GroupingPlanResponse.review_all'),
        );
        expect(
          (r.duplicates.single.personA, r.duplicates.single.personB),
          (1, 4),
        );
        expect(r.unsortedFaceIds, [106, 107]);
        expect(
          GroupingPlanResponse.fromJson(
            fixture('GroupingPlanResponse.review_distinct_pair'),
          ).duplicates,
          isEmpty,
        );
      },
    );

    test('a request is gzipped JSON that decodes to the same document', () {
      final request = GroupingPlanRequest.fromJson(
        fixture('GroupingPlanRequest.review_all'),
      );
      final bytes = request.encodeGzip();
      expect(
        bytes.length,
        lessThan(utf8.encode(jsonEncode(request.toJson())).length),
        reason: 'it is compressed',
      );
      expect(jsonDecode(utf8.decode(gzip.decode(bytes))), request.toJson());
    });

    test('broken documents say which field is wrong', () {
      final bad = copyOf(fixture('GroupingPlanResponse.apply_basic'));
      (bad['assignments'] as List).first['score'] = 'high';
      expect(
        () => GroupingPlanResponse.fromJson(bad),
        throwsA(isA<FormatException>()),
      );
      final worse = copyOf(fixture('GroupingPlanRequest.apply_basic'));
      (worse['models'] as List).first['proto'] = 'AAAA';
      expect(
        () => GroupingPlanRequest.fromJson(worse),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('person models (person_linking.build_person_models)', () {
    test(
      'the prototype is the unit mean weighted by clip(quality)^2, members are best-first and capped',
      () {
        final faces = [
          FaceVector(unitVec(1), 0.9),
          FaceVector(unitVec(2), 0.3),
          FaceVector(near(unitVec(1), 3, 0.5), 0.7),
          FaceVector(unitVec(4), 0.01), // below 0.05: weighted as 0.05
        ];
        final m = buildPersonModel(7, faces, cap: 3);

        final sum = Float64List(embeddingDim);
        for (final f in faces) {
          final w = pow(f.quality.clamp(0.05, 1.0), 2).toDouble();
          for (var d = 0; d < embeddingDim; d++) {
            sum[d] += f.embedding[d] * w;
          }
        }
        final norm = sqrt(sum.fold<double>(0, (a, b) => a + b * b));
        final expected = Float32List.fromList([for (final x in sum) x / norm]);
        expect(dot(m.proto, expected), closeTo(1.0, 1e-5));
        expect(
          dot(m.proto, m.proto),
          closeTo(1.0, 1e-5),
          reason: 'unit length',
        );

        expect(m.pid, 7);
        expect(m.count, 4, reason: 'count is every face, not just the members');
        expect(m.members.length, 3, reason: 'capped');
        expect(
          dot(m.members[0], faces[0].embedding),
          closeTo(1.0, 1e-5),
          reason: 'best quality first',
        );
        expect(dot(m.members[1], faces[2].embedding), closeTo(1.0, 1e-5));
        expect(dot(m.members[2], faces[1].embedding), closeTo(1.0, 1e-5));
      },
    );

    test(
      'the default cap keeps the PC readable: at least the 50 members its duplicate scoring uses',
      () {
        expect(groupingMemberCap, greaterThanOrEqualTo(50));
        final faces = [
          for (var i = 0; i < 120; i++)
            FaceVector(unitVec(i + 10), 0.5 + (i % 40) / 100),
        ];
        final m = buildPersonModel(1, faces);
        expect(m.members.length, groupingMemberCap);
        expect(m.count, 120);
      },
    );
  });

  group('reading the library into a request', () {
    late AppDatabase db;
    late GroupingInputs inputs;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      inputs = GroupingInputs(db);
    });
    tearDown(() => db.close());

    test(
      'models: one per person with faces, built from their stored embeddings',
      () async {
        final sara = await seedPerson(db, name: 'Sara');
        final omar = await seedPerson(db, name: 'Omar');
        await seedPerson(db, name: 'Nobody yet'); // no faces: no model
        for (var i = 0; i < 4; i++) {
          await seedFace(
            db,
            personId: sara,
            seed: 10 + i,
            quality: 0.6 + i / 20,
          );
        }
        await seedFace(db, personId: omar, seed: 50);
        await seedFace(db, seed: 60); // unassigned: not part of anyone's model

        final models = await inputs.models();
        expect(models.map((m) => (m.pid, m.count)), [(sara, 4), (omar, 1)]);
        expect(models.first.members.length, 4);
        expect(dot(models.last.proto, unitVec(50)), closeTo(1.0, 1e-5));
      },
    );

    test(
      'pending: unassigned faces with their same-photo key and the people they were told they are not',
      () async {
        final sara = await seedPerson(db);
        final photo = await seedMedia(db, asset: 'p1');
        final video = await seedMedia(db, asset: 'v1', kind: 'video');
        final a = await seedFace(db, mediaId: photo, seed: 1);
        final b = await seedFace(db, mediaId: video, frameNumber: 90, seed: 2);
        final c = await seedFace(db, seed: 3); // no photo: no constraint
        await seedFace(db, personId: sara, seed: 4); // assigned: not pending
        await db
            .into(db.faceRejections)
            .insert(FaceRejectionsCompanion.insert(faceId: a, personId: sara));

        final pending = await inputs.pending();
        expect(pending.map((f) => f.id), [a, b, c]);
        expect(pending[0].frameKey, '$photo:');
        expect(pending[1].frameKey, '$video:90');
        expect(pending[2].frameKey, isNull);
        expect(pending[0].rejectedPersonIds, [sara]);
        expect(pending[1].rejectedPersonIds, isEmpty);
        expect(dot(pending[0].embedding, unitVec(1)), closeTo(1.0, 1e-5));
      },
    );

    test('dismissed faces and distinct pairs', () async {
      final a = await seedPerson(db), b = await seedPerson(db);
      final hidden = await seedFace(db, seed: 1, dismissed: true);
      await seedFace(db, seed: 2);
      await seedFace(
        db,
        personId: a,
        seed: 3,
        dismissed: true,
      ); // assigned: irrelevant
      await db
          .into(db.personDistinct)
          .insert(PersonDistinctCompanion.insert(personA: a, personB: b));
      expect(await inputs.dismissedFaceIds(), [hidden]);
      expect(await inputs.distinctPairs(), [(a, b)]);
    });

    test(
      'bodies: only photos with a faceless body to explain are sent, derived links optionally dropped',
      () async {
        final sara = await seedPerson(db);
        final withLoose = await seedMedia(db, asset: 'm1');
        final allKnown = await seedMedia(db, asset: 'm2');
        final noEvidence = await seedMedia(db, asset: 'm3');
        final face = await seedFace(
          db,
          mediaId: withLoose,
          personId: sara,
          seed: 1,
        );

        final anchored = await seedBody(
          db,
          mediaId: withLoose,
          faceId: face,
          appearance: outfit(1),
          frameNumber: 0,
        );
        final loose = await seedBody(
          db,
          mediaId: withLoose,
          appearance: outfit(2),
          frameNumber: 60,
        );
        final derived = await seedBody(
          db,
          mediaId: withLoose,
          personId: sara,
          linkMethod: 'appearance',
          linkConfidence: 0.9,
          appearance: outfit(3),
          frameNumber: 90,
        );
        final manual = await seedBody(
          db,
          mediaId: withLoose,
          personId: sara,
          linkMethod: 'manual',
          appearance: outfit(4),
        );
        await seedBody(
          db,
          mediaId: allKnown,
          personId: sara,
          linkMethod: 'manual',
          appearance: outfit(5),
        );
        await seedBody(
          db,
          mediaId: noEvidence,
        ); // faceless but nothing to compare
        final weakOnly = await seedBody(
          db,
          mediaId: noEvidence,
          weakFace: unitVec(9),
        );

        final reviewBodies = {
          for (final b in await inputs.bodies(dropDerived: false)) b.id: b,
        };
        expect(
          reviewBodies.keys.toSet(),
          {anchored, loose, derived, manual, weakOnly},
          reason: 'm2 (everyone known) and the evidence-less body are left out',
        );
        expect(reviewBodies[anchored]!.anchorPersonId, sara);
        expect(reviewBodies[loose]!.anchorPersonId, isNull);
        expect(
          reviewBodies[derived]!.anchorPersonId,
          sara,
          reason: 'review sees every current link',
        );
        expect(reviewBodies[manual]!.anchorPersonId, sara);
        expect(reviewBodies[weakOnly]!.weakFaceEmbedding, isNotNull);
        expect(reviewBodies[loose]!.appearance!.length, 80);

        final apply = {
          for (final b in await inputs.bodies(dropDerived: true)) b.id: b,
        };
        expect(
          apply[derived]!.anchorPersonId,
          isNull,
          reason: 'being re-derived, so no longer an anchor',
        );
        expect(
          apply[manual]!.anchorPersonId,
          sara,
          reason: 'links made by hand always stay',
        );
        expect(apply[anchored]!.anchorPersonId, sara);
      },
    );

    test('request(): each round only reads what its stages need', () async {
      final sara = await seedPerson(db);
      await seedFace(db, personId: sara, seed: 1);
      await seedFace(db, seed: 2);

      final cluster = await inputs.request(
        mode: 'apply',
        stages: ['cluster'],
        strictness: 'loose',
      );
      expect(cluster.models, isEmpty, reason: 'clustering needs no people');
      expect(cluster.pending.length, 1);
      expect(cluster.strictness, 'loose');

      final round1 = await inputs.request(
        mode: 'apply',
        stages: round1Stages,
        strictness: 'balanced',
      );
      expect((round1.models.length, round1.pending.length), (1, 1));
      expect(round1.dismissedFaceIds, isEmpty);

      final bodies = await inputs.request(
        mode: 'apply',
        stages: round2Stages,
        strictness: 'balanced',
        dropDerived: true,
      );
      expect(bodies.pending, isEmpty);
      expect(
        bodies.models.length,
        1,
        reason: 'body linking compares against people',
      );

      final review = await inputs.request(
        mode: 'review',
        stages: round3Stages,
        strictness: 'strict',
      );
      expect(review.mode, 'review');
      expect(review.stages, ['match', 'cluster', 'duplicates', 'bodies']);
      expect(review.maxSuggestionsPerPerson, groupingMaxSuggestionsPerPerson);
    });

    test(
      'the request for a real library is a valid document the PC accepts (shape check)',
      () async {
        final sara = await seedPerson(db);
        for (var i = 0; i < 3; i++) {
          await seedFace(db, personId: sara, seed: i + 1);
        }
        await seedFace(db, seed: 9);
        final request = await inputs.request(
          mode: 'review',
          stages: round3Stages,
          strictness: 'balanced',
        );
        final json =
            jsonDecode(jsonEncode(request.toJson())) as Map<String, dynamic>;
        expect(json.keys.toSet(), {
          'mode',
          'stages',
          'strictness',
          'models',
          'pending',
          'dismissed_face_ids',
          'distinct_pairs',
          'bodies',
          'max_suggestions_per_person',
        });
        expect(((json['models'] as List).first as Map).keys.toSet(), {
          'pid',
          'proto',
          'members',
          'count',
        });
        expect(((json['pending'] as List).first as Map).keys.toSet(), {
          'id',
          'embedding',
          'quality',
          'frame_key',
          'rejected_person_ids',
        });
        expect(
          ((json['models'] as List).first as Map)['proto'],
          hasLength(2732),
        );
        // and it round-trips through the same DTO the golden fixtures use
        expect(GroupingPlanRequest.fromJson(json).toJson(), json);
      },
    );
  });
}
