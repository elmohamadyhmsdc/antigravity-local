import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

class RefaceTarget {
  const RefaceTarget.photo(Uint8List bytes) : photo = bytes, video = null;
  const RefaceTarget.video(File file) : video = file, photo = null;
  final Uint8List? photo;
  final File? video;
}

/// image_picker's combined Android picker does not always supply a MIME type.
/// Read only a small header when the cached filename has no useful extension.
Future<bool> isVideoTarget(XFile media) async {
  final mime = media.mimeType;
  if (mime != null && mime.startsWith('video/')) return true;
  if (mime != null && mime.startsWith('image/')) return false;
  final extension = media.path.split('.').last.toLowerCase();
  if (const {
    'mp4',
    'mov',
    'm4v',
    'webm',
    'mkv',
    'avi',
    '3gp',
    '3g2',
    'mpg',
    'mpeg',
    'ts',
  }.contains(extension)) {
    return true;
  }
  if (const {
    'jpg',
    'jpeg',
    'png',
    'webp',
    'gif',
    'heic',
    'heif',
    'avif',
    'bmp',
  }.contains(extension)) {
    return false;
  }
  final input = await File(media.path).open();
  try {
    final header = await input.read(64);
    String tag(int start, int end) => header.length < end
        ? ''
        : String.fromCharCodes(header.sublist(start, end));
    if (tag(4, 8) == 'ftyp') {
      return !const {
        'heic',
        'heix',
        'hevc',
        'hevx',
        'mif1',
        'msf1',
        'avif',
        'avis',
      }.contains(tag(8, 12));
    }
    if (tag(0, 4) == 'RIFF') return tag(8, 12) == 'AVI ';
    return header.length >= 4 &&
        header[0] == 0x1a &&
        header[1] == 0x45 &&
        header[2] == 0xdf &&
        header[3] == 0xa3;
  } finally {
    await input.close();
  }
}

final refaceTargetPickerProvider = Provider<Future<RefaceTarget?> Function()>(
  (ref) => () async {
    final media = await ImagePicker().pickMedia(
      maxWidth: 2560,
      maxHeight: 2560,
      imageQuality: 92,
      requestFullMetadata: false,
    );
    if (media == null) return null;
    return await isVideoTarget(media)
        ? RefaceTarget.video(File(media.path))
        : RefaceTarget.photo(await media.readAsBytes());
  },
);
