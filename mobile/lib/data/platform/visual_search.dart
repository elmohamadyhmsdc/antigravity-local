import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

abstract interface class VisualSearch {
  Future<void> search(Uint8List image);
}

final visualSearchProvider = Provider<VisualSearch>(
  (ref) => const GoogleLensSearch(),
);

/// Only the image explicitly chosen by the user is handed to the receiving app.
/// Keep the cache copy alive: Android may read the URI after the intent returns.
class GoogleLensSearch implements VisualSearch {
  const GoogleLensSearch({this.cacheDirectory});
  final Future<Directory> Function()? cacheDirectory;

  @override
  Future<void> search(Uint8List image) async {
    if (image.isEmpty) throw const FormatException('Empty image');
    final cache = await (cacheDirectory ?? getTemporaryDirectory)();
    final directory = await Directory(
      '${cache.path}/visual_search',
    ).create(recursive: true);
    final extension = image.length >= 4 && image[0] == 0x89 && image[1] == 0x50
        ? 'png'
        : image.length >= 4 && image[0] == 0x52 && image[1] == 0x49
        ? 'webp'
        : image.length >= 3 && image[0] == 0x47 && image[1] == 0x49
        ? 'gif'
        : 'jpg';
    final file = File(
      '${directory.path}/${DateTime.now().microsecondsSinceEpoch}.$extension',
    );
    await file.writeAsBytes(image, flush: true);
    await const MethodChannel(
      'antigravity/lens',
    ).invokeMethod<String>('searchImage', {'path': file.path});
  }
}
