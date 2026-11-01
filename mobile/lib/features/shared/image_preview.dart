import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/platform/visual_search.dart';
import '../../data/platform/video_frames.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../../providers.dart';

class ImagePreviewSource {
  const ImagePreviewSource.bytes(this.bytes)
    : file = null,
      cropPath = null,
      assetId = null,
      video = false,
      timestampMs = 0,
      fallbackBytes = null;
  const ImagePreviewSource.file(this.file)
    : bytes = null,
      cropPath = null,
      assetId = null,
      video = false,
      timestampMs = 0,
      fallbackBytes = null;
  const ImagePreviewSource.crop(this.cropPath)
    : bytes = null,
      file = null,
      assetId = null,
      video = false,
      timestampMs = 0,
      fallbackBytes = null;
  const ImagePreviewSource.asset(
    this.assetId, {
    this.video = false,
    this.timestampMs = 0,
    this.fallbackBytes,
  }) : bytes = null,
       file = null,
       cropPath = null;

  final Uint8List? bytes;
  final Uint8List? fallbackBytes;
  final File? file;
  final String? cropPath, assetId;
  final bool video;
  final int timestampMs;
}

final previewVideoFramesProvider = Provider<LocalVideoFrames>(
  (ref) => const AndroidVideoFrames(),
);

Future<Uint8List?> loadPreviewImage(
  WidgetRef ref,
  ImagePreviewSource source,
) async {
  try {
    if (source.bytes != null) return source.bytes;
    if (source.file != null) return await source.file!.readAsBytes();
    if (source.cropPath != null) {
      final cache = ref.read(cropCacheProvider);
      final file = await cache.ensure(source.cropPath!);
      return await file?.readAsBytes();
    }
    if (source.assetId != null) {
      if (source.video) {
        final frames = await ref.read(previewVideoFramesProvider).frames(
          source.assetId!,
          [source.timestampMs],
          maxSide: 2560,
        );
        return frames.isEmpty
            ? source.fallbackBytes
            : frames.first ?? source.fallbackBytes;
      }
      return await ref
              .read(mediaLibraryProvider)
              .viewerImage(source.assetId!, maxSide: 2560) ??
          source.fallbackBytes;
    }
  } catch (_) {
    // A removed original or evicted crop must not prevent returning to the task.
  }
  return source.fallbackBytes;
}

Future<ImagePreviewSource?> _originalForCrop(WidgetRef ref, String path) async {
  final db = ref.read(databaseProvider);
  final rows = await db
      .customSelect(
        '''
    SELECT m.asset_id, m.kind, COALESCE(t.timestamp_ms, d.timestamp_ms, 0) AS time_ms
    FROM faces t LEFT JOIN media_detections d ON d.ref_id = t.id AND d.kind = 'f'
    JOIN media m ON m.id = COALESCE(t.media_id, d.media_id)
    WHERE t.crop_path = ?
    UNION ALL
    SELECT m.asset_id, m.kind, COALESCE(t.timestamp_ms, d.timestamp_ms, 0) AS time_ms
    FROM bodies t LEFT JOIN media_detections d ON d.ref_id = t.id AND d.kind = 'b'
    JOIN media m ON m.id = COALESCE(t.media_id, d.media_id)
    WHERE t.crop_path = ? LIMIT 1
  ''',
        variables: [Variable.withString(path), Variable.withString(path)],
      )
      .get();
  if (rows.isEmpty) return null;
  final row = rows.first;
  return ImagePreviewSource.asset(
    row.read<String>('asset_id'),
    video: row.read<String>('kind') == 'video',
    timestampMs: row.read<int>('time_ms'),
  );
}

Future<void> searchPreviewImage(
  BuildContext context,
  WidgetRef ref,
  ImagePreviewSource source, {
  ImagePreviewSource? fallback,
}) async {
  final search = ref.read(visualSearchProvider);
  final l = AppLocalizations.of(context);
  try {
    var bytes = await loadPreviewImage(ref, source);
    if (!context.mounted) return;
    if (bytes == null && fallback != null) {
      bytes = await loadPreviewImage(ref, fallback);
    }
    if (bytes == null || bytes.isEmpty) {
      throw const FormatException('Image unavailable');
    }
    if (!context.mounted) return;
    await search.search(bytes);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.googleLensError)));
    }
  }
}

Future<void> openImagePreview(
  BuildContext context,
  ImagePreviewSource source,
) => Navigator.of(context, rootNavigator: true).push<void>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => ImagePreviewScreen(source: source),
  ),
);

/// The small, separate control preserves the containing tile's selection/navigation gesture.
class ImageExpand extends StatelessWidget {
  const ImageExpand({
    super.key,
    required this.source,
    required this.child,
    this.onExpand,
  });
  final ImagePreviewSource source;
  final Widget child;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.passthrough,
    children: [
      child,
      PositionedDirectional(
        top: 2,
        end: 2,
        child: IconButton(
          key: const Key('image-expand'),
          tooltip: AppLocalizations.of(context).imageExpand,
          onPressed: onExpand ?? () => openImagePreview(context, source),
          style: IconButton.styleFrom(
            backgroundColor: Colors.black54,
            foregroundColor: Colors.white,
            minimumSize: const Size(28, 28),
            maximumSize: const Size(36, 36),
            padding: const EdgeInsets.all(4),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.open_in_full, size: 18),
        ),
      ),
    ],
  );
}

