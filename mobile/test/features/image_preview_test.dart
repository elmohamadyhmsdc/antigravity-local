import 'dart:convert';
import 'dart:io';

import 'package:antigravity_mobile/app.dart';
import 'package:antigravity_mobile/data/db/app_database.dart';
import 'package:antigravity_mobile/data/files/crop_cache.dart';
import 'package:antigravity_mobile/data/platform/visual_search.dart';
import 'package:antigravity_mobile/features/review/highlighted_photo.dart';
import 'package:antigravity_mobile/features/shared/image_preview.dart';
import 'package:antigravity_mobile/l10n/app_localizations.dart';
import 'package:antigravity_mobile/library_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

final _photo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAIAAAD8GO2jAAAAWElEQVRIDbXBAQEAAAABIF433wpV5KnIU5GnIk9Fnoo8FXkq8lTkqchTkaciT0WeijwVeSryVOSpyFORpyJPRZ6KPBV5KvJU5KnIU5GnIk9Fnoo8FXkq8jThJy0h7YJJqAAAAABJRU5ErkJggg==',
);

Future<void> _releaseImages(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
}

class _Search implements VisualSearch {
  final images = <Uint8List>[];
  bool fail = false;
  @override
  Future<void> search(Uint8List image) async {
    if (fail) throw PlatformException(code: 'unavailable');
    images.add(image);
  }
}

Future<void> _settle(WidgetTester tester) async {
  // File existence, cache touch, read and codec decoding each cross the real IO loop.
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
  }
  await tester.pumpAndSettle();
}

Future<void> _pump(
  WidgetTester tester,
  TestEnv env,
  Widget child,
  _Search search,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...env.overrides,
        visualSearchProvider.overrideWithValue(search),
        cropCacheProvider.overrideWith(
          (ref) => CropCache(
            db: env.db,
            files: env.files,
            loadOriginal: (_, _, _) async => null,
            cut: (_, _, _) async => null,
          ),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Center(child: SizedBox(width: 180, height: 180, child: child)),
        ),
      ),
    ),
  );
  await _settle(tester);
}

