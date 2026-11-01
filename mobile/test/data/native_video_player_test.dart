import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:antigravity_mobile/data/platform/native_video_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('NativeVideoPlayer invokes antigravity/video_player channel with uri', () async {
    MethodCall? call;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('antigravity/video_player'),
      (c) async {
        call = c;
        return true;
      },
    );

    final result = await NativeVideoPlayer.openVideo(
      'content://media/external/video/media/12345',
      title: 'Sample Video',
    );

    expect(result, isTrue);
    expect(call?.method, 'openNativePlayer');
    expect(call?.arguments['uri'], 'content://media/external/video/media/12345');
    expect(call?.arguments['title'], 'Sample Video');
  });

  test('NativeVideoPlayer handles platform error gracefully', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('antigravity/video_player'),
      (c) async => throw PlatformException(code: 'error'),
    );

    final result = await NativeVideoPlayer.openVideo('invalid_uri');
    expect(result, isFalse);
  });
}
