import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/repositories/review_visual_repository.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/seed.dart';

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test(
    'linked occurrences use their own original, box and video timestamp',
    () async {
      final first = await seedMedia(db, asset: 'photo');
      final video = await seedMedia(db, asset: 'video', kind: 'video');
      final face = await seedFace(db, mediaId: first, seed: 1);
      await db
          .into(db.mediaDetections)
          .insert(
            MediaDetectionsCompanion.insert(
              mediaId: video,
              kind: 'f',
              refId: face,
              x: .6,
              y: .2,
              w: .1,
              h: .3,
              timestampMs: const Value(65000),
              frameNumber: const Value(1950),
            ),
          );
      final visuals = await ReviewVisualRepository(
        db,
      ).load([ReviewTarget('f', face)]);
      expect(visuals, hasLength(2));
      expect((visuals[0].assetId, visuals[0].x), ('photo', .1));
      expect(
        (
          visuals[1].assetId,
          visuals[1].mediaKind,
          visuals[1].x,
          visuals[1].timestampMs,
        ),
        ('video', 'video', .6, 65000),
      );
    },
  );

  test(
    'face and body with the same ID stay distinct and requested order is preserved',
    () async {
      final media = await seedMedia(db);
      final face = await seedFace(db, mediaId: media);
      final body = await seedBody(db, mediaId: media);
      final visuals = await ReviewVisualRepository(
        db,
      ).load([ReviewTarget('b', body), ReviewTarget('f', face)]);
      expect(visuals.map((v) => v.target.kind), ['b', 'f']);
      expect((visuals[0].x, visuals[0].w), (.2, .4));
      expect((visuals[1].x, visuals[1].w), (.1, .2));
    },
  );

  test(
    'older detections without occurrence rows still expose the saved source box',
    () async {
      final media = await seedMedia(db);
      final id = await seedFace(db, mediaId: media, x: .4, y: .3);
      await db.delete(db.mediaDetections).go();
      final visuals = await ReviewVisualRepository(
        db,
      ).load([ReviewTarget('f', id)]);
      expect(visuals.single.assetId, 'asset-1');
      expect((visuals.single.x, visuals.single.y), (.4, .3));
    },
  );
}
