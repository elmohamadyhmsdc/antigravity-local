import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/repositories/identity_groups.dart';
import 'package:antigravity_mobile/domain/organization/person_media_organizer.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fake_media_organizer.dart';
import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late FakeMediaOrganizer bridge;
  late PersonMediaOrganizer organizer;
  late int luffy;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    bridge = FakeMediaOrganizer();
    organizer = PersonMediaOrganizer(db: db, bridge: bridge);
    luffy = await seedPerson(db, name: 'Luffy');
    final group = await IdentityGroupsRepository(db).create('One Piece');
    await IdentityGroupsRepository(db).assign([luffy], group);
  });
  tearDown(() => db.close());
  Future<int> media(String asset, {String kind = 'photo', int? owner}) async {
    final id = await seedMedia(db, asset: asset, kind: kind);
    await seedFace(db, mediaId: id, personId: owner ?? luffy);
    bridge.seed(asset, name: kind == 'video' ? 'clip.mp4' : 'photo.HEIC');
    return id;
  }

  test(
    'preview uses nested groups, separate image/video numbers and never writes files',
    () async {
      await media('1');
      await media('2', kind: 'video');
      await media('3');
      final plan = await organizer.plan({luffy});
      expect(plan.map((i) => i.request!.targetPath).toSet(), {
        'DCIM/Your Gallery/One Piece/Luffy/',
      });
      expect(plan.map((i) => i.request!.targetName), [
        'Luffy_image_0001.heic',
        'Luffy_video_0001.mp4',
        'Luffy_image_0002.heic',
      ]);
      expect(bridge.moves, isEmpty);
      expect(await db.select(db.personMediaMoves).get(), isEmpty);
    },
  );
  test('each shared file gets exactly one owner and one native move', () async {
    final zoro = await seedPerson(db, name: 'Zoro');
    final id = await media('1');
    await seedFace(db, mediaId: id, personId: zoro);
    expect((await organizer.plan({luffy, zoro})).single.status, 'choose_owner');
    final chosen = await organizer.plan({luffy, zoro}, choices: {id: zoro});
    expect(chosen.single.ownerId, zoro);
    await organizer.apply(chosen);
    expect(bridge.moves.single, hasLength(1));
    expect(bridge.originals['1']!.path, 'DCIM/Your Gallery/Zoro/');
    expect(await db.select(db.media).get(), hasLength(1));
    expect(await db.select(db.faces).get(), hasLength(2));
  });
  test(
    'journal commits before the native move and updates timestamps without dropping detections',
    () async {
      final id = await media('1');
      bridge.beforeWrite = () async {
        expect(
          (await db.select(db.personMediaMoves).get()).single.state,
          'pending',
        );
      };
      await organizer.apply(await organizer.plan({luffy}));
      final row = (await db.select(db.media).get()).single;
      expect(
        (row.id, row.assetId, row.modifiedAt, row.scanStatus),
        (id, '1', 2000, 'done'),
      );
      expect(await db.select(db.mediaDetections).get(), hasLength(1));
      final repeated = await organizer.plan({luffy});
      expect(repeated.single.status, 'already');
      expect(repeated.single.request!.targetName, 'Luffy_image_0001.heic');
    },
  );
  test(
    'denied permission keeps originals and never marks a file moved',
    () async {
      await media('1');
      bridge.cancel = true;
      final result = await organizer.apply(await organizer.plan({luffy}));
      expect(result.single.status, 'cancelled');
      expect(bridge.originals['1']!.path, 'DCIM/Camera/');
      expect(
        (await db.select(db.personMediaMoves).get()).single.state,
        'cancelled',
      );
      expect((await db.select(db.media).get()).single.modifiedAt, 1000);
    },
  );
  test(
    'an interrupted move is reconciled by stable asset ID and does not move twice',
    () async {
      await media('1');
      bridge.crashAfter = 1;
      await expectLater(
        organizer.apply(await organizer.plan({luffy})),
        throwsStateError,
      );
      expect(
        (await db.select(db.personMediaMoves).get()).single.state,
        'pending',
      );
      expect((await organizer.plan({luffy})).single.status, 'pending');
      bridge.crashAfter = null;
      final pending = await organizer.pending();
      expect(pending.single.status, 'already');
      await organizer.apply(pending);
      expect(
        (await db.select(db.personMediaMoves).get()).single.state,
        'moved',
      );
      expect((await db.select(db.media).get()).single.modifiedAt, 2000);
    },
  );
  test(
    'destination conflicts and edits after detection are excluded',
    () async {
      await media('1');
      bridge.seed(
        'existing',
        name: 'Luffy_image_0001.heic',
        path: 'DCIM/Your Gallery/One Piece/Luffy/',
      );
      final conflict = await organizer.plan({luffy});
      expect(conflict.single.status, 'conflict');
      expect(await organizer.apply(conflict), isEmpty);
      bridge.originals.remove('existing');
      bridge.seed('1', modifiedAt: 3000);
      expect((await organizer.plan({luffy})).single.status, 'stale_scan');
    },
  );
  test(
    'sanitized duplicate names get distinct folders; non-Latin names remain readable',
    () async {
      final other = await seedPerson(db, name: 'Luffy');
      await IdentityGroupsRepository(
        db,
      ).assign([other], (await db.select(db.identityGroups).get()).single.id);
      await media('1');
      await media('2', owner: other);
      final plan = await organizer.plan({luffy, other});
      expect(plan.map((i) => i.request!.targetPath).toSet(), hasLength(2));
      expect(organizationSegment('../لوفي/زورو'), contains('لوفي_زورو'));
      expect(organizationSegment('..'), isNot('..'));
    },
  );
}
