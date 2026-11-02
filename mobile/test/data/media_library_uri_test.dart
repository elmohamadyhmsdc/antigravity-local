import 'package:flutter_test/flutter_test.dart';
import '../support/fakes.dart';

void main() {
  test('FakeMediaLibrary provides videoUri for assets', () async {
    final library = FakeMediaLibrary(
      uris: {'video_1': 'content://media/external/video/media/1'},
    );
    expect(
      await library.videoUri('video_1'),
      'content://media/external/video/media/1',
    );
    expect(await library.videoUri('unknown'), isNull);
  });
}
