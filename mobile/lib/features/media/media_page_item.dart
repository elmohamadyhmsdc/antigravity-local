import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/app_database.dart';
import '../../data/repositories/media_queries.dart';
import '../../data/repositories/people_repository.dart';
import '../../l10n/app_localizations.dart';
import '../../library_providers.dart';
import '../shared/empty_state.dart';
import 'detection_overlay.dart';
import 'layers_popover.dart';
import 'video_media_view.dart';

class LoadedImage {
  const LoadedImage(
    this.bytes,
    this.width,
    this.height, {
    this.fallback = false,
  });
  final Uint8List bytes;
  final int width;
  final int height;
  final bool fallback;
}

final mediaRowProvider = StreamProvider.autoDispose.family<MediaRow?, int>(
  (ref, id) => ref.watch(libraryRepositoryProvider).watchMedia(id),
);

final detectionsProvider = StreamProvider.autoDispose
    .family<List<MediaDetection>, int>(
      (ref, id) => ref.watch(mediaQueriesProvider).watchDetections(id),
    );

/// L3 / P5b — Page view item for photo or video inside the media viewer.
class MediaPageViewItem extends ConsumerStatefulWidget {
  const MediaPageViewItem({
    super.key,
    required this.mediaId,
    required this.isActive,
    required this.onToggleChrome,
    required this.onZoomChanged,
    required this.layers,
    required this.people,
    required this.onTapBox,
    this.initialTimestampMs,
    required this.onOpenNativePlayer,
  });

  final int mediaId;
  final bool isActive;
  final VoidCallback onToggleChrome;
  final ValueChanged<bool> onZoomChanged;
  final ViewerLayers layers;
  final Map<int, PersonSummary> people;
  final void Function(MediaDetection) onTapBox;
  final int? initialTimestampMs;
  final VoidCallback onOpenNativePlayer;

  @override
  ConsumerState<MediaPageViewItem> createState() => _MediaPageViewItemState();
}

class _MediaPageViewItemState extends ConsumerState<MediaPageViewItem> {
  final _transform = TransformationController();
  Offset _doubleTap = Offset.zero;
  Future<LoadedImage?>? _image;
  String? _assetId;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _transform.removeListener(_onTransformChanged);
    _transform.dispose();
    super.dispose();
  }

  void _onTransformChanged() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    widget.onZoomChanged(zoomed);
  }

  Future<LoadedImage?> _load(String assetId, int width, int height) async {
    final library = ref.read(mediaLibraryProvider);
    var bytes = await library.viewerImage(assetId);
    final fallback = bytes == null;
    bytes ??= await ref
        .read(thumbnailServiceProvider)
        .get(assetId, width: width, height: height);
    if (bytes == null || bytes.isEmpty) return null;
    final decoded = await ui.instantiateImageCodec(bytes);
    final frame = await decoded.getNextFrame();
    final loaded = LoadedImage(
      bytes,
      frame.image.width,
      frame.image.height,
      fallback: fallback,
    );
    frame.image.dispose();
    decoded.dispose();
    return loaded;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final row = ref.watch(mediaRowProvider(widget.mediaId));
    final detections =
        ref.watch(detectionsProvider(widget.mediaId)).value ??
        const <MediaDetection>[];

    return row.when(
      loading: () => const LoadingBox(),
      error: (_, _) =>
          EmptyState(icon: Icons.photo_outlined, title: l10n.photoGone),
      data: (media) {
        if (media == null) {
          return EmptyState(icon: Icons.photo_outlined, title: l10n.photoGone);
        }
        if (media.kind == 'video') {
          return VideoMediaView(
            key: ValueKey(media.assetId),
            assetId: media.assetId,
            initialTimestampMs: widget.initialTimestampMs,
            library: ref.watch(mediaLibraryProvider),
            detections: detections,
            people: widget.people,
            showBodies: widget.layers.bodies,
            showFaces: widget.layers.faces,
            onTapBox: widget.onTapBox,
            isActive: widget.isActive,
            onOpenNativePlayer: widget.onOpenNativePlayer,
          );
        }
        if (_assetId != media.assetId) {
          _assetId = media.assetId;
          _image = _load(media.assetId, media.width ?? 1, media.height ?? 1);
        }
        return FutureBuilder<LoadedImage?>(
          future: _image,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LoadingBox();
            }
            final image = snapshot.data;
            if (image == null) {
              return EmptyState(
                icon: Icons.photo_outlined,
                title: l10n.photoGone,
                body: l10n.photoGoneBody,
              );
            }
            return Stack(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final fitted = applyBoxFit(
                      BoxFit.contain,
                      Size(image.width.toDouble(), image.height.toDouble()),
                      constraints.biggest,
                    ).destination;
                    return Center(
                      child: GestureDetector(
                        onTap: widget.onToggleChrome,
                        onDoubleTapDown: (details) =>
                            _doubleTap = details.localPosition,
                        onDoubleTap: () {
                          _transform.value =
                              _transform.value.getMaxScaleOnAxis() > 1.01
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
                          maxScale: 5,
                          child: SizedBox(
                            key: const Key('annotated-photo'),
                            width: fitted.width,
                            height: fitted.height,
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.memory(
                                  image.bytes,
                                  fit: BoxFit.fill,
                                  gaplessPlayback: true,
                                ),
                                if (!image.fallback)
                                  DetectionOverlay(
                                    detections: detections,
                                    fittedSize: fitted,
                                    layers: widget.layers,
                                    people: widget.people,
                                    onTapDetection: widget.onTapBox,
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                if (image.fallback)
                  const Positioned(
                    bottom: 8,
                    left: 8,
                    child: ColoredBox(
                      color: Colors.black87,
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Text(
                          'Preview only · original unavailable',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}
