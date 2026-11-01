import 'dart:io';
import 'dart:typed_data';

import '../db/app_database.dart';
import '../media/media_library.dart';
import 'library_repository.dart';
import 'media_queries.dart';

class ResolvedMediaAction {
  const ResolvedMediaAction({
    required this.media,
    required this.photoBytes,
    required this.originalFile,
    required this.target,
  });

  final MediaRow media;
  final Uint8List? photoBytes;
  final File? originalFile;

  /// Explicit occurrence in this file, never a guessed identity or a source face.
  final MediaDetection? target;

  bool get isVideo => media.kind == 'video';
}

class MediaActionSource {
  const MediaActionSource({
    required this.repository,
    required this.queries,
    required this.library,
  });

  final LibraryRepository repository;
  final MediaQueries queries;
  final MediaLibrary library;

  Future<ResolvedMediaAction> resolve(
    int mediaId, {
    int? targetDetectionId,
    int maxSide = 2560,
  }) async {
    final row = await repository.watchMedia(mediaId).first;
    if (row == null) {
      throw const FormatException('This original is no longer in the library.');
    }
    MediaDetection? target;
    if (targetDetectionId != null) {
      final occurrences = await queries.watchDetections(mediaId).first;
      for (final occurrence in occurrences) {
        if (occurrence.id == targetDetectionId) {
          target = occurrence;
          break;
        }
      }
      if (target == null) {
        throw const FormatException(
          'The selected detection has changed. Select the target again.',
        );
      }
    }
    File? file;
    final originals = library;
    try {
      if (originals is OriginalMediaLibrary) {
        file = await (originals as OriginalMediaLibrary).originalFile(
          row.assetId,
        );
      } else if (originals is VideoMediaLibrary && row.kind == 'video') {
        file = await (originals as VideoMediaLibrary).videoFile(row.assetId);
      }
      if (file != null && !await file.exists()) file = null;
    } on Object {
      file = null;
    }
    if (row.kind == 'video') {
      if (file == null) {
        throw const FormatException(
          'The original video is missing or no longer accessible.',
        );
      }
      return ResolvedMediaAction(
        media: row,
        photoBytes: null,
        originalFile: file,
        target: target,
      );
    }
    Uint8List? bytes;
    try {
      bytes = await library.downscaledJpeg(
        row.assetId,
        width: row.width ?? 1,
        height: row.height ?? 1,
        maxSide: maxSide,
      );
    } on Object {
      throw const FormatException(
        'The original photo is missing or no longer accessible.',
      );
    }
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException(
        'The original photo is missing or no longer accessible.',
      );
    }
    return ResolvedMediaAction(
      media: row,
      photoBytes: bytes,
      originalFile: file,
      target: target,
    );
  }
}
