import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:antigravity_mobile/data/media/thumbnail_service.dart';
import 'package:antigravity_mobile/features/media/viewer_image_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:antigravity_mobile/app.dart';
import '../support/fakes.dart';
import '../support/harness.dart';
import '../support/seed.dart';

class CountingLibrary extends FakeMediaLibrary {
  final calls = <String>[];
  @override
  Future<Uint8List?> viewerImage(String id, {int maxSide = 1800}) async {
    calls.add(id);
    return bytes[id];
  }
}

void main() {
  appTest('photo swipes and returning do not reread viewer images', (
    tester,
    env,
  ) async {
    final png = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
      final image = await recorder.endRecording().toImage(2, 2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return data!.buffer.asUint8List();
    }))!;
    env.library.bytes.addAll({'a': png, 'b': png});
    final library = CountingLibrary()..bytes.addAll({'a': png, 'b': png});
    final first = await seedMedia(env.db, asset: 'a');
    await seedMedia(env.db, asset: 'b');
    await env.pump(
      tester,
      settle: false,
      extra: [
        initialLocationProvider.overrideWithValue('/media/$first'),
        viewerImageCacheProvider.overrideWithValue(
          ViewerImageCache(library, ThumbnailService(library)),
        ),
      ],
    );
    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 40)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    final pages = find.byKey(const Key('media-page-view'));
    await tester.drag(pages, const Offset(350, 0));
    await settle();
    await tester.drag(pages, const Offset(-350, 0));
    await settle();
    expect(library.calls.where((id) => id == 'a'), hasLength(1));
    expect(library.calls.where((id) => id == 'b'), hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'swiping back reuses preview and simultaneous requests share one read',
    (tester) async {
      final library = CountingLibrary()..bytes['a'] = tinyPng;
      final cache = ViewerImageCache(library, ThumbnailService(library));
      await tester.runAsync(() async {
        final images = await Future.wait([cache.get('a'), cache.get('a')]);
        expect(images.first, isNotNull);
        expect(images.first!.width, 1);
        expect(await cache.get('a'), same(images.first));
        expect(library.calls, ['a']);
        cache.clear();
        await cache.get('a');
        expect(library.calls, ['a', 'a']);
      });
    },
  );

  testWidgets('viewer cache evicts by bytes and retries unavailable media', (
    tester,
  ) async {
    final library = CountingLibrary()
      ..bytes.addAll({'a': tinyPng, 'b': tinyPng});
    final cache = ViewerImageCache(
      library,
      ThumbnailService(library),
      maxBytes: tinyPng.length,
    );
    await tester.runAsync(() async {
      await cache.get('a');
      await cache.get('b');
      expect(cache.peek('a'), isNull);
      expect(cache.peek('b'), isNotNull);
      expect(await cache.get('missing'), isNull);
      library.bytes['missing'] = tinyPng;
      expect(await cache.get('missing'), isNotNull);
    });
  });
}
