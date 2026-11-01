import 'package:antigravity_mobile/data/api/dtos/analyze.dart';
import 'package:antigravity_mobile/data/api/equipment_api.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/domain/pose/equipment_library.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/seed.dart';

void main() {
  test(
    'equipment corrections and removals survive repeat recognition and shifted boxes',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final media = await seedMedia(db);
      final body = await seedBody(db, mediaId: media);
      final bodies = await db.select(db.bodies).get();
      final library = EquipmentLibrary(
        db: db,
        media: FakeMediaLibrary(),
        api: () => null,
      );
      EquipmentResponse detection({String key = 'a', double x = .2}) =>
          EquipmentResponse(
            version: 1,
            objects: [
              EquipmentObject(
                key: key,
                label: 'racket',
                bodyIndex: 0,
                box: BBox(x: x, y: .2, w: .2, h: .2),
              ),
            ],
          );
      await library.store(media, bodies, detection());
      final object = (await library.objects()).single;
      expect(object.bodyId, body);
      await library.correct(object, 'Tennis racket', null);
      await library.store(media, bodies, detection(key: 'moved', x: .205));
      var corrected = (await library.objects()).single;
      expect(
        (corrected.label, corrected.bodyId, corrected.state),
        ('tennis racket', null, 'confirmed'),
      );
      await library.reject(corrected);
      await library.store(media, bodies, detection());
      expect(await library.objects(), isEmpty);
      expect((await db.select(db.equipmentPhotos).get()).single.version, 1);
      await library.add(media, 'Dumbbell', body);
      expect((await library.objects()).single.label, 'dumbbell');
      final otherPhoto = await seedMedia(db, asset: 'elsewhere');
      final otherBody = await seedBody(db, mediaId: otherPhoto);
      await expectLater(
        library.correct(corrected, 'racket', otherBody),
        throwsArgumentError,
      );
    },
  );
  test(
    'deleting a photo removes equipment and detection checkpoints',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final media = await seedMedia(db);
      final library = EquipmentLibrary(
        db: db,
        media: FakeMediaLibrary(),
        api: () => null,
      );
      await library.store(
        media,
        [],
        const EquipmentResponse(
          version: 1,
          objects: [
            EquipmentObject(
              key: 'shared',
              label: 'ball',
              box: BBox(x: .2, y: .2, w: .2, h: .2),
            ),
          ],
        ),
      );
      await (db.delete(db.media)..where((m) => m.id.equals(media))).go();
      expect(await library.objects(), isEmpty);
      expect(await db.select(db.equipmentPhotos).get(), isEmpty);
    },
  );
}
