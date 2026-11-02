import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/media/thumbnail_service.dart';
import '../support/fakes.dart';

void main() {
  group('ThumbnailService', () {
    test(
      'getSync returns null before fetch, and cached bytes after resolution',
      () async {
        final fakeLib = FakeMediaLibrary();
        final bytes1 = Uint8List.fromList([1, 2, 3, 4]);
        fakeLib.bytes['asset_1'] = bytes1;

        final service = ThumbnailService(fakeLib, capacity: 10);

        // 1. Synchronous check is initially null
        expect(service.getSync('asset_1'), isNull);

        // 2. Fetch asynchronously
        final result = await service.get('asset_1');
        expect(result, equals(bytes1));

        // 3. Synchronous check immediately returns cached bytes
        expect(service.getSync('asset_1'), equals(bytes1));

        // 4. Repeated get returns synchronously / cached
        final cachedResult = await service.get('asset_1');
        expect(cachedResult, equals(bytes1));
      },
    );

    test('evicts oldest items when capacity is exceeded', () async {
      final fakeLib = FakeMediaLibrary();
      for (var i = 0; i < 5; i++) {
        fakeLib.bytes['asset_$i'] = Uint8List.fromList([i]);
      }

      final service = ThumbnailService(fakeLib, capacity: 3);

      for (var i = 0; i < 5; i++) {
        await service.get('asset_$i');
      }

      // Assets 0 and 1 should have been evicted; 2, 3, 4 retained
      expect(service.getSync('asset_0'), isNull);
      expect(service.getSync('asset_1'), isNull);
      expect(service.getSync('asset_2'), isNotNull);
      expect(service.getSync('asset_3'), isNotNull);
      expect(service.getSync('asset_4'), isNotNull);
    });

    test('clear wipes both sync and async cache', () async {
      final fakeLib = FakeMediaLibrary();
      fakeLib.bytes['asset_a'] = Uint8List.fromList([42]);

      final service = ThumbnailService(fakeLib, capacity: 10);
      await service.get('asset_a');
      expect(service.getSync('asset_a'), isNotNull);

      service.clear();
      expect(service.getSync('asset_a'), isNull);
    });

    test('preheat handles empty and populated lists gracefully', () {
      final fakeLib = FakeMediaLibrary();
      final service = ThumbnailService(fakeLib, capacity: 10);

      expect(() => service.preheat([]), returnsNormally);
      expect(() => service.preheat(['asset_1', 'asset_2']), returnsNormally);
    });
  });
}
