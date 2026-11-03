// The "prefer exposed bodies" switch of the LoRA auto-pick: off by default, on = exposed bodies first
// (up to 90% of the body slots), and flipping it re-picks the bodies from the same candidates.

import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/repositories/curation_queries.dart';
import 'package:antigravity_mobile/features/lora/curation_controller.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/seed.dart';

void main() {
  late AppDatabase db;
  late int person;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    person = await seedPerson(db, name: 'Sara');
    // 12 exposed bodies, then 2 clothed ones
    for (var i = 0; i < 14; i++) {
      final m = await seedMedia(db, asset: 'b$i');
      final body = await seedBody(db, mediaId: m, personId: person);
      if (i < 12) {
        await db
            .into(db.sensitiveRegions)
            .insert(
              SensitiveRegionsCompanion.insert(
                mediaId: m,
                bodyId: Value(body),
                label: 'BELLY_EXPOSED',
                exposed: true,
                score: 0.9,
                x: 0.3,
                y: 0.4,
                w: 0.2,
                h: 0.2,
                modelVersion: 1,
                createdAt: 1,
              ),
            );
      }
    }
  });
  tearDown(() => db.close());

  test('off by default; turning it on re-picks the bodies, exposed first but not all of them', () async {
    final notifier = CurationNotifier(queries: CurationQueries(db));
    await notifier.load(person, 'Sara');
    expect(notifier.state.preferExposed, isFalse);

    notifier.setPreferExposed(true);

    expect(notifier.state.preferExposed, isTrue);
    final exposed = notifier.state.body.where((c) => c.hasExposedRegion).length;
    expect(notifier.state.body, hasLength(8));
    expect(exposed, 7, reason: '90% of 8 slots, rounded down');
    expect(notifier.state.body.where((c) => !c.hasExposedRegion), hasLength(1));

    notifier.setPreferExposed(false);

    expect(notifier.state.preferExposed, isFalse);
    expect(notifier.state.body, hasLength(8));
  });

  test('the faces are not touched by the switch', () async {
    final notifier = CurationNotifier(queries: CurationQueries(db));
    await notifier.load(person, 'Sara');
    final before = notifier.state.faces;

    notifier.setPreferExposed(true);

    expect(notifier.state.faces, same(before));
  });
}