void main() {
  appTest(
    'expand is separate from selection; zoom and Lens preserve the parent',
    (tester, env) async {
      final search = _Search();
      var selections = 0;
      await _pump(
        tester,
        env,
        GestureDetector(
          onTap: () => selections++,
          child: PreviewImage.memory(_photo),
        ),
        search,
      );
      expect(search.images, isEmpty);
      await tester.tap(find.byKey(const Key('image-expand')));
      await _settle(tester);
      expect(selections, 0);
      final viewer = find.byType(InteractiveViewer);
      await tester.tap(viewer);
      await tester.pump(const Duration(milliseconds: 80));
      await tester.tap(viewer);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<InteractiveViewer>(viewer)
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        greaterThan(1),
      );
      await tester.tap(find.byKey(const Key('image-preview-reset')));
      expect(
        tester
            .widget<InteractiveViewer>(viewer)
            .transformationController!
            .value
            .getMaxScaleOnAxis(),
        1,
      );
      await tester.tap(find.byKey(const Key('google-lens')));
      await _settle(tester);
      expect(search.images.single, _photo);
      await tester.tap(find.byKey(const Key('image-preview-close')));
      await _settle(tester);
      await tester.tapAt(
        tester.getBottomLeft(find.byType(PreviewImage)) + const Offset(20, -20),
      );
      expect(selections, 1);
    },
  );

  appTest('a crop expands to its original and Lens follows the chosen image', (
    tester,
    env,
  ) async {
    final search = _Search();
    final original = Uint8List.fromList([..._photo, 0]);
    try {
      final media = await seedMedia(env.db, asset: 'original-photo');
      env.library.bytes['original-photo'] = original;
      await tester.runAsync(() => env.files.write('faces/preview.png', _photo));
      final face = await seedFace(
        env.db,
        mediaId: media,
        cropPath: 'faces/preview.png',
      );
      await _pump(
        tester,
        env,
        ImageExpand(
          source: const ImagePreviewSource.crop('faces/preview.png'),
          child: Image.memory(_photo),
        ),
        search,
      );
      await tester.tap(find.byKey(const Key('image-expand')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('google-lens')));
      await _settle(tester);
      expect(search.images.last, original);
      await tester.tap(find.byKey(const Key('image-preview-toggle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('google-lens')));
      await _settle(tester);
      expect(search.images.last, _photo);
      expect(
        (await env.db.select(env.db.faces).get())
            .singleWhere((f) => f.id == face)
            .personId,
        isNull,
      );
    } finally {
      await _releaseImages(tester);
      if (env.files.root.existsSync()) {
        await tester.runAsync(() => env.files.root.delete(recursive: true));
      }
    }
  });

  appTest(
    'missing originals still allow crop viewing and a failed Lens call is recoverable',
    (tester, env) async {
      final search = _Search()..fail = true;
      try {
        final media = await seedMedia(env.db, asset: 'deleted-original');
        await tester.runAsync(() => env.files.write('faces/saved.png', _photo));
        await seedFace(env.db, mediaId: media, cropPath: 'faces/saved.png');
        await _pump(
          tester,
          env,
          ImageExpand(
            source: const ImagePreviewSource.crop('faces/saved.png'),
            child: Image.memory(_photo),
          ),
          search,
        );
        await tester.tap(find.byKey(const Key('image-expand')));
        await _settle(tester);
        expect(find.byKey(const Key('image-preview-toggle')), findsNothing);
        await tester.tap(find.byKey(const Key('google-lens')));
        await _settle(tester);
        expect(find.text('Could not launch Google Lens'), findsOneWidget);
        expect(find.byKey(const Key('image-preview-screen')), findsOneWidget);
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('google-lens')))
              .onPressed,
          isNotNull,
        );
      } finally {
        await _releaseImages(tester);
        if (env.files.root.existsSync()) {
          await tester.runAsync(() => env.files.root.delete(recursive: true));
        }
      }
    },
  );

  appTest(
    'Who is this can open Lens and return with the draft name intact',
    (tester, env) async {
      final search = _Search();
      final media = await seedMedia(env.db, asset: 'unknown-person');
      env.library.bytes['unknown-person'] = _photo;
      final faces = [
        await seedFace(env.db, mediaId: media, seed: 1),
        await seedFace(env.db, mediaId: media, seed: 2),
      ];
      await env.db
          .into(env.db.reviewGroups)
          .insert(
            ReviewGroupsCompanion.insert(
              faceIds: jsonEncode(faces),
              cohesion: .8,
              quality: .8,
            ),
          );
      await env.pump(
        tester,
        extra: [
          initialLocationProvider.overrideWithValue('/review?view=quick'),
          visualSearchProvider.overrideWithValue(search),
        ],
        settle: false,
      );
      await _settle(tester);
      await tester.enterText(
        find.byKey(const Key('quick-group-name')),
        'Mariam',
      );
      tester.testTextInput.hide();
      await _settle(tester);
      final expand = find
          .descendant(
            of: find.byType(HighlightedPhoto).first,
            matching: find.byKey(const Key('image-expand')),
          )
          .first;
      await tester.tap(expand);
      await _settle(tester);
      expect(find.byKey(const Key('review-photo-pages')), findsOneWidget);
      await tester.tap(find.byKey(const Key('google-lens')));
      await _settle(tester);
      expect(search.images.single, _photo);
      await tester.pageBack();
      await _settle(tester);
      expect(
        tester
            .widget<TextField>(find.byKey(const Key('quick-group-name')))
            .controller!
            .text,
        'Mariam',
      );
      expect(await env.db.select(env.db.persons).get(), isEmpty);
      expect(
        (await env.db.select(env.db.faces).get()).every(
          (f) => f.personId == null,
        ),
        isTrue,
      );
    },
    session: testSession,
  );

  appTest('the preview and Lens button fit a small screen with large text', (
    tester,
    env,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.8;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _pump(tester, env, PreviewImage.memory(_photo), _Search());
    await tester.tap(find.byKey(const Key('image-expand')));
    await _settle(tester);
    expect(find.byKey(const Key('google-lens')).hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  appTest(
    'library thumbnails expand using the full original, with a thumbnail fallback',
    (tester, env) async {
      final search = _Search();
      final original = Uint8List.fromList([..._photo, 0]);
      env.library.bytes['full-image'] = original;
      await _pump(
        tester,
        env,
        PreviewImage.memory(
          _photo,
          fullSource: ImagePreviewSource.asset(
            'full-image',
            fallbackBytes: _photo,
          ),
        ),
        search,
      );
      await tester.tap(find.byKey(const Key('image-expand')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('google-lens')));
      await _settle(tester);
      expect(search.images.single, original);
      await tester.tap(find.byKey(const Key('image-preview-close')));
      await _settle(tester);
      env.library.bytes.remove('full-image');
      await tester.tap(find.byKey(const Key('image-expand')));
      await _settle(tester);
      await tester.tap(find.byKey(const Key('google-lens')));
      await _settle(tester);
      expect(search.images.last, _photo);
    },
  );

  test(
    'Lens receives a readable cache URI source with the exact selected bytes',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final directory = await Directory.systemTemp.createTemp('lens-test-');
      addTearDown(() => directory.delete(recursive: true));
      const channel = MethodChannel('antigravity/lens');
      String? path;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'searchImage');
            path = (call.arguments as Map)['path'] as String;
            expect(await File(path!).readAsBytes(), _photo);
            return 'lens';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await GoogleLensSearch(
        cacheDirectory: () async => directory,
      ).search(_photo);
      expect(path, endsWith('.png'));
    },
  );
}
