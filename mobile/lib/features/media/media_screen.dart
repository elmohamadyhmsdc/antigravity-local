import 'package:flutter/material.dart';
import '../../data/repositories/media_queries.dart';
import 'media_viewer_screen.dart';

export 'media_page_item.dart' show mediaRowProvider, detectionsProvider;
export 'media_viewer_screen.dart';

/// L3 / P5b — MediaScreen: Top-level entry point for media viewer.
class MediaScreen extends StatelessWidget {
  const MediaScreen({
    super.key,
    required this.mediaId,
    this.initialTimestampMs,
    this.filter,
    this.collection,
  });

  final int mediaId;
  final int? initialTimestampMs;
  final MediaFilter? filter;
  final MediaCollectionContext? collection;

  @override
  Widget build(BuildContext context) {
    return MediaViewerScreen(
      mediaId: mediaId,
      initialTimestampMs: initialTimestampMs,
      filter: filter,
      collection: collection,
    );
  }
}
