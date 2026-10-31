import 'dart:convert';
import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/features/review/review_media_viewer.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

final _photo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAWElEQVRIDbXBAQEAAAABIF433wpV5KnIU5GnIk9Fnoo8FXkq8lTkqchTkaciT0WeijwVeSryVOSpyFORpyJPRZ6KPBV5KvJU5KnIU5GnIk9Fnoo8FXkq8jThJy0h7YJJqAAAAABJRU5ErkJggg==',
);

Future<void> _open(WidgetTester tester, TestEnv env) => env.pump(
  tester,
  extra: [initialLocationProvider.overrideWithValue('/review')],
);

Future<void> _viewerSettle(WidgetTester tester) async {
  // Codec creation and frame decoding each cross the real engine event loop.
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  await tester.pumpAndSettle();
}

void main() {
  appTest(
    'full original photos can be swiped without changing selection',
    (tester, env) async {
      final person = await seedPerson(env.db, name: 'Sara');
      final media = await seedMedia(env.db, asset: 'swipe-source');
      env.library.bytes['swipe-source'] = _photo;
      final ids = [
        await seedFace(env.db, mediaId: media, seed: 1),
        await seedFace(env.db, mediaId: media, seed: 2),
      ];
      for (final id in ids) {
        await env.db
            .into(env.db.reviewMatches)
            .insert(
              ReviewMatchesCompanion.insert(
                faceId: Value(id),
                personId: person,
                score: .8,
                margin: .1,
                decision: 'suggest',
              ),
            );
      }
      await _open(tester, env);
      await tester.tap(find.byKey(Key('match-face-${ids.first}')));
      await _viewerSettle(tester);
      await tester.drag(
        find.byKey(const Key('review-photo-pages')),
        const Offset(-350, 0),
      );
      await _viewerSettle(tester);
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.tap(find.byKey(const Key('review-photo-previous')));
      await _viewerSettle(tester);
      expect(find.text('1 / 2'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Add 2 faces'), findsOneWidget);
    },
    session: testSession,
  );
  appTest(
    'a photo opens full size with exactly the suggested face highlighted; selection is separate',
    (tester, env) async {
      final person = await seedPerson(env.db, name: 'Sara');
      final media = await seedMedia(env.db, asset: 'source');
      env.library.bytes['source'] = _photo;
      final face = await seedFace(
        env.db,
        mediaId: media,
        x: .6,
        y: .2,
        w: .2,
        h: .3,
      );
      await seedFace(env.db, mediaId: media, x: .1, y: .1);
      await env.db
          .into(env.db.reviewMatches)
          .insert(
            ReviewMatchesCompanion.insert(
              faceId: Value(face),
              personId: person,
              score: .7,
              margin: .1,
              decision: 'suggest',
            ),
          );
      await _open(tester, env);
      await tester.tap(find.byKey(Key('match-face-$face')));
      await _viewerSettle(tester);
      expect(find.byKey(const Key('review-photo-pages')), findsOneWidget);
      expect(
        find.text('Review the face inside the yellow box'),
        findsOneWidget,
      );
      final overlay =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const Key('review-target-highlight')),
                  )
                  .painter!
              as ReviewHighlightPainter;
      expect(overlay.box, const Rect.fromLTWH(.6, .2, .2, .3));
      expect(find.byType(InteractiveViewer), findsWidgets);
      await tester.tap(find.byKey(const Key('review-viewer-include')));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<FilledButton>(find.byKey(Key('match-accept-$person')))
            .onPressed,
        isNull,
      );
      expect(
        (await env.db.select(env.db.faces).get()).where(
          (f) => f.personId != null,
        ),
        isEmpty,
      );
    },
    session: testSession,
  );

  appTest(
    'every group photo can be reviewed beyond the old 14-photo limit and excluded before creating',
    (tester, env) async {
      final faces = <int>[];
      for (var i = 0; i < 22; i++) {
        faces.add(await seedFace(env.db, seed: i + 1));
      }
      final group = await env.db
          .into(env.db.reviewGroups)
          .insert(
            ReviewGroupsCompanion.insert(
              faceIds: jsonEncode(faces),
              cohesion: .8,
              quality: .8,
            ),
          );
      await _open(tester, env);
      await tester.tap(find.byKey(const Key('review-tab-groups')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(Key('group-view-all-$group')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('group-view-all-$group')));
      await tester.pumpAndSettle();
      expect(find.text('1 / 22'), findsOneWidget);
      expect(
        find.text('The original is unavailable. This is the saved crop only.'),
        findsWidgets,
      );
      await tester.scrollUntilVisible(
        find.byKey(const Key('review-photo-thumb-20')),
        260,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.tap(find.byKey(const Key('review-photo-thumb-20')));
      await tester.pumpAndSettle();
      expect(find.text('21 / 22'), findsOneWidget);
      await tester.tap(find.byKey(const Key('review-viewer-include')));
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('21 selected'), findsOneWidget);
      await tester.ensureVisible(find.byKey(Key('group-create-$group')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('group-create-$group')));
      await tester.pumpAndSettle();
      final saved = await env.db.select(env.db.faces).get();
      expect(saved.where((f) => f.personId != null), hasLength(21));
      expect(saved.firstWhere((f) => f.id == faces[20]).personId, isNull);
    },
    session: testSession,
  );

  appTest(
    'body review highlights the body and records a rejection from the full photo',
    (tester, env) async {
      final person = await seedPerson(env.db, name: 'Sara');
      final media = await seedMedia(env.db, asset: 'body-photo');
      env.library.bytes['body-photo'] = _photo;
      await seedFace(env.db, mediaId: media);
      final body = await seedBody(env.db, mediaId: media);
      await env.db
          .into(env.db.reviewBodyLinks)
          .insert(
            ReviewBodyLinksCompanion.insert(
              bodyId: Value(body),
              personId: person,
              method: 'appearance',
              confidence: .7,
            ),
          );
      await _open(tester, env);
      await tester.ensureVisible(find.byKey(const Key('review-tab-outfits')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-tab-outfits')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(Key('outfit-view-$body')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('outfit-view-$body')));
      await _viewerSettle(tester);
      expect(
        find.text('Review the body inside the yellow box'),
        findsOneWidget,
      );
      final overlay =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const Key('review-target-highlight')),
                  )
                  .painter!
              as ReviewHighlightPainter;
      expect(overlay.box, const Rect.fromLTWH(.2, .1, .4, .8));
      await tester.tap(find.byKey(const Key('review-viewer-no')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('review-photo-pages')), findsNothing);
      expect(
        (await env.db.select(env.db.bodyRejections).get()).single.bodyId,
        body,
      );
    },
    session: testSession,
  );
}