/// File and in-memory images use the same viewer as private face/body crops.
class PreviewImage extends StatelessWidget {
  PreviewImage.memory(
    Uint8List bytes, {
    super.key,
    BoxFit? fit,
    double? width,
    double? height,
    int? cacheWidth,
    bool gaplessPlayback = false,
    ImageErrorWidgetBuilder? errorBuilder,
    ImagePreviewSource? fullSource,
  }) : source = fullSource ?? ImagePreviewSource.bytes(bytes),
       image = Image.memory(
         bytes,
         fit: fit,
         width: width,
         height: height,
         cacheWidth: cacheWidth,
         gaplessPlayback: gaplessPlayback,
         errorBuilder: errorBuilder,
       );

  PreviewImage.file(
    File file, {
    super.key,
    BoxFit? fit,
    double? width,
    double? height,
    int? cacheWidth,
    bool gaplessPlayback = false,
    ImageErrorWidgetBuilder? errorBuilder,
    String? cropPath,
  }) : source = cropPath == null
           ? ImagePreviewSource.file(file)
           : ImagePreviewSource.crop(cropPath),
       image = Image.file(
         file,
         fit: fit,
         width: width,
         height: height,
         cacheWidth: cacheWidth,
         gaplessPlayback: gaplessPlayback,
         errorBuilder: errorBuilder,
       );

  final ImagePreviewSource source;
  final Image image;

  @override
  Widget build(BuildContext context) =>
      ImageExpand(source: source, child: image);
}

class ImagePreviewScreen extends ConsumerStatefulWidget {
  const ImagePreviewScreen({super.key, required this.source});
  final ImagePreviewSource source;
  @override
  ConsumerState<ImagePreviewScreen> createState() => _ImagePreviewScreenState();
}

class _ImagePreviewScreenState extends ConsumerState<ImagePreviewScreen> {
  late final Future<(Uint8List?, Uint8List?)> _images;
  final _transform = TransformationController();
  bool _original = true, _searching = false;
  Offset _doubleTap = Offset.zero;

  @override
  void initState() {
    super.initState();
    _images = _load();
  }

  Future<(Uint8List?, Uint8List?)> _load() async {
    final crop = loadPreviewImage(ref, widget.source);
    Uint8List? original;
    if (widget.source.cropPath != null) {
      try {
        final source = await _originalForCrop(ref, widget.source.cropPath!);
        if (source != null && mounted) {
          original = await loadPreviewImage(ref, source);
        }
      } catch (_) {
        /* The saved crop remains viewable. */
      }
    }
    return (await crop, original);
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _search(Uint8List bytes) async {
    final search = ref.read(visualSearchProvider);
    setState(() => _searching = true);
    try {
      await search.search(bytes);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context).googleLensError)),
        );
      }
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      key: const Key('image-preview-screen'),
      appBar: AppBar(
        leading: const CloseButton(key: Key('image-preview-close')),
        title: Text(l.imagePreviewTitle),
        actions: [
          IconButton(
            key: const Key('image-preview-reset'),
            tooltip: l.imageResetZoom,
            onPressed: () => _transform.value = Matrix4.identity(),
            icon: const Icon(Icons.fit_screen),
          ),
        ],
      ),
      body: FutureBuilder<(Uint8List?, Uint8List?)>(
        future: _images,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final (crop, original) = snapshot.data!;
          final bytes = _original ? original ?? crop : crop ?? original;
          if (bytes == null || bytes.isEmpty) {
            return Center(child: Text(l.imageUnavailable));
          }
          return Column(
            children: [
              Expanded(
                child: GestureDetector(
                  onDoubleTapDown: (details) =>
                      _doubleTap = details.localPosition,
                  onDoubleTap: () {
                    _transform.value = _transform.value.getMaxScaleOnAxis() > 1
                        ? Matrix4.identity()
                        : (Matrix4.identity()
                            ..translateByDouble(
                              -_doubleTap.dx * 2,
                              -_doubleTap.dy * 2,
                              0,
                              1,
                            )
                            ..scaleByDouble(3, 3, 1, 1));
                  },
                  child: InteractiveViewer(
                    transformationController: _transform,
                    minScale: 1,
                    maxScale: 8,
                    child: SizedBox.expand(
                      child: Image.memory(
                        bytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) =>
                            Center(child: Text(l.imageUnavailable)),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      if (crop != null && original != null)
                        TextButton.icon(
                          key: const Key('image-preview-toggle'),
                          onPressed: () => setState(() {
                            _original = !_original;
                            _transform.value = Matrix4.identity();
                          }),
                          icon: Icon(
                            _original ? Icons.crop : Icons.photo_outlined,
                          ),
                          label: Text(
                            _original ? l.reviewCrop : l.reviewFullPhoto,
                          ),
                        ),
                      FilledButton.icon(
                        key: const Key('google-lens'),
                        onPressed: _searching ? null : () => _search(bytes),
                        icon: _searching
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.image_search),
                        label: Text(l.searchGoogleLens),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
