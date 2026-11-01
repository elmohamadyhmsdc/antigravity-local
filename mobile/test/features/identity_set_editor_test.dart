import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/repositories/identity_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

void main() {
  appTest(
    'editing a saved identity changes its name and faces without replacing its id',
    (tester, env) async {
      final person = await seedPerson(env.db, name: 'Sara');
      final first = await seedFace(env.db, personId: person, seed: 1);
      final second = await seedFace(env.db, personId: person, seed: 2);
      final repo = IdentityRepository(env.db);
      final id = await repo.save(
        name: 'Original',
        personId: person,
        faceIds: [first, second],
      );
      await env.pump(
        tester,
        extra: [initialLocationProvider.overrideWithValue('/people/$person')],
      );
      await tester.tap(find.text('Identity'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Saved identities'));
      await tester.tap(find.text('Saved identities'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Edit identity'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Updated');
      await tester.tap(find.widgetWithText(CheckboxListTile, 'Face $second'));
      await tester.tap(find.text('Save identity'));
      await tester.pumpAndSettle();
      final set = (await env.db.select(env.db.identitySets).get()).single;
      expect((set.id, set.name), (id, 'Updated'));
      expect((await repo.faces(id)).map((f) => f.id), [first]);
    },
    session: testSession,
  );
}
