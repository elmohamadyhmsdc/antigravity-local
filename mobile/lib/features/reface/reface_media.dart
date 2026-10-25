import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/app_localizations.dart';

enum RefaceMediaSource { gallery, files }

Future<RefaceMediaSource?> chooseRefaceMediaSource(BuildContext context) {
  final l = AppLocalizations.of(context);
  return showModalBottomSheet<RefaceMediaSource>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            key: const Key('reface-source-gallery'),
            leading: const Icon(Icons.photo_library_outlined),
            title: Text(l.refaceGallerySource),
            subtitle: Text(l.refaceGallerySourceHint),
            onTap: () => Navigator.pop(context, RefaceMediaSource.gallery),
          ),
          ListTile(
            key: const Key('reface-source-files'),
            leading: const Icon(Icons.folder_open_outlined),
            title: Text(l.refaceFilesSource),
            subtitle: Text(l.refaceFilesSourceHint),
            onTap: () => Navigator.pop(context, RefaceMediaSource.files),
          ),
        ],
      ),
    ),
  );
}

class RefaceTarget {
  const RefaceTarget.photo(Uint8List bytes) : photo = bytes, video = null;
  const RefaceTarget.video(File file) : video = file, photo = null;
  final Uint8List? photo;
  final File? video;
}

/// Picked files do not always supply a MIME type.
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

final refaceTargetPickerProvider =
    Provider<Future<RefaceTarget?> Function(RefaceMediaSource)>(
      (ref) => (source) async {
        if (source == RefaceMediaSource.gallery) {
          XFile? media;
          if (Platform.isAndroid) {
            final result = await const MethodChannel(
              'antigravity/media_picker',
            ).invokeMapMethod<String, dynamic>('pickGalleryMedia');
            if (result == null) return null;
            media = XFile(
              result['path'] as String,
              mimeType: result['mimeType'] as String?,
            );
          } else {
            media = await ImagePicker().pickMedia(
              maxWidth: 2560,
              maxHeight: 2560,
              imageQuality: 92,
              requestFullMetadata: false,
            );
          }
          if (media == null) return null;
          return await isVideoTarget(media)
              ? RefaceTarget.video(File(media.path))
              : RefaceTarget.photo(await media.readAsBytes());
        }
        // Custom filters use Android ACTION_OPEN_DOCUMENT (Files), whereas the
        // plugin's media/image/video types can open a gallery provider instead.
        final picked = await FilePicker.pickFile(
          type: FileType.custom,
          allowedExtensions: const [
            'jpg',
            'jpeg',
            'png',
            'webp',
            'gif',
            'heic',
            'heif',
            'avif',
            'bmp',
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
          ],
        );
        if (picked == null) return null;
        final media = picked.xFile;
        return await isVideoTarget(media)
            ? RefaceTarget.video(File(media.path))
            : RefaceTarget.photo(await media.readAsBytes());
      },
    );
